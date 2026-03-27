from fastapi import FastAPI, HTTPException, Request  # pyright: ignore[reportMissingImports]
from fastapi.middleware.cors import CORSMiddleware  # pyright: ignore[reportMissingImports]
from fastapi.responses import FileResponse  # pyright: ignore[reportMissingImports]
from pydantic import BaseModel  # pyright: ignore[reportMissingImports]
from google import genai
from google.genai import types  # pyright: ignore[reportMissingImports]
from download import download_instagram_reel, download_tiktok_video
import time
import json
import re
import os
import shutil
import uuid
from typing import Optional
from dotenv import load_dotenv  # pyright: ignore[reportMissingImports]
import httpx
load_dotenv()

app = FastAPI()

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

class RecipeResponse(BaseModel):
    recipe_name: str
    description: str
    creator: str = ""
    estimated_cooking_time: str = "0"
    prep_time: str = "0"
    ingredients: list
    instructions: list
    video_url: Optional[str] = None

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")  # pyright: ignore[reportOptionalMemberAccess]
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY")


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
    }}
    Guidelines:
    1. If specific quantities are not mentioned, use "As needed".
    2. Ensure the output is valid JSON only, with no introductory or concluding text.
    3. Try add some icons to each ingredient in the front.
    4. Make sure each step is short and concise.
    5. Please include prep_time and estimated_cooking_time as MINUTES in numeric string form (e.g. "5", "10"). Do NOT add words like "minutes".
    6. Make sure the creator name is right if it's a youtube video.
    7. Use language code {lang} for all user-facing text values (keys must stay in English)."""

    
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
    if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
        return

    user_id = request.headers.get("X-User-Id")
    if not user_id:
        # No user id; treat as anonymous free user – you can choose to block or allow.
        raise HTTPException(status_code=401, detail="Missing X-User-Id for AI usage tracking.")

    rpc_url = f"{SUPABASE_URL.rstrip('/')}/rest/v1/rpc/use_ai_once"
    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.post(
            rpc_url,
            headers={
                "apikey": SUPABASE_SERVICE_KEY,
                "Authorization": f"Bearer {SUPABASE_SERVICE_KEY}",
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
            json={"user_id": user_id},
        )
    if resp.status_code >= 400:
        # Surface a friendly error to the client.
        try:
            detail = resp.json()
        except Exception:
            detail = resp.text
        raise HTTPException(
            status_code=429,
            detail=f"AI usage limit reached or not allowed: {detail}",
        )



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


SERVED_VIDEOS_DIR = "served_videos"

@app.get("/video/{video_id}")
async def serve_video(video_id: str):
    """Serve a previously downloaded video file for in-app playback."""
    path = os.path.join(SERVED_VIDEOS_DIR, f"{video_id}.mp4")
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="Video not found")
    return FileResponse(path, media_type="video/mp4")

@app.post("/analyze_reel", response_model=RecipeResponse)
async def analyze_reel(request: Request, req: AnalyzeRequest):
    url = (req.url or "").strip()
    if not url:
        raise HTTPException(status_code=400, detail="URL is required")

    # Verify AI usage with Supabase before calling Gemini (if configured).
    await verify_ai_quota(request)
    client = genai.Client(api_key=GEMINI_API_KEY)
    current_prompt = build_prompt(req.language)
    video_url = None
    # Some platforms block creator metadata; keep it optional.
    creator_name = ""

    if is_youtube_url(url):
        # YouTube: send the link to Gemini directly (no download)
        video_part = types.Part.from_uri(file_uri=url, mime_type="video/mp4")
        response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=[current_prompt, video_part],
        )
    elif is_tiktok_url(url):
        # TikTok: download via tiktok-api-dl then upload file to Gemini
        tk_result = download_tiktok_video(url)
        # Support both legacy return shapes:
        # - "path.mp4"
        # - ("path.mp4", "author name")
        if isinstance(tk_result, tuple):
            videoName = tk_result[0] if len(tk_result) > 0 else None
            creator_name = tk_result[1] if len(tk_result) > 1 and tk_result[1] else creator_name
        else:
            videoName = tk_result
        if not videoName:
            raise HTTPException(status_code=500, detail="Failed to download TikTok video")
        video_file = client.files.upload(file=videoName)
        while video_file.state.name == "PROCESSING":
            print(".", end="")
            time.sleep(10)
            video_file = client.files.get(name=video_file.name)
        if video_file.state.name == "FAILED":
            raise HTTPException(status_code=500, detail="Video processing failed")
        response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=[current_prompt, video_file],
        )
        if os.path.isfile(videoName):
            os.makedirs(SERVED_VIDEOS_DIR, exist_ok=True)
            video_id = str(uuid.uuid4())
            dest = os.path.join(SERVED_VIDEOS_DIR, f"{video_id}.mp4")
            shutil.copy2(videoName, dest)
            base = str(request.base_url).rstrip("/")
            video_url = f"{base}/video/{video_id}"
    else:
        # Instagram (or other): download then upload file to Gemini
        ig_result = download_instagram_reel(url)
        if not ig_result:
            raise HTTPException(status_code=500, detail="Failed to download video")
        videoName, creator_name = ig_result
        creator_name = creator_name or ""
        if not videoName:
            raise HTTPException(status_code=500, detail="Failed to download video")
        video_file = client.files.upload(file=videoName)
        while video_file.state.name == "PROCESSING":
            print(".", end="")
            time.sleep(10)
            video_file = client.files.get(name=video_file.name)
        if video_file.state.name == "FAILED":
            raise HTTPException(status_code=500, detail="Video processing failed")
        response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=[current_prompt, video_file],
        )
        if os.path.isfile(videoName):
            os.makedirs(SERVED_VIDEOS_DIR, exist_ok=True)
            video_id = str(uuid.uuid4())
            dest = os.path.join(SERVED_VIDEOS_DIR, f"{video_id}.mp4")
            shutil.copy2(videoName, dest)
            base = str(request.base_url).rstrip("/")
            video_url = f"{base}/video/{video_id}"

    raw_text = getattr(response, "text", None) or ""
    try:
        data = extract_json_from_response(raw_text)
        creator_name = creator_name or data.get("creator", "")
        # YouTube: Gemini often guesses wrong; prefer oEmbed channel name.
        if is_youtube_url(url):
            yt_author = await youtube_oembed_author_name(url)
            if yt_author:
                creator_name = yt_author
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
    # Ensure keys expected by RecipeResponse exist (RecipeResponse has recipe_name, description, ingredients, instructions)
    return RecipeResponse(
        recipe_name=data.get("recipe_name", "Untitled Recipe"),
        description=data.get("description", ""),
        creator=creator_name,
        estimated_cooking_time=str(data.get("estimated_cooking_time", "0")),
        prep_time=str(data.get("prep_time", "0")),
        ingredients=data.get("ingredients", []),
        instructions=data.get("instructions", []),
        video_url=video_url,
    )


