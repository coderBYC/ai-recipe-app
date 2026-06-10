"""Legacy thumbnail redirect endpoint."""

from __future__ import annotations

import os

from cloudinaryconfig import thumbnail_delivery_url
from fastapi import APIRouter  # pyright: ignore[reportMissingImports]
from fastapi.responses import FileResponse, RedirectResponse  # pyright: ignore[reportMissingImports]
from thumbnails import legacy_thumbnail_path

router = APIRouter(tags=["thumbnails"])


@router.get("/thumbnail/{thumb_id}")
async def serve_thumbnail(thumb_id: str):
    """
    Legacy route for old Render/local URLs. New imports store Cloudinary URLs directly.
    Redirects to Cloudinary; falls back to local JPG if present from older builds.
    """
    path = legacy_thumbnail_path(thumb_id)
    if os.path.isfile(path):
        return FileResponse(path, media_type="image/jpeg")
    return RedirectResponse(url=thumbnail_delivery_url(thumb_id), status_code=307)
