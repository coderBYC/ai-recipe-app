#!/usr/bin/env bash
# Local RecipeBackend: Python venv + Node deps + uvicorn with reload.
# Usage: ./run_local.sh
# Requires: Python 3.10+, Node 18+ (for npm ci / TikTok). GEMINI_API_KEY in .env (copy from .env.example).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [[ ! -d .venv ]]; then
  python3 -m venv .venv
fi
# shellcheck source=/dev/null
source .venv/bin/activate
pip install -r requirements.txt
npm ci --omit=dev

PORT="${PORT:-8000}"
echo "API: http://127.0.0.1:${PORT}  (Simulator: use 127.0.0.1; device: use your Mac LAN IP + this port)"
exec uvicorn main:app --reload --host 0.0.0.0 --port "${PORT}"
