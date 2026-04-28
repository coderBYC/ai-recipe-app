from pathlib import Path
from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile  # pyright: ignore[reportMissingImports]
from fastapi.middleware.cors import CORSMiddleware  # pyright: ignore[reportMissingImports]
from fastapi.responses import FileResponse  # pyright: ignore[reportMissingImports]
from pydantic import BaseModel  # pyright: ignore[reportMissingImports]
from google import genai
from google.genai import errors as genai_errors  # pyright: ignore[reportMissingImports]
from download import (
    download_instagram_reel,
    download_tiktok_video,
    InstagramBlockedError,
)
import asyncio
import time
import json
import re
import os
import uuid
import tempfile
from typing import Any, Callable, Optional, TypeVar
from dotenv import load_dotenv  # pyright: ignore[reportMissingImports]
import httpx
import cv2
from supabase import create_client  # pyright: ignore[reportMissingImports]
from postgrest.exceptions import APIError  # pyright: ignore[reportMissingImports]
from datetime import datetime, timezone
from worker import ImportQueueWorker
load_dotenv()

app = FastAPI()


@app.on_event("startup")
async def _log_registered_upload_routes() -> None:
    """Helps verify the running process includes the multipart upload route (if empty, you are on an old build)."""
    lines: list[str] = []
    for route in app.routes:
        path = getattr(route, "path", "") or ""
        methods = getattr(route, "methods", None) or set()
        if "upload" in path and "POST" in methods:
            lines.append(f"POST {path}")
    print("[RecipeBackend] Registered upload routes:", lines if lines else "NONE (old code or import error?)")


@app.on_event("startup")
async def _start_import_worker() -> None:
    global _import_worker
    if _import_worker is not None:
        return
    _import_worker = ImportQueueWorker(
        concurrency=_IMPORT_WORKER_CONCURRENCY,
        poll_interval_sec=_IMPORT_POLL_INTERVAL_SEC,
        scan_batch=_IMPORT_SCAN_BATCH,
        retry_after_429_sec=_IMPORT_RETRY_AFTER_429_SEC,
        local_api_base=_IMPORT_WORKER_LOCAL_API_BASE,
        jobs_table=_IMPORT_JOBS_TABLE,
        get_supabase=_get_supabase,
        supabase_call=_supabase_call,
    )
    await _import_worker.start()


@app.on_event("shutdown")
async def _stop_import_worker() -> None:
    global _import_worker
    if _import_worker is None:
        return
    await _import_worker.stop()
    _import_worker = None


app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class AnalyzeRequest(BaseModel):
    url: str
    language: str

class ImportEnqueueRequest(BaseModel):
    url: str
    language: str = "en"

class ImportBatchEnqueueRequest(BaseModel):
    jobs: list[ImportEnqueueRequest]

class ImportJobView(BaseModel):
    id: str
    url: str
    user_id: str
    source_type: str = "other"
    status: str
    created_at: Optional[str] = None
    updated_at: Optional[str] = None
    error_log: Optional[str] = None
    result_json: Optional[dict[str, Any]] = None

class RecipeResponse(BaseModel):
    recipe_name: str
    description: str
    creator: str = ""
    estimated_cooking_time: str = "0"
    prep_time: str = "0"
    ingredients: list
    instructions: list
    video_url: Optional[str] = None
    thumbnail_url: Optional[str] = None
    dish_hero_timestamp_seconds: str = "0"

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")  # pyright: ignore[reportOptionalMemberAccess]
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY")
PUBLIC_BASE_URL = os.getenv("PUBLIC_BASE_URL", "").strip().rstrip("/")
FREE_IMPORTS_PER_DAY = 5
FREE_INSTAGRAM_COOLDOWN_SECONDS = 1 * 60

# In-memory rate state for free users (per backend instance/process).
# If you run multiple replicas, move this to shared storage (e.g. Redis/Postgres).
_free_daily_import_usage: dict[str, tuple[str, int]] = {}
_free_last_instagram_import_at: dict[str, float] = {}


