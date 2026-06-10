"""Supabase client helpers."""

from __future__ import annotations

import asyncio
from typing import Any, Callable, Optional, TypeVar

from config import SUPABASE_SERVICE_KEY, SUPABASE_URL
from postgrest.exceptions import APIError  # pyright: ignore[reportMissingImports]
from supabase import create_client  # pyright: ignore[reportMissingImports]

T = TypeVar("T")

_supabase_client: Any = None


def get_supabase() -> Optional[Any]:
    """Lazily create a Supabase client with the service role key (server-side only)."""
    global _supabase_client
    if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
        return None
    if _supabase_client is None:
        _supabase_client = create_client(
            SUPABASE_URL.strip().rstrip("/"),
            SUPABASE_SERVICE_KEY.strip(),
        )
    return _supabase_client


async def supabase_call(fn: Callable[[], T]) -> T:
    """Run sync supabase-py calls in a thread pool (FastAPI async routes)."""
    return await asyncio.to_thread(fn)


def api_error_detail(exc: APIError) -> str:
    parts = [exc.message or "Supabase error"]
    if exc.details:
        parts.append(str(exc.details))
    if exc.hint:
        parts.append(str(exc.hint))
    return " — ".join(parts)
