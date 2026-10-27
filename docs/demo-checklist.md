# Demo Checklist

A short live demo should prove four things:

1. the UI works and generates plausible locale-aware users;
2. the same identity reproduces the same record;
3. all attributes come from PostgreSQL, not Python;
4. batches and locales are navigable and the measured timing is visible.

> **Status:** no demo video has been recorded. This checklist is ready for the
> person recording it. Do not add a video URL to the submission until a real file
> exists.

## 1. Before recording

- [ ] `.env` contains real local values and is **not** open on screen.
- [ ] `docker compose up -d` shows both services healthy.
- [ ] `Invoke-RestMethod http://localhost:8000/health` returns `status: ok`.
- [ ] Browser zoom is 100%; window is at least 1280×720.
- [ ] Close unrelated tabs, terminals, password managers and notifications.
- [ ] Terminal font is large enough to read (16–18 pt).
- [ ] Prepare two terminal tabs: one for HTTP checks, one for `psql`.
- [ ] Decide on a fixed demo identity: `en_US`, seed `2026`, batch `0`, size `10`.
- [ ] Note the first user's name, email and height before recording, so you can
      point out that they are identical after a restart.

Useful commands:

```powershell
docker compose ps
Invoke-RestMethod http://localhost:8000/health | ConvertTo-Json -Depth 5
docker compose exec -T db psql -U sul -d synthetic_user_lab -P pager=off `
    -c "SELECT locale_code, first_name, last_name, email, height_cm FROM sul.generate_user('en_US', 2026, 0, 0);"
```

## 2. Suggested 6–8 minute script

| Time | Action | Expected result / point to make |
| ---: | --- | --- |
| 0:00 | Show the generator page at `http://localhost:8000` | Locale selector, seed, batch index, batch size, generate button |
| 0:20 | Explain the architecture in one sentence | “Flask validates input and calls `sul.generate_users`; every user attribute is produced in PostgreSQL.” |
| 0:40 | Keep `en_US`, seed `2026`, batch `0`, size `10`; generate | Ten-row table, summary card, duration and users/s |
| 1:10 | Point at names, address, phone, email, height/weight, coordinates | Locale-appropriate formats; example email domains |
| 1:40 | Note the first row's name/email/height | This is the reproducibility anchor |
| 2:00 | Change batch size to `5`; generate | First five identities stay the same; rows 6–10 disappear |
| 2:20 | Return to size `10`; generate | Rows 6–10 return unchanged |
| 2:40 | Click **Next batch** twice, then **Previous batch** once | Batch index changes; records are stable for each identity |
| 3:10 | Change locale to `de_DE` with the same seed and batch | German names, street format, `PLZ city`, `+49`/`030` phone formats |
| 3:40 | Show `/docs` | In-app SQL reference: identity, SHA-256 mapping, algorithms, limits |
| 4:10 | Open `/health` | `status: ok`, `schema_ready`, `pgcrypto_ready`, `digest_ready` |
| 4:30 | Call `/api/users` for 3 users | JSON rows plus duration and users/s metadata |
| 5:00 | Run the direct SQL query above in the second terminal | Same first row as the UI for `en_US`, seed 2026, batch 0, row 0 |
| 5:40 | Restart the app container: `docker compose restart app` | Service returns; regenerate the same identity |
| 6:10 | Regenerate `en_US`, seed `2026`, batch `0`, size `10` | Identical record after restart; no state was stored |
| 6:40 | Run a small benchmark command | Show measured throughput; state that the saved 100k run is in `docs/benchmark.md` |
| 7:10 | State limitations | Emails unique within a batch only; coordinates independent of address; no public deployment yet |

Keep the narration factual. Do not claim a one-million-user benchmark or a public
deployment that was not performed.

## 3. Determinism proof (detailed)