_IMPORT_JOBS_TABLE = "import_jobs"
_IMPORT_POLL_INTERVAL_SEC = max(1.0, float(os.getenv("IMPORT_POLL_INTERVAL_SEC", "2")))
_IMPORT_SCAN_BATCH = max(1, int(os.getenv("IMPORT_SCAN_BATCH", "10")))
_IMPORT_WORKER_CONCURRENCY = max(1, int(os.getenv("IMPORT_WORKER_CONCURRENCY", "2")))
_IMPORT_RETRY_AFTER_429_SEC = max(5.0, float(os.getenv("IMPORT_RETRY_AFTER_429_SEC", "300")))
_LOCAL_PORT = (os.getenv("PORT") or "8000").strip() or "8000"
_IMPORT_WORKER_LOCAL_API_BASE = os.getenv(
    "IMPORT_WORKER_LOCAL_API_BASE",
    f"http://127.0.0.1:{_LOCAL_PORT}",
).strip().rstrip("/")
_ANALYZE_QUEUE_WAIT_TIMEOUT_SEC = max(5.0, float(os.getenv("ANALYZE_QUEUE_WAIT_TIMEOUT_SEC", "240")))
_ANALYZE_QUEUE_WAIT_POLL_SEC = max(0.2, float(os.getenv("ANALYZE_QUEUE_WAIT_POLL_SEC", "1.0")))
_import_worker: Optional["ImportQueueWorker"] = None

_supabase_client: Any = None
def _get_supabase() -> Optional[Any]:
    """Lazily create a Supabase client with the service role key (server-side only)."""
    global _supabase_client
    if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
        return None
    if _supabase_client is None:
        _supabase_client = create_client(
            SUPABASE_URL.strip().rstrip("/"),
            SUPABASE_SERVICE_KEY.strip(),
        )
    return _supabase_client

T = TypeVar("T")
async def _supabase_call(fn: Callable[[], T]) -> T:
    """Run sync supabase-py calls in a thread pool (FastAPI async routes)."""
    return await asyncio.to_thread(fn)


def _api_error_detail(exc: APIError) -> str:
    parts = [exc.message or "Supabase error"]
    if exc.details:
        parts.append(str(exc.details))
    if exc.hint:
        parts.append(str(exc.hint))
    return " — ".join(parts)


def build_prompt(language: str) -> str:
    """Builds the Gemini prompt, telling it which language to use for values."""
    lang = language.lower()
    print(lang)
    return f"""Analyze the attached cooking video. 
    Extract the recipe and output the result strictly in JSON format. JSON keys must be English.
    The JSON structure must match this template:
    {{
    "recipe_name": "Title of the dish",
    "creator": "Name of the creator",
    "prep_time": "5",
    "estimated_cooking_time": "10",
    "description": "A short summary of the dish based on the video context",
    "ingredients": [
        {{
        "item": "🍔Ingredient Name",
        "amount": "Quantity and unit" 
        }}
    ],
    "instructions": [
        {{
        "step": 1,
        "description": "Detailed description of this cooking step"
        }},
    ],
    "dish_hero_timestamp_seconds": "0"
    }}
    Guidelines:
    1. If specific quantities are not mentioned, use "As needed".
    2. Ensure the output is valid JSON only, with no introductory or concluding text.
    3. Try add some icons to each ingredient in the front.
    4. Make sure each step is concise, don't include timestamps.
    5. Please include prep_time and estimated_cooking_time as MINUTES in numeric string form (e.g. "5", "10"). Do NOT add words like "minutes".
    6. Make sure the creator name is right if it's a youtube video.
    7. Use language code {lang} for all user-facing text values (keys must stay in English).
    8. Set "dish_hero_timestamp_seconds" to a single number as a string (seconds from the start of the video, e.g. "42" or "12.5") for the best moment the final dish is shown clearly and in focus. If you don't know, use the last second of the video."""

    
def _require_user_id(request: Request) -> str:
    """Supabase auth user id from the app (same header as analyze routes)."""
    user_id = (request.headers.get("X-User-Id") or "").strip()
    if not user_id:
        raise HTTPException(status_code=401, detail="Missing X-User-Id.")
    return user_id


async def supabase_rpc_use_export_once(user_id: str) -> None:
    sb = _get_supabase()
    if not sb:
        return

    def _rpc() -> None:
        sb.rpc("use_export_once", {"user_id": user_id}).execute()

    try:
        print(f"supabase_rpc_use_export_once: {user_id}")
        await _supabase_call(_rpc)
        
    except APIError as e:
        raise HTTPException(
            status_code=429,
            detail=f"Export usage limit reached or not allowed: {_api_error_detail(e)}",
        ) from e


async def supabase_update_profile_plan(user_id: str, plan_type: str) -> None:
    """PATCH `profiles.plan_type` for the given user (service role). No-op if Supabase is not configured."""
    sb = _get_supabase()
    if not sb:
        return

    def _patch() -> None:
        sb.table("profiles").update({"plan_type": plan_type}).eq("id", user_id).execute()

    try:
        await _supabase_call(_patch)
    except APIError as e:
        raise HTTPException(
            status_code=400,
            detail=f"Could not update subscription plan: {_api_error_detail(e)}",
        ) from e


class PlanUpdateRequest(BaseModel):
    plan_type: str


