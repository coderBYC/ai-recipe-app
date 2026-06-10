"""Import queue HTTP endpoints."""

from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, HTTPException, Request  # pyright: ignore[reportMissingImports]
from import_jobs_service import (
    enqueue_import_batch,
    enqueue_import_job,
    get_import_job_for_user,
    list_import_jobs_for_user,
)
from models import ImportBatchEnqueueRequest, ImportEnqueueRequest, ImportJobView
from quota import require_user_id

router = APIRouter(tags=["imports"])


@router.post("/import")
async def enqueue_import(request: Request, body: ImportEnqueueRequest):
    user_id = require_user_id(request)
    url = (body.url or "").strip()
    if not url:
        raise HTTPException(status_code=400, detail="URL is required")
    language = (body.language or "en").strip() or "en"
    row = await enqueue_import_job(user_id=user_id, url=url, language=language)
    return {"job_id": row["id"], "status": "pending"}


@router.post("/import/batch")
async def enqueue_import_batch_route(request: Request, body: ImportBatchEnqueueRequest):
    user_id = require_user_id(request)
    jobs = body.jobs or []
    if not jobs:
        raise HTTPException(status_code=400, detail="No jobs provided.")

    normalized = [
        {"url": (job.url or "").strip()}
        for job in jobs
        if (job.url or "").strip()
    ]
    if not normalized:
        raise HTTPException(status_code=400, detail="All job URLs are empty.")

    rows = await enqueue_import_batch(user_id=user_id, jobs=normalized)
    return {
        "count": len(rows),
        "job_ids": [r.get("id") for r in rows if isinstance(r, dict)],
        "status": "pending",
    }


@router.get("/import/jobs", response_model=list[ImportJobView])
async def list_import_jobs(
    request: Request,
    status: Optional[str] = None,
    limit: int = 50,
):
    user_id = require_user_id(request)
    return await list_import_jobs_for_user(user_id=user_id, status=status, limit=limit)


@router.get("/import/jobs/{job_id}", response_model=ImportJobView)
async def get_import_job(job_id: str, request: Request):
    user_id = require_user_id(request)
    return await get_import_job_for_user(user_id=user_id, job_id=job_id)
