"""Fetch written recipe pages and extract Schema.org Recipe JSON-LD for GPT reformatting."""

from __future__ import annotations

import asyncio
import json
import os
import re
import time
import uuid
from typing import Any, Optional
from urllib.parse import urljoin, urlparse

import httpx
from cloudinaryconfig import (
    cloudinary_credentials_configured,
    upload_thumbnail_from_url,
    upload_thumbnail_jpg,
)
from config import OPENAI_API_KEY
from openai import OpenAI  # pyright: ignore[reportMissingImports]
from recipe_analysis import (
    build_website_extract_prompt,
    build_website_url_prompt,
    extract_json_from_response,
    normalize_recipe_language,
)

_LD_SCRIPT_RE = re.compile(
    r'<script[^>]*type=["\']application/ld\+json["\'][^>]*>(.*?)</script>',
    re.IGNORECASE | re.DOTALL,
)
_ISO_DURATION_RE = re.compile(
    r"P(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?|(?:(\d+)D)(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?)",
    re.IGNORECASE,
)
_FETCH_TIMEOUT_SEC = float(os.getenv("WEBSITE_RECIPE_FETCH_TIMEOUT_SEC", "20"))
_IMAGE_TIMEOUT_SEC = float(os.getenv("WEBSITE_RECIPE_IMAGE_TIMEOUT_SEC", "15"))
_OPENAI_TIMEOUT_SEC = float(os.getenv("WEBSITE_RECIPE_OPENAI_TIMEOUT_SEC", "90"))
_MAX_HTML_BYTES = 6 * 1024 * 1024
_MAX_IMAGE_BYTES = 8 * 1024 * 1024
_BROWSER_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
)
_BLOCKED_IMAGE_HOSTS = {"localhost", "127.0.0.1", "0.0.0.0", "::1"}
_OG_IMAGE_RE = re.compile(
    r'<meta[^>]+(?:property|name)=["\'](?:og:image(?:\:secure_url)?|twitter:image(?::src)?)["\'][^>]*content=["\']([^"\']+)["\']',
    re.IGNORECASE,
)
_OG_IMAGE_RE_REV = re.compile(
    r'<meta[^>]+content=["\']([^"\']+)["\'][^>]*(?:property|name)=["\'](?:og:image(?:\:secure_url)?|twitter:image(?::src)?)["\']',
    re.IGNORECASE,
)
_CURL_IMPERSONATES = [
    name.strip()
    for name in (os.getenv("WEBSITE_RECIPE_IMPERSONATE") or "chrome124,chrome,safari").split(",")
    if name.strip()
]


class WebsiteRecipeError(Exception):
    """Raised when a website recipe cannot be fetched or extracted."""


def extract_json_ld(html: str) -> Optional[dict[str, Any]]:
    """Return the first Schema.org Recipe object found in JSON-LD script tags."""
    if not html:
        return None
    for raw in _LD_SCRIPT_RE.findall(html):
        text = raw.strip()
        if not text:
            continue
        if text.startswith("<!--"):
            text = re.sub(r"^<!--|-->$", "", text).strip()
        try:
            payload = json.loads(text)
        except json.JSONDecodeError:
            continue
        found = _find_recipe_object(payload)
        if found:
            return found
    return None


def _find_recipe_object(node: Any) -> Optional[dict[str, Any]]:
    if isinstance(node, list):
        for item in node:
            found = _find_recipe_object(item)
            if found:
                return found
        return None
    if not isinstance(node, dict):
        return None
    if _node_is_recipe(node):
        return node
    graph = node.get("@graph")
    if graph is not None:
        found = _find_recipe_object(graph)
        if found:
            return found
    for key in ("mainEntity", "mainEntityOfPage"):
        if key in node:
            found = _find_recipe_object(node.get(key))
            if found:
                return found
    return None


def _node_is_recipe(node: dict[str, Any]) -> bool:
    raw_type = node.get("@type")
    types: list[str] = []
    if isinstance(raw_type, str):
        types = [raw_type]
    elif isinstance(raw_type, list):
        types = [str(t) for t in raw_type]
    return any(t.split("/")[-1].lower() == "recipe" for t in types)


