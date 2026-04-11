"""
Compatibility shim: older RecipeBackend `main.py` revisions imported this module.

OpenClaw was removed; Instagram flows use `download_instagram_reel` in `download.py` only.
Prefer using the current `main.py` from the repo (no OpenClaw imports or env flags).
"""

from __future__ import annotations


class OpenClawClientError(Exception):
    """Kept so legacy `except OpenClawClientError` blocks remain valid."""


async def extract_recipe_from_instagram_reel(*_args, **_kwargs) -> dict:
    raise OpenClawClientError(
        "OpenClaw support was removed. Update RecipeBackend/main.py from the repo and unset OPENCLAW_* env vars."
    )
