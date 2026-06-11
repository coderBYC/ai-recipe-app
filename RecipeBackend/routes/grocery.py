"""Grocery list merge endpoint."""

from __future__ import annotations

from fastapi import APIRouter  # pyright: ignore[reportMissingImports]
from grocery_merge import merge_grocery_ingredients
from models import GroceryIngredientItem, GroceryMergeRequest, GroceryMergeResponse

router = APIRouter(tags=["grocery"])


@router.post("/merge_grocery", response_model=GroceryMergeResponse)
async def merge_grocery(body: GroceryMergeRequest):
    raw = [{"item": i.item, "amount": i.amount} for i in body.ingredients]
    merged = merge_grocery_ingredients(raw)
    return GroceryMergeResponse(
        ingredients=[
            GroceryIngredientItem(
                item=str(row.get("item", "")),
                amount=str(row.get("amount", "")),
            )
            for row in merged
        ]
    )
