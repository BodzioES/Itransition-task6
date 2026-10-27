"""PostgreSQL connectivity and the generation repository.

This module is deliberately boring: it parameterises SQL, invokes the public
SQL API and returns rows. No user attribute is calculated in Python.
"""

from __future__ import annotations

import logging
from typing import Any

import psycopg
from psycopg.rows import dict_row

logger = logging.getLogger(__name__)


class DatabaseUnavailable(RuntimeError):
    """Raised when the database is not configured or cannot be reached."""


class DatabaseQueryError(RuntimeError):
    """Raised when a database request fails after connecting."""


class Database:
    """Small read-only repository around the PostgreSQL generation API."""

    def __init__(
        self,
        dsn: str | None,
        connect_timeout: int = 5,
        statement_timeout_ms: int = 30_000,
    ) -> None:
        self.dsn = dsn
        self.connect_timeout = connect_timeout
        self.statement_timeout_ms = statement_timeout_ms

    def _connect(self) -> psycopg.Connection:
        if not self.dsn:
            raise DatabaseUnavailable("DATABASE_URL is not configured.")
        try:
            return psycopg.connect(
                self.dsn,
                connect_timeout=self.connect_timeout,
                application_name="synthetic-user-lab",
                options=f"-c statement_timeout={self.statement_timeout_ms}",
            )
        except psycopg.Error as exc:
            raise DatabaseUnavailable("The database could not be reached.") from exc

    def list_locales(self) -> list[dict[str, Any]]:
        """Return locale display metadata for the web form."""
        try:
            with self._connect() as conn:
                with conn.cursor(row_factory=dict_row) as cur:
                    cur.execute(
                        """
                        SELECT locale_code, language_name, country_name,
                               country_code, default_phone_prefix
                        FROM sul.locales
                        ORDER BY display_order, locale_code
                        """
                    )
                    return list(cur.fetchall())
        except DatabaseUnavailable:
            raise
        except psycopg.Error as exc:
            raise DatabaseQueryError("Locale lookup failed.") from exc

    def generate_users(
        self,
        locale_code: str,
        seed: int,
        batch_index: int,
        batch_size: int,
    ) -> list[dict[str, Any]]:
        """Invoke the SQL batch generator and fetch every generated row."""
        try:
            with self._connect() as conn:
                with conn.cursor(row_factory=dict_row) as cur:
                    cur.execute(
                        """
                        SELECT *
                        FROM sul.generate_users(%s, %s, %s, %s)
                        ORDER BY row_index
                        """,
                        (locale_code, seed, batch_index, batch_size),
                    )
                    rows = list(cur.fetchall())
        except DatabaseUnavailable:
            raise
        except psycopg.Error as exc:
            raise DatabaseQueryError("User generation failed.") from exc

        if len(rows) != batch_size:
            raise DatabaseQueryError(
                "The database returned an incomplete batch; no partial result is shown."
            )
        return rows

    def health(self) -> dict[str, Any]:
        """Return non-sensitive database readiness information."""
        try:
            with self._connect() as conn:
                with conn.cursor(row_factory=dict_row) as cur:
                    cur.execute(
                        """
                        SELECT
                            to_regclass('sul.locales') IS NOT NULL
                            AND to_regprocedure(
                                'sul.generate_users(text,bigint,integer,integer)'
                            ) IS NOT NULL AS schema_ready,
                            to_regprocedure('public.digest(bytea,text)') IS NOT NULL
                                AS digest_ready,
                            EXISTS (
                                SELECT 1 FROM pg_extension WHERE extname = 'pgcrypto'
                            ) AS pgcrypto_ready,
                            current_setting('server_version') AS server_version
                        """
                    )
                    row = cur.fetchone()
                    if row is None:
                        return {"status": "unavailable", "reason": "empty_health_result"}
                    schema_ready = bool(row["schema_ready"])
                    digest_ready = bool(row["digest_ready"])
                    return {
                        "status": "ok" if schema_ready and digest_ready else "not_ready",
                        "schema_ready": schema_ready,
                        "pgcrypto_ready": bool(row["pgcrypto_ready"]),
                        "digest_ready": digest_ready,
                        "server_version": row["server_version"],
                    }
        except DatabaseUnavailable as exc:
            logger.warning("Database health check failed: %s", exc)
            return {"status": "unavailable", "reason": "connection_failed"}
        except psycopg.Error as exc:
            logger.warning("Database health query failed: %s", exc.__class__.__name__)
            return {"status": "unavailable", "reason": "query_failed"}
