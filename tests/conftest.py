"""Shared pytest fixtures.

Integration tests use TEST_DATABASE_URL, falling back to DATABASE_URL. If no
reachable PostgreSQL is configured, only those tests are skipped; pure unit and
graceful-failure tests still run and the skip reason is reported.
"""

from __future__ import annotations

import os

import psycopg
import pytest
from dotenv import load_dotenv
from psycopg.rows import dict_row

from app import create_app
from scripts.init_db import apply_migrations, connect_with_retry

load_dotenv()


def _configured_database_url() -> str | None:
    return (
        os.getenv("TEST_DATABASE_URL")
        or os.getenv("DATABASE_URL")
        or None
    )


@pytest.fixture(scope="session")
def database_url() -> str:
    dsn = _configured_database_url()
    if not dsn:
        pytest.skip("TEST_DATABASE_URL/DATABASE_URL is not configured")
    try:
        with psycopg.connect(dsn, connect_timeout=3) as conn:
            conn.execute("SELECT 1")
    except psycopg.Error as exc:
        pytest.skip(f"PostgreSQL is not reachable for integration tests: {exc.__class__.__name__}")
    return dsn


@pytest.fixture(scope="session")
def initialized_database(database_url: str) -> str:
    with connect_with_retry(database_url, wait_seconds=3) as conn:
        apply_migrations(conn)
    return database_url


@pytest.fixture(scope="session")
def db(initialized_database: str) -> psycopg.Connection:
    conn = psycopg.connect(
        initialized_database,
        autocommit=True,
        row_factory=dict_row,
        application_name="synthetic-user-lab-tests",
    )
    yield conn
    conn.close()


@pytest.fixture()
def app(initialized_database: str):
    application = create_app(
        {
            "TESTING": True,
            "DATABASE_URL": initialized_database,
            "SECRET_KEY": "test-only-secret",
            "WEB_MAX_BATCH_SIZE": 100,
            "DB_CONNECT_TIMEOUT": 3,
            "DB_STATEMENT_TIMEOUT_MS": 30_000,
        }
    )
    yield application


@pytest.fixture()
def client(app):
    return app.test_client()
