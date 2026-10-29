# Deployment Guide

## Current status

The application has been:

- built into a Docker image;
- started with Docker Compose against PostgreSQL 16.15;
- migrated automatically on startup;
- checked at `/health` with `schema_ready`, `pgcrypto_ready` and `digest_ready`
  all `true`;
- exercised through `/`, `/api/users` and `/health`.

It has **not** been deployed to a public host. No hosting account, domain,
credentials or authorization was available. The `render.yaml` Blueprint and this
guide make deployment straightforward, but they are not evidence that a
deployment occurred.

## Runtime topology

```text
Browser
  |
  v
Gunicorn (2 workers x 4 threads by default)
  |
  v
Flask app (validation, repository, HTML/JSON)
  |
  v
PostgreSQL 16 + pgcrypto
  |
  v
sul schema: lookup tables + PL/pgSQL generator
```

The app container runs migrations once before starting Gunicorn:

```text
python scripts/init_db.py && exec gunicorn ... wsgi:app
```

Migrations are transactional, checksummed and protected by a PostgreSQL advisory
lock, so repeated starts are safe.

## Prerequisites

- Docker Engine 24+ with Compose v2, or a Python 3.12 + PostgreSQL 15+ environment.
- PostgreSQL must allow `CREATE EXTENSION pgcrypto`. On managed services this is
  normally allowed for the database owner; verify it before deploying.
- A strong database password and a long random `SECRET_KEY`.
- A host port for the web app and, if needed, a non-conflicting host port for
  PostgreSQL.

## Environment variables

| Variable | Required | Default | Notes |
| --- | --- | --- | --- |
| `POSTGRES_DB` | Compose | — | Database name |
| `POSTGRES_USER` | Compose | — | Database user |
| `POSTGRES_PASSWORD` | Compose | — | Strong password, URL-encode special characters in DSNs |
| `POSTGRES_PORT` | No | `5432` | Host-only mapping; change if 5432 is occupied |
| `DATABASE_URL` | Yes for host runs | — | `postgresql://user:password@host:port/db` |
| `SECRET_KEY` | Yes in production | random per process if absent | Set a stable long random value |
| `LOG_LEVEL` | No | `INFO` | `DEBUG` is noisy; avoid in production |
| `WEB_MAX_BATCH_SIZE` | No | `100` | Web cap, hard maximum 10,000 |
| `DB_CONNECT_TIMEOUT` | No | `5` | Seconds |
| `DB_STATEMENT_TIMEOUT_MS` | No | `30000` | Per-statement timeout |
| `APP_PORT` | No | `8000` | Host port for the app |
| `WEB_CONCURRENCY` | No | `2` | Gunicorn workers |
| `GUNICORN_THREADS` | No | `4` | Gunicorn threads per worker |

Never commit `.env`. The repository ignores it in both Git and the Docker build
context. `.env.example` contains placeholders only.

## Docker Compose

```powershell
Copy-Item .env.example .env
# Edit .env:
#   POSTGRES_PASSWORD=<strong password>
#   DATABASE_URL=postgresql://sul:<encoded password>@localhost:5432/synthetic_user_lab
#   SECRET_KEY=<long random value>

docker compose up --build -d
docker compose ps
```

Wait for both services to become healthy, then:

```powershell
Invoke-RestMethod http://localhost:8000/health
```

Expected shape:

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

Verify the UI and JSON API:

```powershell
Invoke-WebRequest http://localhost:8000/ -UseBasicParsing | Select-Object StatusCode
Invoke-RestMethod "http://localhost:8000/api/users?locale=en_US&seed=2026&batch_index=0&batch_size=3" |
    ConvertTo-Json -Depth 6
```

Inspect migrations:

```powershell
docker compose exec app python scripts/init_db.py --status
docker compose exec app python scripts/init_db.py --check
```

Stop and clean up:

```powershell
docker compose down        # keeps the postgres_data volume
docker compose down -v     # deletes all database data
```

### Port conflict on 5432