async def verify_ai_quota(request: Request) -> None:
    """
    Optional server-side check with Supabase before using Gemini.
    Expects SUPABASE_URL and SUPABASE_SERVICE_KEY in the environment, and
    an X-User-Id header with the Supabase auth user id.

    This function calls the Postgres RPC `use_ai_once` which should:
    - Check the user's plan_type and remaining ai_usage_count
    - Increment ai_usage_count if allowed
    - Raise an error if the limit is reached
    """
    sb = _get_supabase()
    if not sb:
        return

    user_id = request.headers.get("X-User-Id")
    if not user_id:
        # No user id; treat as anonymous free user – you can choose to block or allow.
        raise HTTPException(status_code=401, detail="Missing X-User-Id for AI usage tracking.")

    def _rpc() -> None:
        sb.rpc("use_ai_once", {"user_id": user_id}).execute()

    try:
        await _supabase_call(_rpc)
    except APIError as e:
        raise HTTPException(
            status_code=429,
            detail=f"AI usage limit reached or not allowed: {_api_error_detail(e)}",
        ) from e


async def is_pro_user(request: Request) -> bool:
    """
    Determine Pro entitlement for deciding whether we generate/store a downloadable video.

    Priority:
    1) If the app sends `X-Is-Pro`, use it (RevenueCat entitlement).
    2) Otherwise, fall back to Supabase `profiles.plan_type`.
    """
    header_plan = (request.headers.get("X-Is-Pro") or "").strip().lower()
    if header_plan:
        return header_plan in {"true", "1", "pro", "premium", "yes"}

    sb = _get_supabase()
    if not sb:
        return False

    user_id = request.headers.get("X-User-Id")
    if not user_id:
        return False

    def _fetch_plan() -> str:
        res = sb.table("profiles").select("plan_type").eq("id", user_id).limit(1).execute()
        rows = getattr(res, "data", None) or []
        if not rows:
            return ""
        return str((rows[0] or {}).get("plan_type") or "").strip().lower()

    try:
        plan = await _supabase_call(_fetch_plan)
        return plan == "pro"
    except Exception:
        return False


async def youtube_oembed_author_name(video_url: str) -> str:
    """Official channel display name from YouTube oEmbed (no API key)."""
    try:
        api = "https://www.youtube.com/oembed"
        params = {"url": video_url.strip(), "format": "json"}
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(api, params=params)
        if resp.status_code != 200:
            return ""
        payload = resp.json()
        name = (payload.get("author_name") or "").strip()
        return name
    except Exception:
        return ""


def is_youtube_url(url: str) -> bool:
    """Return True if the URL is a YouTube video (youtube.com or youtu.be)."""
    u = (url or "").lower().strip()
    return "youtube.com" in u or "youtu.be" in u


def is_tiktok_url(url: str) -> bool:
    """Return True if the URL is a TikTok video (tiktok.com or vt.tiktok.com)."""
    u = (url or "").lower().strip()
    return "tiktok.com" in u or "vt.tiktok.com" in u


def is_instagram_url(url: str) -> bool:
    """Return True if the URL is an Instagram link."""
    u = (url or "").lower().strip()
    return "instagram.com" in u or "instagr.am" in u


