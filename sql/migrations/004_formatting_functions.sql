-- ============================================================================
-- Synthetic User Lab - lookup selection and formatting
-- Migration: 004_formatting_functions.sql
--
-- Lookup selection is weighted with a cumulative-weight scan ordered by id.
-- The input u determines a target in [0,total_weight); the first row whose
-- cumulative weight reaches that target is selected. This is deterministic,
-- locale-aware and independent of physical table order.
-- ============================================================================

CREATE OR REPLACE FUNCTION sul.select_lookup_value(
    p_locale_code TEXT,
    p_lookup_type TEXT,
    p_u           DOUBLE PRECISION,
    p_gender      CHAR(1) DEFAULT NULL
) RETURNS TABLE (lookup_id BIGINT, lookup_value TEXT)
LANGUAGE plpgsql
STABLE
PARALLEL SAFE
AS $$
BEGIN
    IF p_u IS NULL OR p_u <= 0 OR p_u >= 1 THEN
        RAISE EXCEPTION 'select_lookup_value: p_u must be in the open interval (0,1)'
            USING ERRCODE = '22023';
    END IF;
    IF p_locale_code IS NULL OR p_locale_code = '' THEN
        RAISE EXCEPTION 'select_lookup_value: locale is required'
            USING ERRCODE = '22023';
    END IF;
    IF p_gender IS NOT NULL AND p_gender NOT IN ('F', 'M') THEN
        RAISE EXCEPTION 'select_lookup_value: gender must be F or M'
            USING ERRCODE = '22023';
    END IF;

    IF p_lookup_type = 'first_name' THEN
        IF p_gender IS NULL THEN
            RAISE EXCEPTION 'select_lookup_value: first_name requires p_gender'
                USING ERRCODE = '22023';
        END IF;
        RETURN QUERY
        SELECT r.id::BIGINT, r.value
        FROM (
            SELECT x.id, x.name AS value,
                   sum(x.weight) OVER (ORDER BY x.id) AS cumulative,
                   sum(x.weight) OVER () AS total
            FROM sul.first_names x
            WHERE x.locale_code = p_locale_code AND x.gender = p_gender
        ) r
        WHERE r.cumulative >= p_u * r.total
        ORDER BY r.id
        LIMIT 1;

    ELSIF p_lookup_type = 'middle_name' THEN
        RETURN QUERY
        SELECT r.id::BIGINT, r.value FROM (
            SELECT x.id, x.name AS value,
                   sum(x.weight) OVER (ORDER BY x.id) AS cumulative,
                   sum(x.weight) OVER () AS total
            FROM sul.middle_names x WHERE x.locale_code = p_locale_code
        ) r
        WHERE r.cumulative >= p_u * r.total ORDER BY r.id LIMIT 1;

    ELSIF p_lookup_type = 'last_name' THEN
        RETURN QUERY
        SELECT r.id::BIGINT, r.value FROM (
            SELECT x.id, x.name AS value,
                   sum(x.weight) OVER (ORDER BY x.id) AS cumulative,
                   sum(x.weight) OVER () AS total
            FROM sul.last_names x WHERE x.locale_code = p_locale_code
        ) r
        WHERE r.cumulative >= p_u * r.total ORDER BY r.id LIMIT 1;

    ELSIF p_lookup_type = 'title' THEN
        IF p_gender IS NULL THEN
            RAISE EXCEPTION 'select_lookup_value: title requires p_gender'
                USING ERRCODE = '22023';
        END IF;
        RETURN QUERY
        SELECT r.id::BIGINT, r.value FROM (
            SELECT x.id, x.title AS value,
                   sum(x.weight) OVER (ORDER BY x.id) AS cumulative,
                   sum(x.weight) OVER () AS total
            FROM sul.titles x
            WHERE x.locale_code = p_locale_code
              AND (x.gender IS NULL OR x.gender = p_gender)
        ) r
        WHERE r.cumulative >= p_u * r.total ORDER BY r.id LIMIT 1;

    ELSIF p_lookup_type = 'street' THEN
        RETURN QUERY
        SELECT r.id::BIGINT, r.value FROM (
            SELECT x.id, x.name AS value,
                   sum(x.weight) OVER (ORDER BY x.id) AS cumulative,
                   sum(x.weight) OVER () AS total
            FROM sul.street_names x WHERE x.locale_code = p_locale_code
        ) r
        WHERE r.cumulative >= p_u * r.total ORDER BY r.id LIMIT 1;

    ELSIF p_lookup_type = 'city' THEN
        RETURN QUERY
        SELECT r.id::BIGINT, r.value FROM (
            SELECT x.id, x.name AS value,
                   sum(x.weight) OVER (ORDER BY x.id) AS cumulative,
                   sum(x.weight) OVER () AS total
            FROM sul.cities x WHERE x.locale_code = p_locale_code
        ) r
        WHERE r.cumulative >= p_u * r.total ORDER BY r.id LIMIT 1;

    ELSIF p_lookup_type = 'email_domain' THEN
        RETURN QUERY
        SELECT r.id::BIGINT, r.value FROM (
            SELECT x.id, x.domain AS value,
                   sum(x.weight) OVER (ORDER BY x.id) AS cumulative,
                   sum(x.weight) OVER () AS total
            FROM sul.email_domains x
            WHERE x.locale_code = p_locale_code OR x.locale_code IS NULL
        ) r
        WHERE r.cumulative >= p_u * r.total ORDER BY r.id LIMIT 1;

    ELSIF p_lookup_type = 'email_pattern' THEN
        RETURN QUERY
        SELECT r.id::BIGINT, r.value FROM (
            SELECT x.id, x.pattern AS value,
                   sum(x.weight) OVER (ORDER BY x.id) AS cumulative,
                   sum(x.weight) OVER () AS total
            FROM sul.email_patterns x WHERE x.locale_code = p_locale_code
        ) r
        WHERE r.cumulative >= p_u * r.total ORDER BY r.id LIMIT 1;

    ELSIF p_lookup_type = 'phone_format' THEN
        RETURN QUERY
        SELECT r.id::BIGINT, r.value FROM (
            SELECT x.id, x.format_pattern AS value,
                   sum(x.weight) OVER (ORDER BY x.id) AS cumulative,
                   sum(x.weight) OVER () AS total
            FROM sul.phone_formats x WHERE x.locale_code = p_locale_code
        ) r
        WHERE r.cumulative >= p_u * r.total ORDER BY r.id LIMIT 1;

    ELSIF p_lookup_type = 'eye_color' THEN
        RETURN QUERY
        SELECT r.id::BIGINT, r.value FROM (
            SELECT x.id, x.color_name AS value,
                   sum(x.weight) OVER (ORDER BY x.id) AS cumulative,
                   sum(x.weight) OVER () AS total
            FROM sul.eye_colors x
            WHERE x.locale_code = p_locale_code OR x.locale_code IS NULL
        ) r
        WHERE r.cumulative >= p_u * r.total ORDER BY r.id LIMIT 1;

    ELSIF p_lookup_type = 'hair_color' THEN
        RETURN QUERY
        SELECT r.id::BIGINT, r.value FROM (
            SELECT x.id, x.color_name AS value,
                   sum(x.weight) OVER (ORDER BY x.id) AS cumulative,
                   sum(x.weight) OVER () AS total
            FROM sul.hair_colors x
            WHERE x.locale_code = p_locale_code OR x.locale_code IS NULL
        ) r
        WHERE r.cumulative >= p_u * r.total ORDER BY r.id LIMIT 1;

    ELSE
        RAISE EXCEPTION 'select_lookup_value: unsupported lookup type "%"', p_lookup_type
            USING ERRCODE = '22023';
    END IF;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'select_lookup_value: no % lookup data for locale %',
            p_lookup_type, p_locale_code USING ERRCODE = 'P0002';
    END IF;
