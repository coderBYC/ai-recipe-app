"""Identify fridge items from a photo using Gemini 2.5 Flash."""

from __future__ import annotations

import json
import os
import time
from datetime import date, datetime, timedelta

from config import GEMINI_API_KEY
from google import genai
from google.genai import types  # pyright: ignore[reportMissingImports]
from recipe_analysis import extract_json_from_response

_FRIDGE_SCAN_MODEL = (os.getenv("FRIDGE_SCAN_GEMINI_MODEL") or "gemini-2.5-flash").strip()
_MAX_IMAGE_BYTES = 15 * 1024 * 1024


class FridgeScanError(Exception):
    """Raised when scan fails; route maps to HTTP status."""


def _build_scan_prompt(zone: str, today: date) -> str:
    return f"""Analyze this photo of a refrigerator zone.

The photo shows the **{zone}** section of the fridge (this is where these items are stored).

Identify every distinct food or drink item you can see. For each item return:
- "name": clear, concise item name (no emoji)
- "quantity_display": estimated amount (e.g. "1 bottle", "half full", "6 eggs") or "" if unknown
- "expiration_date": ISO date YYYY-MM-DD if printed on packaging; otherwise your best estimate from typical shelf life starting today ({today.isoformat()}); use null only if you truly cannot estimate

Return valid JSON only, no markdown:
{{"items": [{{"name": "Greek yogurt", "quantity_display": "1 tub", "expiration_date": "2026-06-15"}}]}}

If nothing edible is visible, return {{"items": []}}."""


def _normalize_expiration(raw, *, reference: date) -> str:
    default = (reference + timedelta(days=7)).isoformat()
    if raw is None:
        return default
    if isinstance(raw, str):
        text = raw.strip()
        if not text or text.lower() in ("null", "none", "unknown"):
            return default
        for fmt in ("%Y-%m-%d", "%m/%d/%Y", "%d/%m/%Y"):
            try:
                return datetime.strptime(text[:10], fmt).date().isoformat()
            except ValueError:
                continue
    return default


def scan_fridge_photo(zone: str, image_bytes: bytes, mime_type: str) -> list[dict]:
    zone_name = (zone or "").strip()
    if not zone_name:
        raise FridgeScanError("Zone is required")
    if not image_bytes:
        raise FridgeScanError("Image is empty")
    if len(image_bytes) > _MAX_IMAGE_BYTES:
        raise FridgeScanError("Image is too large (max 15 MB)")

    if not GEMINI_API_KEY:
        raise FridgeScanError("Gemini API key not configured")

    mime = (mime_type or "image/jpeg").strip().lower()
    if not mime.startswith("image/"):
        mime = "image/jpeg"

    today = date.today()
    prompt = _build_scan_prompt(zone_name, today)
    client = genai.Client(api_key=GEMINI_API_KEY)
    image_part = types.Part.from_bytes(data=image_bytes, mime_type=mime)
    contents = [prompt, image_part]

    started = time.monotonic()
    try:
        print(f"[FridgeScan] zone={zone_name!r} model={_FRIDGE_SCAN_MODEL} bytes={len(image_bytes)}")
        response = client.models.generate_content(
            model=_FRIDGE_SCAN_MODEL,
            contents=contents,
        )
    except Exception as e:
        raise FridgeScanError(f"Gemini scan failed: {e}") from e

    raw = (getattr(response, "text", None) or "").strip()
    print(f"[FridgeScan] Gemini done in {time.monotonic() - started:.1f}s")
    if not raw:
        raise FridgeScanError("Gemini returned empty response")

    try:
        data = extract_json_from_response(raw)
    except (ValueError, json.JSONDecodeError) as e:
        raise FridgeScanError(
            f"Model response was not valid JSON: {e}. Raw (first 400 chars): {raw[:400]!r}"
        ) from e

    items_raw = data.get("items")
    if not isinstance(items_raw, list):
        raise FridgeScanError("Model JSON missing items array")

    out: list[dict] = []
    for row in items_raw:
        if not isinstance(row, dict):
            continue
        name = str(row.get("name", "") or "").strip()
        if not name:
            continue
        quantity = str(row.get("quantity_display", "") or "").strip()
        expiration = _normalize_expiration(row.get("expiration_date"), reference=today)
        out.append(
            {
                "name": name,
                "quantity_display": quantity,
                "expiration_date": expiration,
            }
        )
    print(f"[FridgeScan] parsed {len(out)} item(s)")
    return out
