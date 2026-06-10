"""Persist downloaded MP4s for Cook Mode per-step frame capture on iOS."""

from __future__ import annotations

import os
import re
import shutil
import uuid
from typing import Optional

from config import PUBLIC_BASE_URL, SERVED_VIDEOS_DIR
from fastapi import Request  # pyright: ignore[reportMissingImports]


def resolve_public_base_url(request: Request | None) -> str:
    if request is not None:
        header = (request.headers.get("X-Public-Base-Url") or "").strip().rstrip("/")
        if header:
            return header
    if PUBLIC_BASE_URL:
        return PUBLIC_BASE_URL
    if request is not None and request.base_url:
        return str(request.base_url).rstrip("/")
    return ""


def legacy_video_path(video_id: str) -> str:
    safe = re.sub(r"[^a-zA-Z0-9\-]", "", video_id or "")
    return os.path.join(SERVED_VIDEOS_DIR, f"{safe}.mp4")


def persist_served_video(local_video_path: str, request: Request | None) -> Optional[str]:
    """
    Copy a temp download into ``served_videos/{uuid}.mp4`` and return a public playback URL.
    The source file may still be deleted by the caller after this returns.
    """
    if not local_video_path or not os.path.isfile(local_video_path):
        return None
    base = resolve_public_base_url(request)
    if not base:
        print("[ServedVideo] skip persist: PUBLIC_BASE_URL / X-Public-Base-Url not set")
        return None

    os.makedirs(SERVED_VIDEOS_DIR, exist_ok=True)
    video_id = str(uuid.uuid4())
    dest = legacy_video_path(video_id)
    try:
        shutil.copy2(local_video_path, dest)
    except OSError as e:
        print(f"[ServedVideo] copy failed: {e!r}")
        return None

    url = f"{base}/video/{video_id}"
    print(f"[ServedVideo] persisted {dest} -> {url}")
    return url
