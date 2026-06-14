"""Gemini/OpenAI recipe extraction from local video files."""

from __future__ import annotations

import asyncio
import json
import os
import re
import time
from typing import Any, Optional

from ai_video_analysis import analyze_video_with_openai, recipe_ai_provider_chain
from config import GEMINI_API_KEY
from fastapi import HTTPException  # pyright: ignore[reportMissingImports]
from google import genai
from google.genai import errors as genai_errors  # pyright: ignore[reportMissingImports]


def build_prompt(language: str, *, include_nutrition: bool = False) -> str:
    lang = language.lower()
    nutrition_block = ""
    nutrition_guideline = ""
    if include_nutrition:
        nutrition_block = """,
    "nutrition": {
    "calories": 450,
    "protein_g": 32,
    "carbs_g": 28,
    "fat_g": 18
    }"""
        nutrition_guideline = """
    10. Include a "nutrition" object with estimated **per-serving** values from the ingredients: "calories" (integer kcal), "protein_g", "carbs_g", "fat_g" (integer grams). Use reasonable estimates when exact values are unknown."""
    print(lang)
    return f"""Analyze the attached cooking video. 
    Extract the recipe and output the result strictly in JSON format. JSON keys must be English.
    The JSON structure must match this template:
    {{
    "recipe_name": "Title of the dish",
    "creator": "Name of the creator",
    "prep_time": "5",
    "estimated_cooking_time": "10",
    "estimated_servings": "4",
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
        "description": "Detailed description of this cooking step",
        "timestamp_seconds": "12.5"
        }},
    ],
    "dish_hero_timestamp_seconds": "0"{nutrition_block}
    }}
    Guidelines:
    1. If specific quantities are not mentioned, use "As needed".
    2. Ensure the output is valid JSON only, with no introductory or concluding text.
    3. Try add some icons to each ingredient in the front.
    4. Make sure each step is concise, don't include timestamps.
    5. Please include prep_time and estimated_cooking_time as MINUTES in numeric string form (e.g. "5", "10"). Do NOT add words like "minutes".
    5b. Set "estimated_servings" to how many people the recipe serves, as a numeric string (e.g. "2", "4"). If unclear, use your best estimate; minimum "1".
    6. Make sure the creator name is right if it's a youtube video.
    7. Use language code {lang} for all user-facing text values (keys must stay in English).
    8. Set "dish_hero_timestamp_seconds" to a single number as a string (seconds from the start of the video, e.g. "42" or "12.5") for the best moment the final dish is shown clearly and in focus. If you don't know, use the last second of the video.
    9. For EVERY instruction, set "timestamp_seconds" to the video time (seconds from start, as a string) when that step is shown on screen. Use the clearest frame for that step. Steps must be in ascending time order.{nutrition_guideline}"""


def normalize_timestamp_seconds(raw) -> str:
    if raw is None:
        return "0"
    s = str(raw).strip().replace(",", ".")
    if not s:
        return "0"
    try:
        v = float(s)
        if v != v or v < 0:
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


def normalize_instruction_timestamps(data: dict) -> None:
    """Ensure each instruction dict has a normalized timestamp_seconds string."""
    instructions = data.get("instructions")
    if not isinstance(instructions, list):
        return
    for item in instructions:
        if not isinstance(item, dict):
            continue
        item["timestamp_seconds"] = normalize_timestamp_seconds(item.get("timestamp_seconds"))


def normalize_dish_hero_timestamp_seconds(data: dict) -> str:
    return normalize_timestamp_seconds(data.get("dish_hero_timestamp_seconds"))


def nutrition_info_from_data(data: dict):
    """Parse optional nutrition object from model JSON."""
    from models import NutritionInfo

    raw = data.get("nutrition")
    if not isinstance(raw, dict):
        return None

    def _int(key: str) -> Optional[int]:
        value = raw.get(key)
        if value is None:
            return None
        try:
            return max(0, int(float(str(value).strip().replace(",", "."))))
        except (ValueError, TypeError):
            return None

    parsed = {
        "calories": _int("calories"),
        "protein_g": _int("protein_g"),
        "carbs_g": _int("carbs_g"),
        "fat_g": _int("fat_g"),
    }
    if all(v is None for v in parsed.values()):
        return None
    return NutritionInfo(**{k: v for k, v in parsed.items() if v is not None})


