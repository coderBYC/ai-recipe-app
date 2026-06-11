"""Grocery list merge endpoint."""

from __future__ import annotations

import asyncio
import time

from fastapi import APIRouter, HTTPException  # pyright: ignore[reportMissingImports]
from grocery_merge import GroceryMergeError, merge_grocery_ingredients
from models import GroceryIngredientItem, GroceryMergeRequest, GroceryMergeResponse

router = APIRouter(tags=["grocery"])


@router.post("/merge_grocery", response_model=GroceryMergeResponse)
async def merge_grocery(body: GroceryMergeRequest):
    raw = [{"item": i.item, "amount": i.amount} for i in body.ingredients]
    print(f"[GroceryMerge] request: {len(raw)} ingredient lines")
    started = time.monotonic()
    try:
        merged = await asyncio.to_thread(merge_grocery_ingredients, raw)
    except GroceryMergeError as e:
        print(f"[GroceryMerge] failed after {time.monotonic() - started:.1f}s: {e}")
        raise HTTPException(status_code=503, detail=str(e)) from e
    except Exception as e:
        print(f"[GroceryMerge] unexpected error after {time.monotonic() - started:.1f}s: {e!r}")
        raise HTTPException(status_code=503, detail=f"Merge failed: {e}") from e

    print(f"[GroceryMerge] success in {time.monotonic() - started:.1f}s → {len(merged)} lines")
    return GroceryMergeResponse(
        ingredients=[
            GroceryIngredientItem(
                item=str(row.get("item", "")),
                amount=str(row.get("amount", "")),
            )
            for row in merged
        ]
    )
