"""URL classification and platform metadata helpers."""

from __future__ import annotations

from typing import Optional
from urllib.parse import parse_qs, urlparse

import httpx


def is_youtube_url(url: str) -> bool:
    u = (url or "").lower().strip()
    return "youtube.com" in u or "youtu.be" in u


def youtube_video_id(url: str) -> Optional[str]:
    """Extract a YouTube video id from watch, youtu.be, embed, or shorts URLs."""
    raw = (url or "").strip()
    if not raw:
        return None
    parsed = urlparse(raw)
    host = (parsed.netloc or "").lower().replace("www.", "")
    path = parsed.path or ""

    if host in ("youtu.be",):
        candidate = path.lstrip("/").split("/")[0].split("?")[0]
        return candidate or None

    if "youtube.com" not in host:
        return None

    if path.startswith("/shorts/"):
        parts = [p for p in path.split("/") if p]
        return parts[1] if len(parts) >= 2 and parts[0] == "shorts" else None
    if path.startswith("/embed/"):
        parts = [p for p in path.split("/") if p]
        return parts[1] if len(parts) >= 2 and parts[0] == "embed" else None
    if path.startswith("/live/"):
        parts = [p for p in path.split("/") if p]
        return parts[1] if len(parts) >= 2 and parts[0] == "live" else None

    query = parse_qs(parsed.query)
    video_ids = query.get("v") or []
    if video_ids:
        return (video_ids[0] or "").strip() or None
    return None


def youtube_watch_url(url: str) -> str:
    """Canonical watch URL for Gemini YouTube attachment."""
    video_id = youtube_video_id(url)
    if video_id:
        return f"https://www.youtube.com/watch?v={video_id}"
    return (url or "").strip()


def youtube_thumbnail_url(url: str) -> str:
    video_id = youtube_video_id(url)
    if not video_id:
        return ""
    return f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg"


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
