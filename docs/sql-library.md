# SQL Library Reference

All generator objects live in the `sul` schema of a PostgreSQL 15+ database.
The public entry points are `sul.generate_user` and `sul.generate_users`; the
lower-level helpers are documented because they can be tested and reused
independently.

The library requires the `pgcrypto` extension for SHA-256. Migration
`001_schema.sql` runs `CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public`
and fails loudly when the extension cannot be installed. Digest calls are
schema-qualified as `public.digest(...)`.

## Quick reference

| Function | Volatility | Returns |
| --- | --- | --- |
| `sul.generate_users(TEXT, BIGINT, INTEGER, INTEGER)` | `STABLE` | 28-column table, `batch_size` rows |
| `sul.generate_user(TEXT, BIGINT, INTEGER, INTEGER)` | `STABLE` | 28-column table, one row |
| `sul.deterministic_uniform(TEXT, BIGINT, INTEGER, INTEGER, TEXT)` | `IMMUTABLE` | `DOUBLE PRECISION` in `(0,1)` |
| `sul.deterministic_integer(TEXT, BIGINT, INTEGER, INTEGER, TEXT, INTEGER, INTEGER)` | `IMMUTABLE` | `INTEGER` |
| `sul.deterministic_normal(TEXT, BIGINT, INTEGER, INTEGER, TEXT, DOUBLE PRECISION, DOUBLE PRECISION)` | `IMMUTABLE` | `DOUBLE PRECISION` |
| `sul.select_lookup_value(TEXT, TEXT, DOUBLE PRECISION, CHAR)` | `STABLE` | `(lookup_id BIGINT, lookup_value TEXT)` |
| `sul.format_full_name(TEXT, TEXT, TEXT, TEXT)` | `STABLE` | `TEXT` |
| `sul.format_street_address(TEXT, TEXT, INTEGER, TEXT)` | `STABLE` | `TEXT` |
| `sul.format_address(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT)` | `STABLE` | `TEXT` |
| `sul.format_phone(TEXT, TEXT, BIGINT, INTEGER, INTEGER)` | `IMMUTABLE` | `TEXT` |
| `sul.slugify(TEXT)` | `IMMUTABLE` | `TEXT` |
| `sul.format_email(TEXT, TEXT, TEXT, TEXT, TEXT)` | `IMMUTABLE` | `TEXT` |

The view `sul.lookup_coverage` reports seeded row counts per locale. The table
`public.schema_migrations` is migration infrastructure, not part of the generator
API.

## Entry points

### `sul.generate_users`

```sql
sul.generate_users(
    p_locale_code TEXT,
    p_seed        BIGINT,
    p_batch_index INTEGER,
    p_batch_size  INTEGER
) RETURNS TABLE (...)
LANGUAGE plpgsql STABLE
```

Generates `p_batch_size` users for row indexes `0..p_batch_size-1` and returns
them ordered by `row_index`. It is the API used by the Flask repository and the
benchmark.

| Argument | Rule |
| --- | --- |
| `p_locale_code` | Required, non-empty, must exist in `sul.locales` |
| `p_seed` | Required, non-negative `BIGINT` (`0..9,223,372,036,854,775,807`) |
| `p_batch_index` | `0..1,000,000` |
| `p_batch_size` | `1..10,000` |

Example:

```sql
SELECT *
FROM sul.generate_users(
    p_locale_code => 'en_US',
    p_seed        => 12345,
    p_batch_index => 0,
    p_batch_size  => 10
)
ORDER BY row_index;
```

Errors raised with SQLSTATE `22023` (`invalid_parameter_value`): missing locale,
negative seed, out-of-range batch index, out-of-range batch size, unsupported
locale. A missing body-statistics row raises `P0002` (`no_data_found`).

### `sul.generate_user`

```sql
sul.generate_user(
    p_locale_code TEXT,
    p_seed        BIGINT,
    p_batch_index INTEGER,
    p_row_index   INTEGER
) RETURNS TABLE (...)
LANGUAGE plpgsql STABLE
```

Generates exactly one record for the explicit identity. It can reproduce a single
row without generating earlier batches and is used by `generate_users` through a
`LATERAL` join.

| Argument | Rule |
| --- | --- |
| `p_locale_code` | Required, non-empty, must exist in `sul.locales` |
| `p_seed` | Required, non-negative `BIGINT` |
| `p_batch_index` | `0..1,000,000` |
| `p_row_index` | `0..9,999` |