END;
$$;

COMMENT ON FUNCTION sul.select_lookup_value(TEXT, TEXT, DOUBLE PRECISION, CHAR) IS
    'Deterministically selects a weighted, locale-compatible lookup row. Supported types: first_name, middle_name, last_name, title, street, city, email_domain, email_pattern, phone_format, eye_color, hair_color.';

-- ---------------------------------------------------------------------------
-- Name and address formatting
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION sul.format_full_name(
    p_locale_code TEXT,
    p_first_name  TEXT,
    p_middle_name TEXT,
    p_last_name   TEXT
) RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_pattern TEXT;
    v_result  TEXT;
BEGIN
    SELECT full_name_format INTO v_pattern
    FROM sul.locales WHERE locale_code = p_locale_code;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'format_full_name: unknown locale "%"', p_locale_code
            USING ERRCODE = '22023';
    END IF;
    IF p_first_name IS NULL OR p_first_name = '' OR p_last_name IS NULL OR p_last_name = '' THEN
        RAISE EXCEPTION 'format_full_name: first and last names are required'
            USING ERRCODE = '22023';
    END IF;

    v_result := replace(v_pattern, '{first}', p_first_name);
    v_result := replace(v_result, '{middle}', coalesce(p_middle_name, ''));
    v_result := replace(v_result, '{last}', p_last_name);
    v_result := btrim(regexp_replace(v_result, '\s+', ' ', 'g'));
    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION sul.format_full_name(TEXT, TEXT, TEXT, TEXT) IS
    'Builds a locale-configured full name and removes an omitted middle name cleanly.';