def extract_json_from_response(raw: str) -> dict:
    if not raw or not raw.strip():
        raise ValueError("Model returned empty response")
    text = raw.strip()
    code_block = re.search(r"```(?:json)?\s*([\s\S]*?)\s*```", text)
    if code_block:
        text = code_block.group(1).strip()
    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end != -1 and end > start:
        text = text[start : end + 1]
    return json.loads(text)


def _gemini_model_candidates() -> list[str]:
    primary = (os.getenv("GEMINI_MODEL") or "gemini-3.1-pro-preview").strip()
    fallbacks_raw = os.getenv(
        "GEMINI_MODEL_FALLBACKS",
        "gemini-3.1-flash-lite,gemini-3.5-flash,gemini-2.5-flash",
    )
    ordered: list[str] = []
    for name in [primary, *fallbacks_raw.split(",")]:
        name = name.strip()
        if name and name not in ordered:
            ordered.append(name)
    return ordered or ["gemini-3.1-pro-preview"]


def _is_transient_gemini_error(err: BaseException) -> bool:
    if isinstance(err, genai_errors.ServerError):
        return True
    if isinstance(err, genai_errors.APIError):
        code = getattr(err, "code", None)
        if code in (429, 500, 503):
            return True
    msg = str(err).lower()
    return any(
        phrase in msg
        for phrase in (
            "high demand",
            "unavailable",
            "overloaded",
            "resource exhausted",
            "too many requests",
            "503",
            "429",
        )
    )


def _generate_content_with_retry(client: genai.Client, contents, attempts_per_model: int = 2):
    models = _gemini_model_candidates()
    errors: list[tuple[str, BaseException]] = []

    for model in models:
        for idx in range(attempts_per_model):
            try:
                print(f"[Gemini] generate_content model={model} attempt={idx + 1}/{attempts_per_model}")
                return client.models.generate_content(model=model, contents=contents)
            except Exception as e:
                if not _is_transient_gemini_error(e):
                    raise
                errors.append((model, e))
                if idx < attempts_per_model - 1:
                    time.sleep(2 * (idx + 1))
                    continue
                print(f"[Gemini] model={model} still failing ({e!r}); trying next fallback model")
                break

    if errors:
        raise errors[-1][1]
    raise RuntimeError("Gemini generation failed: no models configured.")


def require_recipe_ai_configured() -> None:
    chain = recipe_ai_provider_chain()
    if not chain:
        raise HTTPException(
            status_code=500,
            detail="No recipe AI provider configured (set GEMINI_API_KEY and/or OPENAI_API_KEY)",
        )


def _gemini_file_poll_interval_sec() -> float:
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


async def _gemini_analyze_local_video(
    client: genai.Client,
    video_path: str,
    prompt: str,
    extra_context: Optional[list[str]] = None,
):
    video_file = client.files.upload(file=video_path)
    video_file = await _wait_for_gemini_file_ready(client, video_file)
    contents: list[Any] = [prompt]
    if extra_context:
        contents.extend(extra_context)
    contents.append(video_file)
    return _generate_content_with_retry(client, contents)


async def analyze_local_video_path(
    video_path: str,
    language: str,
    extra_context: Optional[list[str]] = None,
    *,
    include_nutrition: bool = False,
) -> str:
    prompt = build_prompt(language, include_nutrition=include_nutrition)
    errors: list[tuple[str, BaseException]] = []
    chain = recipe_ai_provider_chain()

    for i, provider in enumerate(chain):
        try:
            print(f"[RecipeAI] analyzing video with provider={provider}")
            if provider == "openai":
                raw = await asyncio.to_thread(
                    analyze_video_with_openai,
                    video_path,
                    prompt,
                    extra_context,
                )
                print("[RecipeAI] OpenAI analysis succeeded")
                return raw
            client = genai.Client(api_key=GEMINI_API_KEY)
            response = await _gemini_analyze_local_video(client, video_path, prompt, extra_context)
            print("[RecipeAI] Gemini analysis succeeded")
            return getattr(response, "text", None) or ""
        except Exception as e:
            errors.append((provider, e))
            print(f"[RecipeAI] provider={provider} failed: {e!r}")
            if i + 1 < len(chain):
                print(f"[RecipeAI] falling back to: {chain[i + 1]}")

    if errors:
        raise errors[-1][1]
    raise RuntimeError("No recipe AI provider configured")
