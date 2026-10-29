# Verification Report

This report records what was actually executed, on which environment, and what
was **not** done. It is a snapshot, not a substitute for re-running the commands.

## Snapshot

| Item | Value |
| --- | --- |
| Date | 2026-10-29 |
| Commit | Audit commit (see `git log -1`) |
| Host | Windows, Docker Desktop, WSL2 backend |
| PostgreSQL | 16.15 |
| Python (host) | 3.12.10 |
| Python (container) | 3.12.16 |
| psycopg | 3.3.6 |
| Gunicorn | 26.2.0 |
| Public deployment | **Not performed** |
| Demo video | **Not recorded** |
| Git remote | `origin` → <https://github.com/BodzioES/Itransition-task6> (`main` pushed) |

## Docker Compose

Command:

```powershell
docker compose up -d --build
docker compose ps
```

Observed: `synthetic-user-lab-db-1` and `synthetic-user-lab-app-1` both reached
`healthy`; the app published `0.0.0.0:8000->8000/tcp`.

Observed startup log after the `/app` ownership fix:

```text
Database schema is already up to date.
[INFO] Starting gunicorn 26.2.0
[INFO] Listening at: http://0.0.0.0:8000
[INFO] Using worker: gthread
[INFO] Booting worker with pid: 8
[INFO] Booting worker with pid: 9
[INFO] Control socket listening at /app/.gunicorn/gunicorn.ctl
```

The earlier `Control server error: [Errno 13] Permission denied: '/app/.gunicorn'`
is gone. The Dockerfile now runs `chown -R app:app /app` after copying files.

## Health

```powershell
Invoke-RestMethod http://localhost:8000/health
```

Observed:

```json
{
  "status": "ok",
  "service": "synthetic-user-lab",
  "version": "1.0.0",
  "database": {
    "status": "ok",
    "schema_ready": true,
    "pgcrypto_ready": true,
    "digest_ready": true,
    "server_version": "16.15"
  }
}
```

## Migrations

```powershell
docker compose exec app python scripts/init_db.py --check
docker compose exec app python scripts/init_db.py --status
```

Observed: exit code `0`; all six migrations reported `applied`:

```text
001_schema.sql: applied
002_seed_lookup_data.sql: applied
003_random_functions.sql: applied
004_formatting_functions.sql: applied
005_user_generator.sql: applied
006_indexes_and_constraints.sql: applied
```

## Python test suite

```powershell
$env:TEST_DATABASE_URL='postgresql://sul:sul_test_password@localhost:54320/synthetic_user_lab'
python -m pytest -q
```

Observed:

```text
.....................................................                    [100%]
53 passed in 18.51s
```

The suite covers validation, determinism, batch-size stability, locale data quality,
distribution statistics, web routes, JSON API behaviour, security headers, and
graceful database-failure handling. Integration tests ran against a PostgreSQL
16.15 test container on port `54320`, not against mocks.

## SQL assertion scripts

Re-run against the Compose database during the 2026-10-29 audit:

```powershell
docker compose cp sql/tests db:/tmp/sql-tests
docker compose exec -T db psql -U sul -d synthetic_user_lab -v ON_ERROR_STOP=1 `
    -f /tmp/sql-tests/deterministic_tests.sql `
    -f /tmp/sql-tests/distribution_tests.sql
```

Run against the separate test container:

```powershell
docker cp sql/tests sul-pg-test:/tmp/sql-tests
docker exec -i sul-pg-test psql -U sul -d synthetic_user_lab -v ON_ERROR_STOP=1 `
    -f /tmp/sql-tests/deterministic_tests.sql `
    -f /tmp/sql-tests/distribution_tests.sql
```

Observed on both databases:

```text
deterministic_tests.sql: PASS
distribution_tests.sql: PASS
```

## Distribution validation

Re-run during the 2026-10-29 audit and recorded in
[`benchmark_results/distribution-validation.json`](../benchmark_results/distribution-validation.json):

| Check | Measured | Result |
| --- | ---: | --- |
| Uniform mean (n=20,000) | 0.50296 | pass |
| Uniform SD | 0.28828 | pass |
| Normal mean (n=20,000) | -0.00477 | pass |
| Normal SD | 0.99498 | pass |
| Sphere `z` mean (n=5,000) | 0.00763 | pass |
| Sphere `z` SD | 0.57329 | pass |
| Equator fraction | 0.5042 | pass |
| East longitude fraction | 0.4862 | pass |

The full run reported `"passed": true` with no failures.

## Benchmarks

Measured inside the Compose app container, against the Compose PostgreSQL. Full
method and raw JSON are in [benchmark.md](benchmark.md).

| Users | Batch | Runs | Best | Median |
| ---: | ---: | ---: | ---: | ---: |
| 10,000 | 1,000 | 3 | 501.7 users/s | 478.6 users/s |
| 100,000 | 2,500 | 2 | 628.1 users/s | 618.4 users/s |

No one-million-user run was executed. The benchmark excludes connection setup,
migrations, HTML and disk writes.

## HTTP checks

```powershell
Invoke-WebRequest http://localhost:8000/ -UseBasicParsing
Invoke-RestMethod "http://localhost:8000/api/users?locale=en_US&seed=2026&batch_index=0&batch_size=5"
```

Observed:

- `GET /` → `200`, page contains the generator, both locale options and the empty
  state.
- `POST /generate` with `de_DE`, seed `777`, batch `2`, size `5` → `200`, results
  table, duration/throughput metric and the coordinate-independence note present.
- Two identical API requests returned the same first row.
- First row email for `en_US`, seed `2026`, batch `0`, row `0`:
  `lindamendoza.001@example.com`.
- Direct SQL `sul.generate_user('en_US', 2026, 0, 0)` returned `Linda Mendoza`,
  the same email, height `160.8`, latitude `33.278044301659214`, longitude
  `-118.9034729562901`.
- Security headers observed: `X-Content-Type-Options: nosniff`,
  `X-Frame-Options: DENY`, `Referrer-Policy: strict-origin-when-cross-origin`, and
  a Content Security Policy.

## Repository audit

- `git status --short` was clean after the audit commit.
- `.env` is ignored by Git and Docker build context; `.env.example` contains
  placeholders only.
- `git grep` found no local development password, test password or private key in
  tracked files.
- `git grep` found no `TODO`, `FIXME` or `XXX` markers in tracked code.
- No Faker, NumPy or Python `random` usage exists in the generation path. Flask’s
  fallback `SECRET_KEY` uses `secrets`, which is not user-data generation.
- The audit removed unused Flask context values, an unused extension entry, an
  unused `os` import and the unused `APP_ENV` setting, and fixed the distribution
  validator’s transaction/autocommit ordering.
- The only remaining bracketed placeholders are intentional fields in the
  submission email draft.

## Environment-specific note

On this Windows host, a native PostgreSQL process already listens on port `5432`,
so host connections to `localhost:5432` can reach that server and fail with
`password authentication failed for user "sul"`. The Compose app is unaffected
because it uses the internal `db:5432` address. Benchmarks were therefore run
inside the app container. On a clean host without that conflict, the host commands
in the README and benchmark guide work directly. See the deployment guide’s port
conflict section.

## Not done

- No public deployment, hosting account, domain or TLS certificate.
- No demo video recording.
- No GitHub release.
- No one-million-user benchmark.
- No load test with concurrent HTTP clients.

These are stated as limitations rather than claimed as completed work.
