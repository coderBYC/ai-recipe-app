"""Pro/free entitlement checks and import/AI quota enforcement."""

from __future__ import annotations

from datetime import datetime, timezone

from config import FREE_INSTAGRAM_COOLDOWN_SECONDS, FREE_TIKTOK_COOLDOWN_SECONDS
from fastapi import HTTPException, Request  # pyright: ignore[reportMissingImports]
from postgrest.exceptions import APIError  # pyright: ignore[reportMissingImports]

from supabase_client import api_error_detail, get_supabase, supabase_call

# Platform spacing for free users (per backend instance). Import count lives in Supabase `ai_usage_count`.
_free_last_instagram_import_at: dict[str, float] = {}
_free_last_tiktok_import_at: dict[str, float] = {}


def require_user_id(request: Request) -> str:
    """Supabase auth user id from the app (same header as analyze routes)."""
    user_id = (request.headers.get("X-User-Id") or "").strip()
    if not user_id:
        raise HTTPException(status_code=401, detail="Missing X-User-Id.")
    return user_id


async def verify_ai_quota(request: Request) -> None:
    """
    Authoritative import/AI quota via Supabase RPC `use_ai_once`.
    Increments `profiles.ai_usage_count` atomically; free cap is enforced in Postgres.
    """
    sb = get_supabase()
    if not sb:
        return

    user_id = require_user_id(request)

    def _rpc() -> None:
        sb.rpc("use_ai_once", {"user_id": user_id}).execute()

    try:
        await supabase_call(_rpc)
    except APIError as e:
        raise HTTPException(
            status_code=429,
            detail=f"Free import limit reached or not allowed: {api_error_detail(e)}",
        ) from e


async def is_pro_user(request: Request) -> bool:
    """
    Determine Pro entitlement.

    Priority:
    1) If the app sends `X-Is-Pro`, use it (RevenueCat entitlement).
    2) Otherwise, fall back to Supabase `profiles.plan_type`.
    """
    header_plan = (request.headers.get("X-Is-Pro") or "").strip().lower()
    if header_plan:
        return header_plan in {"true", "1", "pro", "premium", "yes"}

    sb = get_supabase()
    if not sb:
        return False

    user_id = request.headers.get("X-User-Id")
    if not user_id:
        return False

    def _fetch_plan() -> str:
        res = sb.table("profiles").select("plan_type").eq("id", user_id).limit(1).execute()
        rows = getattr(res, "data", None) or []
        if not rows:
            return ""
        return str((rows[0] or {}).get("plan_type") or "").strip().lower()

    try:
        plan = await supabase_call(_fetch_plan)
        return plan == "pro"
    except Exception:
        return False


def _cooldown_http_detail(platform: str, remaining_sec: int) -> str:
    if remaining_sec >= 60:
        mins = max(1, remaining_sec // 60)
        return f"Free plan {platform} cooldown: try again in about {mins} minute(s)."
    return f"Free plan {platform} cooldown: try again in about {max(1, remaining_sec)} second(s)."


async def _enforce_free_platform_cooldowns(request: Request, source_kind: str) -> None:
    """Spacing between Instagram/TikTok attempts for free users (in-process; not stored in Supabase)."""
    user_id = require_user_id(request)
    now = datetime.now(timezone.utc).timestamp()

    if source_kind == "instagram":
        last_at = _free_last_instagram_import_at.get(user_id)
        if last_at is not None:
            elapsed = now - last_at
            if elapsed < FREE_INSTAGRAM_COOLDOWN_SECONDS:
                remaining = int(FREE_INSTAGRAM_COOLDOWN_SECONDS - elapsed)
                raise HTTPException(
                    status_code=429,
                    detail=_cooldown_http_detail("Instagram", remaining),
                )
        _free_last_instagram_import_at[user_id] = now

    if source_kind == "tiktok":
        last_at = _free_last_tiktok_import_at.get(user_id)
        if last_at is not None:
            elapsed = now - last_at
            if elapsed < FREE_TIKTOK_COOLDOWN_SECONDS:
                remaining = int(FREE_TIKTOK_COOLDOWN_SECONDS - elapsed)
                raise HTTPException(
                    status_code=429,
                    detail=_cooldown_http_detail("TikTok", remaining),
                )
        _free_last_tiktok_import_at[user_id] = now


async def enforce_import_quota(request: Request, source_kind: str) -> None:
    """
    All users: Supabase `use_ai_once` (free cap = profiles.ai_usage_count in DB).
    Free users only: optional Instagram/TikTok cooldown spacing.
    """
    if not await is_pro_user(request):
        await _enforce_free_platform_cooldowns(request, source_kind)
    await verify_ai_quota(request)
