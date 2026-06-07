"""Upload recipe thumbnails to Cloudinary folder ``thumbnail/{thumb_id}.jpg``."""

from __future__ import annotations

import io
import os
from pathlib import Path

import cloudinary
import cloudinary.uploader
from dotenv import load_dotenv

_backend_dir = Path(__file__).resolve().parent
load_dotenv(_backend_dir / ".env")
load_dotenv(_backend_dir.parent / ".env")

CLOUDINARY_CLOUD_NAME = (os.getenv("CLOUDINARY_CLOUD_NAME") or "dosog47lb").strip()
CLOUDINARY_THUMBNAIL_FOLDER = (os.getenv("CLOUDINARY_THUMBNAIL_FOLDER") or "thumbnail").strip().strip("/")


def configure_cloudinary() -> None:
    cloudinary.config(
        cloud_name=CLOUDINARY_CLOUD_NAME,
        api_key=os.getenv("CLOUDINARY_API_KEY"),
        api_secret=os.getenv("CLOUDINARY_API_SECRET"),
        secure=True,
    )


configure_cloudinary()


def thumbnail_delivery_url(thumb_id: str) -> str:
    """
    Public CDN URL for a thumbnail public id ``thumbnail/{thumb_id}``.

    Example: https://res.cloudinary.com/dosog47lb/image/upload/v1/thumbnail/{uuid}.png
    """
    tid = thumb_id.strip().strip("/")
    return (
        f"https://res.cloudinary.com/{CLOUDINARY_CLOUD_NAME}/image/upload/v1/"
        f"{CLOUDINARY_THUMBNAIL_FOLDER}/{tid}.jpg"
    )


def upload_thumbnail_jpg(image_bytes: bytes, thumb_id: str) -> str:
    """Upload JPEG bytes; returns Cloudinary ``secure_url`` (falls back to delivery URL)."""
    if not os.getenv("CLOUDINARY_API_KEY") or not os.getenv("CLOUDINARY_API_SECRET"):
        raise RuntimeError("CLOUDINARY_API_KEY and CLOUDINARY_API_SECRET must be set")

    configure_cloudinary()
    upload_result = cloudinary.uploader.upload(
        io.BytesIO(image_bytes),
        folder=CLOUDINARY_THUMBNAIL_FOLDER,
        public_id=thumb_id,
        overwrite=True,
        resource_type="image",
        format="jpg",
    )
    secure = (upload_result or {}).get("secure_url")
    if secure:
        return str(secure)
    return thumbnail_delivery_url(thumb_id)
