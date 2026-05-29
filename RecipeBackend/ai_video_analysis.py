"""Video → recipe JSON via OpenAI Responses API (GPT-5) or Gemini."""

from __future__ import annotations

import base64
import os
import time
from typing import Optional

import cv2
from openai import OpenAI  # pyright: ignore[reportMissingImports]
from openai import APIError as OpenAIAPIError  # pyright: ignore[reportMissingImports]


def clean_env(name: str, default: str = "") -> str:
    """Strip whitespace and optional quotes from .env values."""
    raw = os.getenv(name, default) or ""
    return raw.strip().strip('"').strip("'")


def recipe_ai_provider() -> str:
    """`openai` (GPT-5 Responses API) or `gemini`. Defaults to OpenAI when key is set."""
    explicit = clean_env("RECIPE_AI_PROVIDER").lower()
    if explicit in ("openai", "gemini"):
        return explicit
    if clean_env("OPENAI_API_KEY"):
        return "openai"
    return "gemini"


def recipe_ai_provider_chain() -> list[str]:
    """Primary provider, then optional fallback (e.g. OpenAI fails → Gemini)."""
    primary = recipe_ai_provider()
    chain: list[str] = [primary]

    explicit_fallback = clean_env("RECIPE_AI_FALLBACK_PROVIDER").lower()
    candidates = [explicit_fallback]
    if primary == "openai":
        candidates.append("gemini")
    elif primary == "gemini":
        candidates.append("openai")

    for name in candidates:
        if name not in ("openai", "gemini") or name in chain:
            continue
        if name == "openai" and not clean_env("OPENAI_API_KEY"):
            continue
        if name == "gemini" and not clean_env("GEMINI_API_KEY"):
            continue
        chain.append(name)
    return chain


def _openai_model_candidates() -> list[str]:
    primary = clean_env("OPENAI_MODEL") or "gpt-5.5"
    fallbacks_raw = clean_env("OPENAI_MODEL_FALLBACKS") or "gpt-5-mini,gpt-4o"
    ordered: list[str] = []
    for name in [primary, *fallbacks_raw.split(",")]:
        name = name.strip()
        if name and name not in ordered:
            ordered.append(name)
    return ordered or ["gpt-5.5"]


def _openai_max_frames() -> int:
    try:
        n = int(clean_env("OPENAI_VIDEO_FRAME_COUNT") or "10")
    except ValueError:
        n = 10
    return max(3, min(n, 16))


def _sample_video_frame_data_urls(
    video_path: str,
    *,
    max_frames: int,
    max_edge: int = 768,
) -> list[str]:
    """
    OpenAI Responses API does not accept raw video (no input_video / mp4 input_file).
    Sample JPEG frames and send as input_image — official workaround.
    """
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise ValueError(f"Cannot open video: {video_path}")

    frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    if frame_count <= 0:
        cap.release()
        raise ValueError(f"No frames in video: {video_path}")

    if frame_count <= max_frames:
        indices = list(range(frame_count))
    else:
        step = frame_count / max_frames
        indices = [min(frame_count - 1, int(i * step)) for i in range(max_frames)]

    data_urls: list[str] = []
    for idx in indices:
        cap.set(cv2.CAP_PROP_POS_FRAMES, idx)
        ok, frame = cap.read()
        if not ok or frame is None:
            continue
        height, width = frame.shape[:2]
        if max(height, width) > max_edge:
            scale = max_edge / max(height, width)
            frame = cv2.resize(
                frame,
                (int(width * scale), int(height * scale)),
                interpolation=cv2.INTER_AREA,
            )
        ok_encode, buf = cv2.imencode(
            ".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), 80]
        )
        if not ok_encode:
            continue
        b64 = base64.b64encode(buf).decode("ascii")
        data_urls.append(f"data:image/jpeg;base64,{b64}")

    cap.release()
    if not data_urls:
        raise ValueError("Could not extract any frames from video")
    return data_urls


def _is_transient_openai_error(err: BaseException) -> bool:
    if isinstance(err, OpenAIAPIError):
        code = getattr(err, "status_code", None)
        if code in (429, 500, 503):
            return True
        if code in (400, 404, 422):
            return False
    msg = str(err).lower()
    return any(
        p in msg
        for p in (
            "rate limit",
            "overloaded",
            "high demand",
            "temporarily unavailable",
        )
    )


def _openai_output_text(response) -> str:
    text = getattr(response, "output_text", None)
    if text:
        return str(text)
    parts: list[str] = []
    for item in getattr(response, "output", None) or []:
        if getattr(item, "type", None) != "message":
            continue
        for block in getattr(item, "content", None) or []:
            if getattr(block, "type", None) == "output_text":
                parts.append(getattr(block, "text", "") or "")
    return "".join(parts)


def analyze_video_with_openai(
    video_path: str,
    prompt: str,
    extra_context: Optional[list[str]] = None,
    *,
    attempts_per_model: int = 2,
) -> str:
    """
    Analyze a local video with GPT-5 via Responses API.

    Note: Responses API does not support input_video or mp4 input_file — we send
    evenly spaced frames as input_image (see OpenAI file-input docs / cookbook).
    """
    api_key = clean_env("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY is not configured")

    max_frames = _openai_max_frames()
    frame_urls = _sample_video_frame_data_urls(video_path, max_frames=max_frames)
    print(f"[OpenAI] extracted {len(frame_urls)} frames from video for vision input")

    text_parts = [prompt]
    if extra_context:
        text_parts.extend(extra_context)
    text_parts.append(
        f"The {len(frame_urls)} images above are sequential frames from one cooking video. "
        "Use them together (including any on-screen text) to extract the full recipe."
    )
    user_text = "\n\n".join(p for p in text_parts if p)

    content: list[dict] = [
        {"type": "input_image", "image_url": url} for url in frame_urls
    ]
    content.append({"type": "input_text", "text": user_text})

    client = OpenAI(api_key=api_key)
    errors: list[tuple[str, BaseException]] = []

    for model in _openai_model_candidates():
        for idx in range(attempts_per_model):
            try:
                print(
                    f"[OpenAI] responses.create model={model} "
                    f"frames={len(frame_urls)} attempt={idx + 1}/{attempts_per_model}"
                )
                response = client.responses.create(
                    model=model,
                    input=[{"role": "user", "content": content}],
                )
                raw = _openai_output_text(response)
                if not raw.strip():
                    raise ValueError("Model returned empty response")
                return raw
            except Exception as e:
                print(f"[OpenAI] model={model} error: {type(e).__name__}: {e}")
                if not _is_transient_openai_error(e):
                    raise
                errors.append((model, e))
                if idx < attempts_per_model - 1:
                    time.sleep(2 * (idx + 1))
                    continue
                print(f"[OpenAI] model={model} exhausted retries; trying next model")
                break

    if errors:
        raise errors[-1][1]
    raise RuntimeError("OpenAI video analysis failed: no models configured")
