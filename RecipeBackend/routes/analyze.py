"""Recipe analysis endpoints (queue, worker process, direct upload)."""

from __future__ import annotations

import json
import os
import tempfile
from typing import Optional

from ai_video_analysis import recipe_ai_provider_chain
from config import MAX_VIDEO_UPLOAD_BYTES
from download import (
    InstagramBlockedError,
    TikTokBlockedError,
    download_instagram_reel,
    download_tiktok_video,
    download_youtube_video,
)
from fastapi import APIRouter, File, Form, HTTPException, Request, UploadFile  # pyright: ignore[reportMissingImports]
from import_jobs_service import (
    default_analyze_wait_timeout,
    enqueue_import_job,
    wait_for_job_result,
)
from models import AnalyzeRequest, RecipeResponse
from quota import enforce_import_quota, require_user_id
from recipe_analysis import (
    analyze_local_video_path,
    extract_json_from_response,
    normalize_dish_hero_timestamp_seconds,
    normalize_instruction_timestamps,
    require_recipe_ai_configured,
)
from served_videos import persist_served_video
from thumbnails import save_thumbnail_from_video, upload_suffix
from url_utils import is_tiktok_url, is_youtube_url, youtube_oembed_author_name

router = APIRouter(tags=["analyze"])


@router.post("/analyze_reel")
async def analyze_reel_enqueue(request: Request, req: AnalyzeRequest, wait: bool = True):
    """
    Queue-only entrypoint for app traffic.
    Stores job in `import_jobs`; worker handles processing asynchronously.
    """
    user_id = require_user_id(request)
    url = (req.url or "").strip()
    if not url:
        raise HTTPException(status_code=400, detail="URL is required")
    language = (req.language or "en").strip() or "en"
    row = await enqueue_import_job(user_id=user_id, url=url, language=language)
    if not wait:
        return {"job_id": row["id"], "status": "pending"}
    payload = await wait_for_job_result(
        user_id=user_id,
        job_id=str(row["id"]),
        timeout_sec=default_analyze_wait_timeout(),
    )
    return RecipeResponse(
        recipe_name=payload.get("recipe_name", "Untitled Recipe"),
        description=payload.get("description", ""),
        creator=payload.get("creator", ""),
        estimated_cooking_time=str(payload.get("estimated_cooking_time", "0")),
        prep_time=str(payload.get("prep_time", "0")),
        estimated_servings=str(payload.get("estimated_servings", "1")),
        ingredients=payload.get("ingredients", []),
        instructions=payload.get("instructions", []),
        video_url=payload.get("video_url"),
        thumbnail_url=payload.get("thumbnail_url"),
        dish_hero_timestamp_seconds=str(payload.get("dish_hero_timestamp_seconds", "0")),
    )


@router.post("/analyze_reel/process", response_model=RecipeResponse, include_in_schema=False)
async def analyze_reel_process(request: Request, req: AnalyzeRequest):
    url = (req.url or "").strip()
    if not url:
        raise HTTPException(status_code=400, detail="URL is required")

    source_kind = "instagram"
    if is_youtube_url(url):
        source_kind = "youtube"
    elif is_tiktok_url(url):
        source_kind = "tiktok"
    await enforce_import_quota(request, source_kind)
    require_recipe_ai_configured()

    thumbnail_url = None
    video_url: Optional[str] = None
    creator_name = ""
    instagram_caption = ""
    local_video_path: Optional[str] = None
    raw_text = ""
    data: dict = {}

    try:
        if is_youtube_url(url):
            yt_result = download_youtube_video(url)
            if not yt_result:
                raise HTTPException(status_code=500, detail="Failed to download YouTube video")
            local_video_path, creator_name = yt_result[0], yt_result[1] or ""
            raw_text = await analyze_local_video_path(
                local_video_path,
                req.language,
                [f"Original source URL: {url}"],
            )
        elif is_tiktok_url(url):
            tk_result = download_tiktok_video(url)
            if isinstance(tk_result, tuple):
                video_name = tk_result[0] if len(tk_result) > 0 else None
                creator_name = tk_result[1] if len(tk_result) > 1 and tk_result[1] else creator_name
            else:
                video_name = tk_result
            if not video_name:
                raise HTTPException(status_code=500, detail="Failed to download TikTok video")
            local_video_path = video_name
            raw_text = await analyze_local_video_path(
                video_name,
                req.language,
                [f"Original source URL: {url}"],
            )
        else:
            ig_result = download_instagram_reel(url)
            if not ig_result:
                raise HTTPException(status_code=429, detail="Failed to download video")
            video_name, creator_name, instagram_caption = ig_result
            creator_name = creator_name or ""
            if not video_name:
                raise HTTPException(status_code=429, detail="Failed to download video")
            local_video_path = video_name
            extra: list[str] = [f"Original source URL: {url}"]
            if instagram_caption:
                extra.append(
                    f"Instagram caption context (may include ingredients or steps):\n{instagram_caption}"
                )
            raw_text = await analyze_local_video_path(video_name, req.language, extra)
    except InstagramBlockedError as e:
        raise HTTPException(
            status_code=429,
            detail=(
                "Instagram temporarily blocked this server (rate limit/challenge). "
                "Please wait a few minutes and retry, or use a logged-in Instaloader session."
            ),
        ) from e
    except TikTokBlockedError as e:
        raise HTTPException(
            status_code=429,
            detail=(
                "TikTok temporarily blocked or rate-limited this server. "
                "Your import will retry automatically — please wait a few minutes."
            ),
        ) from e
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e)) from e
    except Exception as e:
        chain = " → ".join(recipe_ai_provider_chain())
        raise HTTPException(
            status_code=503,
            detail=f"Recipe AI failed (tried: {chain}). ({e})",
        ) from e

    try:
        data = extract_json_from_response(raw_text)
        normalize_instruction_timestamps(data)
        creator_name = creator_name or data.get("creator", "")
        if is_youtube_url(url):
            yt_author = await youtube_oembed_author_name(url)
            if yt_author:
                creator_name = yt_author
        hero_seconds = float(normalize_dish_hero_timestamp_seconds(data))
        if local_video_path and os.path.isfile(local_video_path):
            thumbnail_url = save_thumbnail_from_video(local_video_path, request, hero_seconds)
            video_url = persist_served_video(local_video_path, request)
    except json.JSONDecodeError as e:
        raise HTTPException(
            status_code=502,
            detail=f"Model response was not valid JSON: {e}. Raw (first 500 chars): {raw_text[:500]!r}",
        )
    except ValueError as e:
        raise HTTPException(
            status_code=502,
            detail=f"Model response error: {e}. Raw (first 500 chars): {raw_text[:500]!r}",
        )
    finally:
        if local_video_path and os.path.isfile(local_video_path):
            try:
                os.remove(local_video_path)
            except OSError:
                pass

    return RecipeResponse(
        recipe_name=data.get("recipe_name", "Untitled Recipe"),
        description=data.get("description", ""),
        creator=creator_name,
        estimated_cooking_time=str(data.get("estimated_cooking_time", "0")),
        prep_time=str(data.get("prep_time", "0")),
        estimated_servings=str(data.get("estimated_servings", "1")),
        ingredients=data.get("ingredients", []),
        instructions=data.get("instructions", []),
        video_url=video_url,
        thumbnail_url=thumbnail_url,
        dish_hero_timestamp_seconds=normalize_dish_hero_timestamp_seconds(data),
    )


