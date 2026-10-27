"""Statistical validation of SQL distributions.

These tests are deterministic themselves: the same seeds always produce the
same samples. Tolerances are wide enough to be robust but narrow enough to
detect a uniform-instead-of-normal or uniform-latitude regression.
"""

from __future__ import annotations

import math

import pytest

pytestmark = pytest.mark.integration


def test_deterministic_uniform_is_open_interval_and_fair(db) -> None:
    row = db.execute(
        """
        SELECT avg(u) AS mean,
               stddev_samp(u) AS sd,
               min(u) AS minimum,
               max(u) AS maximum,
               count(*) AS n
        FROM (
            SELECT sul.deterministic_uniform('en_US', 2026, 0, i, 'uniform_probe') AS u
            FROM generate_series(0, 19999) AS i
        ) sample
        """
    ).fetchone()
    assert row["n"] == 20000
    assert 0.0 < row["minimum"] < 0.01
    assert 0.99 < row["maximum"] < 1.0
    assert abs(row["mean"] - 0.5) < 0.012
    assert abs(row["sd"] - (1.0 / math.sqrt(12.0))) < 0.012


def test_deterministic_normal_matches_standard_normal(db) -> None:
    row = db.execute(
        """
        SELECT avg(z) AS mean, stddev_samp(z) AS sd,
               min(z) AS minimum, max(z) AS maximum, count(*) AS n
        FROM (
            SELECT sul.deterministic_normal(
                'en_US', 2026, 0, i, 'normal_probe', 0.0, 1.0
            ) AS z
            FROM generate_series(0, 19999) AS i
        ) sample
        """
    ).fetchone()
    assert row["n"] == 20000
    assert abs(row["mean"]) < 0.035
    assert abs(row["sd"] - 1.0) < 0.035
    assert row["minimum"] > -6.0
    assert row["maximum"] < 6.0


def test_normal_distribution_is_reproducible(db) -> None:
    first = db.execute(
        "SELECT sul.deterministic_normal('de_DE', 7, 3, 4, 'height', 170.0, 8.0) AS z"
    ).fetchone()["z"]
    second = db.execute(
        "SELECT sul.deterministic_normal('de_DE', 7, 3, 4, 'height', 170.0, 8.0) AS z"
    ).fetchone()["z"]
    assert first == second


def test_generated_coordinates_are_uniform_on_the_sphere(db) -> None:
    rows = db.execute(
        """
        SELECT latitude, longitude
        FROM sul.generate_users('en_US', 424242, 5, 4000)
        """
    ).fetchall()
    assert len(rows) == 4000

    z_values = [math.sin(math.radians(row["latitude"])) for row in rows]
    z_mean = sum(z_values) / len(z_values)
    z_sd = math.sqrt(
        sum((value - z_mean) ** 2 for value in z_values) / (len(z_values) - 1)
    )
    equator_fraction = sum(abs(row["latitude"]) < 30.0 for row in rows) / len(rows)
    east_fraction = sum(row["longitude"] > 0 for row in rows) / len(rows)

    # Uniform z in [-1,1] has mean 0 and standard deviation 1/sqrt(3).
    assert abs(z_mean) < 0.04
    assert 0.53 < z_sd < 0.62

    # Spherical sampling puts half the surface within +-30 degrees latitude.
    # A uniform-latitude draw would put only one third there.
    assert 0.44 < equator_fraction < 0.56
    assert equator_fraction > 0.40
    assert 0.44 < east_fraction < 0.56
    assert all(-90.0 <= row["latitude"] <= 90.0 for row in rows)
    assert all(-180.0 <= row["longitude"] < 180.0 for row in rows)
