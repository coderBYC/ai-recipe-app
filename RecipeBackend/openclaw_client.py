from __future__ import annotations

import json
import re
from typing import Any

import httpx


class OpenClawClientError(Exception):
    """Raised when OpenClaw returns an error or malformed response."""


def _extract_first_json_object(text: str) -> dict[str, Any]:
    raw = (text or "").strip()
    if not raw:
        raise OpenClawClientError("OpenClaw returned empty content.")

    # Try direct JSON first.
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, dict):
            return parsed
    except Exception:
        pass

    # Then try markdown code block.
    code_block = re.search(r"```(?:json)?\s*([\s\S]*?)\s*```", raw)
    if code_block:
        candidate = code_block.group(1).strip()
        try:
            parsed = json.loads(candidate)
            if isinstance(parsed, dict):
                return parsed
        except Exception:
            pass

    # Finally trim to first {...} object.
    start = raw.find("{")
    end = raw.rfind("}")
    if start != -1 and end != -1 and end > start:
        candidate = raw[start : end + 1]
        try:
            parsed = json.loads(candidate)
            if isinstance(parsed, dict):
                return parsed
        except Exception as e:
            raise OpenClawClientError(f"OpenClaw content was not valid JSON: {e}") from e

    raise OpenClawClientError("OpenClaw content did not include a JSON object.")


async def extract_recipe_from_instagram_reel(
    reel_url: str,
    *,
    base_url: str,
    auth_token: str,
    session_id: str,
    agent: str = "main",
    profile: str = "user",
    timeout_seconds: float = 90.0,
    messages_path_template: str | None = None,
) -> dict[str, Any]:
    """
    Sends a prompt to OpenClaw Sessions API and returns a parsed recipe dict.
    Endpoint:
      POST {base_url}/api/sessions/{session_id}/messages
    """
    if not reel_url.strip():
        raise OpenClawClientError("Missing Instagram reel URL.")
    if not auth_token.strip():
        raise OpenClawClientError("Missing OpenClaw auth token.")
    if not session_id.strip():
        raise OpenClawClientError("Missing OpenClaw session id.")

    base = base_url.rstrip("/")
    templates = []
    if messages_path_template:
        templates.append(messages_path_template)
    templates.extend(
        [
            "/api/sessions/{session_id}/messages",
            "/v1/api/sessions/{session_id}/messages",
            "/sessions/{session_id}/messages",
            "/api/session/{session_id}/messages",
        ]
    )
    headers = {
        "Authorization": f"Bearer {auth_token}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    payload = {
        "message": (
            f"Open {reel_url} and extract the recipe strictly in JSON format. "
            "Return only JSON with keys: recipe_name, creator, prep_time, "
            "estimated_cooking_time, description, ingredients, instructions. "
            "Each ingredient item must include item and amount. "
            "Each instruction item must include step and description."
        ),
        "agent": agent,
        "profile": profile,
    }

    errors: list[str] = []
    resp = None
    url = ""
    async with httpx.AsyncClient(timeout=timeout_seconds) as client:
        for template in templates:
            path = template.format(session_id=session_id)
            if not path.startswith("/"):
                path = f"/{path}"
            url = f"{base}{path}"
            candidate = await client.post(url, headers=headers, json=payload)
            if candidate.status_code < 400:
                resp = candidate
                break
            errors.append(f"{url} -> {candidate.status_code}")

    if resp is None:
        detail = "; ".join(errors)[:1800]
        raise OpenClawClientError(f"OpenClaw message endpoint not found/failed. Tried: {detail}")

    try:
        data = resp.json()
    except Exception as e:
        raise OpenClawClientError(f"OpenClaw returned non-JSON response: {e}") from e

    # Session APIs often return message content as a string field.
    content = data.get("content")
    if isinstance(content, dict):
        return content
    if isinstance(content, str):
        return _extract_first_json_object(content)

    # Fallback for alternate schemas.
    if isinstance(data.get("message"), str):
        return _extract_first_json_object(data["message"])
    if isinstance(data.get("result"), dict):
        return data["result"]

    raise OpenClawClientError(
        "OpenClaw response did not contain expected `content`/`message`/`result` fields."
    )
