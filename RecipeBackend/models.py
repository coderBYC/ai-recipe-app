"""Pydantic request/response models."""

from __future__ import annotations

from typing import Any, Optional

from pydantic import BaseModel  # pyright: ignore[reportMissingImports]


class AnalyzeRequest(BaseModel):
    url: str
    language: str


class ImportEnqueueRequest(BaseModel):
    url: str
    language: str = "en"


class ImportBatchEnqueueRequest(BaseModel):
    jobs: list[ImportEnqueueRequest]


class ImportJobView(BaseModel):
    id: str
    url: str
    user_id: str
    source_type: str = "other"
    status: str
    created_at: Optional[str] = None
    updated_at: Optional[str] = None
    error_log: Optional[str] = None
    result_json: Optional[dict[str, Any]] = None


class RecipeResponse(BaseModel):
    recipe_name: str
    description: str
    creator: str = ""
    estimated_cooking_time: str = "0"
    prep_time: str = "0"
    estimated_servings: str = "1"
    ingredients: list
    instructions: list
    video_url: Optional[str] = None
    thumbnail_url: Optional[str] = None
    dish_hero_timestamp_seconds: str = "0"


class PlanUpdateRequest(BaseModel):
    plan_type: str


class GroceryIngredientItem(BaseModel):
    item: str
    amount: str = ""


class GroceryMergeRequest(BaseModel):
    ingredients: list[GroceryIngredientItem]


class GroceryMergeResponse(BaseModel):
    ingredients: list[GroceryIngredientItem]
