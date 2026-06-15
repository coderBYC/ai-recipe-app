"""Fridge photo scan endpoint."""

from __future__ import annotations

import asyncio
import time

from config import MAX_VIDEO_UPLOAD_BYTES
from fastapi import APIRouter, File, Form, HTTPException, UploadFile  # pyright: ignore[reportMissingImports]
from fridge_scan import FridgeScanError, scan_fridge_photo
from models import FridgeScanItem, FridgeScanResponse

router = APIRouter(tags=["fridge"])

_MAX_IMAGE_BYTES = min(15 * 1024 * 1024, MAX_VIDEO_UPLOAD_BYTES)


@router.post("/scan-fridge", response_model=FridgeScanResponse)
async def scan_fridge(
    zone: str = Form(...),
    file: UploadFile = File(...),
):
    zone_name = (zone or "").strip()
    if not zone_name:
        raise HTTPException(status_code=400, detail="Zone is required")

    content_type = (file.content_type or "image/jpeg").strip().lower()
    if content_type and not content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="Upload must be an image")

    started = time.monotonic()
    try:
        image_bytes = await file.read()
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Could not read upload: {e}") from e

    if not image_bytes:
        raise HTTPException(status_code=400, detail="Image is empty")
    if len(image_bytes) > _MAX_IMAGE_BYTES:
        raise HTTPException(status_code=400, detail="Image is too large (max 15 MB)")

    print(f"[FridgeScan] request zone={zone_name!r} size={len(image_bytes)} type={content_type}")
    try:
        rows = await asyncio.to_thread(
            scan_fridge_photo,
            zone_name,
            image_bytes,
            content_type or "image/jpeg",
        )
    except FridgeScanError as e:
        print(f"[FridgeScan] failed after {time.monotonic() - started:.1f}s: {e}")
        raise HTTPException(status_code=503, detail=str(e)) from e
    except Exception as e:
        print(f"[FridgeScan] unexpected error after {time.monotonic() - started:.1f}s: {e!r}")
        raise HTTPException(status_code=503, detail=f"Scan failed: {e}") from e

    print(f"[FridgeScan] success in {time.monotonic() - started:.1f}s → {len(rows)} items")
    return FridgeScanResponse(
        items=[
            FridgeScanItem(
                name=str(row.get("name", "")),
                quantity_display=str(row.get("quantity_display", "") or ""),
                expiration_date=str(row.get("expiration_date", "") or ""),
            )
            for row in rows
        ]
    )