CREATE OR REPLACE FUNCTION sul.format_street_address(
    p_locale_code     TEXT,
    p_street_name     TEXT,
    p_house_number    INTEGER,
    p_house_suffix    TEXT DEFAULT NULL
) RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_pattern TEXT;
    v_result  TEXT;
BEGIN
    SELECT street_address_format INTO v_pattern
    FROM sul.locales WHERE locale_code = p_locale_code;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'format_street_address: unknown locale "%"', p_locale_code
            USING ERRCODE = '22023';
    END IF;
    IF p_street_name IS NULL OR p_street_name = '' OR p_house_number IS NULL THEN
        RAISE EXCEPTION 'format_street_address: street name and house number are required'
            USING ERRCODE = '22023';
    END IF;

    v_result := replace(v_pattern, '{street_name}', p_street_name);
    v_result := replace(v_result, '{house_number}', p_house_number::TEXT);
    v_result := replace(v_result, '{house_suffix}', coalesce(p_house_suffix, ''));
    RETURN btrim(regexp_replace(v_result, '\s+', ' ', 'g'));
END;
$$;

COMMENT ON FUNCTION sul.format_street_address(TEXT, TEXT, INTEGER, TEXT) IS
    'Builds a country-appropriate street line (US: number + street; DE: street + number + optional letter).';

CREATE OR REPLACE FUNCTION sul.format_address(
    p_locale_code      TEXT,
    p_street_address   TEXT,
    p_city             TEXT,
    p_region_name      TEXT,
    p_region_code      TEXT,
    p_postal_code      TEXT,
    p_country          TEXT
) RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_pattern TEXT;
    v_result  TEXT;
BEGIN
    SELECT address_format INTO v_pattern
    FROM sul.locales WHERE locale_code = p_locale_code;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'format_address: unknown locale "%"', p_locale_code
            USING ERRCODE = '22023';
    END IF;
    IF p_street_address IS NULL OR p_city IS NULL OR p_postal_code IS NULL OR p_country IS NULL
       OR p_street_address = '' OR p_city = '' OR p_postal_code = '' OR p_country = '' THEN
        RAISE EXCEPTION 'format_address: street, city, postal code and country are required'
            USING ERRCODE = '22023';
    END IF;

    v_result := replace(v_pattern, '{street_address}', p_street_address);
    v_result := replace(v_result, '{city}', p_city);
    v_result := replace(v_result, '{region_name}', coalesce(p_region_name, ''));
    v_result := replace(v_result, '{region_code}', coalesce(p_region_code, ''));
    v_result := replace(v_result, '{postal_code}', p_postal_code);
    v_result := replace(v_result, '{country}', p_country);
    v_result := regexp_replace(v_result, '\s+', ' ', 'g');
    v_result := regexp_replace(v_result, '\s*,\s*', ', ', 'g');
    RETURN btrim(v_result);
END;
$$;

COMMENT ON FUNCTION sul.format_address(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) IS
    'Formats a complete locale-aware postal address from generated components.';

