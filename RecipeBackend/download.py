from __future__ import annotations

import instaloader  # pyright: ignore[reportMissingImports]
import os
import re
import time
import glob
import subprocess
import threading
import uuid
import traceback
import shutil
from typing import Any, Optional, Tuple
#import pyktok as pyk # pyright: ignore[reportMissingImports]

import yt_dlp  # pyright: ignore[reportMissingImports]
from yt_dlp.utils import DownloadError  # pyright: ignore[reportMissingImports]

# Keep in sync with RecipeBackend/main.py MAX_VIDEO_UPLOAD_BYTES for Gemini uploads.
_MAX_YOUTUBE_DOWNLOAD_BYTES = 200 * 1024 * 1024


class InstagramBlockedError(Exception):
    """Raised when Instagram throttles or blocks scraping requests."""


class TikTokBlockedError(Exception):
    """Raised when TikTok or the downloader API throttles or blocks requests."""


_TIKTOK_DOWNLOAD_LOCK = threading.Lock()
_last_global_tiktok_attempt_at: float = 0.0

_TIKTOK_RATE_LIMIT_RE = re.compile(
    r"(rate\s*limit|ratelimit|too\s+many|429|captcha|verify\s+you|"
    r"blocked|try\s+again|ip\s*ban|forbidden|access\s+denied|"
    r"api\s+limit|empty\s+response|temporarily\s+unavailable|"
    r"service\s+unavailable|503|502|exceeded)",
    re.IGNORECASE,
)


def _tiktok_output_looks_rate_limited(text: str) -> bool:
    if not text or not text.strip():
        return False
    return bool(_TIKTOK_RATE_LIMIT_RE.search(text))


def _tiktok_min_interval_seconds() -> float:
    try:
        return max(0.0, float(os.environ.get("TIKTOK_MIN_INTERVAL_SECONDS", "45").strip()))
    except ValueError:
        return 45.0


def _tiktok_pre_fetch_delay_seconds() -> float:
    try:
        return max(0.0, float(os.environ.get("TIKTOK_PRE_FETCH_DELAY_SEC", "1").strip()))
    except ValueError:
        return 1.0


def _acquire_global_tiktok_slot() -> None:
    """Wait for minimum spacing since the last TikTok fetch (call while holding _TIKTOK_DOWNLOAD_LOCK)."""
    global _last_global_tiktok_attempt_at
    min_interval = _tiktok_min_interval_seconds()
    if min_interval > 0 and _last_global_tiktok_attempt_at > 0:
        elapsed = time.time() - _last_global_tiktok_attempt_at
        if elapsed < min_interval:
            time.sleep(min_interval - elapsed)
    pre_delay = _tiktok_pre_fetch_delay_seconds()
    if pre_delay > 0:
        time.sleep(min(pre_delay, 120.0))
    _last_global_tiktok_attempt_at = time.time()


def _node_executable() -> Optional[str]:
    """Resolve Node for TikTok helper (Docker sets NODE_EXECUTABLE=/usr/bin/node)."""
    env_bin = os.environ.get("NODE_EXECUTABLE", "").strip()
    if env_bin and os.path.isfile(env_bin) and os.access(env_bin, os.X_OK):
        return env_bin
    for path in ("/usr/bin/node", "/usr/local/bin/node"):
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    found = shutil.which("node")
    return found


