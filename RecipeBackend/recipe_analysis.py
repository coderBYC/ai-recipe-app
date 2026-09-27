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
from google.genai import types  # pyright: ignore[reportMissingImports]

from url_utils import youtube_watch_url


def normalize_recipe_language(language: str) -> str:
    """Map client language codes to the form used in prompts."""
    raw = (language or "en").strip().lower().replace("_", "-")
    if raw in ("zh", "zh-tw", "zh-hant", "zh-hk", "cmn-hant", "mandarin"):
        return "zh-TW"
    if raw in ("zh-cn", "zh-hans", "zh-sg"):
        return "zh-CN"
    if raw in ("es", "spanish"):
        return "es"
    if raw in ("hi", "hindi"):
        return "hi"
    if raw in ("ko", "korean"):
        return "ko"
    if raw in ("en", "english", "system", ""):
        return "en"
    return raw or "en"


def _audience_guidelines(lang: str) -> str:
    """Extra locale-specific instructions for user-facing recipe text."""
    if lang == "zh-TW":
        return """
    7. Audience: This content is for Taiwanese users.
    7a. Write ALL user-facing text values in Traditional Chinese (繁體中文) as used in Taiwan (language code zh-TW). Do NOT use Simplified Chinese.
    7b. Prefer Taiwanese culinary wording and units people use in Taiwan (e.g. 起司 not 奶酪, 醬料/調味 familiar in TW markets). Keep JSON keys in English."""
    if lang == "zh-CN":
        return """
    7. Write ALL user-facing text values in Simplified Chinese (简体中文). Keep JSON keys in English."""
    return f"""
    7. Use language code {lang} for all user-facing text values (keys must stay in English)."""


def user_adjustment_guidelines(adjustments: str) -> str:
    text = (adjustments or "").strip()
    if not text:
        return ""
    return f"""
    11. The user asked to customize this recipe: {text}
    Adapt ingredients, amounts, and steps to satisfy those preferences while keeping the same dish recognizable.
    Mention the customization briefly in the description."""


def build_prompt(language: str, *, include_nutrition: bool = False, adjustments: str = "") -> str:
    lang = normalize_recipe_language(language)
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
    audience = _audience_guidelines(lang)
    print(f"[RecipeAnalysis] language={lang}")
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
    1. If specific quantities are not mentioned, use "As needed" (or the equivalent in the target language).
    2. Ensure the output is valid JSON only, with no introductory or concluding text.
    3. Try add some icons to each ingredient in the front.
    4. Make sure each step is concise, don't include timestamps.
    5. Please include prep_time and estimated_cooking_time as MINUTES in numeric string form (e.g. "5", "10"). Do NOT add words like "minutes".
    5b. Set "estimated_servings" to how many people the recipe serves, as a numeric string (e.g. "2", "4"). If unclear, use your best estimate; minimum "1".
    6. Make sure the creator name is right if it's a youtube video.{audience}
    8. Set "dish_hero_timestamp_seconds" to a single number as a string (seconds from the start of the video, e.g. "42" or "12.5") for the best moment the final dish is shown clearly and in focus. If you don't know, use the last second of the video.
    9. For EVERY instruction, set "timestamp_seconds" to the video time (seconds from start, as a string) when that step is shown on screen. Use the clearest frame for that step. Steps must be in ascending time order.{nutrition_guideline}{user_adjustment_guidelines(adjustments)}"""


def build_website_extract_prompt(language: str, *, include_nutrition: bool = False, adjustments: str = "") -> str:
    """Prompt for written recipes scraped from a website. Extract only — do not invent."""
    lang = normalize_recipe_language(language)
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
    10. Include a "nutrition" object ONLY if calories / protein / carbs / fat appear in the SOURCE TEXT. Copy those values; do not estimate or invent macros."""
    audience = _audience_guidelines(lang)
    print(f"[WebsiteRecipe] language={lang}")
    return f"""You are reformatting a recipe that was already extracted from a website (JSON-LD / Schema.org).

CRITICAL RULES:
- EXTRACT and reformat only. Do NOT invent, guess, or complete missing steps or ingredients.
- Do NOT add ingredients that are not in the source text.
- Do NOT add cooking steps that are not in the source text.
- Do NOT "improve", rewrite into a new recipe, or fill gaps from general cooking knowledge.
- If a quantity is missing in the source, use "As needed" (or the equivalent in the target language). Do not invent a number.
- If a field is missing in the source, use an empty string or a safe default listed below — never fabricate content.

Output valid JSON only. JSON keys must stay in English.
The JSON structure must match this template:
{{
    "recipe_name": "Title of the dish",
    "creator": "Name of the creator or site",
    "prep_time": "5",
    "estimated_cooking_time": "10",
    "estimated_servings": "4",
    "description": "Short summary copied or lightly condensed from the source — do not invent a new story",
    "ingredients": [
        {{
        "item": "🍔Ingredient Name",
        "amount": "Quantity and unit"
        }}
    ],
    "instructions": [
        {{
        "step": 1,
        "description": "This cooking step as written in the source",
        "timestamp_seconds": "0"
        }}
    ],
    "dish_hero_timestamp_seconds": "0"{nutrition_block}
}}
Guidelines:
    1. Every ingredient and every instruction must come from the SOURCE TEXT below.
    2. Valid JSON only — no markdown, no intro, no outro.
    3. You may add a fitting emoji at the start of each ingredient name.
    4. Keep steps concise; do not add new technique.
    5. prep_time and estimated_cooking_time are MINUTES as numeric strings (e.g. "5", "10") only if the source states them. Otherwise "0".
    5b. estimated_servings is a numeric string only if the source states yield/servings. Otherwise "1".
    6. creator is the author or publication from the source, if present.{audience}
    8. There is no video. Set "dish_hero_timestamp_seconds" to "0".
    9. Set every instruction "timestamp_seconds" to "0".{nutrition_guideline}{user_adjustment_guidelines(adjustments)}

SOURCE TEXT:
"""


