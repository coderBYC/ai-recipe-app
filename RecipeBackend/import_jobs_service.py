"""Supabase-backed import job queue operations."""

from __future__ import annotations

import asyncio
import time
from typing import Any, Optional

from config import (
    ANALYZE_QUEUE_WAIT_POLL_SEC,
    ANALYZE_QUEUE_WAIT_TIMEOUT_SEC,
    IMPORT_JOBS_TABLE,
)
from fastapi import HTTPException  # pyright: ignore[reportMissingImports]
from import_worker_state import get_import_worker
from models import ImportJobView
from postgrest.exceptions import APIError  # pyright: ignore[reportMissingImports]
from supabase_client import api_error_detail, get_supabase, supabase_call
from url_utils import source_type_for_url


async def enqueue_import_job(*, user_id: str, url: str, language: str) -> dict[str, Any]:
    _ = language  # reserved for future per-job language on worker row
    sb = get_supabase()
    if not sb:
        raise HTTPException(status_code=503, detail="Supabase is not configured on the server.")

    def _insert() -> Any:
        return (
            sb.table(IMPORT_JOBS_TABLE)
            .insert(
                {
                    "url": url,
                    "user_id": user_id,
                    "source_type": source_type_for_url(url),
                    "status": "pending",
                }
            )
            .execute()
        )

    try:
        job = await supabase_call(_insert)
    except APIError as e:
        raise HTTPException(status_code=400, detail=f"Supabase insert failed: {e.message}") from e
    rows = getattr(job, "data", None) or []
    if not rows:
        raise HTTPException(status_code=500, detail="Supabase insert returned no row.")
    worker = get_import_worker()
    if worker:
        await worker.nudge()
    return rows[0]


async def enqueue_import_batch(*, user_id: str, jobs: list[dict[str, str]]) -> list[dict[str, Any]]:
    sb = get_supabase()
    if not sb:
        raise HTTPException(status_code=503, detail="Supabase is not configured on the server.")

    rows_to_insert = [
        {
            "url": job["url"],
            "user_id": user_id,
            "source_type": source_type_for_url(job["url"]),
            "status": "pending",
        }
        for job in jobs
    ]

    def _insert_many() -> Any:
        return sb.table(IMPORT_JOBS_TABLE).insert(rows_to_insert).execute()

    try:
        inserted = await supabase_call(_insert_many)
    except APIError as e:
        raise HTTPException(status_code=400, detail=f"Supabase insert failed: {api_error_detail(e)}") from e

    rows = getattr(inserted, "data", None) or []
    worker = get_import_worker()
    if worker:
        await worker.nudge()
    return rows


async def wait_for_job_result(*, user_id: str, job_id: str, timeout_sec: float) -> dict[str, Any]:
    sb = get_supabase()
    if not sb:
        raise HTTPException(status_code=503, detail="Supabase is not configured on the server.")

    async def _load_once() -> Optional[dict[str, Any]]:
        def _q() -> Any:
            return (
                sb.table(IMPORT_JOBS_TABLE)
                .select("id,status,error_log,result_json")
                .eq("id", job_id)
                .eq("user_id", user_id)
                .limit(1)
                .execute()
            )

        try:
            res = await supabase_call(_q)
        except APIError as e:
            raise HTTPException(
                status_code=400,
                detail=f"Supabase job polling failed: {api_error_detail(e)}",
            ) from e
        rows = getattr(res, "data", None) or []
        if not rows:
            return None
        return rows[0] if isinstance(rows[0], dict) else None

    deadline = time.monotonic() + timeout_sec
    while time.monotonic() < deadline:
        row = await _load_once()
        if row:
            status = str(row.get("status") or "").lower()
            if status == "ready":
                payload = row.get("result_json")
                if isinstance(payload, dict):
                    return payload
                raise HTTPException(status_code=502, detail="Import finished without valid result_json.")
            if status == "failed":
                msg = row.get("error_log") or "Import failed."
                raise HTTPException(status_code=502, detail=str(msg))
        await asyncio.sleep(ANALYZE_QUEUE_WAIT_POLL_SEC)
    raise HTTPException(status_code=504, detail="Queued import timed out waiting for result.")


async def list_import_jobs_for_user(
    *,
    user_id: str,
    status: Optional[str],
    limit: int,
) -> list[ImportJobView]:
    sb = get_supabase()
    if not sb:
        raise HTTPException(status_code=503, detail="Supabase is not configured on the server.")
    capped_limit = max(1, min(limit, 200))

    def _query() -> Any:
        q = (
            sb.table(IMPORT_JOBS_TABLE)
            .select("id,url,user_id,source_type,status,created_at,updated_at,error_log,result_json")
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .limit(capped_limit)
        )
        if status:
            q = q.eq("status", status.strip().lower())
        return q.execute()

    try:
        res = await supabase_call(_query)
    except APIError as e:
        raise HTTPException(status_code=400, detail=f"Supabase query failed: {api_error_detail(e)}") from e
    rows = getattr(res, "data", None) or []
    return [ImportJobView(**row) for row in rows if isinstance(row, dict)]


async def get_import_job_for_user(*, user_id: str, job_id: str) -> ImportJobView:
    sb = get_supabase()
    if not sb:
        raise HTTPException(status_code=503, detail="Supabase is not configured on the server.")
    rid = (job_id or "").strip()
    if not rid:
        raise HTTPException(status_code=400, detail="job_id is required")

    def _query_one() -> Any:
        return (
            sb.table(IMPORT_JOBS_TABLE)
            .select("id,url,user_id,source_type,status,created_at,updated_at,error_log,result_json")
            .eq("id", rid)
            .eq("user_id", user_id)
            .limit(1)
            .execute()
        )

    try:
        res = await supabase_call(_query_one)
    except APIError as e:
        raise HTTPException(status_code=400, detail=f"Supabase query failed: {api_error_detail(e)}") from e
    rows = getattr(res, "data", None) or []
    if not rows:
        raise HTTPException(status_code=404, detail="Import job not found")
    return ImportJobView(**rows[0])


def default_analyze_wait_timeout() -> float:
    return ANALYZE_QUEUE_WAIT_TIMEOUT_SEC