-- ---------------------------------------------------------------------------
-- Phone, email and slug helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION sul.format_phone(
    p_locale_code    TEXT,
    p_format_pattern TEXT,
    p_seed           BIGINT,
    p_batch_index    INTEGER,
    p_row_index      INTEGER
) RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_chars  TEXT[];
    v_result TEXT := '';
    v_digit  INTEGER := 0;
    i        INTEGER;
BEGIN
    IF p_format_pattern IS NULL OR position('#' IN p_format_pattern) = 0 THEN
        RAISE EXCEPTION 'format_phone: format pattern must contain at least one #'
            USING ERRCODE = '22023';
    END IF;

    v_chars := regexp_split_to_array(p_format_pattern, '');
    FOR i IN 1 .. array_length(v_chars, 1) LOOP
        IF v_chars[i] = '#' THEN
            v_digit := v_digit + 1;
            v_result := v_result || sul.deterministic_integer(
                p_locale_code, p_seed, p_batch_index, p_row_index,
                'phone_digit:' || v_digit::TEXT, 0, 9
            )::TEXT;
        ELSE
            v_result := v_result || v_chars[i];
        END IF;
    END LOOP;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION sul.format_phone(TEXT, TEXT, BIGINT, INTEGER, INTEGER) IS
    'Replaces each # in a locale phone pattern with an independently salted deterministic digit.';

CREATE OR REPLACE FUNCTION sul.slugify(p_input TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
STRICT
AS $$
DECLARE
    v_result TEXT;
BEGIN
    v_result := translate(
        lower(p_input),
        'äöüßáàâãåéèêëíìîïóòôõúùûçñøæœ',
        'aousaaaaaeeeeiiiioooouuuucnoao'
    );
    v_result := regexp_replace(v_result, '[^a-z0-9]+', '', 'g');
    IF v_result = '' THEN
        v_result := 'user';
    END IF;
    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION sul.slugify(TEXT) IS
    'Lowercase ASCII email-friendly form; transliterates common European characters and removes other punctuation.';

CREATE OR REPLACE FUNCTION sul.format_email(
    p_first_name TEXT,
    p_last_name  TEXT,
    p_pattern    TEXT,
    p_domain     TEXT,
    p_suffix     TEXT
) RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_first TEXT;
    v_last  TEXT;
    v_local TEXT;
    v_domain TEXT;
    v_suffix TEXT;
BEGIN
    IF p_first_name IS NULL OR p_last_name IS NULL OR p_pattern IS NULL
       OR p_domain IS NULL OR p_pattern = '' OR p_domain = '' THEN
        RAISE EXCEPTION 'format_email: name, pattern and domain are required'
            USING ERRCODE = '22023';
    END IF;

    v_domain := lower(btrim(p_domain));
    IF v_domain !~ '^example\.(com|net|org)$' THEN
        RAISE EXCEPTION 'format_email: domain must be an RFC 2606 example domain'
            USING ERRCODE = '22023';
    END IF;

    v_first := sul.slugify(p_first_name);
    v_last  := sul.slugify(p_last_name);

    v_local := replace(p_pattern, '{first}', v_first);
    v_local := replace(v_local, '{last}', v_last);
    v_local := replace(v_local, '{fi}', left(v_first, 1));
    v_local := regexp_replace(lower(v_local), '[^a-z0-9._-]+', '', 'g');
    v_local := btrim(v_local, '._-');

    v_suffix := nullif(regexp_replace(coalesce(p_suffix, ''), '[^a-z0-9]+', '', 'gi'), '');
    IF v_suffix IS NOT NULL THEN
        v_local := left(v_local, greatest(1, 64 - length(v_suffix) - 1)) || '.' || v_suffix;
    END IF;

    IF v_local = '' THEN
        v_local := 'user';
    END IF;

    RETURN v_local || '@' || v_domain;
END;
$$;

COMMENT ON FUNCTION sul.format_email(TEXT, TEXT, TEXT, TEXT, TEXT) IS
    'Builds an ASCII local-part from localized name components, appends a deterministic per-row suffix, and enforces an example domain.';