If a local PostgreSQL installation already listens on `5432`, the host-side
publication can conflict. Set:

```dotenv
POSTGRES_PORT=5433
```

Then update a host-run `DATABASE_URL` to port `5433`. The Compose app is unaffected:
it connects internally to `db:5432`.

Symptom of this situation on the host: `password authentication failed for user
"sul"` even though the container is healthy, because host connections reach the
local server instead of the container. Check which process owns the port:

```powershell
Get-NetTCPConnection -LocalPort 5432 -State Listen |
    Select-Object LocalAddress, OwningProcess
```

## Host-run production

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python scripts/init_db.py
gunicorn --bind 0.0.0.0:8000 --workers 2 --threads 4 --timeout 60 `
    --access-logfile - --error-logfile - wsgi:app
```

Use a process supervisor (systemd, Windows Service wrapper, container runtime) so
Gunicorn restarts after failures. Terminate TLS at a reverse proxy such as nginx,
Caddy or a managed load balancer. Forward `X-Forwarded-Proto` if the proxy
terminates TLS; Flask's security headers include HSTS only for secure requests.

### Gunicorn workers

This workload is CPU-bound inside PostgreSQL, and Flask is mostly waiting on the
database. Start with 2 workers and 4 threads per worker, then measure. Do not
blindly multiply workers on a small database: concurrent generation increases
PostgreSQL CPU and memory pressure.

## Render Blueprint

`render.yaml` provisions a PostgreSQL database and a Docker web service:

1. Push the repository to a Git provider.
2. In Render, create a Blueprint and select the repository.
3. Review the plan names against your current Render offering.
4. Confirm the database user can create `pgcrypto`.
5. Set the health check path to `/health` (already in the Blueprint).
6. Deploy and watch the build logs for migration output and Gunicorn startup.
7. Open the public URL and verify `/health`, `/`, `/docs` and `/api/users`.

The Blueprint generates `SECRET_KEY` and injects `DATABASE_URL` from the managed
database. No secret is stored in the repository. Free instances may sleep; the
first request after sleep is slower and the benchmark numbers in this repository
do not describe that case.

## Other platforms

Any platform that supports a Dockerfile and a PostgreSQL connection string works:

- Fly.io, Railway, Koyeb, AWS ECS/Fargate, Azure Container Apps, Google Cloud Run.
- For serverless containers, ensure the database is reachable and the startup
  migration step is allowed to run. If the platform imposes a short startup
  budget, run `scripts/init_db.py` as a separate release/job command instead.
