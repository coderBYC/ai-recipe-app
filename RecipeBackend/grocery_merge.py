"""Merge grocery ingredients via OpenAI GPT-4o-mini."""

from __future__ import annotations

import json

from config import OPENAI_API_KEY
from fastapi import HTTPException  # pyright: ignore[reportMissingImports]
from openai import OpenAI  # pyright: ignore[reportMissingImports]
from recipe_analysis import extract_json_from_response


def _build_merge_prompt(ingredients: list[dict]) -> str:
    payload = json.dumps(ingredients, ensure_ascii=False)
    return f"""Merge these grocery ingredients from multiple recipes into one consolidated shopping list.

Input:
{payload}

Rules:
1. Combine duplicate or equivalent ingredients (sum amounts when units match; otherwise keep separate lines).
2. Keep unrelated items as separate lines.
3. Put one fitting food emoji at the START of each item name (e.g. "🍔 Ground beef", "🧅 Onion").
4. If quantity is unknown, use "As needed" for amount.
5. Return valid JSON only — no markdown, no commentary.

Output JSON schema:
{{
  "ingredients": [
    {{"item": "🍔 Ingredient name", "amount": "quantity and unit"}}
  ]
}}"""


def merge_grocery_ingredients(ingredients: list[dict]) -> list[dict]:
    if not ingredients:
        return []
    if not OPENAI_API_KEY:
        raise HTTPException(status_code=500, detail="OpenAI API key not configured")

    client = OpenAI(api_key=OPENAI_API_KEY)
    prompt = _build_merge_prompt(ingredients)

    try:
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {
                    "role": "system",
                    "content": "You merge grocery shopping lists. Respond with JSON only.",
                },
                {"role": "user", "content": prompt},
            ],
            temperature=0.2,
        )
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"OpenAI merge failed: {e}") from e

    raw = (response.choices[0].message.content or "").strip()
    if not raw:
        raise HTTPException(status_code=502, detail="OpenAI returned empty response")

    try:
        data = extract_json_from_response(raw)
    except (ValueError, json.JSONDecodeError) as e:
        raise HTTPException(
            status_code=502,
            detail=f"Model response was not valid JSON: {e}. Raw (first 400 chars): {raw[:400]!r}",
        ) from e

    merged = data.get("ingredients")
    if not isinstance(merged, list):
        raise HTTPException(status_code=502, detail="Model JSON missing ingredients array")

    out: list[dict] = []
    for row in merged:
        if not isinstance(row, dict):
            continue
        item = str(row.get("item", "") or "").strip()
        amount = str(row.get("amount", "") or "").strip()
        if not item:
            continue
        out.append({"item": item, "amount": amount or "As needed"})
    return out
