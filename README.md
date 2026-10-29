# Synthetic User Lab

A Flask + PostgreSQL web application that generates reproducible synthetic user
records **entirely inside PostgreSQL**. Python validates input, calls one SQL
function, measures the request, and renders the returned rows. Names, addresses,
phone numbers, email addresses, coordinates, body measurements and colours are
never generated in Python.

> **Deployment status:** the application has been built, migrated, tested and run
> locally with Docker Compose. No public deployment has been performed because no
> hosting account or credentials were available. Nothing in this repository
> claims otherwise. See [docs/deployment.md](docs/deployment.md).

## What it does

- Generates `en_US` and `de_DE` users from a numeric seed.
- Shows a batch of 10 users by default, with previous/next batch navigation.
- Keeps every `(locale, seed, batch_index, row_index)` identity stable across
  requests, restarts, locale switches and batch-size changes.
- Displays generation duration and users per second for every request.
- Exposes a read-only JSON endpoint and a SQL API that can be called directly.
- Uses seeded, locale-keyed lookup tables rather than per-locale SQL branches.
- Uses RFC 2606 `example.com` / `example.net` / `example.org` email domains and
  fictional phone ranges.
- States in the results table and SQL guide that coordinates are independent
  synthetic points, not the coordinates of the generated postal address.

## Stack

| Layer | Technology |
| --- | --- |
| Web | Python 3.12, Flask 3.1, Jinja2, plain CSS, minimal JavaScript |
| Database | PostgreSQL 16 (15+ supported), PL/pgSQL, `pgcrypto` SHA-256 |
| Driver | psycopg 3 |
| Production server | Gunicorn 26 |
| Tests | pytest, SQL assertion scripts |
| Packaging | Docker, Docker Compose, Render Blueprint |

## Quick start with Docker Compose

Prerequisites: Docker Desktop (or Docker Engine with Compose v2).

```powershell
Copy-Item .env.example .env
# Edit .env and replace POSTGRES_PASSWORD, DATABASE_URL and SECRET_KEY.
docker compose up --build -d
docker compose ps
```

Open <http://localhost:8000>. The application applies versioned migrations on
startup before Gunicorn begins serving. Check readiness with:

```powershell
Invoke-RestMethod http://localhost:8000/health
```

Expected top-level status is `ok`, with `schema_ready`, `pgcrypto_ready` and
`digest_ready` all `true`.

Useful commands:

```powershell
docker compose logs -f app          # application and Gunicorn logs
docker compose exec app python scripts/init_db.py --status
docker compose down                 # stop, keep the database volume
docker compose down -v              # stop and delete the database volume
```

If port `5432` is already used by a local PostgreSQL installation, set
`POSTGRES_PORT=5433` in `.env` before the first start. The app container still
reaches the database internally on `db:5432`; only the host mapping changes.

## Local development without Docker

You need a PostgreSQL database with the `pgcrypto` extension available and a
Python 3.12 virtual environment.

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements-dev.txt

# Point DATABASE_URL at an empty database, then:
python scripts/init_db.py

# Run Flask on http://127.0.0.1:5000
python main.py
```

Production-style local run:

```powershell
gunicorn --bind 0.0.0.0:8000 --workers 2 --threads 4 wsgi:app
```

## Determinism

Each field gets its own derived random value. The canonical hashed string is:

```text
locale_code | seed | batch_index | row_index | field_salt
```

The first 56 bits of the SHA-256 digest become an unsigned integer `v`, mapped to

```text
u = (v + 0.5) / 2^56        0 < u < 1
```

Independent salts (`first_name`, `street`, `latitude`, `height`, `phone_digit:3`,
etc.) keep one field from shifting when another field changes. The implementation
does not use `random()`, `setseed()`, table row order, session state or query
plans.

Identity rules:

- `batch_index` is zero-based and limited to `0..1,000,000`.
- `row_index` is zero-based and limited to `0..9,999`.
- Batch size controls how many rows are returned; it never renumbers rows that
  remain in the batch.
- A generated user is not stored. The same request returns the same record after
  a restart.

Normally distributed height and weight use Box–Muller with independently salted
uniforms and are clamped to locale/gender-specific plausible bounds. Latitude and
longitude use a uniform point on the sphere:

```text
z          = 2u - 1              (uniform in -1..1)
latitude   = degrees(asin(z))    (uniform over sphere area)
longitude  = -180 + 360u         (uniform in -180..180)
```

See [docs/sql-library.md](docs/sql-library.md) for formulas, signatures and error
behaviour.

## Using the web application

1. Choose `en_US` or `de_DE`.
2. Enter a non-negative integer seed (default `2026`).
3. Enter a zero-based batch index and a batch size (default `10`; web maximum
   `100`).
4. Select **Generate batch**.
5. Use **Previous batch** / **Next batch** to move through adjacent batches with
   the same locale, seed and batch size.

The result card reports the measured database-call duration and users per second.
The table is horizontally scrollable on small screens; a note under the table
explains that coordinates are independent synthetic points.

## HTTP API

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/` | Generator page |
| `POST` | `/generate` | Validate and generate a batch (HTML) |
| `POST` | `/next` | Next batch (HTML) |
| `POST` | `/previous` | Previous batch (HTML) |
| `GET` | `/api/users` | JSON users plus timing metadata |
| `GET` | `/health` | Application, schema and extension readiness |
| `GET` | `/docs` | In-app SQL reference |

