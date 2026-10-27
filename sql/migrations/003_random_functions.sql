-- ============================================================================
-- Synthetic User Lab - deterministic randomness
-- Migration: 003_random_functions.sql
--
-- Core idea
-- ---------
-- Every field draws from its own SHA-256 hash of:
--
--     locale_code | seed | batch_index | row_index | field_salt
--
-- The first 56 bits of the digest are interpreted as an unsigned integer and
-- mapped to:
--
--     u = (v + 0.5) / 2^56          where 0 < u < 1
--
-- The +0.5 avoids the closed endpoints 0 and 1, which matters for logarithms
-- and spherical coordinates. 56 bits exceed the 53-bit mantissa of a double,
-- so the final double can round the least significant bits; the mapping is
-- nevertheless stable on a given PostgreSQL build and is not affected by
-- session state, row ordering or query plans. This is deliberately NOT based
-- on random()/setseed().
-- ============================================================================

CREATE OR REPLACE FUNCTION sul.deterministic_uniform(
    p_locale_code TEXT,
    p_seed        BIGINT,
    p_batch_index INTEGER,
    p_row_index   INTEGER,
    p_salt        TEXT
) RETURNS DOUBLE PRECISION
LANGUAGE plpgsql
IMMUTABLE
STRICT
PARALLEL SAFE
AS $$
DECLARE
    v_hash   BYTEA;
    v_bits   BIGINT;
    v_denom  CONSTANT NUMERIC := 72057594037927936; -- 2^56
BEGIN
    IF p_salt = '' THEN
        RAISE EXCEPTION 'deterministic_uniform: p_salt must not be empty'
            USING ERRCODE = '22023';
    END IF;

    v_hash := public.digest(
        concat_ws('|', p_locale_code, p_seed::TEXT, p_batch_index::TEXT,
                  p_row_index::TEXT, p_salt),
        'sha256'
    );

    -- First 7 bytes = 56 bits. A 56-bit bit string is non-negative when cast
    -- to BIGINT, avoiding the sign trap of a full 64-bit cast.
    v_bits := ('x' || substring(encode(v_hash, 'hex') FROM 1 FOR 14))::bit(56)::BIGINT;

    RETURN ((v_bits::NUMERIC + 0.5) / v_denom)::DOUBLE PRECISION;
END;
$$;

COMMENT ON FUNCTION sul.deterministic_uniform(TEXT, BIGINT, INTEGER, INTEGER, TEXT) IS
    'SHA-256 based uniform value in the open interval (0,1) for a stable generation identity and field salt.';

CREATE OR REPLACE FUNCTION sul.deterministic_integer(
    p_locale_code TEXT,
    p_seed        BIGINT,
    p_batch_index INTEGER,
    p_row_index   INTEGER,
    p_salt        TEXT,
    p_min_value   INTEGER,
    p_max_value   INTEGER
) RETURNS INTEGER
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
    v_u    DOUBLE PRECISION;
    v_span BIGINT;
BEGIN
    IF p_min_value IS NULL OR p_max_value IS NULL THEN
        RAISE EXCEPTION 'deterministic_integer: bounds must not be NULL'
            USING ERRCODE = '22023';
    END IF;

    IF p_max_value < p_min_value THEN
        RAISE EXCEPTION 'deterministic_integer: max (%) must be >= min (%)',
            p_max_value, p_min_value USING ERRCODE = '22023';
    END IF;

    v_span := p_max_value::BIGINT - p_min_value::BIGINT + 1;

    IF v_span > 4294967296 THEN
        RAISE EXCEPTION 'deterministic_integer: range is too large'
            USING ERRCODE = '22023';
    END IF;

    v_u := sul.deterministic_uniform(
        p_locale_code, p_seed, p_batch_index, p_row_index, p_salt
    );

    -- Inclusive on both ends. floor(u * span) is in [0, span-1] because
    -- u is strictly less than 1.
    RETURN (p_min_value::BIGINT + floor(v_u * v_span)::BIGINT)::INTEGER;
END;
$$;

COMMENT ON FUNCTION sul.deterministic_integer(TEXT, BIGINT, INTEGER, INTEGER, TEXT, INTEGER, INTEGER) IS
    'Deterministically maps a uniform value to an inclusive integer range [min,max].';

CREATE OR REPLACE FUNCTION sul.deterministic_normal(
    p_locale_code TEXT,
    p_seed        BIGINT,
    p_batch_index INTEGER,
    p_row_index   INTEGER,
    p_salt        TEXT,
    p_mean        DOUBLE PRECISION,
    p_stddev      DOUBLE PRECISION
) RETURNS DOUBLE PRECISION
LANGUAGE plpgsql
IMMUTABLE
STRICT
PARALLEL SAFE
AS $$
DECLARE
    v_u1 DOUBLE PRECISION;
    v_u2 DOUBLE PRECISION;
BEGIN
    IF p_stddev <= 0 THEN
        RAISE EXCEPTION 'deterministic_normal: p_stddev must be positive'
            USING ERRCODE = '22023';
    END IF;

    -- Independent derived salts keep u1 and u2 independent.
    v_u1 := sul.deterministic_uniform(
        p_locale_code, p_seed, p_batch_index, p_row_index, p_salt || ':u1'
    );
    v_u2 := sul.deterministic_uniform(
        p_locale_code, p_seed, p_batch_index, p_row_index, p_salt || ':u2'
    );

    -- Box-Muller transform:
    --   z = sqrt(-2 ln(u1)) * cos(2*pi*u2),  z ~ N(0,1)
    -- u1 is guaranteed to be > 0 by deterministic_uniform.
    RETURN p_mean + p_stddev
           * sqrt(-2.0 * ln(v_u1))
           * cos(2.0 * pi() * v_u2);
END;
$$;

COMMENT ON FUNCTION sul.deterministic_normal(TEXT, BIGINT, INTEGER, INTEGER, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) IS
    'Deterministic Box-Muller normal sample N(mean, stddev^2). Caller is responsible for documented plausible-range clamping.';