async def enforce_free_import_limits(request: Request, source_kind: str) -> None:
    """
    Free users:
      1) max 5 imports per UTC day
      2) Instagram imports: at most once every 10 minutes
    """
    if await is_pro_user(request):
        return

    user_id = _require_user_id(request)
    now = datetime.now(timezone.utc).timestamp()
    day_key = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    stored_day, used = _free_daily_import_usage.get(user_id, (day_key, 0))
    if stored_day != day_key:
        used = 0

    if used >= FREE_IMPORTS_PER_DAY:
        raise HTTPException(
            status_code=429,
            detail=f"Free plan limit reached: {FREE_IMPORTS_PER_DAY} imports per day.",
        )

    if source_kind == "instagram":
        last_at = _free_last_instagram_import_at.get(user_id)
        if last_at is not None:
            elapsed = now - last_at
            if elapsed < FREE_INSTAGRAM_COOLDOWN_SECONDS:
                remaining = int(FREE_INSTAGRAM_COOLDOWN_SECONDS - elapsed)
                mins = max(1, remaining // 60)
                raise HTTPException(
                    status_code=429,
                    detail=f"Free plan Instagram cooldown: try again in about {mins} minute(s).",
                )

    # Record successful reservation of this import slot.
    _free_daily_import_usage[user_id] = (day_key, used + 1)
    if source_kind == "instagram":
        _free_last_instagram_import_at[user_id] = now


def normalize_dish_hero_timestamp_seconds(data: dict) -> str:
    """Coerce model output to a non-negative seconds string for the API response."""
    raw = data.get("dish_hero_timestamp_seconds")
    if raw is None:
        return "0"
    s = str(raw).strip().replace(",", ".")
    if not s:
        return "0"
    try:
        v = float(s)
        if v != v or v < 0:  # NaN or negative
            return "0"
        return str(v)
    except ValueError:
        pass
    m = re.search(r"[\d.]+", s)
    if m:
        try:
            v = float(m.group(0))
            return str(max(0.0, v))
        except ValueError:
            pass
    return "0"


def extract_json_from_response(raw: str) -> dict:
    """Extract JSON from Gemini output, which may be wrapped in markdown code blocks or have extra text."""
    if not raw or not raw.strip():
        raise ValueError("Model returned empty response")
    text = raw.strip()
    # Strip markdown code block if present (e.g. ```json ... ``` or ``` ... ```)
    code_block = re.search(r"```(?:json)?\s*([\s\S]*?)\s*```", text)
    if code_block:
        text = code_block.group(1).strip()
    # Find first { and last } to get a single JSON object
    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end != -1 and end > start:
        text = text[start : end + 1]
    return json.loads(text)


def _generate_content_with_retry(client: genai.Client, contents, attempts: int = 3):
    """Retry transient Gemini overload errors before failing."""
    last_err = None
    for idx in range(attempts):
        try:
            return client.models.generate_content(
                model="gemini-2.5-flash",
                contents=contents,
            )
        except genai_errors.ServerError as e:
            last_err = e
            # Typical transient: 503 UNAVAILABLE (high demand)
            if idx < attempts - 1:
                time.sleep(2 * (idx + 1))
                continue
            raise
    if last_err:
        raise last_err
    raise RuntimeError("Gemini generation failed without an explicit error.")


def _gemini_file_poll_interval_sec() -> float:
    """Poll Gemini Files API while uploaded video is PROCESSING (was 10s; default 3s)."""
    try:
        v = float(os.getenv("GEMINI_FILE_POLL_INTERVAL_SEC", "3"))
    except ValueError:
        v = 3.0
    return max(1.0, min(v, 15.0))


def _gemini_file_poll_max_sec() -> float:
    try:
        return max(30.0, float(os.getenv("GEMINI_FILE_POLL_MAX_SEC", "600")))
    except ValueError:
        return 600.0


async def _wait_for_gemini_file_ready(client: genai.Client, video_file):
    """Poll until Gemini finishes indexing the uploaded file; uses asyncio.sleep (non-blocking for other requests)."""
    interval = _gemini_file_poll_interval_sec()
    deadline = time.monotonic() + _gemini_file_poll_max_sec()
    while video_file.state.name == "PROCESSING":
        if time.monotonic() > deadline:
            raise HTTPException(
                status_code=504,
                detail="Timed out waiting for Gemini to process the video file. Try a shorter clip or retry later.",
            )
        print(".", end="", flush=True)
        await asyncio.sleep(interval)
        video_file = client.files.get(name=video_file.name)
    if video_file.state.name == "FAILED":
        raise HTTPException(status_code=500, detail="Video processing failed")
    return video_file


SERVED_THUMBS_DIR = "served_thumbnails"
MAX_VIDEO_UPLOAD_BYTES = 200 * 1024 * 1024
ALLOWED_VIDEO_SUFFIXES = {".mp4", ".mov", ".m4v", ".mpeg", ".mpg"}


def _upload_suffix(filename: str) -> str:
    ext = Path(filename or "").suffix.lower()
    return ext if ext in ALLOWED_VIDEO_SUFFIXES else ".mp4"


def _save_thumbnail_from_video(video_path: str, request: Request, seconds: float) -> Optional[str]:
    """
    Extract one frame from `video_path` and persist it as a JPG served by this backend.
    Returns absolute thumbnail URL or None on failure.
    """
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return None
    try:
        fps = cap.get(cv2.CAP_PROP_FPS) or 0.0
        frame_count = cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0.0
        if fps > 0 and frame_count > 0:
            duration = frame_count / fps
            target_sec = max(0.0, min(seconds, duration * 0.99))
        else:
            target_sec = max(0.0, seconds)
        cap.set(cv2.CAP_PROP_POS_MSEC, target_sec * 1000.0)
        ok, frame = cap.read()
        if not ok or frame is None:
            cap.set(cv2.CAP_PROP_POS_MSEC, 0)
            ok, frame = cap.read()
            if not ok or frame is None:
                return None
        os.makedirs(SERVED_THUMBS_DIR, exist_ok=True)
        thumb_id = str(uuid.uuid4())
        out_path = os.path.join(SERVED_THUMBS_DIR, f"{thumb_id}.jpg")
        if not cv2.imwrite(out_path, frame):
            return None
        base = PUBLIC_BASE_URL if PUBLIC_BASE_URL else str(request.base_url).rstrip("/")
        return f"{base}/thumbnail/{thumb_id}"
    finally:
        cap.release()


@app.post("/usage/export_once")
async def usage_export_once(request: Request):
    """
    Records one recipe export/share against the user's quota (Supabase RPC `use_export_once`).
    """
    user_id = _require_user_id(request)
    print(f"usage_export_once: {user_id}")
    await supabase_rpc_use_export_once(user_id)
    return {"ok": True}


@app.post("/profile/plan")
async def profile_update_plan(request: Request, body: PlanUpdateRequest):
    """
    Mirrors RevenueCat entitlement to `profiles.plan_type` (e.g. pro / free).
    """
    user_id = _require_user_id(request)
    raw = (body.plan_type or "").strip().lower()
    if raw not in {"pro", "free"}:
        raise HTTPException(status_code=400, detail="plan_type must be 'pro' or 'free'")
    await supabase_update_profile_plan(user_id, raw)
    return {"ok": True}

def _source_type_for_url(url: str) -> str:
    u = (url or "").lower()
    if "instagram.com" in u or "instagr.am" in u:
        return "instagram"
    if "tiktok.com" in u or "vt.tiktok.com" in u:
        return "tiktok"
    if "youtube.com" in u or "youtu.be" in u:
        return "youtube"
    return "other"


async def _enqueue_import_job(*, user_id: str, url: str, language: str) -> dict[str, Any]:
    sb = _get_supabase()
    if not sb:
        raise HTTPException(status_code=503, detail="Supabase is not configured on the server.")

    def _insert() -> Any:
        return (
            sb.table(_IMPORT_JOBS_TABLE)
            .insert(
                {
                    "url": url,
                    "user_id": user_id,
                    "source_type": _source_type_for_url(url),
                    "status": "pending",
                }
            )
            .execute()
        )

    try:
        job = await _supabase_call(_insert)
    except APIError as e:
        raise HTTPException(status_code=400, detail=f"Supabase insert failed: {e.message}") from e
    rows = getattr(job, "data", None) or []
    if not rows:
        raise HTTPException(status_code=500, detail="Supabase insert returned no row.")
    if _import_worker:
        await _import_worker.nudge()
    return rows[0]


async def _wait_for_job_result(*, user_id: str, job_id: str, timeout_sec: float) -> dict[str, Any]:
    sb = _get_supabase()
    if not sb:
        raise HTTPException(status_code=503, detail="Supabase is not configured on the server.")

    async def _load_once() -> Optional[dict[str, Any]]:
        def _q() -> Any:
            return (
                sb.table(_IMPORT_JOBS_TABLE)
                .select("id,status,error_log,result_json")
                .eq("id", job_id)
                .eq("user_id", user_id)
                .limit(1)
                .execute()
            )
        try:
            res = await _supabase_call(_q)
        except APIError as e:
            raise HTTPException(
                status_code=400,
                detail=f"Supabase job polling failed: {_api_error_detail(e)}",
            ) from e
        rows = getattr(res, "data", None) or []
        if not rows:
            return None
        return rows[0] if isinstance(rows[0], dict) else None

    deadline = time.monotonic() + timeout_sec
    while time.monotonic() < deadline:
        row = await _load_once()
        if row:
            status = str(row.get("status") or "").lower()
            if status == "ready":
                payload = row.get("result_json")
                if isinstance(payload, dict):
                    return payload
                raise HTTPException(status_code=502, detail="Import finished without valid result_json.")
            if status == "failed":
                msg = row.get("error_log") or "Import failed."
                raise HTTPException(status_code=502, detail=str(msg))
        await asyncio.sleep(_ANALYZE_QUEUE_WAIT_POLL_SEC)
    raise HTTPException(status_code=504, detail="Queued import timed out waiting for result.")


@app.post("/import")
async def enqueue_import(request: Request, body: ImportEnqueueRequest):
    user_id = _require_user_id(request)
    url = (body.url or "").strip()
    if not url:
        raise HTTPException(status_code=400, detail="URL is required")
    language = (body.language or "en").strip() or "en"
    row = await _enqueue_import_job(user_id=user_id, url=url, language=language)
    return {"job_id": row["id"], "status": "pending"}


@app.post("/import/batch")
async def enqueue_import_batch(request: Request, body: ImportBatchEnqueueRequest):
    sb = _get_supabase()
    if not sb:
        raise HTTPException(status_code=503, detail="Supabase is not configured on the server.")
    user_id = _require_user_id(request)
    jobs = body.jobs or []
    if not jobs:
        raise HTTPException(status_code=400, detail="No jobs provided.")

    rows_to_insert = [
        {
            "url": (job.url or "").strip(),
            "user_id": user_id,
            "source_type": _source_type_for_url(job.url),
            "status": "pending",
        }
        for job in jobs
        if (job.url or "").strip()
    ]
    if not rows_to_insert:
        raise HTTPException(status_code=400, detail="All job URLs are empty.")

    def _insert_many() -> Any:
        return sb.table(_IMPORT_JOBS_TABLE).insert(rows_to_insert).execute()

    try:
        inserted = await _supabase_call(_insert_many)
    except APIError as e:
        raise HTTPException(status_code=400, detail=f"Supabase insert failed: {_api_error_detail(e)}") from e

    rows = getattr(inserted, "data", None) or []
    if _import_worker:
        await _import_worker.nudge()
    return {
        "count": len(rows),
        "job_ids": [r.get("id") for r in rows if isinstance(r, dict)],
        "status": "pending",
    }


@app.get("/import/jobs", response_model=list[ImportJobView])
async def list_import_jobs(
    request: Request,
    status: Optional[str] = None,
    limit: int = 50,
):
    """
    Poll queue state for current user.
    Supports optional status filter (`pending|processing|ready|failed`).
    """
    sb = _get_supabase()
    if not sb:
        raise HTTPException(status_code=503, detail="Supabase is not configured on the server.")
    user_id = _require_user_id(request)
    capped_limit = max(1, min(limit, 200))

    def _query() -> Any:
        q = (
            sb.table(_IMPORT_JOBS_TABLE)
            .select("id,url,user_id,source_type,status,created_at,updated_at,error_log,result_json")
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .limit(capped_limit)
        )
        if status:
            q = q.eq("status", status.strip().lower())
        return q.execute()

    try:
        res = await _supabase_call(_query)
    except APIError as e:
        raise HTTPException(status_code=400, detail=f"Supabase query failed: {_api_error_detail(e)}") from e
    rows = getattr(res, "data", None) or []
    return [ImportJobView(**row) for row in rows if isinstance(row, dict)]


@app.get("/import/jobs/{job_id}", response_model=ImportJobView)
async def get_import_job(job_id: str, request: Request):
    """
    Fetch one job by id for the current user (includes `result_json` once ready).
    """
    sb = _get_supabase()
    if not sb:
        raise HTTPException(status_code=503, detail="Supabase is not configured on the server.")
    user_id = _require_user_id(request)
    rid = (job_id or "").strip()
    if not rid:
        raise HTTPException(status_code=400, detail="job_id is required")

    def _query_one() -> Any:
        return (
            sb.table(_IMPORT_JOBS_TABLE)
            .select("id,url,user_id,source_type,status,created_at,updated_at,error_log,result_json")
            .eq("id", rid)
            .eq("user_id", user_id)
            .limit(1)
            .execute()
        )

    try:
        res = await _supabase_call(_query_one)
    except APIError as e:
        raise HTTPException(status_code=400, detail=f"Supabase query failed: {_api_error_detail(e)}") from e
    rows = getattr(res, "data", None) or []
    if not rows:
        raise HTTPException(status_code=404, detail="Import job not found")
    return ImportJobView(**rows[0])


@app.get("/thumbnail/{thumb_id}")
async def serve_thumbnail(thumb_id: str):
    """Serve generated JPG thumbnail extracted from analyzed video."""
    path = os.path.join(SERVED_THUMBS_DIR, f"{thumb_id}.jpg")
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="Thumbnail not found")
    return FileResponse(path, media_type="image/jpeg")

