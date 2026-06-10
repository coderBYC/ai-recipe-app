"""Serve persisted MP4 files for Cook Mode frame capture."""

from __future__ import annotations

import os

from fastapi import APIRouter, HTTPException  # pyright: ignore[reportMissingImports]
from fastapi.responses import FileResponse  # pyright: ignore[reportMissingImports]
from served_videos import legacy_video_path

router = APIRouter(tags=["videos"])


@router.get("/video/{video_id}")
async def serve_video(video_id: str):
  path = legacy_video_path(video_id)
  if not os.path.isfile(path):
    raise HTTPException(status_code=404, detail="Video not found")
  return FileResponse(path, media_type="video/mp4")
