# RecipeBackend

FastAPI backend for the AI Recipe app: analyze cooking videos (YouTube, TikTok, Instagram) via Gemini and serve extracted recipes.

## Setup

### Python

```bash
python3 -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

### Node.js (for TikTok downloads)

TikTok video downloads use [@tobyg74/tiktok-api-dl](https://github.com/TobyG74/tiktok-api-dl). Install dependencies:

```bash
npm install
```

If `npm install` fails due to native modules (e.g. `canvas`), use:

```bash
npm install --ignore-scripts
```

Ensure Node is on your PATH so the backend can run `node download_tiktok.js ...`.

### Run

```bash
source .venv/bin/activate
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

## Endpoints

- **POST /analyze_reel** – Body: `{ "url": "https://..." }`. Supports YouTube, TikTok (`tiktok.com`, `vt.tiktok.com`), and Instagram Reels. Returns recipe JSON and optional `video_url` for in-app playback.
- **GET /video/{video_id}** – Stream a previously downloaded video (e.g. from TikTok/Instagram).

## Supported URL types

| Platform   | Example URLs                    |
|-----------|----------------------------------|
| YouTube   | `youtube.com/watch?v=...`, `youtu.be/...` |
| TikTok    | `tiktok.com/@user/video/...`, `vt.tiktok.com/...` |
| Instagram | Reel URLs                        |
