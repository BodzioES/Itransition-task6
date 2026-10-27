"""Reproducible benchmark for the SQL-native generation API.

Measures PostgreSQL generation, result transfer and Python row consumption.
It does not measure HTML rendering or any Python-side attribute formatting.

Example:
    python scripts/benchmark.py --locale en_US --seed 12345 --count 100000 \
        --batch-size 1000 --repeat 2 --json benchmark_results/en_us.json
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import platform
import statistics
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import psycopg

BASE_DIR = Path(__file__).resolve().parent.parent
if str(BASE_DIR) not in sys.path:
    sys.path.insert(0, str(BASE_DIR))

from scripts.init_db import apply_migrations, connect_with_retry  # noqa: E402
MAX_COUNT = 1_000_000
MAX_BATCH_SIZE = 10_000
MAX_BATCH_INDEX = 1_000_000


def _positive_int(raw: str) -> int:
    try:
        value = int(raw)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("must be an integer") from exc
    if value <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return value


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Benchmark SQL-native synthetic user generation."
    )
    parser.add_argument("--database-url", default=os.getenv("DATABASE_URL"))
    parser.add_argument("--locale", default="en_US")
    parser.add_argument("--seed", type=int, default=12345)
    parser.add_argument("--count", type=_positive_int, default=10_000)
    parser.add_argument("--batch-size", type=_positive_int, default=1_000)
    parser.add_argument("--batch-offset", type=int, default=0)
    parser.add_argument("--repeat", type=_positive_int, default=1)
    parser.add_argument(
        "--warmup",
        type=int,
        default=1,
        help="Number of warm-up batches before measurement (default: 1).",
    )
    parser.add_argument("--json", type=Path, help="Write full results as JSON.")
    parser.add_argument("--csv", type=Path, help="Append one row per run to CSV.")
    parser.add_argument(
        "--skip-migrations",
        action="store_true",
        help="Verify connectivity and an existing schema without applying migrations.",
    )
    return parser


def _validate_args(args: argparse.Namespace) -> None:
    if not args.database_url:
        raise RuntimeError("DATABASE_URL is not configured.")
    if args.count > MAX_COUNT:
        raise RuntimeError(f"--count must be <= {MAX_COUNT:,}")
    if args.batch_size > MAX_BATCH_SIZE:
        raise RuntimeError(f"--batch-size must be <= {MAX_BATCH_SIZE:,}")
    if args.seed < 0:
        raise RuntimeError("--seed must be non-negative")
    if args.batch_offset < 0:
        raise RuntimeError("--batch-offset must be non-negative")
    batches = (args.count + args.batch_size - 1) // args.batch_size
    if args.batch_offset + batches + args.warmup > MAX_BATCH_INDEX:
        raise RuntimeError("The requested batch range exceeds the SQL batch-index limit.")


def _prepare_database(args: argparse.Namespace) -> dict[str, Any]:
    with connect_with_retry(args.database_url, wait_seconds=20) as conn:
        if args.skip_migrations:
            exists = conn.execute(
                "SELECT to_regprocedure("
                "'sul.generate_users(text,bigint,integer,integer)'"
                ") IS NOT NULL AS ready"
            ).fetchone()[0]
            if not exists:
                raise RuntimeError(
                    "Schema is not initialized. Re-run without --skip-migrations."
                )
        else:
            apply_migrations(conn)
        row = conn.execute(
            """
            SELECT current_setting('server_version') AS server_version,
                   current_database() AS database_name
            """
        ).fetchone()
    return {"server_version": row[0], "database_name": row[1]}


def _iter_batches(
    conn: psycopg.Connection,
    *,
    locale: str,
    seed: int,
    count: int,
    batch_size: int,
    batch_offset: int,
) -> int:
    consumed = 0
    batch_number = 0
    with conn.cursor() as cur:
        while consumed < count:
            this_size = min(batch_size, count - consumed)
            cur.execute(
                """
                SELECT *
                FROM sul.generate_users(%s, %s, %s, %s)
                ORDER BY row_index
                """,
                (locale, seed, batch_offset + batch_number, this_size),
            )
            rows = cur.fetchall()
            if len(rows) != this_size:
                raise RuntimeError(
                    f"Expected {this_size} rows, received {len(rows)}; aborting."
                )
            consumed += len(rows)
            batch_number += 1
    return consumed


def _warm_up(
    conn: psycopg.Connection,
    args: argparse.Namespace,
    start_batch: int,
) -> dict[str, Any]:
    if args.warmup <= 0:
        return {"batches": 0}
    total = 0
    started = time.perf_counter()
    for index in range(args.warmup):
        total += _iter_batches(
            conn,
            locale=args.locale,
            seed=args.seed,
            count=args.batch_size,
            batch_size=args.batch_size,
            batch_offset=start_batch + index,
        )
    elapsed = time.perf_counter() - started
    return {
        "batches": args.warmup,
        "users": total,
        "elapsed_seconds": elapsed,
        "users_per_second": total / elapsed if elapsed else None,
    }


def _run_once(conn: psycopg.Connection, args: argparse.Namespace) -> dict[str, Any]:
    started = time.perf_counter()
    count = _iter_batches(
        conn,
        locale=args.locale,
        seed=args.seed,
        count=args.count,
        batch_size=args.batch_size,
        batch_offset=args.batch_offset,
    )
    elapsed = time.perf_counter() - started
    return {
        "count": count,
        "elapsed_seconds": elapsed,
        "users_per_second": count / elapsed,
        "batch_size": args.batch_size,
    }


def _environment(server: dict[str, Any]) -> dict[str, Any]:
    return {
        "python": platform.python_version(),
        "platform": platform.platform(),
        "processor": platform.processor() or "unknown",
        "cpu_count": os.cpu_count(),
        "psycopg": psycopg.__version__,
        "postgresql_server_version": server["server_version"],
        "database_name": server["database_name"],
        "os": os.name,
    }


def _format_number(value: float | None) -> str:
    return "n/a" if value is None else f"{value:,.1f}"


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=False) + "\n", encoding="utf-8")


def _write_csv(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    exists = path.exists()
    fieldnames = [
        "generated_at",
        "locale",
        "seed",
        "count",
        "batch_size",
        "run",
        "elapsed_seconds",
        "users_per_second",
        "python",
        "postgresql_server_version",
    ]
    with path.open("a", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        if not exists:
            writer.writeheader()
        for index, run in enumerate(payload["runs"], start=1):
            writer.writerow(
                {
                    "generated_at": payload["generated_at"],
                    "locale": payload["parameters"]["locale"],
                    "seed": payload["parameters"]["seed"],
                    "count": run["count"],
                    "batch_size": run["batch_size"],
                    "run": index,
                    "elapsed_seconds": f"{run['elapsed_seconds']:.6f}",
                    "users_per_second": f"{run['users_per_second']:.3f}",
                    "python": payload["environment"]["python"],
                    "postgresql_server_version": payload["environment"][
                        "postgresql_server_version"
                    ],
                }
            )


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        _validate_args(args)
        server = _prepare_database(args)
        environment = _environment(server)

        with psycopg.connect(
            args.database_url,
            autocommit=True,
            application_name="synthetic-user-lab-benchmark",
        ) as conn:
            warmup = _warm_up(
                conn,
                args,
                start_batch=args.batch_offset,
            )
            runs = [
                _run_once(conn, args)
                for _ in range(args.repeat)
            ]

        rates = [run["users_per_second"] for run in runs]
        payload = {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "parameters": {
                "locale": args.locale,
                "seed": args.seed,
                "count": args.count,
                "batch_size": args.batch_size,
                "batch_offset": args.batch_offset,
                "repeat": args.repeat,
                "warmup_batches": args.warmup,
            },
            "environment": environment,
            "warmup": warmup,
            "runs": runs,
            "summary": {
                "best_users_per_second": max(rates),
                "median_users_per_second": statistics.median(rates),
                "worst_users_per_second": min(rates),
                "runs": len(runs),
            },
            "measurement_scope": (
                "PostgreSQL SQL generation (including ORDER BY row_index), "
                "result transfer over the client connection and Python fetchall(). "
                "Excludes connection setup, migrations, HTML rendering and disk writes."
            ),
            "notes": [
                "No benchmark result is fabricated; values come from the run above.",
                "The application UI default batch size is smaller than the SQL limit.",
            ],
        }

        print("Synthetic User Lab - SQL generation benchmark")
        print("=" * 52)
        print(f"PostgreSQL      : {environment['postgresql_server_version']}")
        print(f"Python          : {environment['python']} ({platform.system()})")
        print(f"Locale / seed   : {args.locale} / {args.seed}")
        print(f"Users           : {args.count:,}")
        print(f"Batch size      : {args.batch_size:,}")
        print(f"Repeats         : {args.repeat}")
        if warmup.get("users"):
            print(
                "Warm-up         : "
                f"{warmup['users']:,} users in {warmup['elapsed_seconds']:.3f}s "
                "(excluded)"
            )
        for index, run in enumerate(runs, start=1):
            print(
                f"Run {index:<12}: {run['count']:,} users in "
                f"{run['elapsed_seconds']:.3f}s = "
                f"{_format_number(run['users_per_second'])} users/s"
            )
        print("-" * 52)
        print(
            "Best / median   : "
            f"{_format_number(payload['summary']['best_users_per_second'])} / "
            f"{_format_number(payload['summary']['median_users_per_second'])} users/s"
        )
        print("Scope           : SQL generation + result transfer/fetch (not HTML).")

        if args.json:
            _write_json(args.json, payload)
            print(f"JSON written    : {args.json}")
        if args.csv:
            _write_csv(args.csv, payload)
            print(f"CSV updated     : {args.csv}")
        return 0
    except (RuntimeError, psycopg.Error) as exc:
        print(f"Benchmark failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
