# Submission Email Draft

Fill every bracketed placeholder with a real value before sending. Do not send
this draft with placeholders, and do not claim a deployment or video that does not
exist.

## Recipient

- To: `[Recipient name and email address]`
- Subject: `Itransition Task 6 – Synthetic User Lab – [Your full name]`

## Email body

```text
Hello [Recipient name],

Please find my submission for Task 6 below. The project is a Flask/PostgreSQL
web application that generates reproducible synthetic users entirely inside
PostgreSQL.

Submission details
------------------
Full name:       [Your full name]
GitHub repository: https://github.com/BodzioES/Itransition-task6
Deployed app:    [https://your-deployed-app.example]
Documentation:   https://github.com/BodzioES/Itransition-task6#readme
Demo video:      [https://.../synthetic-user-lab-demo.mp4]
Benchmark:       100,000 users, median 618.4 users/s (best 628.1), measured locally

What the application does
-------------------------
- Generates en_US and de_DE synthetic users from a numeric seed.
- Uses zero-based batch and row identities:
  (locale_code, seed, batch_index, row_index).
- Returns the same record for the same identity after restarts, request
  reordering, locale switches and batch-size changes.
- Shows a 10-row default batch with previous/next navigation, duration and
  users/s.
- Exposes a read-only JSON endpoint (/api/users) and a health endpoint
  (/health).
- Uses example.com/net/org addresses and fictional phone ranges.
- Labels coordinates as independent synthetic points, not the address location.

SQL-only generation
-------------------
All user attributes are produced by PL/pgSQL functions in the sul schema. Python
only validates input, calls sul.generate_users(...), measures the call and renders
HTML/JSON. There is no Faker, NumPy, Python random usage, or Python-side attribute
formatting.

Randomness is SHA-256 based: each field hashes
locale | seed | batch_index | row_index | field_salt, takes the first 56 bits and
maps them to u = (v + 0.5) / 2^56 in (0,1). Height and weight use Box–Muller
normals with clamping; latitude/longitude use uniform spherical sampling with
z = sin(latitude).

Lookup data and scale
---------------------
Lookup tables are shared and keyed by locale_code. Seeded coverage includes 120
en_US / 136 de_DE first names, 102 / 100 last names, 126 / 114 street names,
22 / 20 cities, and 6 / 5 titles. One seed supports 10,000,010,000 identities
(1,000,001 batches x 10,000 rows). Conservative categorical combinations are
about 1.28e28 for en_US and 1.07e25 for de_DE, far above the 100,000–1,000,000
records required, so lookup tables are not sized per generated user.

Stack and delivery
------------------
- Python 3.12, Flask 3.1, psycopg 3, Jinja2, plain CSS, minimal JavaScript.
- PostgreSQL 16 with versioned SQL migrations and pgcrypto.
- pytest suite and standalone SQL assertion scripts.
- Dockerfile, Docker Compose, Gunicorn and a Render Blueprint.
- README, SQL API reference, deployment guide, benchmark notes and demo checklist.

Verification actually performed
-------------------------------
- pytest: 53 passed on 2026-10-29.
- SQL deterministic tests: PASS.
- SQL distribution tests: PASS.
- Distribution validator: passed (uniform mean 0.50296; normal mean -0.00477;
  sphere z mean 0.00763, z SD 0.57329, equator fraction 0.5042).
- Docker Compose deployment verified locally on 2026-10-27 (re-checked on
  2026-10-29): app and database healthy, /health returned 200 with schema_ready,
  pgcrypto_ready and digest_ready all true.
- Benchmarks measured inside the Compose app container (PostgreSQL 16.15,
  Python 3.12.16, 16 logical CPUs):
    10,000 users, batch 1,000, 3 runs: median 478.6 users/s (best 501.7).
    100,000 users, batch 2,500, 2 runs: median 618.4 users/s (best 628.1).
  Scope: SQL generation plus result transfer and fetchall; excludes HTML and
  migrations. A one-million-user run was not executed, so no such claim is made.

Please note
-----------
This submission was verified locally. The public deployment and demo video are
provided at the URLs above only if those links are real and reachable. The
generator stores no users; emails are unique within a batch but are not a global
registry, phone numbers may repeat, and coordinates are independent of the
address.

Thank you for reviewing the submission.

Best regards,
[Your full name]
[Phone number, optional]
[Email address]
```

## Before sending

- [ ] Replace every `[...]` placeholder.
- [ ] Confirm the GitHub repository is public or accessible to the reviewer.
- [ ] Confirm the deployed URL opens and `/health` returns `200`.
- [ ] Confirm the video link works in a private/incognito browser.
- [ ] Re-run the tests and update `53 passed` if the result changed.
- [ ] Re-check the benchmark numbers against `benchmark_results/*.json`.
- [ ] Remove this file's instructional text from the email.
- [ ] Do not attach `.env`, database dumps, logs containing credentials or local
      screenshots with secrets.

## Shorter variant

```text
Hello [Recipient name],

My Task 6 submission is ready.

Repository: https://github.com/BodzioES/Itransition-task6
Deployed app: [URL]
Documentation: https://github.com/BodzioES/Itransition-task6#readme
Demo video: [URL]
Benchmark: median 618.4 users/s for 100,000 users (best 628.1), measured locally

The app is a Flask/PostgreSQL synthetic-user generator. All user attributes are
generated by PL/pgSQL functions using SHA-256-derived deterministic randomness;
Python only validates input, calls the SQL API and renders results. It supports
en_US and de_DE, seed and batch navigation, and a reproducible identity for every
(locale, seed, batch_index, row_index).

Verified locally: 53 pytest tests passed, SQL deterministic and distribution
tests passed, Docker Compose healthy at /health, and benchmarks saved in the
repository. The public deployment and video are available at the links above
only if those links are real. No one-million-user benchmark was run.

Best regards,
[Your full name]
```

## If deployment is still unavailable

Do not send a fake URL. Use an honest sentence:

```text
The application is fully runnable with `docker compose up --build` and was
verified locally. A public deployment is not included because hosting credentials
were not available; deployment instructions and a Render Blueprint are included
in the repository.
```

Then remove the `Deployed app` line and the claim that a public deployment is
available.
