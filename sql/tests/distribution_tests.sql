\set ON_ERROR_STOP on
-- Distribution checks. Run with:
--   psql -v ON_ERROR_STOP=1 "$DATABASE_URL" -f sql/tests/distribution_tests.sql

DO $$
DECLARE
    v_mean DOUBLE PRECISION;
    v_sd DOUBLE PRECISION;
    v_min DOUBLE PRECISION;
    v_max DOUBLE PRECISION;
    v_equator DOUBLE PRECISION;
    v_east DOUBLE PRECISION;
BEGIN
    SELECT avg(u), stddev_samp(u), min(u), max(u)
      INTO v_mean, v_sd, v_min, v_max
    FROM (
        SELECT sul.deterministic_uniform('en_US', 2026, 0, i, 'uniform_probe') AS u
        FROM generate_series(0, 19999) AS i
    ) s;

    IF v_min <= 0 OR v_max >= 1 THEN
        RAISE EXCEPTION 'FAIL: uniform values are not in (0,1): min %, max %', v_min, v_max;
    END IF;
    IF abs(v_mean - 0.5) > 0.015 THEN
        RAISE EXCEPTION 'FAIL: uniform mean % is too far from 0.5', v_mean;
    END IF;
    IF abs(v_sd - 0.2886751345948129) > 0.015 THEN
        RAISE EXCEPTION 'FAIL: uniform standard deviation % is unexpected', v_sd;
    END IF;

    SELECT avg(z), stddev_samp(z), min(z), max(z)
      INTO v_mean, v_sd, v_min, v_max
    FROM (
        SELECT sul.deterministic_normal('en_US', 2026, 0, i, 'normal_probe', 0.0, 1.0) AS z
        FROM generate_series(0, 19999) AS i
    ) s;

    IF abs(v_mean) > 0.04 THEN
        RAISE EXCEPTION 'FAIL: normal mean % is too far from 0', v_mean;
    END IF;
    IF abs(v_sd - 1.0) > 0.04 THEN
        RAISE EXCEPTION 'FAIL: normal standard deviation % is not near 1', v_sd;
    END IF;

    SELECT avg(sin(radians(latitude))),
           stddev_samp(sin(radians(latitude))),
           avg(CASE WHEN abs(latitude) < 30 THEN 1.0 ELSE 0.0 END),
           avg(CASE WHEN longitude > 0 THEN 1.0 ELSE 0.0 END)
      INTO v_mean, v_sd, v_equator, v_east
    FROM sul.generate_users('de_DE', 987654, 9, 2000);

    -- z must be uniform: mean 0, SD 1/sqrt(3). Spherical sampling puts half
    -- the surface within +-30 degrees latitude; uniform latitude gives 1/3.
    IF abs(v_mean) > 0.055 THEN
        RAISE EXCEPTION 'FAIL: spherical z mean % is too far from 0', v_mean;
    END IF;
    IF v_sd < 0.52 OR v_sd > 0.63 THEN
        RAISE EXCEPTION 'FAIL: spherical z SD % is outside [0.52,0.63]', v_sd;
    END IF;
    IF v_equator < 0.43 OR v_equator > 0.57 THEN
        RAISE EXCEPTION 'FAIL: equator fraction % indicates non-spherical latitude', v_equator;
    END IF;
    IF v_east < 0.43 OR v_east > 0.57 THEN
        RAISE EXCEPTION 'FAIL: east/west fraction % indicates longitude bias', v_east;
    END IF;
END $$;

\echo 'distribution_tests.sql: PASS'
