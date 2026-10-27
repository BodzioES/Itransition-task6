\set ON_ERROR_STOP on
-- Deterministic behavior checks. Run with:
--   psql -v ON_ERROR_STOP=1 "$DATABASE_URL" -f sql/tests/deterministic_tests.sql
-- The script raises an exception (non-zero exit) on failure.

DROP TABLE IF EXISTS det_a;
DROP TABLE IF EXISTS det_b;
DROP TABLE IF EXISTS det_batch;
DROP TABLE IF EXISTS det_batch_short;

CREATE TEMP TABLE det_a AS
SELECT * FROM sul.generate_user('en_US', 4242, 3, 7);

CREATE TEMP TABLE det_b AS
SELECT * FROM sul.generate_user('en_US', 4242, 3, 7);

DO $$
BEGIN
    IF EXISTS (SELECT * FROM det_a EXCEPT SELECT * FROM det_b)
       OR EXISTS (SELECT * FROM det_b EXCEPT SELECT * FROM det_a) THEN
        RAISE EXCEPTION 'FAIL: the same identity returned different records';
    END IF;
END $$;

CREATE TEMP TABLE det_batch AS
SELECT * FROM sul.generate_users('en_US', 4242, 3, 10);

DO $$
DECLARE
    v_direct RECORD;
    v_batch  RECORD;
BEGIN
    SELECT * INTO v_direct FROM sul.generate_user('en_US', 4242, 3, 7);
    SELECT * INTO v_batch FROM det_batch WHERE row_index = 7;
    IF v_direct IS DISTINCT FROM v_batch THEN
        RAISE EXCEPTION 'FAIL: direct user differs from the same row in a batch';
    END IF;
END $$;

CREATE TEMP TABLE det_batch_short AS
SELECT * FROM sul.generate_users('en_US', 4242, 3, 5);

DO $$
BEGIN
    IF EXISTS (
        SELECT * FROM det_batch_short
        EXCEPT
        SELECT * FROM det_batch WHERE row_index < 5
    ) THEN
        RAISE EXCEPTION 'FAIL: changing batch_size renumbered existing rows';
    END IF;
END $$;

DO $$
DECLARE
    v_before RECORD;
    v_after  RECORD;
BEGIN
    SELECT * INTO v_before FROM sul.generate_user('de_DE', 9191, 20, 4);
    PERFORM * FROM sul.generate_users('en_US', 1, 0, 5);
    PERFORM * FROM sul.generate_users('de_DE', 9191, 21, 5);
    SELECT * INTO v_after FROM sul.generate_user('de_DE', 9191, 20, 4);
    IF v_before IS DISTINCT FROM v_after THEN
        RAISE EXCEPTION 'FAIL: request order changed an existing identity';
    END IF;
END $$;

DO $$
DECLARE
    v_a RECORD;
    v_b RECORD;
BEGIN
    SELECT * INTO v_a FROM sul.generate_user('en_US', 100, 0, 0);
    SELECT * INTO v_b FROM sul.generate_user('en_US', 101, 0, 0);
    IF v_a.first_name = v_b.first_name
       AND v_a.last_name = v_b.last_name
       AND v_a.street_address = v_b.street_address
       AND v_a.email = v_b.email
       AND v_a.height_cm = v_b.height_cm THEN
        RAISE EXCEPTION 'FAIL: changing the seed did not change any sampled field';
    END IF;
END $$;

DO $$
DECLARE
    v_locale_error BOOLEAN := FALSE;
    v_seed_error BOOLEAN := FALSE;
    v_batch_error BOOLEAN := FALSE;
    v_size_error BOOLEAN := FALSE;
    v_row_error BOOLEAN := FALSE;
BEGIN
    BEGIN
        PERFORM * FROM sul.generate_users('xx_XX', 1, 0, 1);
    EXCEPTION WHEN invalid_parameter_value THEN v_locale_error := TRUE;
    END;
    BEGIN
        PERFORM * FROM sul.generate_users('en_US', -1, 0, 1);
    EXCEPTION WHEN invalid_parameter_value THEN v_seed_error := TRUE;
    END;
    BEGIN
        PERFORM * FROM sul.generate_users('en_US', 1, -1, 1);
    EXCEPTION WHEN invalid_parameter_value THEN v_batch_error := TRUE;
    END;
    BEGIN
        PERFORM * FROM sul.generate_users('en_US', 1, 0, 0);
    EXCEPTION WHEN invalid_parameter_value THEN v_size_error := TRUE;
    END;
    BEGIN
        PERFORM * FROM sul.generate_user('en_US', 1, 0, 10000);
    EXCEPTION WHEN invalid_parameter_value THEN v_row_error := TRUE;
    END;

    IF NOT (v_locale_error AND v_seed_error AND v_batch_error
            AND v_size_error AND v_row_error) THEN
        RAISE EXCEPTION 'FAIL: one or more invalid inputs were accepted';
    END IF;
END $$;

\echo 'deterministic_tests.sql: PASS'