Example:

```sql
SELECT *
FROM sul.generate_user('de_DE', 9191, 20, 4);
```

The returned row index is not derived from `p_batch_size`; changing the batch size
does not renumber an existing identity.

### Returned columns

Both entry points return the same 28 columns in this order:

| Column | Type | Meaning |
| --- | --- | --- |
| `locale_code` | `TEXT` | Requested locale |
| `seed` | `BIGINT` | Requested seed |
| `batch_index` | `INTEGER` | Zero-based batch index |
| `row_index` | `INTEGER` | Zero-based row index |
| `gender` | `CHAR(1)` | `F` or `M` |
| `first_name` | `TEXT` | Locale-aware first name |
| `middle_name` | `TEXT` | May be `NULL` |
| `last_name` | `TEXT` | Locale-aware last name |
| `title` | `TEXT` | May be `NULL` |
| `full_name` | `TEXT` | Formatted from first/middle/last |
| `street_name` | `TEXT` | Lookup street name |
| `house_number` | `INTEGER` | Locale range |
| `house_number_suffix` | `TEXT` | Letter for `de_DE`, usually `NULL` |
| `street_address` | `TEXT` | Country-specific street line |
| `city` | `TEXT` | Lookup city |
| `region_name` | `TEXT` | State/Bundesland |
| `region_code` | `TEXT` | Code such as `NY` or `BE` |
| `postal_code` | `TEXT` | Matches locale regex |
| `country` | `TEXT` | Locale country name |
| `full_address` | `TEXT` | Country-specific full address |
| `latitude` | `DOUBLE PRECISION` | Uniform sphere point |
| `longitude` | `DOUBLE PRECISION` | Uniform sphere point |
| `height_cm` | `NUMERIC(5,1)` | Clamped normal |
| `weight_kg` | `NUMERIC(5,1)` | Clamped normal |
| `eye_color` | `TEXT` | Localised label |
| `hair_color` | `TEXT` | Localised label |
| `phone` | `TEXT` | Fictional range, format per locale |
| `email` | `TEXT` | RFC 2606 example domain |

Coordinates are independent synthetic points. They are not geocoded from the
generated address.

## Deterministic randomness

### `sul.deterministic_uniform`

```sql
sul.deterministic_uniform(
    p_locale_code TEXT,
    p_seed        BIGINT,
    p_batch_index INTEGER,
    p_row_index   INTEGER,
    p_salt        TEXT
) RETURNS DOUBLE PRECISION
LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE
```

Algorithm:

1. Build `concat_ws('|', locale, seed, batch_index, row_index, salt)`.
2. Compute `public.digest(..., 'sha256')`.
3. Take the first 7 bytes (56 bits) as an unsigned integer `v`.
4. Return `(v + 0.5) / 2^56` as a double.

The result lies strictly inside `(0,1)`, so `ln(u)` and spherical coordinates are
safe. Using 56 bits avoids the sign problem of casting a full 64-bit digest.
Because a double has a 53-bit mantissa, the least significant bits can round; the
value remains stable on a given PostgreSQL build and independent of session
state, row order and query plans. `random()` and `setseed()` are never used.

`STRICT`: a `NULL` argument returns `NULL` without executing. An empty salt raises
SQLSTATE `22023` with message
`deterministic_uniform: p_salt must not be empty`.

Example:

```sql
SELECT sul.deterministic_uniform('en_US', 12345, 0, 0, 'gender');
```

### `sul.deterministic_integer`

```sql
sul.deterministic_integer(
    p_locale_code TEXT,
    p_seed        BIGINT,
    p_batch_index INTEGER,
    p_row_index   INTEGER,
    p_salt        TEXT,
    p_min_value   INTEGER,
    p_max_value   INTEGER
) RETURNS INTEGER
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
```

Maps a deterministic uniform value to the inclusive range `[p_min_value,
p_max_value]` using `floor(u * span)`. The span `max - min + 1` must not exceed
`2^32`. Errors with SQLSTATE `22023` for `NULL` bounds, `max < min` or an
oversized range.

Example:

```sql
SELECT sul.deterministic_integer('en_US', 12345, 0, 0, 'house_number', 1, 9999);
```

### `sul.deterministic_normal`

```sql
sul.deterministic_normal(
    p_locale_code TEXT,
    p_seed        BIGINT,
    p_batch_index INTEGER,
    p_row_index   INTEGER,
    p_salt        TEXT,
    p_mean        DOUBLE PRECISION,
    p_stddev      DOUBLE PRECISION
) RETURNS DOUBLE PRECISION
LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE
```

