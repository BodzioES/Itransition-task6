"""Independent statistical validation for the SQL distribution algorithms.

Example:
    python scripts/validate_distributions.py --samples 50000 --sphere-samples 10000
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
from pathlib import Path
from typing import Any

import psycopg

BASE_DIR = Path(__file__).resolve().parent.parent
if str(BASE_DIR) not in sys.path:
    sys.path.insert(0, str(BASE_DIR))

from scripts.init_db import apply_migrations, connect_with_retry  # noqa: E402


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database-url", default=os.getenv("DATABASE_URL"))
    parser.add_argument("--locale", default="en_US")
    parser.add_argument("--seed", type=int, default=2026)
    parser.add_argument("--samples", type=int, default=20_000)
    parser.add_argument("--sphere-samples", type=int, default=5_000)
    parser.add_argument("--json", type=Path)
    parser.add_argument("--skip-migrations", action="store_true")
    return parser


def _failures(stats: dict[str, Any]) -> list[str]:
    failures: list[str] = []
    if not (0 < stats["uniform"]["min"] < 0.01):
        failures.append("uniform minimum is not close to 0")
    if not (0.99 < stats["uniform"]["max"] < 1):
        failures.append("uniform maximum is not close to 1")
    if abs(stats["uniform"]["mean"] - 0.5) > 0.015:
        failures.append("uniform mean is outside tolerance")
    if abs(stats["uniform"]["sd"] - 1 / math.sqrt(12)) > 0.015:
        failures.append("uniform standard deviation is outside tolerance")

    if abs(stats["normal"]["mean"]) > 0.04:
        failures.append("normal mean is outside tolerance")
    if abs(stats["normal"]["sd"] - 1.0) > 0.04:
        failures.append("normal standard deviation is outside tolerance")

    if abs(stats["sphere"]["z_mean"]) > 0.045:
        failures.append("spherical z mean is outside tolerance")
    if not (0.53 < stats["sphere"]["z_sd"] < 0.62):
        failures.append("spherical z standard deviation is outside tolerance")
    if not (0.44 < stats["sphere"]["equator_fraction"] < 0.56):
        failures.append("equator fraction does not indicate spherical latitude sampling")
    if not (0.44 < stats["sphere"]["east_fraction"] < 0.56):
        failures.append("longitude east/west split is outside tolerance")
    return failures


def _collect(
    conn: psycopg.Connection,
    *,
    locale: str,
    seed: int,
    samples: int,
    sphere_samples: int,
) -> dict[str, Any]:
    uniform = conn.execute(
        """
        SELECT avg(u) AS mean, stddev_samp(u) AS sd, min(u) AS min, max(u) AS max
        FROM (
            SELECT sul.deterministic_uniform(%s, %s, 0, i, 'uniform_probe') AS u
            FROM generate_series(0, %s) AS i
        ) s
        """,
        (locale, seed, samples - 1),
    ).fetchone()

    normal = conn.execute(
        """
        SELECT avg(z) AS mean, stddev_samp(z) AS sd, min(z) AS min, max(z) AS max
        FROM (
            SELECT sul.deterministic_normal(%s, %s, 0, i, 'normal_probe', 0.0, 1.0) AS z
            FROM generate_series(0, %s) AS i
        ) s
        """,
        (locale, seed, samples - 1),
    ).fetchone()

    sphere = conn.execute(
        """
        SELECT
            avg(sin(radians(latitude))) AS z_mean,
            stddev_samp(sin(radians(latitude))) AS z_sd,
            avg(CASE WHEN abs(latitude) < 30 THEN 1.0 ELSE 0.0 END) AS equator_fraction,
            avg(CASE WHEN longitude > 0 THEN 1.0 ELSE 0.0 END) AS east_fraction,
            count(*) AS n
        FROM sul.generate_users(%s, %s, 0, %s)
        """,
        (locale, seed, sphere_samples),
    ).fetchone()

    return {
        "uniform": {
            "samples": samples,
            "mean": float(uniform[0]),
            "sd": float(uniform[1]),
            "min": float(uniform[2]),
            "max": float(uniform[3]),
            "expected_mean": 0.5,
            "expected_sd": 1 / math.sqrt(12),
        },
        "normal": {
            "samples": samples,
            "mean": float(normal[0]),
            "sd": float(normal[1]),
            "min": float(normal[2]),
            "max": float(normal[3]),
            "expected_mean": 0.0,
            "expected_sd": 1.0,
        },
        "sphere": {
            "samples": int(sphere[4]),
            "z_mean": float(sphere[0]),
            "z_sd": float(sphere[1]),
            "equator_fraction": float(sphere[2]),
            "uniform_latitude_equator_fraction": 1 / 3,
            "east_fraction": float(sphere[3]),
        },
    }


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    if not args.database_url:
        print("DATABASE_URL is not configured.", file=sys.stderr)
        return 2
    if args.samples < 1_000:
        print("--samples must be at least 1000 for a meaningful test.", file=sys.stderr)
        return 2
    if not 1 <= args.sphere_samples <= 10_000:
        print("--sphere-samples must be between 1 and 10000.", file=sys.stderr)
        return 2

    try:
        with connect_with_retry(args.database_url, wait_seconds=20) as conn:
            if not args.skip_migrations:
                apply_migrations(conn)
            conn.autocommit = True
            stats = _collect(
                conn,
                locale=args.locale,
                seed=args.seed,
                samples=args.samples,
                sphere_samples=args.sphere_samples,
            )
    except (RuntimeError, psycopg.Error) as exc:
        print(f"Validation failed: {exc}", file=sys.stderr)
        return 1

    failures = _failures(stats)
    payload = {
        "locale": args.locale,
        "seed": args.seed,
        "statistics": stats,
        "tolerances": {
            "uniform_mean_abs": 0.015,
            "uniform_sd_abs": 0.015,
            "normal_mean_abs": 0.04,
            "normal_sd_abs": 0.04,
            "sphere_z_mean_abs": 0.045,
            "sphere_z_sd_range": [0.53, 0.62],
            "equator_fraction_range": [0.44, 0.56],
        },
        "passed": not failures,
        "failures": failures,
    }

    print("Synthetic User Lab - distribution validation")
    print("=" * 48)
    print(
        f"Uniform  : n={stats['uniform']['samples']:,} "
        f"mean={stats['uniform']['mean']:.5f} "
        f"sd={stats['uniform']['sd']:.5f} "
        f"range=({stats['uniform']['min']:.6f}, {stats['uniform']['max']:.6f})"
    )
    print(
        f"Normal   : n={stats['normal']['samples']:,} "
        f"mean={stats['normal']['mean']:.5f} "
        f"sd={stats['normal']['sd']:.5f}"
    )
    print(
        f"Sphere   : n={stats['sphere']['samples']:,} "
        f"z_mean={stats['sphere']['z_mean']:.5f} "
        f"z_sd={stats['sphere']['z_sd']:.5f}"
    )
    print(
        f"Latitude : |lat|<30 fraction={stats['sphere']['equator_fraction']:.4f} "
        f"(uniform latitude would be {1/3:.4f})"
    )
    print(
        f"Longitude: east fraction={stats['sphere']['east_fraction']:.4f}"
    )
    print("=" * 48)
    if failures:
        print("FAILED:")
        for failure in failures:
            print(f"  - {failure}")
    else:
        print("PASS: observed distributions match the documented algorithms.")

    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        print(f"JSON written: {args.json}")
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