def _as_list(value: Any) -> list[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def _plain_text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return re.sub(r"\s+", " ", value).strip()
    if isinstance(value, dict):
        for key in ("text", "name", "description"):
            text = _plain_text(value.get(key))
            if text:
                return text
        return ""
    if isinstance(value, list):
        parts = [_plain_text(v) for v in value]
        return ", ".join(p for p in parts if p)
    return str(value).strip()


def _author_name(recipe: dict[str, Any]) -> str:
    for key in ("author", "publisher", "creator"):
        for item in _as_list(recipe.get(key)):
            if isinstance(item, str) and item.strip():
                return item.strip()
            if isinstance(item, dict):
                name = _plain_text(item.get("name") or item.get("legalName"))
                if name:
                    return name
    return ""


def _recipe_image_url(recipe: dict[str, Any], page_url: str) -> str:
    for item in _as_list(recipe.get("image")):
        raw = ""
        if isinstance(item, str):
            raw = item.strip()
        elif isinstance(item, dict):
            raw = str(
                item.get("url")
                or item.get("contentUrl")
                or item.get("thumbnailUrl")
                or item.get("@id")
                or ""
            ).strip()
        if raw:
            return urljoin(page_url, raw)
    return ""


def _open_graph_image_url(html: str, page_url: str) -> str:
    if not html:
        return ""
    for pattern in (_OG_IMAGE_RE, _OG_IMAGE_RE_REV):
        match = pattern.search(html)
        if not match:
            continue
        raw = (match.group(1) or "").strip()
        if raw:
            return urljoin(page_url, raw)
    return ""


def _first_page_image_url(html: str, recipe: Optional[dict[str, Any]], page_url: str) -> str:
    if recipe:
        found = _recipe_image_url(recipe, page_url)
        if found:
            return found
    return _open_graph_image_url(html, page_url)


def _is_safe_image_url(url: str) -> bool:
    parsed = urlparse((url or "").strip())
    if parsed.scheme not in ("http", "https"):
        return False
    host = (parsed.hostname or "").lower()
    if not host or host in _BLOCKED_IMAGE_HOSTS:
        return False
    return True


def _browser_headers(*, referer: str = "") -> dict[str, str]:
    headers = {
        "User-Agent": os.getenv("WEBSITE_RECIPE_USER_AGENT", _BROWSER_UA),
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.9",
        "Cache-Control": "no-cache",
        "Pragma": "no-cache",
        "Upgrade-Insecure-Requests": "1",
    }
    if referer:
        headers["Referer"] = referer
    return headers


async def _download_image_bytes(url: str, *, referer: str = "") -> bytes:
    headers = _browser_headers(referer=referer or url)
    headers["Accept"] = "image/avif,image/webp,image/apng,image/jpeg,image/png,image/*,*/*;q=0.8"
    data = b""
    try:
        data = await asyncio.to_thread(_curl_cffi_get_bytes, url, headers)
    except Exception as e:
        print(f"[WebsiteRecipe] curl image download failed: {e!r}")
    if not data:
        async with httpx.AsyncClient(
            timeout=_IMAGE_TIMEOUT_SEC,
            follow_redirects=True,
            headers=headers,
            trust_env=False,
        ) as client:
            resp = await client.get(url)
        if resp.status_code >= 400:
            raise WebsiteRecipeError(f"Image returned HTTP {resp.status_code}")
        data = resp.content or b""
    if not data:
        raise WebsiteRecipeError("Image download was empty")
    if len(data) > _MAX_IMAGE_BYTES:
        raise WebsiteRecipeError("Image is too large")
    return data


async def _cloudinary_url_for_page_image(image_url: str, *, page_url: str = "") -> str:
    """Store the first recipe photo in Cloudinary; fall back to the original URL."""
    raw = (image_url or "").strip()
    if not raw or not _is_safe_image_url(raw):
        return ""
    if not cloudinary_credentials_configured():
        print("[WebsiteRecipe] Cloudinary keys missing; using original page image URL")
        return raw
    thumb_id = str(uuid.uuid4())
    try:
        uploaded = await asyncio.to_thread(upload_thumbnail_from_url, raw, thumb_id)
        print(f"[WebsiteRecipe] uploaded thumbnail to Cloudinary: {uploaded}")
        return uploaded
    except Exception as e:
        print(f"[WebsiteRecipe] Cloudinary fetch-upload failed: {e!r}")
    try:
        data = await _download_image_bytes(raw, referer=page_url)
        uploaded = await asyncio.to_thread(upload_thumbnail_jpg, data, thumb_id)
        print(f"[WebsiteRecipe] uploaded thumbnail bytes to Cloudinary: {uploaded}")
        return uploaded
    except Exception as e:
        print(f"[WebsiteRecipe] thumbnail upload failed: {e!r}; using original image URL")
        return raw


def _iso_duration_to_minutes(raw: Any) -> str:
    text = _plain_text(raw)
    if not text:
        return ""
    if text.isdigit():
        return text
    match = _ISO_DURATION_RE.fullmatch(text.replace(" ", "").upper())
    if not match:
        numbers = re.findall(r"\d+", text)
        return numbers[0] if numbers else ""
    days = int(match.group(4) or 0)
    hours = int(match.group(1) or match.group(5) or 0)
    minutes = int(match.group(2) or match.group(6) or 0)
    seconds = int(match.group(3) or match.group(7) or 0)
    total = days * 24 * 60 + hours * 60 + minutes + (1 if seconds >= 30 else 0)
    return str(total) if total > 0 else ""


def _instruction_lines(recipe: dict[str, Any]) -> list[str]:
    lines: list[str] = []

    def walk(node: Any) -> None:
        if node is None:
            return
        if isinstance(node, str):
            text = _plain_text(node)
            if text:
                lines.append(text)
            return
        if isinstance(node, list):
            for item in node:
                walk(item)
            return
        if not isinstance(node, dict):
            return
        raw_type = str(node.get("@type") or "")
        if raw_type.lower().endswith("howtosection"):
            walk(node.get("itemListElement") or node.get("steps"))
            return
        text = _plain_text(node.get("text") or node.get("name"))
        if text:
            lines.append(text)
        walk(node.get("itemListElement"))

    walk(recipe.get("recipeInstructions"))
    return lines


def _ingredient_lines(recipe: dict[str, Any]) -> list[str]:
    out: list[str] = []
    for item in _as_list(recipe.get("recipeIngredient") or recipe.get("ingredients")):
        text = _plain_text(item)
        if text:
            out.append(text)
    return out


def format_recipe_source_text(recipe: dict[str, Any], page_url: str) -> str:
    """Flatten JSON-LD Recipe fields into the text GPT will extract from."""
    parts = [f"Source URL: {page_url}"]
    name = _plain_text(recipe.get("name") or recipe.get("headline"))
    if name:
        parts.append(f"Title: {name}")
    author = _author_name(recipe)
    if author:
        parts.append(f"Author: {author}")
    description = _plain_text(recipe.get("description"))
    if description:
        parts.append(f"Description: {description}")
    servings = _plain_text(recipe.get("recipeYield") or recipe.get("yield"))
    if servings:
        parts.append(f"Servings / yield: {servings}")
    prep = _iso_duration_to_minutes(recipe.get("prepTime"))
    cook = _iso_duration_to_minutes(recipe.get("cookTime") or recipe.get("totalTime"))
    if prep:
        parts.append(f"Prep time minutes: {prep}")
    if cook:
        parts.append(f"Cook time minutes: {cook}")

    ingredients = _ingredient_lines(recipe)
    if ingredients:
        parts.append("Ingredients:")
        parts.extend(f"- {line}" for line in ingredients)

    steps = _instruction_lines(recipe)
    if steps:
        parts.append("Instructions:")
        parts.extend(f"{idx}. {line}" for idx, line in enumerate(steps, start=1))

    nutrition = recipe.get("nutrition")
    if isinstance(nutrition, dict):
        bits = []
        for key in (
            "calories",
            "proteinContent",
            "carbohydrateContent",
            "fatContent",
            "servingSize",
        ):
            val = _plain_text(nutrition.get(key))
            if val:
                bits.append(f"{key}: {val}")
        if bits:
            parts.append("Nutrition from page: " + "; ".join(bits))

    return "\n".join(parts).strip()


def _curl_cffi_get_text(url: str, impersonate: str) -> tuple[int, str]:
    from curl_cffi import requests as curl_requests

    resp = curl_requests.get(
        url,
        impersonate=impersonate,
        timeout=_FETCH_TIMEOUT_SEC,
        allow_redirects=True,
        headers=_browser_headers(referer="https://www.google.com/"),
    )
    return int(resp.status_code), resp.text or ""


def _curl_cffi_get_bytes(url: str, headers: dict[str, str]) -> bytes:
    from curl_cffi import requests as curl_requests

    last_err: Optional[BaseException] = None
    for impersonate in _CURL_IMPERSONATES:
        try:
            resp = curl_requests.get(
                url,
                impersonate=impersonate,
                timeout=_IMAGE_TIMEOUT_SEC,
                allow_redirects=True,
                headers=headers,
            )
            if resp.status_code < 400 and resp.content:
                return resp.content
        except Exception as e:
            last_err = e
            continue
    if last_err:
        raise last_err
    return b""


async def _fetch_html_with_curl_cffi(url: str) -> str:
    last_status = 0
    for impersonate in _CURL_IMPERSONATES:
        try:
            status, text = await asyncio.to_thread(_curl_cffi_get_text, url, impersonate)
        except Exception as e:
            print(f"[WebsiteRecipe] curl_cffi impersonate={impersonate} failed: {e!r}")
            continue
        last_status = status
        if status < 400 and _html_looks_usable(text) and len(text.encode("utf-8", "ignore")) <= _MAX_HTML_BYTES:
            print(f"[WebsiteRecipe] fetched HTML via curl_cffi impersonate={impersonate}")
            return text
        print(f"[WebsiteRecipe] curl_cffi impersonate={impersonate} HTTP {status}")
    if last_status >= 400:
        raise WebsiteRecipeError(f"Website returned HTTP {last_status}")
    return ""


async def _fetch_html_with_httpx(url: str) -> str:
    headers = _browser_headers(referer="https://www.google.com/")
    try:
        async with httpx.AsyncClient(
            timeout=_FETCH_TIMEOUT_SEC,
            follow_redirects=True,
            headers=headers,
            trust_env=False,
        ) as client:
            resp = await client.get(url)
    except httpx.HTTPError as e:
        raise WebsiteRecipeError(f"Could not fetch website: {e}") from e

    if resp.status_code >= 400:
        raise WebsiteRecipeError(f"Website returned HTTP {resp.status_code}")
    content = resp.content or b""
    if len(content) > _MAX_HTML_BYTES:
        raise WebsiteRecipeError("Website HTML is too large to parse")
    return resp.text or ""


async def fetch_page_html(url: str) -> str:
    curl_error: Optional[Exception] = None
    try:
        html = await _fetch_html_with_curl_cffi(url)
        if _html_looks_usable(html):
            return html
    except Exception as e:
        curl_error = e
        print(f"[WebsiteRecipe] curl_cffi fetch failed ({e}); trying httpx")

    try:
        html = await _fetch_html_with_httpx(url)
        if _html_looks_usable(html):
            return html
    except Exception as e:
        if curl_error:
            raise WebsiteRecipeError(f"Could not fetch website: {curl_error}") from e
        raise

    raise WebsiteRecipeError("Website HTML is empty or blocked")


def _openai_website_models() -> list[str]:
    primary = (os.getenv("WEBSITE_RECIPE_OPENAI_MODEL") or os.getenv("OPENAI_MODEL") or "gpt-4o-mini").strip()
    fallbacks = (os.getenv("WEBSITE_RECIPE_OPENAI_FALLBACKS") or "gpt-4o-mini,gpt-4o").strip()
    ordered: list[str] = []
    for name in [primary, *fallbacks.split(",")]:
        name = name.strip()
        if name and name not in ordered:
            ordered.append(name)
    return ordered or ["gpt-4o-mini"]


def _html_looks_usable(html: str) -> bool:
    text = (html or "").strip()
    if len(text) < 80:
        return False
    lowered = text.lower()
    looks_like_challenge = (
        "cf-browser-verification" in lowered
        or "cdn-cgi/challenge" in lowered
        or ("just a moment" in lowered and "cloudflare" in lowered)
        or "enable javascript and cookies to continue" in lowered
    )
    if looks_like_challenge and len(text) < 20_000:
        return False
    if "ld+json" in lowered or "og:image" in lowered or "recipeingredient" in lowered:
        return True
    if "<html" in lowered or "<body" in lowered or "<article" in lowered:
        return True
    return False


def _call_gpt(
    user_content: str,
    language: str,
    *,
    system: str,
    log_label: str,
) -> str:
    if not OPENAI_API_KEY:
        raise WebsiteRecipeError("OPENAI_API_KEY is required for website recipe imports")
    lang = normalize_recipe_language(language)
    client = OpenAI(api_key=OPENAI_API_KEY, timeout=_OPENAI_TIMEOUT_SEC, max_retries=1)
    last_err: Optional[BaseException] = None
    for model in _openai_website_models():
        try:
            print(f"[WebsiteRecipe] {log_label} model={model} language={lang}")
            response = client.chat.completions.create(
                model=model,
                messages=[
                    {"role": "system", "content": system},
                    {"role": "user", "content": user_content},
                ],
                temperature=0,
                response_format={"type": "json_object"},
            )
            raw = (response.choices[0].message.content or "").strip()
            if not raw:
                raise WebsiteRecipeError("GPT returned an empty recipe")
            extract_json_from_response(raw)
            return raw
        except WebsiteRecipeError:
            raise
        except Exception as e:
            last_err = e
            print(f"[WebsiteRecipe] model={model} failed: {e!r}")
            continue
    raise WebsiteRecipeError(f"GPT extract failed: {last_err}") from last_err


def _call_gpt_extract(
    source_text: str,
    language: str,
    *,
    include_nutrition: bool,
    adjustments: str = "",
) -> str:
    prompt = build_website_extract_prompt(
        language,
        include_nutrition=include_nutrition,
        adjustments=adjustments,
    )
    system = (
        "You extract the recipe from the source text, then adapt it to the user's customization. "
        "Return one JSON object."
        if (adjustments or "").strip()
        else (
            "You extract recipes from provided source text only. "
            "Never invent ingredients or steps. Return one JSON object."
        )
    )
    return _call_gpt(
        f"{prompt}\n{source_text}",
        language,
        system=system,
        log_label="GPT extract from JSON-LD",
    )


def _call_gpt_from_url(
    page_url: str,
    language: str,
    *,
    include_nutrition: bool,
    adjustments: str = "",
) -> str:
    prompt = build_website_url_prompt(
        language,
        page_url,
        include_nutrition=include_nutrition,
        adjustments=adjustments,
    )
    system = (
        "The page HTML was missing or had no recipe elements. "
        "Use the given URL as the source, then adapt the recipe to the user's customization. "
        "Return one JSON object."
        if (adjustments or "").strip()
        else (
            "The page HTML was missing or had no recipe elements. "
            "Use the given URL as the source. Extract only; never invent ingredients or steps. "
            "Return one JSON object."
        )
    )
    return _call_gpt(
        prompt,
        language,
        system=system,
        log_label="GPT extract from URL",
    )


async def analyze_website_recipe(
    url: str,
    language: str,
    *,
    include_nutrition: bool = False,
    adjustments: str = "",
) -> tuple[str, str, str]:
    """
    Fetch page → extract_json_ld → GPT reformat.
    If HTML/JSON-LD is missing, send the URL to GPT instead.
    Returns (raw_model_json, creator, thumbnail_url).
    """
    page_url = (url or "").strip()
    if not page_url:
        raise WebsiteRecipeError("URL is required")

    started = time.monotonic()
    html = ""
    try:
        html = await fetch_page_html(page_url)
    except WebsiteRecipeError as e:
        print(f"[WebsiteRecipe] fetch failed ({e}); sending URL to GPT")

    recipe = extract_json_ld(html) if html else None
    source_text = format_recipe_source_text(recipe, page_url) if recipe else ""
    has_elements = bool(recipe) and (
        "Ingredients:" in source_text or "Instructions:" in source_text
    )
    page_image = _first_page_image_url(html, recipe, page_url)
    if page_image:
        print(f"[WebsiteRecipe] found page image {page_image}")
    else:
        print("[WebsiteRecipe] no page image found")

    if has_elements and recipe:
        creator = _author_name(recipe)
        print(
            f"[WebsiteRecipe] extracted JSON-LD title={_plain_text(recipe.get('name'))!r} "
            f"ingredients={len(_ingredient_lines(recipe))} steps={len(_instruction_lines(recipe))}"
        )
        raw = _call_gpt_extract(
            source_text,
            language,
            include_nutrition=include_nutrition,
            adjustments=adjustments,
        )
        thumbnail = await _cloudinary_url_for_page_image(page_image, page_url=page_url)
        print(f"[WebsiteRecipe] done in {time.monotonic() - started:.1f}s thumb={thumbnail!r}")
        return raw, creator, thumbnail

    reason = "no HTML" if not _html_looks_usable(html) else "no Recipe JSON-LD / recipe elements"
    print(f"[WebsiteRecipe] {reason}; sending URL to GPT: {page_url}")
    raw = _call_gpt_from_url(
        page_url,
        language,
        include_nutrition=include_nutrition,
        adjustments=adjustments,
    )
    thumbnail = await _cloudinary_url_for_page_image(page_image, page_url=page_url)
    print(f"[WebsiteRecipe] URL fallback done in {time.monotonic() - started:.1f}s thumb={thumbnail!r}")
    return raw, "", thumbnail
