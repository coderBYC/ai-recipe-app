from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys

from openclaw_client import OpenClawClientError, extract_recipe_from_instagram_reel


DEFAULT_BASE_URL = "http://127.0.0.1:18789"


def is_instagram_reel(url: str) -> bool:
    u = url.lower()
    return ("instagram.com" in u or "instagr.am" in u) and ("/reel/" in u or "/reels/" in u)


def summarize_instagram_fields(data: dict) -> dict:
    return {
        "recipe_name": data.get("recipe_name"),
        "creator": data.get("creator"),
        "prep_time": data.get("prep_time"),
        "estimated_cooking_time": data.get("estimated_cooking_time"),
        "ingredients_count": len(data.get("ingredients", [])) if isinstance(data.get("ingredients"), list) else 0,
        "instructions_count": len(data.get("instructions", [])) if isinstance(data.get("instructions"), list) else 0,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Fetch Instagram reel recipe JSON from OpenClaw Sessions API."
    )
    parser.add_argument("reel_url", help="Instagram reel URL, e.g. https://www.instagram.com/reel/...")
    parser.add_argument(
        "--base-url",
        default=os.environ.get("OPENCLAW_BASE_URL", DEFAULT_BASE_URL),
        help=f"Gateway base URL (default: {DEFAULT_BASE_URL} or OPENCLAW_BASE_URL env var).",
    )
    parser.add_argument(
        "--token",
        default=os.environ.get("OPENCLAW_AUTH_TOKEN", ""),
        help="Gateway auth token (or set OPENCLAW_AUTH_TOKEN).",
    )
    parser.add_argument(
        "--session-id",
        default=os.environ.get("OPENCLAW_SESSION_ID", "recipe-extraction-prod"),
        help="OpenClaw session id (default: recipe-extraction-prod or OPENCLAW_SESSION_ID).",
    )
    parser.add_argument(
        "--agent",
        default=os.environ.get("OPENCLAW_AGENT", "main"),
        help="OpenClaw agent id (default: main).",
    )
    parser.add_argument(
        "--profile",
        default=os.environ.get("OPENCLAW_PROFILE", "user"),
        help="OpenClaw profile id (default: user).",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=90.0,
        help="Request timeout in seconds (default: 90).",
    )
    parser.add_argument(
        "--messages-path-template",
        default=os.environ.get("OPENCLAW_MESSAGES_PATH_TEMPLATE", ""),
        help="Optional endpoint template, e.g. /api/sessions/{session_id}/messages",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    reel_url = args.reel_url.strip()

    if not is_instagram_reel(reel_url):
        print("Error: URL must be an Instagram reel URL (/reel/ or /reels/).", file=sys.stderr)
        return 2
    if not args.token:
        print("Error: missing token. Pass --token or set OPENCLAW_AUTH_TOKEN.", file=sys.stderr)
        return 2

    try:
        data = asyncio.run(
            extract_recipe_from_instagram_reel(
                reel_url,
                base_url=args.base_url,
                auth_token=args.token,
                session_id=args.session_id,
                agent=args.agent,
                profile=args.profile,
                timeout_seconds=args.timeout,
                messages_path_template=(args.messages_path_template or None),
            )
        )
    except OpenClawClientError as e:
        print(f"OpenClaw request failed: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"OpenClaw request failed: {e}", file=sys.stderr)
        return 1

    print(f"Endpoint: {args.base_url.rstrip('/')}/api/sessions/{args.session_id}/messages")
    print("HTTP: 200")
    print("\n=== Parsed JSON ===")
    print(json.dumps(data, indent=2, ensure_ascii=False))
    print("\n=== Instagram Summary ===")
    print(json.dumps(summarize_instagram_fields(data), indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
