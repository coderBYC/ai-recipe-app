"""URL classification and platform metadata helpers."""

from __future__ import annotations

import httpx


def is_youtube_url(url: str) -> bool:
    u = (url or "").lower().strip()
    return "youtube.com" in u or "youtu.be" in u


def is_tiktok_url(url: str) -> bool:
    u = (url or "").lower().strip()
    return "tiktok.com" in u or "vt.tiktok.com" in u


def is_instagram_url(url: str) -> bool:
    u = (url or "").lower().strip()
    return "instagram.com" in u or "instagr.am" in u


def source_type_for_url(url: str) -> str:
    u = (url or "").lower()
    if "instagram.com" in u or "instagr.am" in u:
        return "instagram"
    if "tiktok.com" in u or "vt.tiktok.com" in u:
        return "tiktok"
    if "youtube.com" in u or "youtu.be" in u:
        return "youtube"
    return "other"


async def youtube_oembed_author_name(video_url: str) -> str:
    """Official channel display name from YouTube oEmbed (no API key)."""
    try:
        api = "https://www.youtube.com/oembed"
        params = {"url": video_url.strip(), "format": "json"}
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(api, params=params)
        if resp.status_code != 200:
            return ""
        payload = resp.json()
        return (payload.get("author_name") or "").strip()
    except Exception:
        return ""