Uses Box–Muller with two independent derived uniforms:

```text
u1 = deterministic_uniform(..., salt || ':u1')
u2 = deterministic_uniform(..., salt || ':u2')
z  = sqrt(-2 ln u1) * cos(2 pi u2)
result = mean + stddev * z
```

`p_stddev` must be positive; otherwise SQLSTATE `22023` is raised. The function
does not clamp. `generate_user` clamps height and weight to the configured
plausible bounds, which intentionally creates small point masses at those bounds.

## Lookup selection

### `sul.select_lookup_value`

```sql
sul.select_lookup_value(
    p_locale_code TEXT,
    p_lookup_type TEXT,
    p_u           DOUBLE PRECISION,
    p_gender      CHAR(1) DEFAULT NULL
) RETURNS TABLE (lookup_id BIGINT, lookup_value TEXT)
LANGUAGE plpgsql STABLE PARALLEL SAFE
```

Selects one weighted, locale-compatible row. Candidate rows are ordered by `id`;
the cumulative weight is computed in SQL; the first row whose cumulative weight
reaches `p_u * total_weight` is returned. Because `p_u` is in `(0,1)` and weights
are positive, exactly one row is selected. `lookup_id` lets callers retrieve
related columns such as a city's region and postal prefix.

| `p_lookup_type` | Source | Gender required |
| --- | --- | --- |
| `first_name` | `sul.first_names` | Yes; filters `F`/`M` |
| `middle_name` | `sul.middle_names` | No |
| `last_name` | `sul.last_names` | No |
| `title` | `sul.titles` | Yes; includes neutral titles |
| `street` | `sul.street_names` | No |
| `city` | `sul.cities` | No |
| `email_domain` | `sul.email_domains` | No; includes shared rows |
| `email_pattern` | `sul.email_patterns` | No |
| `phone_format` | `sul.phone_formats` | No |
| `eye_color` | `sul.eye_colors` | No; includes shared rows |
| `hair_color` | `sul.hair_colors` | No; includes shared rows |

Validation:

- `p_u` must be in the open interval `(0,1)`.
- `p_locale_code` must be non-empty.
- `p_gender`, when supplied, must be `F` or `M`.
- `first_name` and `title` require `p_gender`.
- Unsupported types raise `22023`.
- No matching rows raise `P0002` with a message naming the type and locale.

Examples:

```sql
SELECT * FROM sul.select_lookup_value('en_US', 'first_name', 0.42, 'F');
SELECT * FROM sul.select_lookup_value('de_DE', 'city', 0.87);
```

## Formatting helpers

### `sul.format_full_name`

```sql
sul.format_full_name(
    p_locale_code TEXT,
    p_first_name  TEXT,
    p_middle_name TEXT,
    p_last_name   TEXT
) RETURNS TEXT
LANGUAGE plpgsql STABLE
```

Reads `sul.locales.full_name_format`, replaces `{first}`, `{middle}` and `{last}`,
removes an empty middle name and collapses whitespace. Both locales currently use
`{first} {middle} {last}`. First and last names are required; an unknown locale or
missing required name raises `22023`.

### `sul.format_street_address`

```sql
sul.format_street_address(
    p_locale_code  TEXT,
    p_street_name  TEXT,
    p_house_number INTEGER,
    p_house_suffix TEXT DEFAULT NULL
) RETURNS TEXT
LANGUAGE plpgsql STABLE
```

Uses `sul.locales.street_address_format`:

- `en_US`: `{house_number} {street_name}` → `123 Main Street`
- `de_DE`: `{street_name} {house_number}{house_suffix}` → `Hauptstraße 42a`

Missing street name or number and unknown locales raise `22023`.

### `sul.format_address`

```sql
sul.format_address(
    p_locale_code    TEXT,
    p_street_address TEXT,
    p_city           TEXT,
    p_region_name    TEXT,
    p_region_code    TEXT,
    p_postal_code    TEXT,
    p_country        TEXT
) RETURNS TEXT
LANGUAGE plpgsql STABLE
```

Uses `sul.locales.address_format`, replaces the six placeholders, normalises
spaces and comma spacing. Required values: street address, city, postal code and
country. Region values may be `NULL` and are replaced by an empty string.

### `sul.format_phone`

