"""FastAPI application entrypoint."""

from __future__ import annotations

from contextlib import asynccontextmanager

from ai_video_analysis import recipe_ai_provider_chain
from config import (
    GEMINI_API_KEY,
    IMPORT_JOBS_TABLE,
    IMPORT_POLL_INTERVAL_SEC,
    IMPORT_RETRY_AFTER_429_SEC,
    IMPORT_SCAN_BATCH,
    IMPORT_WORKER_CONCURRENCY,
    IMPORT_WORKER_LOCAL_API_BASE,
    OPENAI_API_KEY,
)
from fastapi import FastAPI  # pyright: ignore[reportMissingImports]
from fastapi.middleware.cors import CORSMiddleware  # pyright: ignore[reportMissingImports]
from import_worker_state import get_import_worker, set_import_worker
from routes import register_routes
from supabase_client import get_supabase, supabase_call
from worker import ImportQueueWorker


@asynccontextmanager
async def lifespan(app: FastAPI):
    chain = recipe_ai_provider_chain()
    print(
        f"[RecipeAI] provider chain: {' → '.join(chain)} "
        f"(openai_key={'yes' if OPENAI_API_KEY else 'no'}, "
        f"gemini_key={'yes' if GEMINI_API_KEY else 'no'})"
    )

    if get_import_worker() is None:
        worker = ImportQueueWorker(
            concurrency=IMPORT_WORKER_CONCURRENCY,
            poll_interval_sec=IMPORT_POLL_INTERVAL_SEC,
            scan_batch=IMPORT_SCAN_BATCH,
            retry_after_429_sec=IMPORT_RETRY_AFTER_429_SEC,
            local_api_base=IMPORT_WORKER_LOCAL_API_BASE,
            jobs_table=IMPORT_JOBS_TABLE,
            get_supabase=get_supabase,
            supabase_call=supabase_call,
        )
        set_import_worker(worker)
        await worker.start()

    yield

    worker = get_import_worker()
    if worker is not None:
        await worker.stop()
        set_import_worker(None)


app = FastAPI(lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

register_routes(app)


@app.get("/healthz")
async def healthz():
    return {"ok": True}
