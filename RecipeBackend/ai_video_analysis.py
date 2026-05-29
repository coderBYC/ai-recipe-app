"""Video → recipe JSON via OpenAI Responses API (GPT-5) or Gemini."""

from __future__ import annotations

import os
import time
from typing import Optional

from openai import OpenAI  # pyright: ignore[reportMissingImports]
from openai import APIError as OpenAIAPIError  # pyright: ignore[reportMissingImports]


def recipe_ai_provider() -> str:
    """`openai` (GPT-5 Responses API) or `gemini`. Defaults to OpenAI when key is set."""
    explicit = (os.getenv("RECIPE_AI_PROVIDER") or "").strip().lower()
    if explicit in ("openai", "gemini"):
        return explicit
    if (os.getenv("OPENAI_API_KEY") or "").strip():
        return "openai"
    return "gemini"


def _openai_model_candidates() -> list[str]:
    primary = (os.getenv("OPENAI_MODEL") or "gpt-5").strip()
    fallbacks_raw = os.getenv("OPENAI_MODEL_FALLBACKS", "gpt-5-mini,gpt-4.1")
    ordered: list[str] = []
    for name in [primary, *fallbacks_raw.split(",")]:
        name = name.strip()
        if name and name not in ordered:
            ordered.append(name)
    return ordered or ["gpt-5"]


def _is_transient_openai_error(err: BaseException) -> bool:
    if isinstance(err, OpenAIAPIError):
        code = getattr(err, "status_code", None)
        if code in (429, 500, 503):
            return True
    msg = str(err).lower()
    return any(
        p in msg
        for p in (
            "rate limit",
            "overloaded",
            "high demand",
            "temporarily unavailable",
            "503",
            "429",
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
    Upload a local video and analyze with GPT-5 via Responses API (input_video + input_text).
    """
    api_key = (os.getenv("OPENAI_API_KEY") or "").strip()
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY is not configured")

    client = OpenAI(api_key=api_key)
    uploaded = None
    try:
        with open(video_path, "rb") as video_file:
            uploaded = client.files.create(file=video_file, purpose="user_data")

        text_parts = [prompt]
        if extra_context:
            text_parts.extend(extra_context)
        user_text = "\n\n".join(p for p in text_parts if p)

        content = [
            {
                "type": "input_video",
                "video": {"file_id": uploaded.id},
            },
            {
                "type": "input_text",
                "text": user_text,
            },
        ]

        errors: list[tuple[str, BaseException]] = []
        for model in _openai_model_candidates():
            for idx in range(attempts_per_model):
                try:
                    print(
                        f"[OpenAI] responses.create model={model} "
                        f"attempt={idx + 1}/{attempts_per_model}"
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
                    if not _is_transient_openai_error(e):
                        raise
                    errors.append((model, e))
                    if idx < attempts_per_model - 1:
                        time.sleep(2 * (idx + 1))
                        continue
                    print(
                        f"[OpenAI] model={model} failed ({e!r}); trying next fallback"
                    )
                    break

        if errors:
            raise errors[-1][1]
        raise RuntimeError("OpenAI video analysis failed: no models configured")
    finally:
        if uploaded is not None:
            try:
                client.files.delete(uploaded.id)
            except Exception:
                pass