def download_tiktok_video(url, target_dir="downloads"):
    """Download a TikTok video using @tobyg74/tiktok-api-dl.
    Returns (video_path, creator_name) on success, or None on failure.
    Raises TikTokBlockedError when the downloader API appears rate-limited.
    """
    script_dir = os.path.dirname(os.path.abspath(__file__))
    script_path = os.path.join(script_dir, "download_tiktok.js")
    if not os.path.isfile(script_path):
        print("❌ download_tiktok.js not found")
        return None
    os.makedirs(target_dir, exist_ok=True)
    out_name = f"tiktok_{uuid.uuid4().hex[:12]}.mp4"
    out_path = os.path.join(target_dir, out_name)
    creator_name = ""
    node_bin = _node_executable()
    if not node_bin:
        print("❌ Node.js not found (set NODE_EXECUTABLE or install node).")
        return None
    try:
        with _TIKTOK_DOWNLOAD_LOCK:
            _acquire_global_tiktok_slot()
            result = subprocess.run(
                [node_bin, script_path, url, os.path.abspath(out_path)],
                capture_output=True,
                text=True,
                timeout=120,
                cwd=script_dir,
            )
            combined_output = "\n".join(
                part for part in (result.stderr or "", result.stdout or "") if part
            )
            if result.returncode != 0:
                print(f"❌ TikTok download failed: {combined_output or '(no output)'}")
                if _tiktok_output_looks_rate_limited(combined_output):
                    raise TikTokBlockedError(
                        combined_output.strip()[:500] or "TikTok downloader rate limited"
                    )
                return None
            if result.stdout:
                for line in result.stdout.splitlines():
                    if line.startswith("CREATOR_NAME:"):
                        creator_name = line.split("CREATOR_NAME:", 1)[1].strip()
                        break
            if os.path.isfile(out_path) and os.path.getsize(out_path) > 0:
                return out_path, creator_name
            if _tiktok_output_looks_rate_limited(combined_output):
                raise TikTokBlockedError(
                    combined_output.strip()[:500] or "TikTok downloader returned no video"
                )
            return None
    except TikTokBlockedError:
        raise
    except subprocess.TimeoutExpired:
        print("❌ TikTok download timed out")
        raise TikTokBlockedError("TikTok download timed out (server may be throttled)")
    except FileNotFoundError:
        print("❌ Node.js not found. Install Node and run: npm install")
        return None
    except Exception as e:
        print(f"❌ Error in download_tiktok_video: {e}")
        traceback.print_exc()
        msg = str(e)
        if _tiktok_output_looks_rate_limited(msg):
            raise TikTokBlockedError(msg) from e
        return None


def _youtube_cookiefile() -> Optional[str]:
    """Netscape cookies.txt from a logged-in browser export; helps when PO-token / bot checks 403."""
    p = os.environ.get("YOUTUBE_COOKIES_FILE", "").strip()
    if p and os.path.isfile(p):
        return p
    return None


def _youtube_extractor_strategies() -> list[Optional[dict[str, Any]]]:
    """
    YouTube often 403s stream URLs for one InnerTube client while another works.
    Order: optional env override, defaults, then common fallbacks (see yt-dlp wiki / GitHub issues).
    """
    strategies: list[Optional[dict[str, Any]]] = []
    env_pc = os.environ.get("YOUTUBE_PLAYER_CLIENT", "").strip()
    if env_pc:
        clients = [c.strip() for c in env_pc.split(",") if c.strip()]
        if clients:
            strategies.append({"youtube": {"player_client": clients}})
    strategies.extend(
        [
            None,  # yt-dlp default client mix (keep updating: pip install -U yt-dlp)
            {"youtube": {"player_client": ["web_embedded"]}},
            {"youtube": {"player_client": ["tv"]}},
            {"youtube": {"player_client": ["ios", "web"]}},
            {"youtube": {"player_client": ["web"]}},
            {"youtube": {"player_client": ["mweb"]}},
            {"youtube": {"player_client": ["android", "web"]}},
        ]
    )
    return strategies


def _cleanup_youtube_attempt_files(target_dir: str, stem: str) -> None:
    for path in glob.glob(os.path.join(target_dir, stem + "*")):
        if not os.path.isfile(path):
            continue
        try:
            os.remove(path)
        except OSError:
            pass


