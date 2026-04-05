# Render: Docker service, root directory = `RecipeBackend` (this folder).
# Node + npm come from NodeSource APT so `node`/`npm` live under /usr/bin (works even if PATH is minimal).
FROM python:3.12-slim-bookworm

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    # Used by download.py so TikTok subprocess always finds Node without relying on PATH.
    NODE_EXECUTABLE=/usr/bin/node \
    PATH=/usr/bin:/usr/local/bin:/bin

# Python, Node 22 + npm (NodeSource), native deps for `canvas` (@tobyg74/tiktok-api-dl).
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
     ca-certificates curl gnupg bash \
     build-essential pkg-config \
     libcairo2-dev libpango1.0-dev libjpeg-dev libpng-dev libgif-dev librsvg2-dev \
  && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/* \
  && node -v \
  && npm -v \
  && test -x /usr/bin/node \
  && test -x /usr/bin/npm

# --- Install dependencies ---
COPY requirements.txt /app/requirements.txt
COPY package.json /app/package.json
COPY package-lock.json /app/package-lock.json

RUN npm ci --omit=dev \
  && node -e "require('@tobyg74/tiktok-api-dl'); console.log('tiktok-api-dl ok')" \
  && pip3 install --no-cache-dir --break-system-packages -r /app/requirements.txt

# --- App code ---
COPY main.py /app/main.py
COPY download.py /app/download.py
COPY download_tiktok.js /app/download_tiktok.js

RUN mkdir -p /app/downloads /app/served_videos

EXPOSE 8000

CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}"]
