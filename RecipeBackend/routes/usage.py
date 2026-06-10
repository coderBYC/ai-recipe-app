"""Usage and profile endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Request  # pyright: ignore[reportMissingImports]
from models import PlanUpdateRequest
from quota import require_user_id
from supabase_service import rpc_use_export_once, update_profile_plan

router = APIRouter(tags=["usage"])


@router.post("/usage/export_once")
async def usage_export_once(request: Request):
    """Records one recipe export/share against the user's quota (Supabase RPC `use_export_once`)."""
    user_id = require_user_id(request)
    print(f"usage_export_once: {user_id}")
    await rpc_use_export_once(user_id)
    return {"ok": True}


@router.post("/profile/plan")
async def profile_update_plan(request: Request, body: PlanUpdateRequest):
    """Mirrors RevenueCat entitlement to `profiles.plan_type` (e.g. pro / free)."""
    from fastapi import HTTPException  # pyright: ignore[reportMissingImports]

    user_id = require_user_id(request)
    raw = (body.plan_type or "").strip().lower()
    if raw not in {"pro", "free"}:
        raise HTTPException(status_code=400, detail="plan_type must be 'pro' or 'free'")
    await update_profile_plan(user_id, raw)
    return {"ok": True}