def download_youtube_video(url: str, target_dir: str = "downloads") -> Optional[Tuple[str, str]]:
    """
    Download a YouTube video or Short with yt-dlp, then upload via Gemini Files API (not from_uri).
    Returns (local_video_path, uploader_name) on success, or None on failure.
    """
    os.makedirs(target_dir, exist_ok=True)
    stem = f"youtube_{uuid.uuid4().hex[:12]}"
    out_template = os.path.join(target_dir, f"{stem}.%(ext)s")
    cookiefile = _youtube_cookiefile()
    base_opts: dict[str, Any] = {
        "outtmpl": out_template,
        # Single-file formats only (no audio+video merge → no ffmpeg required on the server).
        "format": "best[ext=mp4]/best",
        "max_filesize": _MAX_YOUTUBE_DOWNLOAD_BYTES,
        "quiet": True,
        "no_warnings": True,
        "socket_timeout": 120,
        "retries": 2,
        "fragment_retries": 2,
        "noprogress": True,
        "noplaylist": True,
    }
    if cookiefile:
        base_opts["cookiefile"] = cookiefile

    last_err: Optional[BaseException] = None
    for attempt, extractor_args in enumerate(_youtube_extractor_strategies()):
        if attempt:
            _cleanup_youtube_attempt_files(target_dir, stem)
        ydl_opts = dict(base_opts)
        if extractor_args is not None:
            ydl_opts["extractor_args"] = extractor_args
        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                if not info:
                    continue
                if info.get("entries"):
                    continue
                path = ydl.prepare_filename(info)
                creator = (info.get("uploader") or info.get("channel") or "").strip()
            if not path or not os.path.isfile(path):
                matches = glob.glob(os.path.join(target_dir, f"{stem}.*"))
                matches = [p for p in matches if os.path.isfile(p) and not p.endswith(".part")]
                path = max(matches, key=os.path.getmtime) if matches else ""
            if path and os.path.isfile(path) and os.path.getsize(path) > 0:
                return path, creator
        except DownloadError as e:
            last_err = e
            msg = str(e).split("\n", 1)[0]
            print(f"⚠️ YouTube download attempt {attempt + 1} failed ({extractor_args!r}): {msg}")
            continue
        except Exception as e:
            last_err = e
            print(f"⚠️ YouTube download attempt {attempt + 1} error: {e}")
            traceback.print_exc()
            continue

    if last_err:
        print(f"❌ Error in download_youtube_video after all strategies: {last_err}")
    return None


_IPHONE_UA = (
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
)

_INSTAGRAM_SHORTCODE_RE = re.compile(
    r"(?:instagram\.com|instagr\.am)/(?:reel|reels|p|tv)/([A-Za-z0-9_-]+)",
    re.IGNORECASE,
)


def _instagram_shortcode_from_url(url: str) -> Optional[str]:
    m = _INSTAGRAM_SHORTCODE_RE.search((url or "").strip())
    return m.group(1) if m else None


def _instagram_error_looks_blocked(msg: str) -> bool:
    lower = (msg or "").lower()
    return any(
        token in lower
        for token in (
            "please wait a few minutes",
            "401 unauthorized",
            "403 forbidden",
            "challenge_required",
            "login_required",
            "bad response",
            "fetching post metadata failed",
            "nonetype",
            "rate limit",
            "feedback_required",
        )
    )


