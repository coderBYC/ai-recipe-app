# Recipe Backend – Setup Guide

Backend for the AIRecipe app: FastAPI server that analyzes cooking videos (Instagram Reels, TikTok) with Gemini and enforces Supabase AI quotas.

---

## 1. Prerequisites

- **Python 3.9+**
- **Node.js 18+** (for TikTok downloads only)
- **Gemini API key** ([Google AI Studio](https://aistudio.google.com/apikey))
- **Supabase project** (for auth and AI usage RPCs)

---

## 2. Python setup

From the `RecipeBackend` folder:

```bash
cd RecipeBackend

# Create virtual environment
python3 -m venv .venv

# Activate (macOS/Linux)
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

---

## 3. Environment variables

Create a `.env` file in `RecipeBackend` (same folder as `main.py`):

```env
# Required for video analysis
GEMINI_API_KEY=your_gemini_api_key_here

# Optional – Supabase (Pro plan sync; free tier uses in-process daily limits)
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=your_supabase_service_role_key
# FREE_IMPORTS_PER_DAY=3
```

- **GEMINI_API_KEY**: Get from [Google AI Studio](https://aistudio.google.com/apikey). Required for `/analyze_reel`.
- **GEMINI_MODEL** / **GEMINI_MODEL_FALLBACKS**: When you see `503` or “high demand”, the server retries then tries fallback models (default primary: `gemini-3.1-pro-preview`). Example:
  ```env
  GEMINI_MODEL=gemini-3.1-pro-preview
  GEMINI_MODEL_FALLBACKS=gemini-3.1-flash-lite,gemini-3.5-flash,gemini-2.5-flash
  ```
- **SUPABASE_URL** / **SUPABASE_SERVICE_KEY**: From Supabase Dashboard → **Settings** → **API**. Use the **service_role** key for the backend (never ship this in the iOS app). If omitted, AI quota checks are skipped.
- **FREE_IMPORTS_PER_DAY**: Max link/photo imports per UTC day for free users (default **3**). Pro users are unlimited at this layer.

---

## 4. Node.js setup (TikTok only)

TikTok downloads use a small Node script. If you only use Instagram links, you can skip this.

```bash
cd RecipeBackend

# Create package.json if missing, then install
npm init -y
npm install @tobyg74/tiktok-api-dl
```

If install fails (e.g. postinstall scripts), try:

```bash
npm install @tobyg74/tiktok-api-dl --ignore-scripts
```

Ensure `download_tiktok.js` exists in `RecipeBackend`; the Python code calls it via `node download_tiktok.js <url> <output_path>`.

TikTok imports are serialized server-wide (`TIKTOK_MIN_INTERVAL_SECONDS`, default 45s between fetches). Free users also get a per-user cooldown (`FREE_TIKTOK_COOLDOWN_SECONDS`). Rate-limit responses return HTTP 429 so queued import jobs retry instead of failing immediately.

---

## 5. Run the server

With the venv activated:

```bash
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

- **Local**: API base URL is `http://localhost:8000`
- **Same machine as iOS Simulator**: Use `http://localhost:8000` or `http://127.0.0.1:8000`
- **Physical device on same Wi‑Fi**: Use your Mac’s LAN IP (e.g. `http://192.168.1.10:8000`) and ensure no firewall blocks port 8000

---

## 6. Verify

- **Health**: Open `http://localhost:8000/docs` for Swagger UI.
- **Analyze reel**: `POST /analyze_reel` with body `{ "url": "https://...", "language": "en" }`. Send `X-User-Id` if using Supabase quota.

---

## 7. iOS app configuration

In the iOS app (e.g. `RecipeBackendService.swift`), set the base URL to your backend:

- Simulator: `http://localhost:8000`
- Device: `http://<your-mac-ip>:8000`

---

## Summary

| Step | Command / action |
|------|-------------------|
| 1 | `cd RecipeBackend` |
| 2 | `python3 -m venv .venv` → `source .venv/bin/activate` |
| 3 | `pip install -r requirements.txt` |
| 4 | Add `.env` with `GEMINI_API_KEY` (and optionally Supabase keys) |
| 5 | (Optional) `npm install @tobyg74/tiktok-api-dl` for TikTok |
| 6 | `uvicorn main:app --reload --host 0.0.0.0 --port 8000` |
