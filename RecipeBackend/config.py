"""Environment variables and shared constants."""

from __future__ import annotations

import os
from pathlib import Path

from ai_video_analysis import clean_env
from dotenv import load_dotenv

_backend_dir = Path(__file__).resolve().parent
load_dotenv(_backend_dir / ".env")
load_dotenv(_backend_dir.parent / ".env")

GEMINI_API_KEY = clean_env("GEMINI_API_KEY")  # pyright: ignore[reportOptionalMemberAccess]
OPENAI_API_KEY = clean_env("OPENAI_API_KEY")
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY")
PUBLIC_BASE_URL = os.getenv("PUBLIC_BASE_URL", "").strip().rstrip("/")

FREE_INSTAGRAM_COOLDOWN_SECONDS = max(0, int(os.getenv("FREE_INSTAGRAM_COOLDOWN_SECONDS", "60")))
FREE_TIKTOK_COOLDOWN_SECONDS = max(0, int(os.getenv("FREE_TIKTOK_COOLDOWN_SECONDS", "60")))
# Free import cap is enforced in Supabase (`use_ai_once` / profiles.ai_usage_count). Default cap: 3.

IMPORT_JOBS_TABLE = "import_jobs"
IMPORT_POLL_INTERVAL_SEC = max(1.0, float(os.getenv("IMPORT_POLL_INTERVAL_SEC", "2")))
IMPORT_SCAN_BATCH = max(1, int(os.getenv("IMPORT_SCAN_BATCH", "10")))
IMPORT_WORKER_CONCURRENCY = max(1, int(os.getenv("IMPORT_WORKER_CONCURRENCY", "2")))
IMPORT_RETRY_AFTER_429_SEC = max(5.0, float(os.getenv("IMPORT_RETRY_AFTER_429_SEC", "300")))
_LOCAL_PORT = (os.getenv("PORT") or "8000").strip() or "8000"
IMPORT_WORKER_LOCAL_API_BASE = os.getenv(
    "IMPORT_WORKER_LOCAL_API_BASE",
    f"http://127.0.0.1:{_LOCAL_PORT}",
).strip().rstrip("/")
ANALYZE_QUEUE_WAIT_TIMEOUT_SEC = max(5.0, float(os.getenv("ANALYZE_QUEUE_WAIT_TIMEOUT_SEC", "240")))
ANALYZE_QUEUE_WAIT_POLL_SEC = max(0.2, float(os.getenv("ANALYZE_QUEUE_WAIT_POLL_SEC", "1.0")))

SERVED_THUMBS_DIR = "served_thumbnails"
SERVED_VIDEOS_DIR = "served_videos"
MAX_VIDEO_UPLOAD_BYTES = 200 * 1024 * 1024
ALLOWED_VIDEO_SUFFIXES = {".mp4", ".mov", ".m4v", ".mpeg", ".mpg"}
