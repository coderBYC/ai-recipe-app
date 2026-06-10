"""Shared reference to the background import queue worker."""

from __future__ import annotations

from typing import TYPE_CHECKING, Optional

if TYPE_CHECKING:
    from worker import ImportQueueWorker

_import_worker: Optional["ImportQueueWorker"] = None


def get_import_worker() -> Optional["ImportQueueWorker"]:
    return _import_worker


def set_import_worker(worker: Optional["ImportQueueWorker"]) -> None:
    global _import_worker
    _import_worker = worker