def _download_instagram_via_ytdlp(
    url: str, target_dir: str, shortcode: str
) -> Optional[Tuple[str, str, str]]:
    """Fallback when instaloader metadata/download fails (uses same stack as YouTube)."""
    os.makedirs(target_dir, exist_ok=True)
    stem = f"ig_{shortcode}_{uuid.uuid4().hex[:8]}"
    out_template = os.path.join(target_dir, f"{stem}.%(ext)s")
    cookiefile = _youtube_cookiefile()
    ydl_opts: dict[str, Any] = {
        "outtmpl": out_template,
        "format": "best[ext=mp4]/best",
        "quiet": True,
        "no_warnings": True,
        "socket_timeout": 120,
        "retries": 2,
        "noprogress": True,
        "noplaylist": True,
    }
    if cookiefile:
        ydl_opts["cookiefile"] = cookiefile
    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=True)
            if not info or info.get("entries"):
                return None
            path = ydl.prepare_filename(info)
            creator = (
                (info.get("uploader") or info.get("channel") or info.get("creator") or "")
                .strip()
            )
            caption = (info.get("description") or "").strip()
            if len(caption) > 2000:
                caption = caption[:2000]
        if not path or not os.path.isfile(path):
            matches = glob.glob(os.path.join(target_dir, f"{stem}.*"))
            matches = [p for p in matches if os.path.isfile(p) and not p.endswith(".part")]
            path = max(matches, key=os.path.getmtime) if matches else ""
        if not path or not os.path.isfile(path) or os.path.getsize(path) <= 0:
            return None
        final_path = os.path.join(target_dir, f"{shortcode}.mp4")
        if os.path.exists(final_path):
            os.remove(final_path)
        os.rename(path, final_path)
        return final_path, creator, caption
    except DownloadError as e:
        print(f"⚠️ Instagram yt-dlp fallback failed: {e}")
        return None
    except Exception as e:
        print(f"⚠️ Instagram yt-dlp fallback error: {e}")
        traceback.print_exc()
        return None


def download_instagram_reel(url, target_dir="downloads") -> Optional[Tuple[str, str, str]]:
    # Optional courtesy delay before hitting Instagram (was 2–5s random). Set INSTAGRAM_PRE_FETCH_DELAY_SEC=0 to skip.
    try:
        delay = float(os.environ.get("INSTAGRAM_PRE_FETCH_DELAY_SEC", "0.5").strip())
    except ValueError:
        delay = 0.5
    if delay > 0:
        time.sleep(min(delay, 30.0))
    ua = os.environ.get("INSTAGRAM_USER_AGENT", _IPHONE_UA)
    L = instaloader.Instaloader(
        save_metadata=False,
        download_pictures=False,
        download_videos=True,
        download_video_thumbnails=False,
        download_geotags=False,
        post_metadata_txt_pattern=None,
        user_agent=ua,
    )
    session_user = os.environ.get("INSTAGRAM_SESSION_USERNAME", "").strip()
    if session_user:
        try:
            L.load_session_from_file(session_user)
        except Exception as se:
            print(f"⚠️ Could not load Instagram session for {session_user}: {se}")
    shortcode = _instagram_shortcode_from_url(url)
    if not shortcode:
        print(f"❌ Could not parse Instagram shortcode from URL: {url}")
        return None

    os.makedirs(target_dir, exist_ok=True)

    try:
        post = instaloader.Post.from_shortcode(L.context, shortcode)
        author = post.owner_profile.full_name
        caption = (post.caption or "").strip()
        if len(caption) > 2000:
            caption = caption[:2000]
        print(shortcode)
        L.download_post(post, target=target_dir)
        time.sleep(0.25)
        files = glob.glob(os.path.join(target_dir, "*.mp4"))
        if not files:
            raise RuntimeError("Instaloader completed but no .mp4 was written")
        old_file = max(files, key=os.path.getctime)
        new_file = os.path.join(target_dir, f"{shortcode}.mp4")
        if os.path.exists(new_file):
            os.remove(new_file)
        os.rename(old_file, new_file)
        return new_file, author, caption
    except Exception as e:
        print(f"❌ Error in download_instagram_reel (instaloader): {e}")
        traceback.print_exc()
        msg = str(e)
        if _instagram_error_looks_blocked(msg):
            fallback = _download_instagram_via_ytdlp(url, target_dir, shortcode)
            if fallback:
                print("✅ Instagram reel downloaded via yt-dlp fallback")
                return fallback
            raise InstagramBlockedError(msg)
        fallback = _download_instagram_via_ytdlp(url, target_dir, shortcode)
        if fallback:
            print("✅ Instagram reel downloaded via yt-dlp fallback")
            return fallback
        return None