@app.post("/analyze_reel")
async def analyze_reel_enqueue(request: Request, req: AnalyzeRequest, wait: bool = True):
    """
    Queue-only entrypoint for app traffic.
    Stores job in `import_jobs`; worker handles processing asynchronously.
    """
    user_id = _require_user_id(request)
    url = (req.url or "").strip()
    if not url:
        raise HTTPException(status_code=400, detail="URL is required")
    language = (req.language or "en").strip() or "en"
    row = await _enqueue_import_job(user_id=user_id, url=url, language=language)
    if not wait:
        return {"job_id": row["id"], "status": "pending"}
    payload = await _wait_for_job_result(
        user_id=user_id,
        job_id=str(row["id"]),
        timeout_sec=_ANALYZE_QUEUE_WAIT_TIMEOUT_SEC,
    )
    return RecipeResponse(
        recipe_name=payload.get("recipe_name", "Untitled Recipe"),
        description=payload.get("description", ""),
        creator=payload.get("creator", ""),
        estimated_cooking_time=str(payload.get("estimated_cooking_time", "0")),
        prep_time=str(payload.get("prep_time", "0")),
        ingredients=payload.get("ingredients", []),
        instructions=payload.get("instructions", []),
        video_url=payload.get("video_url"),
        thumbnail_url=payload.get("thumbnail_url"),
        dish_hero_timestamp_seconds=str(payload.get("dish_hero_timestamp_seconds", "0")),
    )


