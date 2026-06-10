"""Extract video frames and upload thumbnails to Cloudinary."""

from __future__ import annotations

import os
import uuid
from pathlib import Path
from typing import Optional

import cv2
from cloudinaryconfig import upload_thumbnail_jpg
from config import ALLOWED_VIDEO_SUFFIXES, SERVED_THUMBS_DIR
from fastapi import Request  # pyright: ignore[reportMissingImports]


def upload_suffix(filename: str) -> str:
    ext = Path(filename or "").suffix.lower()
    return ext if ext in ALLOWED_VIDEO_SUFFIXES else ".mp4"


def save_thumbnail_from_video(video_path: str, request: Request, seconds: float) -> Optional[str]:
    """
    Extract one frame from `video_path`, upload JPEG to Cloudinary ``thumbnail/{thumb_id}``,
    and return the public CDN URL.
    """
    _ = request
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return None
    try:
        fps = cap.get(cv2.CAP_PROP_FPS) or 0.0
        frame_count = cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0.0
        if fps > 0 and frame_count > 0:
            duration = frame_count / fps
            target_sec = max(0.0, min(seconds, duration * 0.99))
        else:
            target_sec = max(0.0, seconds)
        cap.set(cv2.CAP_PROP_POS_MSEC, target_sec * 1000.0)
        ok, frame = cap.read()
        if not ok or frame is None:
            cap.set(cv2.CAP_PROP_POS_MSEC, 0)
            ok, frame = cap.read()
            if not ok or frame is None:
                return None
        thumb_id = str(uuid.uuid4())
        ok_encode, buf = cv2.imencode(".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), 85])
        if not ok_encode:
            return None
        try:
            url = upload_thumbnail_jpg(buf.tobytes(), thumb_id)
            print(f"[Thumbnail] uploaded to Cloudinary: {url}")
            return url
        except Exception as e:
            print(f"[Thumbnail] Cloudinary upload failed: {e!r}")
            return None
    finally:
        cap.release()


def legacy_thumbnail_path(thumb_id: str) -> str:
    return os.path.join(SERVED_THUMBS_DIR, f"{thumb_id}.jpg")
