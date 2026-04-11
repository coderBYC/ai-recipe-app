#!/usr/bin/env python3
"""
Run a Cloudflare quick tunnel to a local backend and publish the public URL to a GitHub Gist
as JSON: {"url": "https://....trycloudflare.com"} so iOS clients can discover it without an app update.

Setup (never commit tokens):
  brew install cloudflare/cloudflare/cloudflared
  export GITHUB_TOKEN=ghp_...          # classic PAT with `gist` scope
  export GIST_ID=3207f8bef4c8f9248d79563696042c53
  export GIST_FILENAME=backend_config.json   # optional
  export TUNNEL_TARGET=http://127.0.0.1:8000  # optional

Run (with uvicorn already listening on 8000):
  python3 cloudflare_gist_relay.py

If cloudflared exits (sleep, crash), the script restarts the tunnel and updates the gist again.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from typing import Optional

TUNNEL_URL_RE = re.compile(
    r"https://[a-z0-9-]+\.trycloudflare\.com/?", re.IGNORECASE
)

DEFAULT_TARGET = os.environ.get("TUNNEL_TARGET", "http://127.0.0.1:8000")
GIST_FILENAME = os.environ.get("GIST_FILENAME", "backend_config.json")


def patch_gist(gist_id: str, token: str, filename: str, url: str) -> None:
    body = {
        "files": {
            filename: {"content": json.dumps({"url": url.rstrip("/")})},
        }
    }
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        f"https://api.github.com/gists/{gist_id}",
        data=data,
        method="PATCH",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github.v3+json",
            "Content-Type": "application/json",
            "User-Agent": "recipe-backend-cloudflare-relay",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        if resp.status not in (200, 201):
            raise RuntimeError(f"GitHub API HTTP {resp.status}")


def run_tunnel_loop() -> None:
    token = os.environ.get("GITHUB_TOKEN", "").strip()
    gist_id = os.environ.get("GIST_ID", "").strip()
    if not token or not gist_id:
        print(
            "Set GITHUB_TOKEN and GIST_ID in the environment. "
            "Do not paste tokens into source control.",
            file=sys.stderr,
        )
        sys.exit(1)

    target = DEFAULT_TARGET
    while True:
        print(f"Starting cloudflared → {target} …", flush=True)
        proc = subprocess.Popen(
            ["cloudflared", "tunnel", "--url", target],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        assert proc.stdout is not None
        published: Optional[str] = None
        try:
            for line in proc.stdout:
                print(line, end="", flush=True)
                m = TUNNEL_URL_RE.search(line)
                if m and not published:
                    published = m.group(0).rstrip("/")
                    try:
                        patch_gist(gist_id, token, GIST_FILENAME, published)
                        print(f"Updated gist {gist_id} → {published}", flush=True)
                    except urllib.error.HTTPError as e:
                        print(f"GitHub API error: {e.code} {e.reason}", file=sys.stderr)
                        try:
                            print(e.read().decode(), file=sys.stderr)
                        except Exception:
                            pass
                    except Exception as e:
                        print(f"Failed to update gist: {e}", file=sys.stderr)
        finally:
            proc.wait()
            print(f"cloudflared exited ({proc.returncode}), restarting in 3s …", flush=True)
            time.sleep(3)


if __name__ == "__main__":
    run_tunnel_loop()
