"""Route registration."""

from __future__ import annotations

from fastapi import APIRouter, FastAPI  # pyright: ignore[reportMissingImports]

from routes import analyze, imports, thumbnails, usage, videos


def register_routes(app: FastAPI) -> None:
    api = APIRouter()
    api.include_router(usage.router)
    api.include_router(imports.router)
    api.include_router(thumbnails.router)
    api.include_router(videos.router)
    api.include_router(analyze.router)
    app.include_router(api)
