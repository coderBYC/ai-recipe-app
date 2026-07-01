# Render: Docker service, dockerContext = this folder (RecipeBackend).
# Node + npm from NodeSource; Python deps in a venv (avoids PEP 668 / pip install failures on system Python).
FROM python:3.12-slim-bookworm

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1
# TikTok helper subprocess uses this absolute path (see download.py).
ENV NODE_EXECUTABLE=/usr/bin/node

# Node 22 + npm (NodeSource), native deps for npm `canvas` (@tobyg74/tiktok-api-dl).
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
     ca-certificates curl gnupg bash git \
     build-essential pkg-config \
     libcairo2-dev libpango1.0-dev libjpeg-dev libpng-dev libgif-dev librsvg2-dev \
  && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/* \
  && node -v \
  && npm -v \
  && test -x /usr/bin/node \
  && test -x /usr/bin/npm

# --- Node deps (TikTok) ---
COPY requirements.txt /app/requirements.txt
COPY package.json /app/package.json
COPY package-lock.json /app/package-lock.json

RUN npm ci --omit=dev \
  && node -e "require('@tobyg74/tiktok-api-dl'); console.log('tiktok-api-dl ok')"

# --- Python deps in venv (reliable pip; no --break-system-packages) ---
RUN python3 -m venv /opt/venv \
  && /opt/venv/bin/pip install --no-cache-dir --upgrade pip setuptools wheel \
  && /opt/venv/bin/pip install --no-cache-dir -r /app/requirements.txt

ENV PATH="/opt/venv/bin:/usr/bin:/usr/local/bin:/bin"

# --- App code ---
COPY *.py /app/
COPY routes/ /app/routes/
COPY download_tiktok.js /app/download_tiktok.js

RUN mkdir -p /app/downloads /app/served_videos /app/served_thumbnails

EXPOSE 8000

CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}"]
