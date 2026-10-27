-- ============================================================================
-- Synthetic User Lab - public generation API
-- Migration: 005_user_generator.sql
--
-- generate_user() creates exactly one user for a (locale, seed, batch, row)
-- identity. generate_users() calls it for row indexes 0..batch_size-1 and
-- returns rows in explicit row order. No session state, table of generated
-- users, random() or setseed() is involved.
--
-- Identity convention (zero-based):
--   batch_index >= 0
--   row_index   in [0, batch_size-1]
-- Changing batch_size therefore adds or removes rows from a batch; it never
-- renumbers the identity of a row that remains present.
-- ============================================================================

CREATE OR REPLACE FUNCTION sul.generate_user(
    p_locale_code TEXT,
    p_seed        BIGINT,
    p_batch_index INTEGER,
    p_row_index   INTEGER
) RETURNS TABLE (
    locale_code          TEXT,
    seed                 BIGINT,
    batch_index          INTEGER,
    row_index            INTEGER,
    gender               CHAR(1),
    first_name           TEXT,
    middle_name          TEXT,
    last_name            TEXT,
    title                TEXT,
    full_name            TEXT,
    street_name          TEXT,
    house_number         INTEGER,
    house_number_suffix  TEXT,
    street_address       TEXT,
    city                 TEXT,
    region_name          TEXT,
    region_code          TEXT,
    postal_code          TEXT,
    country              TEXT,
    full_address         TEXT,
    latitude             DOUBLE PRECISION,
    longitude            DOUBLE PRECISION,
    height_cm            NUMERIC(5,1),
    weight_kg            NUMERIC(5,1),
    eye_color            TEXT,
    hair_color           TEXT,
    phone                TEXT,
    email                TEXT
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_locale            sul.locales%ROWTYPE;
    v_body              sul.body_statistics%ROWTYPE;

    v_gender            CHAR(1);
    v_first_name        TEXT;
    v_middle_name       TEXT;
    v_last_name         TEXT;
    v_title             TEXT;
    v_full_name         TEXT;

    v_street_name       TEXT;
    v_house_number      INTEGER;
    v_house_suffix      TEXT;
    v_street_address    TEXT;

    v_city_id           BIGINT;
    v_city              TEXT;
    v_region_name       TEXT;
    v_region_code       TEXT;
    v_postal_prefix     TEXT;
    v_postal_code       TEXT;
    v_postal_length     SMALLINT;
    v_i                 INTEGER;

    v_full_address      TEXT;

    v_z                 DOUBLE PRECISION;
    v_latitude          DOUBLE PRECISION;
    v_longitude         DOUBLE PRECISION;

    v_height            DOUBLE PRECISION;
    v_weight            DOUBLE PRECISION;
    v_eye_color         TEXT;
    v_hair_color        TEXT;

    v_phone_format      TEXT;
    v_phone             TEXT;
    v_email_pattern     TEXT;
    v_email_domain      TEXT;
    v_email             TEXT;
BEGIN
    -- ------------------------------------------------------------------
    -- Input validation
    -- ------------------------------------------------------------------
    IF p_locale_code IS NULL OR btrim(p_locale_code) = '' THEN
        RAISE EXCEPTION 'generate_user: locale is required' USING ERRCODE = '22023';
    END IF;
    IF p_seed IS NULL OR p_seed < 0 THEN
        RAISE EXCEPTION 'generate_user: seed must be a non-negative BIGINT'
            USING ERRCODE = '22023';
    END IF;
    IF p_batch_index IS NULL OR p_batch_index < 0 OR p_batch_index > 1000000 THEN
        RAISE EXCEPTION 'generate_user: batch_index must be between 0 and 1000000'
            USING ERRCODE = '22023';
    END IF;
    IF p_row_index IS NULL OR p_row_index < 0 OR p_row_index > 9999 THEN
        RAISE EXCEPTION 'generate_user: row_index must be between 0 and 9999'
            USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_locale
    FROM sul.locales
    WHERE sul.locales.locale_code = p_locale_code;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'generate_user: unsupported locale "%"', p_locale_code
            USING ERRCODE = '22023';
    END IF;

    -- ------------------------------------------------------------------
    -- Gender and names
    -- ------------------------------------------------------------------
    v_gender := CASE
        WHEN sul.deterministic_uniform(p_locale_code, p_seed, p_batch_index, p_row_index, 'gender') < 0.5
            THEN 'M'
        ELSE 'F'
    END;

    SELECT l.lookup_value INTO v_first_name
    FROM sul.select_lookup_value(
        p_locale_code, 'first_name',
        sul.deterministic_uniform(p_locale_code, p_seed, p_batch_index, p_row_index, 'first_name'),
        v_gender
    ) AS l;

    v_middle_name := NULL;
    IF sul.deterministic_uniform(p_locale_code, p_seed, p_batch_index, p_row_index, 'middle_name_presence')
       < v_locale.middle_name_probability THEN
        SELECT l.lookup_value INTO v_middle_name
        FROM sul.select_lookup_value(
            p_locale_code, 'middle_name',
            sul.deterministic_uniform(p_locale_code, p_seed, p_batch_index, p_row_index, 'middle_name')
        ) AS l;
    END IF;

    SELECT l.lookup_value INTO v_last_name
    FROM sul.select_lookup_value(
        p_locale_code, 'last_name',
        sul.deterministic_uniform(p_locale_code, p_seed, p_batch_index, p_row_index, 'last_name')
    ) AS l;

    v_title := NULL;
    IF sul.deterministic_uniform(p_locale_code, p_seed, p_batch_index, p_row_index, 'title_presence')
       < v_locale.title_probability THEN
        SELECT l.lookup_value INTO v_title
        FROM sul.select_lookup_value(
            p_locale_code, 'title',
            sul.deterministic_uniform(p_locale_code, p_seed, p_batch_index, p_row_index, 'title'),
            v_gender
        ) AS l;
    END IF;

    v_full_name := sul.format_full_name(
        p_locale_code, v_first_name, v_middle_name, v_last_name
    );

    -- ------------------------------------------------------------------
    -- Address, city and postal code
    -- ------------------------------------------------------------------
    SELECT l.lookup_value INTO v_street_name
    FROM sul.select_lookup_value(
        p_locale_code, 'street',
        sul.deterministic_uniform(p_locale_code, p_seed, p_batch_index, p_row_index, 'street')
    ) AS l;

    v_house_number := sul.deterministic_integer(
        p_locale_code, p_seed, p_batch_index, p_row_index, 'house_number',
        v_locale.house_number_min, v_locale.house_number_max
    );

    v_house_suffix := NULL;
    IF sul.deterministic_uniform(p_locale_code, p_seed, p_batch_index, p_row_index, 'house_suffix_presence')
       < v_locale.house_number_suffix_probability THEN
        v_house_suffix := chr(97 + sul.deterministic_integer(
            p_locale_code, p_seed, p_batch_index, p_row_index, 'house_suffix', 0, 3
        ));
    END IF;

    v_street_address := sul.format_street_address(
        p_locale_code, v_street_name, v_house_number, v_house_suffix
    );

    SELECT l.lookup_id INTO v_city_id
    FROM sul.select_lookup_value(
        p_locale_code, 'city',
        sul.deterministic_uniform(p_locale_code, p_seed, p_batch_index, p_row_index, 'city')
    ) AS l;

    SELECT c.name, r.name, r.code, c.postal_prefix
      INTO v_city, v_region_name, v_region_code, v_postal_prefix
    FROM sul.cities c
    JOIN sul.regions r ON r.id = c.region_id
    WHERE c.id = v_city_id;

    v_postal_length := v_locale.postal_code_length;
    v_postal_code := left(v_postal_prefix, v_postal_length);
    IF length(v_postal_code) < v_postal_length THEN
        FOR v_i IN (length(v_postal_code) + 1) .. v_postal_length LOOP
            v_postal_code := v_postal_code || sul.deterministic_integer(
                p_locale_code, p_seed, p_batch_index, p_row_index,
                'postal_code:' || v_i::TEXT, 0, 9
            )::TEXT;
        END LOOP;
    END IF;

    IF v_postal_code !~ v_locale.postal_code_regex THEN
        RAISE EXCEPTION 'generate_user: generated postal code "%" does not match locale pattern',
            v_postal_code USING ERRCODE = 'P0002';
    END IF;

    v_full_address := sul.format_address(
        p_locale_code, v_street_address, v_city,
        v_region_name, v_region_code, v_postal_code, v_locale.country_name
    );

    -- ------------------------------------------------------------------
    -- Spherical coordinates.
    -- z is uniform in (-1,1); latitude = degrees(asin(z)). This is a
    -- uniform distribution over the sphere's surface, unlike a uniform
    -- latitude draw which over-represents the poles.
    -- ------------------------------------------------------------------
    v_z := 2.0 * sul.deterministic_uniform(
        p_locale_code, p_seed, p_batch_index, p_row_index, 'latitude'
    ) - 1.0;
    v_latitude := degrees(asin(v_z));
    v_longitude := -180.0 + 360.0 * sul.deterministic_uniform(
        p_locale_code, p_seed, p_batch_index, p_row_index, 'longitude'
    );

    -- ------------------------------------------------------------------
    -- Body measurements from locale/gender-specific normals.
    -- Values outside the configured plausible bounds are clamped. This
    -- necessarily creates small point masses at the bounds.
    -- ------------------------------------------------------------------
    SELECT * INTO v_body
    FROM sul.body_statistics b
    WHERE b.locale_code = p_locale_code AND b.gender = v_gender;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'generate_user: missing body statistics for locale % and gender %',
            p_locale_code, v_gender USING ERRCODE = 'P0002';
    END IF;

    v_height := sul.deterministic_normal(
        p_locale_code, p_seed, p_batch_index, p_row_index, 'height',
        v_body.height_mean_cm::DOUBLE PRECISION, v_body.height_sd_cm::DOUBLE PRECISION
    );
    v_height := greatest(
        v_body.height_min_cm::DOUBLE PRECISION,
        least(v_body.height_max_cm::DOUBLE PRECISION, v_height)
    );

    v_weight := sul.deterministic_normal(
        p_locale_code, p_seed, p_batch_index, p_row_index, 'weight',
        v_body.weight_mean_kg::DOUBLE PRECISION, v_body.weight_sd_kg::DOUBLE PRECISION
    );
    v_weight := greatest(
        v_body.weight_min_kg::DOUBLE PRECISION,
        least(v_body.weight_max_kg::DOUBLE PRECISION, v_weight)
    );

    SELECT l.lookup_value INTO v_eye_color
    FROM sul.select_lookup_value(
        p_locale_code, 'eye_color',
        sul.deterministic_uniform(p_locale_code, p_seed, p_batch_index, p_row_index, 'eye_color')
    ) AS l;

    SELECT l.lookup_value INTO v_hair_color
    FROM sul.select_lookup_value(
        p_locale_code, 'hair_color',
        sul.deterministic_uniform(p_locale_code, p_seed, p_batch_index, p_row_index, 'hair_color')
    ) AS l;

    -- ------------------------------------------------------------------
    -- Phone and email. The row suffix guarantees email uniqueness inside
    -- a batch while remaining reproducible outside batch context.
    -- ------------------------------------------------------------------
    SELECT l.lookup_value INTO v_phone_format
    FROM sul.select_lookup_value(
        p_locale_code, 'phone_format',
        sul.deterministic_uniform(p_locale_code, p_seed, p_batch_index, p_row_index, 'phone_format')
    ) AS l;

    v_phone := sul.format_phone(
        p_locale_code, v_phone_format, p_seed, p_batch_index, p_row_index
    );

    SELECT l.lookup_value INTO v_email_pattern
    FROM sul.select_lookup_value(
        p_locale_code, 'email_pattern',
        sul.deterministic_uniform(p_locale_code, p_seed, p_batch_index, p_row_index, 'email_pattern')
    ) AS l;

    SELECT l.lookup_value INTO v_email_domain
    FROM sul.select_lookup_value(
        p_locale_code, 'email_domain',
        sul.deterministic_uniform(p_locale_code, p_seed, p_batch_index, p_row_index, 'email_domain')
    ) AS l;

    v_email := sul.format_email(
        v_first_name,
        v_last_name,
        v_email_pattern,
        v_email_domain,
        lpad((p_row_index + 1)::TEXT, 3, '0')
    );

    RETURN QUERY SELECT
        p_locale_code,
        p_seed,
        p_batch_index,
        p_row_index,
        v_gender,
        v_first_name,
        v_middle_name,
        v_last_name,
        v_title,
        v_full_name,
        v_street_name,
        v_house_number,
        v_house_suffix,
        v_street_address,
        v_city,
        v_region_name,
        v_region_code,
        v_postal_code,
        v_locale.country_name,
        v_full_address,
        v_latitude,
        v_longitude,
        round(v_height::NUMERIC, 1)::NUMERIC(5,1),
        round(v_weight::NUMERIC, 1)::NUMERIC(5,1),
        v_eye_color,
        v_hair_color,
        v_phone,
        v_email;
END;
$$;

COMMENT ON FUNCTION sul.generate_user(TEXT, BIGINT, INTEGER, INTEGER) IS
    'Generates one complete deterministic synthetic user for an explicit locale, seed, batch index and zero-based row index.';

CREATE OR REPLACE FUNCTION sul.generate_users(
    p_locale_code TEXT,
    p_seed        BIGINT,
    p_batch_index INTEGER,
    p_batch_size  INTEGER
) RETURNS TABLE (
    locale_code          TEXT,
    seed                 BIGINT,
    batch_index          INTEGER,
    row_index            INTEGER,
    gender               CHAR(1),
    first_name           TEXT,
    middle_name          TEXT,
    last_name            TEXT,
    title                TEXT,
    full_name            TEXT,
    street_name          TEXT,
    house_number         INTEGER,
    house_number_suffix  TEXT,
    street_address       TEXT,
    city                 TEXT,
    region_name          TEXT,
    region_code          TEXT,
    postal_code          TEXT,
    country              TEXT,
    full_address         TEXT,
    latitude             DOUBLE PRECISION,
    longitude            DOUBLE PRECISION,
    height_cm            NUMERIC(5,1),
    weight_kg            NUMERIC(5,1),
    eye_color            TEXT,
    hair_color           TEXT,
    phone                TEXT,
    email                TEXT
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    IF p_locale_code IS NULL OR btrim(p_locale_code) = '' THEN
        RAISE EXCEPTION 'generate_users: locale is required' USING ERRCODE = '22023';
    END IF;
    IF p_seed IS NULL OR p_seed < 0 THEN
        RAISE EXCEPTION 'generate_users: seed must be a non-negative BIGINT'
            USING ERRCODE = '22023';
    END IF;
    IF p_batch_index IS NULL OR p_batch_index < 0 OR p_batch_index > 1000000 THEN
        RAISE EXCEPTION 'generate_users: batch_index must be between 0 and 1000000'
            USING ERRCODE = '22023';
    END IF;
    IF p_batch_size IS NULL OR p_batch_size < 1 OR p_batch_size > 10000 THEN
        RAISE EXCEPTION 'generate_users: batch_size must be between 1 and 10000'
            USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM sul.locales l WHERE l.locale_code = p_locale_code
    ) THEN
        RAISE EXCEPTION 'generate_users: unsupported locale "%"', p_locale_code
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    SELECT u.*
    FROM generate_series(0, p_batch_size - 1) AS s(row_number)
    CROSS JOIN LATERAL sul.generate_user(
        p_locale_code, p_seed, p_batch_index, s.row_number
    ) AS u
    ORDER BY u.row_index;
END;
$$;

COMMENT ON FUNCTION sul.generate_users(TEXT, BIGINT, INTEGER, INTEGER) IS
    'Public batch API. Returns batch_size deterministic users in explicit row_index order. batch_size is limited to 1..10000.';