@app.post("/analyze_reel/process", response_model=RecipeResponse, include_in_schema=False)
async def analyze_reel_process(request: Request, req: AnalyzeRequest):
    url = (req.url or "").strip()
    if not url:
        raise HTTPException(status_code=400, detail="URL is required")

    # Verify AI usage with Supabase before calling Gemini (if configured).
    await verify_ai_quota(request)
    source_kind = "instagram"
    if is_youtube_url(url):
        source_kind = "youtube"
    elif is_tiktok_url(url):
        source_kind = "tiktok"
    await enforce_free_import_limits(request, source_kind)
    client = genai.Client(api_key=GEMINI_API_KEY)
    current_prompt = build_prompt(req.language)
    thumbnail_url = None
    # Some platforms block creator metadata; keep it optional.
    creator_name = ""
    instagram_caption = ""
    local_video_path: Optional[str] = None

    try:
        if is_youtube_url(url):
            # YouTube: pass the source URL as fileData.fileUri for stronger grounding.
            response = _generate_content_with_retry(
                client,
                [
                    current_prompt,
                    {
                        "fileData": {
                            "fileUri": url,
                        }
                    },
                ],
            )
        elif is_tiktok_url(url):
            # TikTok: download via tiktok-api-dl then upload file to Gemini
            tk_result = download_tiktok_video(url)
            if isinstance(tk_result, tuple):
                videoName = tk_result[0] if len(tk_result) > 0 else None
                creator_name = tk_result[1] if len(tk_result) > 1 and tk_result[1] else creator_name
            else:
                videoName = tk_result
            if not videoName:
                raise HTTPException(status_code=500, detail="Failed to download TikTok video")
            local_video_path = videoName
            video_file = client.files.upload(file=videoName)
            video_file = await _wait_for_gemini_file_ready(client, video_file)
            response = _generate_content_with_retry(
                client,
                [
                    current_prompt,
                    f"Original source URL: {url}",
                    video_file,
                ],
            )
        else:
            # Instagram (or other): download then upload file to Gemini
            ig_result = download_instagram_reel(url)
            if not ig_result:
                raise HTTPException(status_code=500, detail="Failed to download video")
            videoName, creator_name, instagram_caption = ig_result
            creator_name = creator_name or ""
            if not videoName:
                raise HTTPException(status_code=500, detail="Failed to download video")
            local_video_path = videoName
            video_file = client.files.upload(file=videoName)
            video_file = await _wait_for_gemini_file_ready(client, video_file)
            extra_caption_context = (
                f"Instagram caption context (may include ingredients or steps):\n{instagram_caption}"
                if instagram_caption
                else ""
            )
            contents = [current_prompt]
            contents.append(f"Original source URL: {url}")
            if extra_caption_context:
                contents.append(extra_caption_context)
            contents.append(video_file)
            response = _generate_content_with_retry(client, contents)
    except InstagramBlockedError as e:
        raise HTTPException(
            status_code=429,
            detail=(
                "Instagram temporarily blocked this server (rate limit/challenge). "
                "Please wait a few minutes and retry, or use a logged-in Instaloader session."
            ),
        ) from e
    except genai_errors.ServerError as e:
        # Avoid leaking as 500 when Gemini is overloaded/transiently unavailable.
        raise HTTPException(
            status_code=503,
            detail=f"Gemini temporarily unavailable. Please retry in a moment. ({e})",
        )
    except genai_errors.APIError as e:
        raise HTTPException(
            status_code=502,
            detail=f"Gemini API error: {e}",
        )

    raw_text = getattr(response, "text", None) or ""
    try:
        data = extract_json_from_response(raw_text)
        creator_name = creator_name or data.get("creator", "")
        if is_youtube_url(url):
            yt_author = await youtube_oembed_author_name(url)
            if yt_author:
                creator_name = yt_author
        hero_seconds = float(normalize_dish_hero_timestamp_seconds(data))
        if local_video_path and os.path.isfile(local_video_path):
            thumbnail_url = _save_thumbnail_from_video(local_video_path, request, hero_seconds)
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
    # Ensure keys expected by RecipeResponse exist (RecipeResponse has recipe_name, description, ingredients, instructions)
    return RecipeResponse(
        recipe_name=data.get("recipe_name", "Untitled Recipe"),
        description=data.get("description", ""),
        creator=creator_name,
        estimated_cooking_time=str(data.get("estimated_cooking_time", "0")),
        prep_time=str(data.get("prep_time", "0")),
        ingredients=data.get("ingredients", []),
        instructions=data.get("instructions", []),
        video_url=None,
        thumbnail_url=thumbnail_url,
        dish_hero_timestamp_seconds=normalize_dish_hero_timestamp_seconds(data),
    )


