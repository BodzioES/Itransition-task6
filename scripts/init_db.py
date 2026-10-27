"""Apply versioned SQL migrations with checksums and an advisory lock.

Examples:
    python scripts/init_db.py
    python scripts/init_db.py --status
    python scripts/init_db.py --check

Environment:
    DATABASE_URL   PostgreSQL DSN (or pass --database-url)
"""

from __future__ import annotations

import argparse
import hashlib
import os
import sys
import time
from dataclasses import dataclass
from pathlib import Path

import psycopg
from dotenv import load_dotenv
from psycopg.rows import dict_row

BASE_DIR = Path(__file__).resolve().parent.parent
MIGRATIONS_DIR = BASE_DIR / "sql" / "migrations"
MIGRATIONS_TABLE = "public.schema_migrations"
LOCK_ID = 736_527_001
load_dotenv(BASE_DIR / ".env")


@dataclass(frozen=True)
class Migration:
    filename: str
    path: Path
    checksum: str
    sql: str


@dataclass(frozen=True)
class MigrationStatus:
    filename: str
    state: str
    applied_at: str | None = None


def _load_migrations() -> list[Migration]:
    if not MIGRATIONS_DIR.is_dir():
        raise RuntimeError(f"Migration directory not found: {MIGRATIONS_DIR}")
    migrations: list[Migration] = []
    for path in sorted(MIGRATIONS_DIR.glob("*.sql")):
        raw = path.read_bytes()
        migrations.append(
            Migration(
                filename=path.name,
                path=path,
                checksum=hashlib.sha256(raw).hexdigest(),
                sql=raw.decode("utf-8"),
            )
        )
    if not migrations:
        raise RuntimeError("No SQL migrations were found.")
    return migrations


def connect_with_retry(dsn: str, wait_seconds: int = 30) -> psycopg.Connection:
    """Connect, retrying transient startup failures without exposing the DSN."""
    if not dsn:
        raise RuntimeError("DATABASE_URL is not configured.")
    deadline = time.monotonic() + max(wait_seconds, 0)
    last_error: Exception | None = None
    while True:
        try:
            return psycopg.connect(dsn, connect_timeout=5, application_name="sul-migrator")
        except psycopg.OperationalError as exc:
            last_error = exc
            if time.monotonic() >= deadline:
                raise RuntimeError(
                    "Could not connect to PostgreSQL while applying migrations. "
                    "Verify DATABASE_URL and that the database is running."
                ) from last_error
            time.sleep(1)


def _ensure_migrations_table(conn: psycopg.Connection) -> None:
    conn.execute(
        f"""
        CREATE TABLE IF NOT EXISTS {MIGRATIONS_TABLE} (
            filename    TEXT PRIMARY KEY,
            checksum    TEXT NOT NULL,
            applied_at  TIMESTAMPTZ NOT NULL DEFAULT now()
        )
        """
    )


def _applied_rows(conn: psycopg.Connection) -> dict[str, dict[str, str]]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(f"SELECT filename, checksum, applied_at::text FROM {MIGRATIONS_TABLE}")
        return {row["filename"]: row for row in cur.fetchall()}


def inspect_status(conn: psycopg.Connection) -> list[MigrationStatus]:
    """Return applied and pending migration states without changing SQL objects."""
    _ensure_migrations_table(conn)
    migrations = _load_migrations()
    applied = _applied_rows(conn)
    statuses: list[MigrationStatus] = []
    for migration in migrations:
        row = applied.get(migration.filename)
        if row is None:
            statuses.append(MigrationStatus(migration.filename, "pending"))
        elif row["checksum"] != migration.checksum:
            statuses.append(
                MigrationStatus(migration.filename, "checksum_mismatch", row["applied_at"])
            )
        else:
            statuses.append(MigrationStatus(migration.filename, "applied", row["applied_at"]))
    return statuses


def apply_migrations(conn: psycopg.Connection) -> list[str]:
    """Apply pending migrations transactionally. Returns applied filenames."""
    _ensure_migrations_table(conn)
    conn.commit()
    migrations = _load_migrations()
    applied = _applied_rows(conn)

    for migration in migrations:
        row = applied.get(migration.filename)
        if row and row["checksum"] != migration.checksum:
            raise RuntimeError(
                f"Checksum mismatch for already-applied migration {migration.filename}. "
                "Do not edit applied migrations; add a new migration instead."
            )

    newly_applied: list[str] = []
    for migration in migrations:
        if migration.filename in applied:
            continue
        print(f"Applying {migration.filename} ...", flush=True)
        with conn.transaction():
            conn.execute(migration.sql)
            conn.execute(
                f"""
                INSERT INTO {MIGRATIONS_TABLE} (filename, checksum)
                VALUES (%s, %s)
                """,
                (migration.filename, migration.checksum),
            )
        newly_applied.append(migration.filename)

    if not newly_applied:
        print("Database schema is already up to date.")
    else:
        print(f"Applied {len(newly_applied)} migration(s).")
    return newly_applied


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Apply or inspect Synthetic User Lab PostgreSQL migrations."
    )
    parser.add_argument(
        "--database-url",
        default=os.getenv("DATABASE_URL"),
        help="PostgreSQL DSN. Defaults to DATABASE_URL.",
    )
    parser.add_argument(
        "--wait-seconds",
        type=int,
        default=30,
        help="Seconds to retry the initial connection (default: 30).",
    )
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--status", action="store_true", help="Show migration status without applying.")
    group.add_argument("--check", action="store_true", help="Exit 1 if migrations are pending or mismatched.")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    if not args.database_url:
        print("DATABASE_URL is not configured.", file=sys.stderr)
        return 2

    try:
        with connect_with_retry(args.database_url, args.wait_seconds) as conn:
            conn.execute("SELECT pg_advisory_lock(%s)", (LOCK_ID,))
            try:
                if args.status or args.check:
                    statuses = inspect_status(conn)
                    for item in statuses:
                        suffix = f" (applied {item.applied_at})" if item.applied_at else ""
                        print(f"{item.filename}: {item.state}{suffix}")
                    if args.check:
                        bad = [s for s in statuses if s.state != "applied"]
                        return 1 if bad else 0
                    return 0
                apply_migrations(conn)
                statuses = inspect_status(conn)
                print("Migration status:")
                for item in statuses:
                    print(f"  {item.filename}: {item.state}")
                return 0
            finally:
                conn.execute("SELECT pg_advisory_unlock(%s)", (LOCK_ID,))
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    except psycopg.Error as exc:
        print(f"PostgreSQL error while applying migrations: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