```sql
sul.format_phone(
    p_locale_code    TEXT,
    p_format_pattern TEXT,
    p_seed           BIGINT,
    p_batch_index    INTEGER,
    p_row_index      INTEGER
) RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE
```

Replaces every `#` in the pattern with an independently salted digit
(`phone_digit:1`, `phone_digit:2`, ...). A pattern without `#` raises `22023`.
Formats are fictional:

| Locale | Formats |
| --- | --- |
| `en_US` | `(###) 555-01##`, `###-555-01##`, `+1 ###-555-01##` |
| `de_DE` | `030 23125###`, `(030) 23125###`, `+49 30 23125###` |

Phone uniqueness is not guaranteed.

### `sul.slugify`

```sql
sul.slugify(p_input TEXT) RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE STRICT
```

Lowercases, transliterates common European characters (`ä→a`, `ö→o`, `ü→u`,
`ß→s`, accented vowels, `ç`, `ñ`, `ø`, `æ`, `œ`), removes everything outside
`[a-z0-9]`, and falls back to `user` when nothing remains. It is intended for the
email local part.

### `sul.format_email`

```sql
sul.format_email(
    p_first_name TEXT,
    p_last_name  TEXT,
    p_pattern    TEXT,
    p_domain     TEXT,
    p_suffix     TEXT
) RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE
```

1. Slugifies first and last names.
2. Replaces `{first}`, `{last}` and `{fi}` in the pattern.
3. Removes characters outside `[a-z0-9._-]`, trims separators and truncates the
   local part if a suffix is present.
4. Appends `.` plus the sanitised suffix.
5. Enforces a domain matching `^example\.(com|net|org)$`.

The domain check is mandatory; a non-example domain raises `22023`. The generator
passes the zero-padded row number as the suffix (`001`, `002`, ...), which
guarantees uniqueness **within a batch**. It is not a global email registry:
different batches can theoretically produce the same address.

## Generation pipeline

For each row, `generate_user` performs these deterministic steps:

1. Validate identity and load the locale configuration.
2. Derive gender (`< 0.5` → `M`, otherwise `F`).
3. Select first name by gender, optional middle name, last name and optional
   gender-compatible title.
4. Format the full name.
5. Select street, house number and optional house suffix; format the street line.
6. Select city, join its region and postal prefix, fill postal digits and verify
   the locale regex.
7. Format the full address.
8. Draw `z = 2u - 1`, set `latitude = degrees(asin(z))` and
   `longitude = -180 + 360u`.
9. Load gender-specific body statistics; draw and clamp height and weight.
10. Select eye and hair colour.
11. Select phone format, fill digits and format the phone.
12. Select email pattern and shared example domain; append the row suffix.
13. Return one row with the identity, all attributes and explicit `row_index`.

Field salts used by the generator:

```text
gender, first_name, middle_name_presence, middle_name, last_name,
title_presence, title, street, house_number, house_suffix_presence,
house_suffix, city, postal_code:<position>, latitude, longitude,
height (+ :u1/:u2), weight (+ :u1/:u2), eye_color, hair_color,
phone_format, phone_digit:<position>, email_pattern, email_domain
```

Changing one salt's output (for example by editing a lookup table) does not shift
the other fields for the same identity.

## Capacity and combinations

A seed supports:

```text
(batch indexes 0..1,000,000) × (row indexes 0..9,999)
= 1,000,001 × 10,000
= 10,000,010,000 identities per locale
```

Seeds add another factor of `2^63`. The generator is stateless; no table stores
generated users.

Current lookup counts from `sul.lookup_coverage`:

| Lookup | `en_US` | `de_DE` |
| --- | ---: | ---: |
| First names | 120 (60 F / 60 M) | 136 (74 F / 62 M) |
| Middle names | 50 | 50 |
| Last names | 102 | 100 |
| Titles | 6 (3 neutral, 2 F, 1 M) | 5 (3 neutral, 1 F, 1 M) |
| Street names | 126 | 114 |
| Cities | 22 | 20 |
| Regions | 16 | 9 |
| Email patterns | 5 | 5 |
| Email domains (shared) | 3 | 3 |
| Phone formats | 3 | 3 |
| Eye colours | 5 | 5 |
| Hair colours | 6 | 6 |

Conservative categorical combination counts, excluding continuous coordinates,
height and weight and excluding the row suffix:

```text
en_US:
2 gender
× 60 first names per gender
× 51 middle-name states (absent + 50)
× 102 last names
× 5.5 title states on average (6 F, 5 M)
× 126 streets
× 9,999 house numbers
× 22 cities
× 100 postal digit combinations per city prefix
× 5 eye colours
× 6 hair colours
× 300,000 phone values (3 formats × 10^5 digits)
× 15 email patterns/domains
× 10,000 row suffixes
≈ 1.28 × 10^28

de_DE:
2 × 68 × 51 × 100 × 5.0 × 114 × 999 × 20 × 100 × 5 × 6
  × 3,000 × 15 × 10,000
≈ 1.07 × 10^25
```

These are reachable combinations, not a promise that a small sample contains every
combination. Even the smallest estimate is many orders of magnitude larger than
1,000,000 generated records, so lookup tables are not sized per generated user.
The estimates ignore house-suffix combinations for `de_DE`, which only increases
the real count; they also ignore the continuous fields entirely.

## Lookup schema

All lookup tables are shared and keyed by `locale_code`; there are no per-locale
tables and no large `CASE` branches for individual records.

| Table | Purpose |
| --- | --- |
| `sul.locales` | Country, format patterns, optional-field probabilities, postal rules |
| `sul.regions` | State/province/Bundesland names and codes |
| `sul.cities` | City, region reference, postal prefix, weight |
| `sul.first_names` | Name, gender, weight |
| `sul.middle_names` | Name, weight |
| `sul.last_names` | Name, weight |
| `sul.titles` | Title, optional gender, weight |
| `sul.street_names` | Street name, weight |
| `sul.email_domains` | Shared RFC 2606 example domains, weight |
| `sul.email_patterns` | Local-part templates, weight |
| `sul.phone_formats` | Display patterns with `#` placeholders, weight |
| `sul.eye_colors` | Localised labels, weight |
| `sul.hair_colors` | Localised labels, weight |
| `sul.body_statistics` | Mean/SD/min/max height and weight by locale and gender |

Maintaining data:

```sql
-- Add a first name.
INSERT INTO sul.first_names (locale_code, name, gender, weight)
VALUES ('en_US', 'Avery', 'F', 25);

-- Add a city and pick an existing region.
INSERT INTO sul.cities (locale_code, region_id, name, postal_prefix, weight)
SELECT 'en_US', r.id, 'Portland', '972', 30
FROM sul.regions r
WHERE r.locale_code = 'en_US' AND r.code = 'OR';

-- Verify coverage.
SELECT * FROM sul.lookup_coverage;
```

Weights must be positive. Editing an already-applied migration is prohibited; add
a new numbered migration. Lookup edits change future output for affected fields
but do not change the deterministic identity or unrelated fields.

## Errors and validation summary

| Condition | SQLSTATE | Raised by |
| --- | --- | --- |
| Empty salt | `22023` | `deterministic_uniform` |
| `NULL` or inverted integer bounds, oversized span | `22023` | `deterministic_integer` |
| Non-positive standard deviation | `22023` | `deterministic_normal` |
| `p_u` outside `(0,1)`, missing locale/gender, bad type | `22023` | `select_lookup_value` |
| No lookup rows | `P0002` | `select_lookup_value` |
| Unknown locale or missing required format input | `22023` | formatting helpers |
| Invalid phone pattern | `22023` | `format_phone` |
| Missing name/pattern/domain or non-example domain | `22023` | `format_email` |
| Invalid seed, batch, row, size or locale | `22023` | `generate_user(s)` |
| Missing body statistics | `P0002` | `generate_user` |
| Generated postal code does not match locale regex | `P0002` | `generate_user` |

The Flask layer catches database errors, logs them server-side and returns a
generic `503` response. It never displays the SQL error text to the user.

## Migration files

| File | Contents |
| --- | --- |
| `001_schema.sql` | `sul` schema, `pgcrypto`, tables, constraints, `lookup_coverage` |
| `002_seed_lookup_data.sql` | Locales, regions, cities, names, formats, colours, body statistics |
| `003_random_functions.sql` | Uniform, integer and Box–Muller normal helpers |
| `004_formatting_functions.sql` | Weighted lookup selection and formatting helpers |
| `005_user_generator.sql` | `generate_user`, `generate_users` |
| `006_indexes_and_constraints.sql` | Covering indexes for weighted lookups |

Migrations are applied transactionally by `scripts/init_db.py`, recorded with
SHA-256 checksums in `public.schema_migrations`, and protected by a PostgreSQL
advisory lock. Use `--status` or `--check` to inspect them without changing data.