# Keep alternate path variants for internal worker/proxy compatibility.
app.add_api_route(
    "/analyze_reel/process/",
    analyze_reel_process,
    methods=["POST"],
    response_model=RecipeResponse,
    include_in_schema=False,
)
app.add_api_route(
    "/api/analyze_reel/process",
    analyze_reel_process,
    methods=["POST"],
    response_model=RecipeResponse,
    include_in_schema=False,
)
app.add_api_route(
    "/api/analyze_reel/process/",
    analyze_reel_process,
    methods=["POST"],
    response_model=RecipeResponse,
    include_in_schema=False,
)


@app.post("/analyze_video_upload", response_model=RecipeResponse)
async def analyze_video_upload(
    request: Request,
    file: UploadFile = File(...),
    language: str = Form(default="en"),
    ):
    if not GEMINI_API_KEY:
        raise HTTPException(status_code=500, detail="Gemini API key not configured")

    await verify_ai_quota(request)
    await enforce_free_import_limits(request, "upload")
    client = genai.Client(api_key=GEMINI_API_KEY)
    current_prompt = build_prompt(language)
    thumbnail_url = None
    creator_name = ""

    suffix = _upload_suffix(file.filename or "")
    tmp_path: Optional[str] = None
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

        video_file = client.files.upload(file=tmp_path)
        video_file = await _wait_for_gemini_file_ready(client, video_file)
        response = _generate_content_with_retry(client, [current_prompt, video_file])
    except genai_errors.ServerError as e:
        raise HTTPException(
            status_code=503,
            detail=f"Gemini temporarily unavailable. Please retry in a moment. ({e})",
        ) from e
    except genai_errors.APIError as e:
        raise HTTPException(
            status_code=502,
            detail=f"Gemini API error: {e}",
        ) from e
    finally:
        if tmp_path and os.path.isfile(tmp_path):
            try:
                os.remove(tmp_path)
            except OSError:
                pass

    raw_text = getattr(response, "text", None) or ""
    try:
        data = extract_json_from_response(raw_text)
        creator_name = creator_name or str(data.get("creator", "") or "")
        hero_seconds = float(normalize_dish_hero_timestamp_seconds(data))
        if tmp_path and os.path.isfile(tmp_path):
            thumbnail_url = _save_thumbnail_from_video(tmp_path, request, hero_seconds)
    except json.JSONDecodeError as e:
        raise HTTPException(
            status_code=502,
            detail=f"Model response was not valid JSON: {e}. Raw (first 500 chars): {raw_text[:500]!r}",
        ) from e
    except ValueError as e:
        raise HTTPException(
            status_code=502,
            detail=f"Model response error: {e}. Raw (first 500 chars): {raw_text[:500]!r}",
        ) from e

    return RecipeResponse(
        recipe_name=data.get("recipe_name", "Untitled Recipe"),
        description=data.get("description", ""),
        creator=creator_name,
        estimated_cooking_time=str(data.get("estimated_cooking_time", "0")),
        prep_time=str(data.get("prep_time", "0")),
        ingredients=data.get("ingredients", []),
        instructions=data.get("instructions", []),
        video_url=None,
        thumbnail_url=thumbnail_url,
        dish_hero_timestamp_seconds=normalize_dish_hero_timestamp_seconds(data),
    )













# Same handler on alternate paths: trailing slash (avoids redirect/body issues) and /api for proxies.
app.add_api_route(
    "/analyze_video_upload/",
    analyze_video_upload,
    methods=["POST"],
    response_model=RecipeResponse,
    include_in_schema=False,
)
app.add_api_route(
    "/api/analyze_video_upload",
    analyze_video_upload,
    methods=["POST"],
    response_model=RecipeResponse,
    include_in_schema=False,
)
app.add_api_route(
    "/api/analyze_video_upload/",
    analyze_video_upload,
    methods=["POST"],
    response_model=RecipeResponse,
    include_in_schema=False,
)