Example:

```powershell
Invoke-RestMethod "http://localhost:8000/api/users?locale=de_DE&seed=12345&batch_index=2&batch_size=3" |
    ConvertTo-Json -Depth 6
```

Validation failures return HTTP `400` with `error.code = "validation_error"` and
per-field messages. Database failures return `503` without exposing credentials or
stack traces. The JSON response is marked `Cache-Control: no-store`.

Web limits are intentionally lower than SQL limits:

| Parameter | Web | SQL |
| --- | --- | --- |
| Seed | `0..9,223,372,036,854,775,807` | non-negative `BIGINT` |
| Batch index | `0..1,000,000` | `0..1,000,000` |
| Batch size | `1..100` (configurable, hard maximum `10,000`) | `1..10,000` |
| Row index | implied by batch size | `0..9,999` |

## Lookup data and capacity

Lookup data is shared by locale and keyed by `locale_code`, so a new locale is a
data exercise. Current seeded coverage (from `sul.lookup_coverage`):

| Lookup | `en_US` | `de_DE` |
| --- | ---: | ---: |
| First names | 120 | 136 |
| Middle names | 50 | 50 |
| Last names | 102 | 100 |
| Titles | 6 | 5 |
| Street names | 126 | 114 |
| Cities | 22 | 20 |
| Regions | 16 | 9 |
| Email domains (shared) | 3 | 3 |
| Email patterns | 5 | 5 |
| Phone formats | 3 | 3 |
| Eye colours | 5 | 5 |
| Hair colours | 6 | 6 |

The per-seed identity space is:

```text
1,000,001 batch indexes × 10,000 row indexes = 10,000,010,000 identities
```

Categorical combinations per row, ignoring continuous coordinates, height and
weight and ignoring the row suffix, are already:

| Locale | Approximate categorical combinations |
| --- | ---: |
| `en_US` | `1.28 × 10^28` |
| `de_DE` | `1.07 × 10^25` |

The `en_US` estimate is
`2 × 60 × 51 × 102 × 5.5 × 126 × 9999 × 22 × 100 × 5 × 6 × 300,000 × 15 × 10,000`
(gender, first names per gender, middle-name presence/value, last names, title
presence/value, streets, house numbers, cities, postal digits, eye colour, hair
colour, phone values, email pattern/domain and row suffix). The estimate is
conservative and describes reachable combinations, not a promise that every
combination appears in a small sample.

Generating 1,000,000 users therefore uses about 0.01% of one seed's identity
space; lookup tables do not need one row per generated user. See
[docs/sql-library.md](docs/sql-library.md) for the exact combinations and
uniqueness caveats.

## Tests

Pure unit tests and live database integration tests share the same suite.

```powershell
# Test database must be reachable and may be empty (migrations are applied).
$env:TEST_DATABASE_URL='postgresql://sul:YOUR_TEST_PASSWORD@localhost:54320/synthetic_user_lab'
python -m pytest -q
```

Recorded result on 2026-10-29 with PostgreSQL 16.15 and Python 3.12:

```text
53 passed in 16.88s
```

SQL assertion scripts are independent of pytest:

```powershell
psql -v ON_ERROR_STOP=1 "$env:DATABASE_URL" -f sql/tests/deterministic_tests.sql
psql -v ON_ERROR_STOP=1 "$env:DATABASE_URL" -f sql/tests/distribution_tests.sql
```

Both scripts printed `PASS` against the Docker Compose database and the separate
test database:

```text
deterministic_tests.sql: PASS
distribution_tests.sql: PASS
```

The Python distribution validator produced
[`benchmark_results/distribution-validation.json`](benchmark_results/distribution-validation.json)
with `"passed": true`: uniform mean `0.50296`, normal mean `-0.00477`, sphere
`z` mean `0.00763` and `z` SD `0.57329`, equator fraction `0.5042`.

## Benchmark

Benchmarks measure PostgreSQL generation, result transfer and Python
`fetchall()`. They exclude connection setup, migrations, HTML rendering and disk
writes. Results are saved in `benchmark_results/` and are not estimated.

Recorded run: `en_US`, seed `12345`, PostgreSQL 16.15, Python 3.12.16 inside the
Compose container, Linux/WSL2, 16 logical CPUs.

| Users | Batch size | Runs | Best | Median |
| ---: | ---: | ---: | ---: | ---: |
| 10,000 | 1,000 | 3 | 501.7 users/s | 478.6 users/s |
| 100,000 | 2,500 | 2 | 628.1 users/s | 618.4 users/s |

Reproduce from the host (replace the DSN with a reachable database):

```powershell
python scripts/benchmark.py --locale en_US --seed 12345 --count 10000 `
    --batch-size 1000 --repeat 3 --json benchmark_results/en_us_10000.json
```

Or run inside the Compose app container:

```powershell
docker compose exec -T app python scripts/benchmark.py --locale en_US --seed 12345 `
    --count 100000 --batch-size 2500 --repeat 2 --skip-migrations `
    --json /app/benchmark_results/en_us_100000.json
```

The measured rate depends heavily on CPU, PostgreSQL settings, network latency
and batch size. A one-million-user run was **not** executed; the SQL limits allow
it, but this repository does not claim a million-record benchmark result. See
[docs/benchmark.md](docs/benchmark.md).

## Repository layout

```text
app/                     Flask factory, routes, validation, repository, templates, CSS
sql/migrations/          Versioned schema, seed data, functions, generator API, indexes
sql/tests/               Deterministic and distribution SQL assertions
scripts/init_db.py       Checksummed migration runner with advisory lock
scripts/benchmark.py     Reproducible throughput benchmark
scripts/validate_distributions.py
tests/                   pytest unit and integration suite
docs/                    SQL reference, deployment, demo, benchmark, email draft
Dockerfile               Gunicorn image, non-root user
docker-compose.yml       PostgreSQL + application
render.yaml              Render Blueprint (deployment-ready, not deployed)
```

## Security and data safety

- All user attributes are generated by PostgreSQL; Python has no Faker, NumPy or
  `random` attribute logic.
- SQL parameters are always bound through psycopg; there is no arbitrary SQL
  endpoint and no string-built SQL from user input.
- `.env` is ignored by Git and Docker build context. `.env.example` contains
  placeholders only.
- Error pages and JSON errors do not expose stack traces or credentials.
- Responses set `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy` and
  a restrictive Content Security Policy.
- Emails use only reserved example domains. Phones use fictional ranges. The data
  is not suitable for identity verification, training claims about real people or
  production customer records.

## Known limitations

- Email uniqueness is guaranteed **within a batch** through a deterministic row
  suffix; it is not a global email registry.
- Phone numbers, names and addresses can repeat across identities.
- Coordinates are independent of the address and do not represent a real place.
- Height and weight are clamped normals, producing small point masses at the
  plausible bounds.
- Locale support is data-driven, but only `en_US` and `de_DE` are seeded and
  tested.
- No public deployment or demo video exists yet. The repository is pushed to
  <https://github.com/BodzioES/Itransition-task6>; confirm its visibility before
  submitting.

## Documentation

- [SQL library reference](docs/sql-library.md)
- [Deployment guide](docs/deployment.md)
- [Demo checklist](docs/demo-checklist.md)
- [Benchmark notes](docs/benchmark.md)
- [Verification report](docs/verification-report.md)
- [Submission email draft](docs/submission-email.md)
