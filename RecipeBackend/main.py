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
    ingredients: list
    instructions: list
    video_url: Optional[str] = None

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")  # pyright: ignore[reportOptionalMemberAccess]


def build_prompt(language: str) -> str:
    """Builds the Gemini prompt, telling it which language to use for values."""
    lang = (language or "en").lower()
    return f"""Analyze the attached cooking video. 
    Extract the recipe and output the result strictly in JSON format using English for all keys and values.
    The JSON structure must match this template:
    {{
    "recipe_name": "Title of the dish",
    "creator": "Name of the creator",
    "estimated_cooking_time": "Estimated cooking time in minutes",
    "description": "A short summary of the dish based on the video context",
    "ingredients": [
        {{
        "item": "Ingredient Name",
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
    3. Try add some icons to each ingredient.
    4. Make sure each step is short and concise.
    5. Please include estimated cooking time.
    6. Use language code '{lang}' for all user-facing text values (keys must stay in English)."""


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
    language = (req.language or "en").strip()
    if not url:
        raise HTTPException(status_code=400, detail="URL is required")
    client = genai.Client(api_key=GEMINI_API_KEY)
    current_prompt = build_prompt(req.language)
    video_url = None

    if is_youtube_url(url):
        # YouTube: send the link to Gemini directly (no download)
        video_part = types.Part.from_uri(file_uri=url, mime_type="video/mp4")
        response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=[current_prompt, video_part],
        )
    elif is_tiktok_url(url):
        # TikTok: download via tiktok-api-dl then upload file to Gemini
        videoName = download_tiktok_video(url)
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
        videoName = download_instagram_reel(url)
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
        creator=data.get("creator", ""),
        estimated_cooking_time=str(data.get("estimated_cooking_time", "0")),
        ingredients=data.get("ingredients", []),
        instructions=data.get("instructions", []),
        video_url=video_url,
    )