1. Generate `en_US`, seed `2026`, batch `0`, size `10`.
2. Record row 0: `full_name`, `email`, `height_cm`.
3. Change batch size to `5`; generate. Row 0 must be unchanged.
4. Change back to `10`; generate. Row 0 must still be unchanged.
5. Go to batch `1`, then back to batch `0`. Row 0 must still be unchanged.
6. Switch to `de_DE`, then back to `en_US` with the same seed and batch. Row 0
   must still be unchanged.
7. Restart the app container and repeat. Row 0 must still be unchanged.

Direct SQL check:

```sql
SELECT locale_code, seed, batch_index, row_index,
       first_name, last_name, email, height_cm
FROM sul.generate_user('en_US', 2026, 0, 0);
```

Batch consistency check:

```sql
SELECT
  (SELECT count(*) FROM sul.generate_users('en_US', 2026, 0, 10)) AS rows,
  (SELECT count(DISTINCT email) FROM sul.generate_users('en_US', 2026, 0, 10)) AS distinct_emails;
```

Expected: `rows = 10`, `distinct_emails = 10`.

## 4. What to show in PostgreSQL

Run from the host:

```powershell
docker compose exec -T db psql -U sul -d synthetic_user_lab -P pager=off `
    -c "SELECT * FROM sul.lookup_coverage;" `
    -c "SELECT proname, provolatile FROM pg_proc WHERE pronamespace = 'sul'::regnamespace ORDER BY proname;"
```

Talking points:

- Lookup tables are shared and keyed by `locale_code`.
- `provolatile` shows `i` (immutable) for deterministic helpers and `s` (stable)
  for table-reading functions.
- The generator is stateless; no generated-user table exists.
- `pgcrypto` supplies SHA-256; migrations fail if it is unavailable.

## 5. What to show in the API

```powershell
Invoke-RestMethod "http://localhost:8000/api/users?locale=en_US&seed=2026&batch_index=0&batch_size=3" |
    ConvertTo-Json -Depth 6
```

Point out:

- `users` array with full attributes;
- `meta.duration_ms` and `meta.users_per_second`;
- `disclaimer` about example domains and independent coordinates;
- validation error behaviour:

```powershell
try {
    Invoke-RestMethod "http://localhost:8000/api/users?locale=xx_XX&seed=-1"
} catch {
    $_.ErrorDetails.Message
}
```

Expected: HTTP 400 with per-field validation messages, no stack trace.

## 6. Recording setup

- Resolution: 1920×1080 or 1280×720, 30 fps.
- Audio: short microphone test; avoid typing noise dominating narration.
- Browser: hide bookmarks bar, use a clean profile, no autofill popups.
- Terminal: dark theme, high contrast, no `.env` contents.
- Cursor: move deliberately; pause briefly after each action.
- Length: aim for 6–8 minutes. Longer demos lose attention.
- File name: `synthetic-user-lab-demo.mp4`.
- Upload: YouTube unlisted, Vimeo, or a shared drive link with viewer access.

## 7. After recording

- [ ] Watch the full video once with sound.
- [ ] Confirm no secret, `.env`, password, email inbox or unrelated window appears.
- [ ] Confirm the spoken claims match the measured results.
- [ ] Upload and set link permissions to “anyone with the link”.
- [ ] Put the real link in `docs/submission-email.md`.
- [ ] Re-run `python -m pytest -q` and record the actual result if it changed.
- [ ] Update the submission email with the real repository, deployment and video
      URLs.

## 8. Recovery steps if something fails on camera

| Problem | Quick fix |
| --- | --- |
| App returns 503 | `docker compose ps`, `docker compose logs app`, check `/health` |
| Port 8000 busy | `APP_PORT=8001` in `.env`, `docker compose up -d` |
| Database connection refused | `docker compose up -d db`, wait for healthy, retry |
| Migration checksum error | Do not edit applied files; restore the file or use a clean volume for the demo |
| Wrong row because batch size changed | Use the same locale, seed, batch and size; identities do not depend on size, but row count does |
| Benchmark is slow | Say the measured value honestly; note the environment and batch size |

If a failure cannot be fixed quickly, stop recording, fix it, and restart the
take. A clean, honest demo is better than an improvised claim.
