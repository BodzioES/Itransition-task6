# Benchmark Notes

This document records only measured runs. No throughput number in this repository
is estimated or copied from another machine.

## What is measured

`scripts/benchmark.py` measures:

1. PostgreSQL executing `sul.generate_users(...)`;
2. transferring every row over the psycopg connection;
3. Python consuming the rows with `fetchall()`.

It excludes connection setup, migrations, HTML rendering, JSON serialisation and
disk writes. Warm-up batches run first and are excluded from the summary. Each run
is timed with `time.perf_counter()`.

The script verifies that every batch returns exactly the requested number of rows
and aborts if it does not.

## Recorded environment

| Item | Value |
| --- | --- |
| Date | 2026-10-27 |
| PostgreSQL | 16.15 |
| Python | 3.12.16 |
| psycopg | 3.3.6 |
| Platform | Linux 6.6 (WSL2), x86-64 |
| Logical CPUs | 16 |
| Locale / seed | `en_US` / `12345` |
| Execution | Inside the Docker Compose `app` container, against `db:5432` |
| Database | `synthetic_user_lab` |

The container shares the host CPU. Results are not a claim about a specific cloud
instance.

## Results

### 10,000 users, batch size 1,000

Warm-up: 2 batches (2,000 users) in 4.878 s, excluded.

| Run | Users | Seconds | Users/s |
| ---: | ---: | ---: | ---: |
| 1 | 10,000 | 19.933 | 501.7 |
| 2 | 10,000 | 20.895 | 478.6 |
| 3 | 10,000 | 21.767 | 459.4 |
| **Best** | | | **501.7** |
| **Median** | | | **478.6** |
| **Worst** | | | **459.4** |

Raw data: [`benchmark_results/en_us_10000.json`](../benchmark_results/en_us_10000.json)

### 100,000 users, batch size 2,500

Warm-up: 1 batch (2,500 users) in 3.467 s, excluded.

| Run | Users | Seconds | Users/s |
| ---: | ---: | ---: | ---: |
| 1 | 100,000 | 159.200 | 628.1 |
| 2 | 100,000 | 164.295 | 608.7 |
| **Best** | | | **628.1** |
| **Median** | | | **618.4** |
| **Worst** | | | **608.7** |

Raw data: [`benchmark_results/en_us_100000.json`](../benchmark_results/en_us_100000.json)

### Combined CSV

[`benchmark_results/benchmarks.csv`](../benchmark_results/benchmarks.csv) contains
one row per measured run with timestamp, locale, seed, count, batch size, elapsed
seconds, users per second, Python version and PostgreSQL version.

## Why the larger run is faster per user

The 100,000-user run uses 2,500-row batches instead of 1,000-row batches. Each
SQL call has fixed overhead, and repeated batch calls dominate smaller runs. The
per-user cost inside the generator is unchanged. This is a useful observation, not
a guarantee: very large batches increase memory use and response latency.

## Reproduce

From the host, with a reachable `DATABASE_URL`:

```powershell
python scripts/benchmark.py --locale en_US --seed 12345 --count 10000 `
    --batch-size 1000 --repeat 3 --warmup 2 `
    --json benchmark_results/en_us_10000.json `
    --csv benchmark_results/benchmarks.csv
```

Inside Docker Compose:

```powershell
docker compose exec -T app python scripts/benchmark.py --locale en_US --seed 12345 `
    --count 100000 --batch-size 2500 --repeat 2 --warmup 1 --skip-migrations `
    --json /app/benchmark_results/en_us_100000.json `
    --csv /app/benchmark_results/benchmarks.csv

docker compose cp app:/app/benchmark_results/en_us_100000.json benchmark_results/
```

Options:

| Option | Meaning |
| --- | --- |
| `--count` | Total users to request, maximum 1,000,000 |
| `--batch-size` | Rows per SQL call, maximum 10,000 |
| `--batch-offset` | First batch index, zero-based |
| `--repeat` | Number of measured runs |
| `--warmup` | Warm-up batches, excluded from summary |
| `--json` / `--csv` | Save machine-readable results |
| `--skip-migrations` | Check existing schema instead of applying migrations |

## Distribution validation

`scripts/validate_distributions.py` checks the statistical helpers independently
of user records:

```powershell
python scripts/validate_distributions.py --locale en_US --seed 2026 `
    --json benchmark_results/distribution-validation.json
```

Measured result: `"passed": true`.

| Check | Samples | Measured | Expected/tolerance |
| --- | ---: | ---: | --- |
| Uniform mean | 20,000 | 0.50296 | `0.5 ± 0.015` |
| Uniform SD | 20,000 | 0.28828 | `0.288675 ± 0.015` |
| Normal mean | 20,000 | -0.00477 | `0 ± 0.04` |
| Normal SD | 20,000 | 0.99498 | `1 ± 0.04` |
| Sphere `z` mean | 5,000 | 0.00763 | `0 ± 0.045` |
| Sphere `z` SD | 5,000 | 0.57329 | `0.53..0.62` (validator) |
| Equator fraction (`|lat| < 30°`) | 5,000 | 0.5042 | `0.44..0.56` (validator) |
| East longitude fraction | 5,000 | 0.4862 | `0.44..0.56` (validator) |

Raw data:
[`benchmark_results/distribution-validation.json`](../benchmark_results/distribution-validation.json)

The equator fraction matters: a naive uniform latitude draw would put about 1/3 of
points within ±30°, while uniform sphere-area sampling puts about 1/2 there.

## Scope and honest limitations

- A one-million-user benchmark was **not** executed. The SQL API allows up to
  1,000,000 users per invocation pattern (subject to batch limits), but this
  repository does not claim a million-record measurement.
- The benchmark does not measure concurrent users, HTTP overhead, HTML rendering,
  TLS, reverse proxies or database cold starts.
- Results vary with CPU, PostgreSQL configuration, storage, container limits,
  client latency and batch size.
- The generator is CPU-bound in SHA-256 and lookup selection; adding workers
  increases aggregate capacity, not single-request speed.
- The saved JSON files are the source of truth for the numbers above.
