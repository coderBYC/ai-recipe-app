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

# Optional – for server-side AI usage limits (use_ai_once RPC)
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=your_supabase_service_role_key
```

- **GEMINI_API_KEY**: Get from [Google AI Studio](https://aistudio.google.com/apikey). Required for `/analyze_reel`.
- **SUPABASE_URL** / **SUPABASE_SERVICE_KEY**: From Supabase Dashboard → **Settings** → **API**. Use the **service_role** key for the backend (never ship this in the iOS app). If omitted, AI quota checks are skipped.

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
