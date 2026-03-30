FROM node:22-bookworm-slim

WORKDIR /app

# System deps for Python packages (and pip).
RUN apt-get update \
  && apt-get install -y --no-install-recommends python3 python3-pip ca-certificates build-essential \
  && rm -rf /var/lib/apt/lists/*

ENV PYTHONDONTWRITEBYTECODE=1

# --- Install dependencies ---
# Copy only the manifests first for better Docker layer caching.
COPY requirements.txt /app/requirements.txt
COPY package.json /app/package.json
COPY package-lock.json /app/package-lock.json

RUN npm ci
RUN pip3 install --no-cache-dir -r /app/requirements.txt

# --- App code ---
COPY main.py /app/main.py
COPY download.py /app/download.py
COPY download_tiktok.js /app/download_tiktok.js

# Storage directories used by the server.
RUN mkdir -p /app/downloads /app/served_videos

EXPOSE 8000

# Render sets $PORT; fall back to 8000 for local runs.
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}"]