- If the platform provides only a TCP proxy with TLS, add `sslmode=require` (or the
  provider's required mode) to `DATABASE_URL`.
- Set `WEB_CONCURRENCY` to the platform's CPU allocation, not higher.

## Migrations

- Files are applied in filename order from `sql/migrations/`.
- Each applied file is recorded with its SHA-256 checksum in
  `public.schema_migrations`.
- Editing an applied migration causes a checksum mismatch and a hard failure. Add
  `007_...sql` instead.
- `scripts/init_db.py --status` shows pending/applied state.
- `scripts/init_db.py --check` exits non-zero if anything is pending or mismatched.
- Migrations require the `pgcrypto` extension. If `CREATE EXTENSION` fails, fix
  database privileges before retrying; do not remove the requirement.

## Operations

### Health

`GET /health` returns `200` only when the schema function and digest are present.
It returns `503` with `status: "degraded"` otherwise. Use it for container and load
balancer health checks.

### Logs

Gunicorn access and error logs go to stdout/stderr. The app logs generation
failures server-side without exposing them to users. Never log the DSN or
passwords.

### Backups

Generated users are not stored, so backups only need the lookup schema and
migration history. Still back up the database:

- Compose: back up the `postgres_data` volume or use `pg_dump`.
- Managed PostgreSQL: enable automated backups and point-in-time recovery.

```powershell
docker compose exec -T db pg_dump -U sul -d synthetic_user_lab -Fc > backup.dump
```

### Scaling

- Increase PostgreSQL CPU before adding many app workers.
- Use a connection pooler (PgBouncer) if worker count grows; each request opens a
  short-lived psycopg connection.
- Large batches increase latency and memory. Keep the public web cap modest
  (`WEB_MAX_BATCH_SIZE=100`) and use the SQL API for bulk generation.
- Cache nothing: determinism makes caching unnecessary for correctness and
  introduces stale-data risk when lookup tables change.

## Security checklist

- [ ] Strong, unique `POSTGRES_PASSWORD`; never the example value.
- [ ] Long random `SECRET_KEY`; stable across restarts.
- [ ] TLS enabled at the edge; HSTS is emitted for secure requests.
- [ ] Database not publicly reachable unless required; restrict by network/firewall.
- [ ] `WEB_MAX_BATCH_SIZE` appropriate for the host.
- [ ] `DB_STATEMENT_TIMEOUT_MS` set to a value the host can tolerate.
- [ ] No `.env`, dump, log or credential committed.
- [ ] `/health` monitored.
- [ ] Rate limiting applied at the proxy/host if the service is public.
- [ ] Dependency versions pinned and reviewed.
- [ ] Error pages checked: no stack traces, DSNs or SQL text.

The app sets `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy` and a
restrictive Content Security Policy. It caps request bodies at 64 KiB. There is no
arbitrary SQL endpoint.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `password authentication failed for user "sul"` from the host | Host port reaches a different PostgreSQL server | Change `POSTGRES_PORT`, update host DSN, or test inside the container |
| App container unhealthy after startup | Migration failed or database not ready | `docker compose logs app` and `docker compose logs db` |
| `pgcrypto` unavailable | Extension not installable by the database user | Grant the required privilege or use a database that supports it |
| `Checksum mismatch for already-applied migration` | An applied SQL file was edited | Restore the file; add a new migration for the change |
| `/health` returns 503 with `schema_ready: false` | Migrations not applied or connected to the wrong database | Run `python scripts/init_db.py`, check `DATABASE_URL` |
| `/health` returns 503 with `digest_ready: false` | `public.digest` missing | Ensure `pgcrypto` is installed in `public` |
| `Control server error: Permission denied: '/app/.gunicorn'` | `/app` not writable by the `app` user | The Dockerfile chowns `/app`; rebuild if using an old image |
| Requests time out on large batches | Batch too large for the host | Lower `WEB_MAX_BATCH_SIZE` or `DB_STATEMENT_TIMEOUT_MS`, use HTTP API with smaller batches |
| Port 8000 already allocated | Another process is using it | Set `APP_PORT=8001` and restart Compose |

### Verified container startup

Observed after the Dockerfile ownership fix:

```text
Database schema is already up to date.
[INFO] Starting gunicorn 26.2.0
[INFO] Listening at: http://0.0.0.0:8000
[INFO] Using worker: gthread
[INFO] Booting worker with pid: 8
[INFO] Booting worker with pid: 9
[INFO] Control socket listening at /app/.gunicorn/gunicorn.ctl
```

## Public deployment checklist

Complete these steps on the target host and record the real outputs:

- [ ] Provision PostgreSQL; confirm `pgcrypto`.
- [ ] Set secrets and production environment variables.
- [ ] Deploy the Docker image / Blueprint.
- [ ] Confirm migrations applied exactly once.
- [ ] `GET /health` returns `200` with all readiness flags true.
- [ ] `GET /` renders both locales.
- [ ] Generate a default batch in both locales.
- [ ] Confirm previous/next batch navigation keeps identities stable.
- [ ] Compare a row from the UI with the same identity from `sul.generate_user`.
- [ ] `GET /api/users` returns JSON with timing metadata.
- [ ] Check logs for errors and absence of secrets.
- [ ] Capture the public URL, documentation URL and a short demo video.
- [ ] Update the submission email with the **actual** URLs and benchmark result.

Do not describe the service as deployed until the public URL and health check have
been verified.
