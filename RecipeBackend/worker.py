from __future__ import annotations

import asyncio
import os
from contextlib import suppress
from datetime import datetime, timezone
from typing import Any, Awaitable, Callable, Optional

import httpx
from postgrest.exceptions import APIError  # pyright: ignore[reportMissingImports]


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


class ImportQueueWorker:
    """
    DB-backed queue worker:
    - polls `import_jobs` for pending rows
    - claims jobs (`pending` -> `processing`)
    - processes via existing `/analyze_reel`
    - writes status + response json back to `import_jobs`
    """

    def __init__(
        self,
        *,
        concurrency: int,
        poll_interval_sec: float,
        scan_batch: int,
        retry_after_429_sec: float,
        local_api_base: str,
        jobs_table: str,
        get_supabase: Callable[[], Optional[Any]],
        supabase_call: Callable[[Callable[[], Any]], Awaitable[Any]],
    ) -> None:
        self.concurrency = max(1, concurrency)
        self.poll_interval_sec = max(1.0, poll_interval_sec)
        self.scan_batch = max(1, scan_batch)
        self.retry_after_429_sec = max(5.0, retry_after_429_sec)
        self.local_api_base = local_api_base.strip().rstrip("/")
        self.jobs_table = jobs_table
        self.get_supabase = get_supabase
        self.supabase_call = supabase_call

        self._queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue()
        self._dispatcher_task: Optional[asyncio.Task[Any]] = None
        self._consumer_tasks: list[asyncio.Task[Any]] = []
        self._stopping = asyncio.Event()

    async def start(self) -> None:
        self._stopping.clear()
        self._dispatcher_task = asyncio.create_task(self._dispatch_loop(), name="import-queue-dispatcher")
        self._consumer_tasks = [
            asyncio.create_task(self._consumer_loop(i), name=f"import-queue-consumer-{i}")
            for i in range(self.concurrency)
        ]
        print(f"[ImportQueueWorker] started with concurrency={self.concurrency}")

    async def stop(self) -> None:
        self._stopping.set()
        if self._dispatcher_task:
            self._dispatcher_task.cancel()
            with suppress(asyncio.CancelledError):
                await self._dispatcher_task
        for t in self._consumer_tasks:
            t.cancel()
        for t in self._consumer_tasks:
            with suppress(asyncio.CancelledError):
                await t
        self._consumer_tasks = []
        print("[ImportQueueWorker] stopped")

    async def nudge(self) -> None:
        with suppress(Exception):
            await self._claim_pending_jobs()

    async def _dispatch_loop(self) -> None:
        while not self._stopping.is_set():
            try:
                await self._claim_pending_jobs()
            except Exception as e:
                print(f"[ImportQueueWorker] dispatch error: {e}")
            await asyncio.sleep(self.poll_interval_sec)

    async def _claim_pending_jobs(self) -> None:
        sb = self.get_supabase()
        if not sb:
            return
        capacity = max(0, self.concurrency * 2 - self._queue.qsize())
        if capacity <= 0:
            return
        limit = min(self.scan_batch, capacity)

        def _select_pending() -> Any:
            return (
                sb.table(self.jobs_table)
                .select("id,url,user_id,status,created_at")
                .eq("status", "pending")
                .order("created_at", desc=True)
                .limit(limit)
                .execute()
            )

        selected = await self.supabase_call(_select_pending)
        rows = getattr(selected, "data", None) or []
        for row in rows:
            claimed = await self._try_claim_row(row)
            if claimed:
                await self._queue.put(claimed)

    async def _try_claim_row(self, row: dict[str, Any]) -> Optional[dict[str, Any]]:
        sb = self.get_supabase()
        if not sb:
            return None
        rid = row.get("id")
        if not rid:
            return None

        def _claim() -> Any:
            return (
                sb.table(self.jobs_table)
                .update({"status": "processing", "updated_at": _utc_now_iso()})
                .eq("id", rid)
                .eq("status", "pending")
                .execute()
            )

        try:
            res = await self.supabase_call(_claim)
            changed = getattr(res, "data", None) or []
            if not changed:
                return None
            return changed[0]
        except APIError:
            return None

    async def _consumer_loop(self, worker_index: int) -> None:
        while not self._stopping.is_set():
            job = await self._queue.get()
            try:
                await self._process_job(job, worker_index)
            finally:
                self._queue.task_done()

    async def _process_job(self, job: dict[str, Any], worker_index: int) -> None:
        rid = str(job.get("id") or "")
        url = str(job.get("url") or "").strip()
        user_id = str(job.get("user_id") or "").strip()
        language = str(job.get("language") or "en").strip() or "en"
        if not rid or not url or not user_id:
            await self._mark_failed(rid=rid, message="Invalid queued job payload (missing id/url/user_id).", response_json=None)
            return

        endpoint = f"{self.local_api_base}/analyze_reel/process"
        print(f"[ImportQueueWorker:{worker_index}] processing id={rid}")
        headers = {"X-User-Id": user_id}
        public_base = (os.getenv("PUBLIC_BASE_URL") or "").strip().rstrip("/")
        if public_base:
            headers["X-Public-Base-Url"] = public_base
        try:
            async with httpx.AsyncClient(timeout=1800) as client:
                resp = await client.post(
                    endpoint,
                    headers=headers,
                    json={"url": url, "language": language},
                )
            if resp.status_code == 429:
                detail: Any
                with suppress(Exception):
                    detail = resp.json()
                if "detail" not in locals():
                    detail = resp.text
                await self._defer_retry(
                    rid=rid,
                    message=f"Waiting for quota window: {detail}",
                    seconds=self.retry_after_429_sec,
                )
                return
            if resp.status_code != 200:
                detail: Any
                with suppress(Exception):
                    detail = resp.json()
                if "detail" not in locals():
                    detail = resp.text
                await self._mark_failed(
                    rid=rid,
                    message=f"analyze_reel failed ({resp.status_code})",
                    response_json={"error": detail},
                )
                return

            payload = resp.json()
            await self._mark_done(rid=rid, payload=payload)
        except Exception as e:
            await self._mark_failed(rid=rid, message=f"Worker exception: {e}", response_json=None)

    async def _mark_done(self, rid: str, payload: dict[str, Any]) -> None:
        if not rid:
            return
        sb = self.get_supabase()
        if not sb:
            return

        def _update() -> Any:
            return (
                sb.table(self.jobs_table)
                .update(
                    {
                        "status": "ready",
                        "result_json": payload,
                        "error_log": None,
                        "updated_at": _utc_now_iso(),
                    }
                )
                .eq("id", rid)
                .execute()
            )

        await self.supabase_call(_update)

    async def _defer_retry(self, rid: str, message: str, seconds: float) -> None:
        if not rid:
            return
        sb = self.get_supabase()
        if not sb:
            return

        def _mark_waiting() -> Any:
            return (
                sb.table(self.jobs_table)
                .update(
                    {
                        "status": "processing",
                        "error_log": message[:1000],
                        "updated_at": _utc_now_iso(),
                    }
                )
                .eq("id", rid)
                .execute()
            )

        await self.supabase_call(_mark_waiting)
        await asyncio.sleep(max(5.0, seconds))

        def _mark_pending() -> Any:
            return (
                sb.table(self.jobs_table)
                .update(
                    {
                        "status": "pending",
                        "updated_at": _utc_now_iso(),
                    }
                )
                .eq("id", rid)
                .eq("status", "processing")
                .execute()
            )

        await self.supabase_call(_mark_pending)

    async def _mark_failed(self, rid: str, message: str, response_json: Optional[dict[str, Any]]) -> None:
        if not rid:
            return
        sb = self.get_supabase()
        if not sb:
            return

        def _update() -> Any:
            data: dict[str, Any] = {
                "status": "failed",
                "error_log": message[:1000],
                "updated_at": _utc_now_iso(),
            }
            if response_json is not None:
                data["result_json"] = response_json
            return sb.table(self.jobs_table).update(data).eq("id", rid).execute()

        await self.supabase_call(_update)
