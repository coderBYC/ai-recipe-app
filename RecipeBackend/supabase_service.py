"""Supabase RPC and profile table operations."""

from __future__ import annotations

from fastapi import HTTPException  # pyright: ignore[reportMissingImports]
from postgrest.exceptions import APIError  # pyright: ignore[reportMissingImports]

from supabase_client import api_error_detail, get_supabase, supabase_call


async def rpc_use_export_once(user_id: str) -> None:
    sb = get_supabase()
    if not sb:
        return

    def _rpc() -> None:
        sb.rpc("use_export_once", {"user_id": user_id}).execute()

    try:
        print(f"supabase_rpc_use_export_once: {user_id}")
        await supabase_call(_rpc)
    except APIError as e:
        raise HTTPException(
            status_code=429,
            detail=f"Export usage limit reached or not allowed: {api_error_detail(e)}",
        ) from e


async def update_profile_plan(user_id: str, plan_type: str) -> None:
    """PATCH `profiles.plan_type` for the given user (service role). No-op if Supabase is not configured."""
    sb = get_supabase()
    if not sb:
        return

    def _patch() -> None:
        sb.table("profiles").update({"plan_type": plan_type}).eq("id", user_id).execute()

    try:
        await supabase_call(_patch)
    except APIError as e:
        raise HTTPException(
            status_code=400,
            detail=f"Could not update subscription plan: {api_error_detail(e)}",
        ) from e
