"""Merge grocery ingredients via OpenAI GPT-4o-mini."""

from __future__ import annotations

import json
import os
import time

from config import OPENAI_API_KEY
from openai import OpenAI  # pyright: ignore[reportMissingImports]
from recipe_analysis import extract_json_from_response

_MAX_INPUT_LINES = 120
_OPENAI_TIMEOUT_SEC = float(os.getenv("GROCERY_MERGE_OPENAI_TIMEOUT_SEC", "90"))


class GroceryMergeError(Exception):
    """Raised when merge fails; route maps to HTTP status."""


def _build_merge_prompt(ingredients: list[dict]) -> str:
    trimmed = ingredients[:_MAX_INPUT_LINES]
    payload = json.dumps(trimmed, ensure_ascii=False)
    return f"""Merge these grocery ingredients from multiple recipes into one consolidated shopping list.

Input ({len(trimmed)} lines):
{payload}

Rules:
1. Combine duplicate or equivalent ingredients (sum amounts when units match; otherwise keep separate lines).
2. Keep unrelated items as separate lines.
3. Put one fitting food emoji at the START of each item name (e.g. "🍔 Ground beef", "🧅 Onion").
4. If quantity is unknown, use "As needed" for amount.
5. Return JSON only matching this schema exactly:
{{"ingredients": [{{"item": "🍔 Name", "amount": "qty unit"}}]}}"""


def merge_grocery_ingredients(ingredients: list[dict]) -> list[dict]:
    if not ingredients:
        return []
    if not OPENAI_API_KEY:
        raise GroceryMergeError("OpenAI API key not configured")

    client = OpenAI(api_key=OPENAI_API_KEY, timeout=_OPENAI_TIMEOUT_SEC, max_retries=2)
    prompt = _build_merge_prompt(ingredients)
    started = time.monotonic()

    try:
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You merge grocery shopping lists. "
                        "Respond with a single JSON object only."
                    ),
                },
                {"role": "user", "content": prompt},
            ],
            temperature=0.2,
            response_format={"type": "json_object"},
        )
    except Exception as e:
        raise GroceryMergeError(f"OpenAI merge failed: {e}") from e

    elapsed = time.monotonic() - started
    raw = (response.choices[0].message.content or "").strip()
    print(f"[GroceryMerge] OpenAI done in {elapsed:.1f}s, {len(ingredients)} in → parsing")
    if not raw:
        raise GroceryMergeError("OpenAI returned empty response")

    try:
        data = extract_json_from_response(raw)
    except (ValueError, json.JSONDecodeError) as e:
        raise GroceryMergeError(
            f"Model response was not valid JSON: {e}. Raw (first 400 chars): {raw[:400]!r}"
        ) from e

    merged = data.get("ingredients")
    if not isinstance(merged, list):
        raise GroceryMergeError("Model JSON missing ingredients array")

    out: list[dict] = []
    for row in merged:
        if not isinstance(row, dict):
            continue
        item = str(row.get("item", "") or "").strip()
        amount = str(row.get("amount", "") or "").strip()
        if not item:
            continue
        out.append({"item": item, "amount": amount or "As needed"})
    print(f"[GroceryMerge] merged to {len(out)} lines")
    return out