@router.post("/analyze_video_upload", response_model=RecipeResponse)
async def analyze_video_upload(
    request: Request,
    file: UploadFile = File(...),
    language: str = Form(default="en"),
):
    require_recipe_ai_configured()
    await enforce_import_quota(request, "upload")

    thumbnail_url = None
    video_url: Optional[str] = None
    creator_name = ""
    suffix = upload_suffix(file.filename or "")
    tmp_path: Optional[str] = None
    raw_text = ""
    data: dict = {}

    try:
        fd, tmp_path = tempfile.mkstemp(suffix=suffix)
        os.close(fd)
        total = 0
        with open(tmp_path, "wb") as out:
            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    break
                total += len(chunk)
                if total > MAX_VIDEO_UPLOAD_BYTES:
                    raise HTTPException(status_code=413, detail="Video file too large")
                out.write(chunk)

        if total == 0:
            raise HTTPException(status_code=400, detail="Empty upload")

        raw_text = await analyze_local_video_path(tmp_path, language)
        data = extract_json_from_response(raw_text)
        normalize_instruction_timestamps(data)
        creator_name = creator_name or str(data.get("creator", "") or "")
        hero_seconds = float(normalize_dish_hero_timestamp_seconds(data))
        if os.path.isfile(tmp_path):
            thumbnail_url = save_thumbnail_from_video(tmp_path, request, hero_seconds)
            video_url = persist_served_video(tmp_path, request)
    except json.JSONDecodeError as e:
        raise HTTPException(
            status_code=502,
            detail=f"Model response was not valid JSON: {e}. Raw (first 500 chars): {raw_text[:500]!r}",
        )
    except ValueError as e:
        raise HTTPException(
            status_code=502,
            detail=f"Model response error: {e}. Raw (first 500 chars): {raw_text[:500]!r}",
        )
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e)) from e
    except Exception as e:
        chain = " → ".join(recipe_ai_provider_chain())
        raise HTTPException(
            status_code=503,
            detail=f"Recipe AI failed (tried: {chain}). ({e})",
        ) from e
    finally:
        if tmp_path and os.path.isfile(tmp_path):
            try:
                os.remove(tmp_path)
            except OSError:
                pass

    return RecipeResponse(
        recipe_name=data.get("recipe_name", "Untitled Recipe"),
        description=data.get("description", ""),
        creator=creator_name,
        estimated_cooking_time=str(data.get("estimated_cooking_time", "0")),
        prep_time=str(data.get("prep_time", "0")),
        estimated_servings=str(data.get("estimated_servings", "1")),
        ingredients=data.get("ingredients", []),
        instructions=data.get("instructions", []),
        video_url=video_url,
        thumbnail_url=thumbnail_url,
        dish_hero_timestamp_seconds=normalize_dish_hero_timestamp_seconds(data),
    )