def build_website_url_prompt(language: str, page_url: str, *, include_nutrition: bool = False, adjustments: str = "") -> str:
    """When the page has no usable HTML/JSON-LD, send the URL itself to GPT."""
    lang = normalize_recipe_language(language)
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
    10. Include a "nutrition" object ONLY if the page states calories / protein / carbs / fat. Do not invent macros."""
    audience = _audience_guidelines(lang)
    print(f"[WebsiteRecipe] URL fallback language={lang}")
    return f"""The recipe page could not be parsed as HTML (no usable Recipe JSON-LD or recipe elements).
Use this URL as the source and extract the recipe from that page:

{page_url}

CRITICAL RULES:
- EXTRACT from that page only. Do NOT invent, guess, or complete missing steps or ingredients.
- Do NOT add ingredients or cooking steps that are not on the page.
- Do NOT fill gaps from general cooking knowledge.
- If a quantity is missing, use "As needed" (or the equivalent in the target language). Do not invent a number.
- If you cannot access the page or it is not a recipe, return JSON with empty ingredients and instructions arrays and recipe_name "".

Output valid JSON only. JSON keys must stay in English.
The JSON structure must match this template:
{{
    "recipe_name": "Title of the dish",
    "creator": "Name of the creator or site",
    "prep_time": "5",
    "estimated_cooking_time": "10",
    "estimated_servings": "4",
    "description": "Short summary from the page — do not invent a new story",
    "ingredients": [
        {{
        "item": "🍔Ingredient Name",
        "amount": "Quantity and unit"
        }}
    ],
    "instructions": [
        {{
        "step": 1,
        "description": "This cooking step as written on the page",
        "timestamp_seconds": "0"
        }}
    ],
    "dish_hero_timestamp_seconds": "0"{nutrition_block}
}}
Guidelines:
    1. Every ingredient and every instruction must come from the page at the URL above.
    2. Valid JSON only — no markdown, no intro, no outro.
    3. You may add a fitting emoji at the start of each ingredient name.
    4. Keep steps concise; do not add new technique.
    5. prep_time and estimated_cooking_time are MINUTES as numeric strings only if the page states them. Otherwise "0".
    5b. estimated_servings is a numeric string only if the page states yield/servings. Otherwise "1".
    6. creator is the author or publication from the page, if present.{audience}
    8. There is no video. Set "dish_hero_timestamp_seconds" to "0".
    9. Set every instruction "timestamp_seconds" to "0".{nutrition_guideline}{user_adjustment_guidelines(adjustments)}"""


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


async def _gemini_analyze_youtube_url(
    client: genai.Client,
    youtube_url: str,
    prompt: str,
    extra_context: Optional[list[str]] = None,
):
    """Analyze a public YouTube video via Gemini file_uri attachment (no local download)."""
    watch_url = youtube_watch_url(youtube_url)
    if not watch_url:
        raise ValueError("Invalid YouTube URL")
    video_part = types.Part(
        file_data=types.FileData(file_uri=watch_url),
    )
    contents: list[Any] = [prompt]
    if extra_context:
        contents.extend(extra_context)
    contents.append(video_part)
    print(f"[Gemini] YouTube attachment: {watch_url}")
    return _generate_content_with_retry(client, contents)


async def analyze_youtube_url(
    youtube_url: str,
    language: str,
    extra_context: Optional[list[str]] = None,
    *,
    include_nutrition: bool = False,
    adjustments: str = "",
) -> str:
    """YouTube imports use Gemini with the watch URL as attachment (no yt-dlp download)."""
    if not GEMINI_API_KEY:
        raise RuntimeError("GEMINI_API_KEY is required for YouTube imports")
    prompt = build_prompt(language, include_nutrition=include_nutrition, adjustments=adjustments)
    client = genai.Client(api_key=GEMINI_API_KEY)
    response = await _gemini_analyze_youtube_url(
        client, youtube_url, prompt, extra_context
    )
    print("[RecipeAI] Gemini YouTube URL analysis succeeded")
    return getattr(response, "text", None) or ""


async def analyze_local_video_path(
    video_path: str,
    language: str,
    extra_context: Optional[list[str]] = None,
    *,
    include_nutrition: bool = False,
    adjustments: str = "",
) -> str:
    prompt = build_prompt(language, include_nutrition=include_nutrition, adjustments=adjustments)
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
