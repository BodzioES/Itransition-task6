"""Environment-based configuration for Synthetic User Lab."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")

APP_VERSION = "1.0.0"
SQL_MAX_BATCH_SIZE = 10_000


def _read_int(name: str, default: int, minimum: int, maximum: int) -> int:
    raw = os.getenv(name)
    if raw is None or raw.strip() == "":
        return default
    try:
        value = int(raw)
    except ValueError as exc:
        raise ValueError(f"{name} must be an integer") from exc
    if not minimum <= value <= maximum:
        raise ValueError(f"{name} must be between {minimum} and {maximum}")
    return value


def load_config() -> dict[str, Any]:
    """Build Flask configuration from environment variables.

    The application remains importable without a database connection so the
    health endpoint can report a useful degraded state. Database-backed routes
    fail gracefully when DATABASE_URL is absent.
    """
    database_url = (os.getenv("DATABASE_URL") or "").strip() or None
    web_max = _read_int(
        "WEB_MAX_BATCH_SIZE",
        default=100,
        minimum=1,
        maximum=SQL_MAX_BATCH_SIZE,
    )

    return {
        "APP_VERSION": APP_VERSION,
        "DATABASE_URL": database_url,
        "WEB_MAX_BATCH_SIZE": web_max,
        "DB_CONNECT_TIMEOUT": _read_int("DB_CONNECT_TIMEOUT", 5, 1, 60),
        "DB_STATEMENT_TIMEOUT_MS": _read_int("DB_STATEMENT_TIMEOUT_MS", 30_000, 1_000, 300_000),
        "LOG_LEVEL": os.getenv("LOG_LEVEL", "INFO").upper(),
        "SECRET_KEY": os.getenv("SECRET_KEY", ""),
        "MAX_CONTENT_LENGTH": 64 * 1024,
        "DEFAULT_LOCALE": "en_US",
        "DEFAULT_SEED": 2026,
        "DEFAULT_BATCH_SIZE": 10,
    }
