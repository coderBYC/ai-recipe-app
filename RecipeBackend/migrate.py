"""
One-off migration: local JPGs in served_thumbnails/ → Supabase Storage bucket `thumbnails`,
then update Postgres rows that still point at the old FastAPI URL.

Important (read before running)
--------------------------------
`main.py` names files `{thumb_id}.jpg` where `thumb_id` is a NEW uuid4 at extract time.
That id is only embedded in the served URL: ``{API_BASE}/thumbnail/{thumb_id}``.
It is NOT the same as your app/Supabase ``recipes.id`` unless you designed it that way.

So we do **not** default to ``.eq("id", thumb_id)``. We match rows whose ``thumbnail_url``
(or whatever column you set below) contains ``/thumbnail/{thumb_id}`` from the old backend.

Env
---
SUPABASE_URL, SUPABASE_SERVICE_KEY — required.

Optional:
  THUMBNAILS_LOCAL_DIR  — default ./served_thumbnails
  STORAGE_BUCKET        — default thumbnails
  STORAGE_OBJECT_PREFIX — folder inside bucket, default "" (object key = ``{prefix}/{filename}``)
  RECIPES_TABLE         — default recipes
  THUMBNAIL_COLUMN      — default thumbnail_url (column that stores the full URL string)
  MIGRATE_MATCH_BY_ROW_ID — set to "1" to use legacy behavior: update where id == filename stem
"""

from __future__ import annotations

import mimetypes
import os
import sys
from pathlib import Path

from supabase import create_client

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY")

LOCAL_FOLDER = Path(os.getenv("THUMBNAILS_LOCAL_DIR", "./served_thumbnails")).resolve()
STORAGE_BUCKET = os.getenv("STORAGE_BUCKET", "thumbnails")
# No leading/trailing slashes; empty means objects live at bucket root: "{uuid}.jpg"
STORAGE_OBJECT_PREFIX = os.getenv("STORAGE_OBJECT_PREFIX", "").strip().strip("/")
RECIPES_TABLE = os.getenv("RECIPES_TABLE", "recipes")
THUMBNAIL_COLUMN = os.getenv("THUMBNAIL_COLUMN", "thumbnail_url")
MATCH_BY_ROW_ID = os.getenv("MIGRATE_MATCH_BY_ROW_ID", "").strip() in ("1", "true", "yes")


def _object_storage_path(filename: str) -> str:
    if STORAGE_OBJECT_PREFIX:
        return f"{STORAGE_OBJECT_PREFIX}/{filename}"
    return filename


def _content_type(filename: str) -> str:
    guessed, _ = mimetypes.guess_type(filename)
    if guessed:
        return guessed
    return "image/jpeg"


def _public_url(supabase, storage_path: str) -> str:
    """supabase-py returns a public URL string for the object."""
    url = supabase.storage.from_(STORAGE_BUCKET).get_public_url(storage_path)
    if isinstance(url, str):
        return url
    # Some versions wrap the string
    data = getattr(url, "data", None)
    if isinstance(data, dict) and "publicUrl" in data:
        return str(data["publicUrl"])
    return str(url)


def migrate() -> None:
    if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
        print("Set SUPABASE_URL and SUPABASE_SERVICE_KEY.", file=sys.stderr)
        sys.exit(1)

    if not LOCAL_FOLDER.is_dir():
        print(f"Local folder not found: {LOCAL_FOLDER}", file=sys.stderr)
        sys.exit(1)

    supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    for path in sorted(LOCAL_FOLDER.iterdir()):
        if not path.is_file():
            continue
        if path.suffix.lower() not in {".jpg", ".jpeg", ".png", ".webp"}:
            continue

        filename = path.name
        thumb_id = path.stem  # uuid before extension; matches /thumbnail/{thumb_id} in main.py
        storage_path = _object_storage_path(filename)
        content_type = _content_type(filename)

        print(f"Uploading {filename} → {STORAGE_BUCKET}/{storage_path} ...")

        try:
            file_bytes = path.read_bytes()
            supabase.storage.from_(STORAGE_BUCKET).upload(
                storage_path,
                file_bytes,
                file_options={
                    "content-type": content_type,
                    "upsert": "true",
                },
            )
        except Exception as e:
            print(f"  ❌ Storage upload failed: {e}")
            continue

        try:
            public_url = _public_url(supabase, storage_path)
        except Exception as e:
            print(f"  ❌ get_public_url failed: {e}")
            continue

        try:
            if MATCH_BY_ROW_ID:
                pattern_desc = f"id eq {thumb_id}"
                pre = (
                    supabase.table(RECIPES_TABLE)
                    .select("id")
                    .eq("id", thumb_id)
                    .limit(1)
                    .execute()
                )
            else:
                # Match old Render/FastAPI URLs from main.py: .../thumbnail/{thumb_id}
                pattern = f"%/thumbnail/{thumb_id}%"
                pattern_desc = f"{THUMBNAIL_COLUMN} ilike {pattern!r}"
                pre = (
                    supabase.table(RECIPES_TABLE)
                    .select("id")
                    .ilike(THUMBNAIL_COLUMN, pattern)
                    .limit(1)
                    .execute()
                )

            if not (pre.data and len(pre.data) > 0):
                print(
                    f"  ⚠️  Uploaded OK; no DB rows matched ({pattern_desc}). "
                    f"Adjust {THUMBNAIL_COLUMN} / table name, or set MIGRATE_MATCH_BY_ROW_ID=1 if id == thumb file stem."
                )
                continue

            if MATCH_BY_ROW_ID:
                supabase.table(RECIPES_TABLE).update({THUMBNAIL_COLUMN: public_url}).eq("id", thumb_id).execute()
            else:
                pattern = f"%/thumbnail/{thumb_id}%"
                supabase.table(RECIPES_TABLE).update({THUMBNAIL_COLUMN: public_url}).ilike(
                    THUMBNAIL_COLUMN, pattern
                ).execute()
            print(f"  ✅ DB updated ({pattern_desc}): {public_url}")
        except Exception as e:
            print(f"  ❌ DB update failed (file is already in storage): {e}")


if __name__ == "__main__":
    migrate()
