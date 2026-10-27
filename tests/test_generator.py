"""Integration tests for deterministic generation and data quality."""

from __future__ import annotations

import re
from decimal import Decimal

import psycopg
import pytest

pytestmark = pytest.mark.integration


def generate(
    db: psycopg.Connection,
    locale: str = "en_US",
    seed: int = 42,
    batch_index: int = 0,
    batch_size: int = 10,
) -> list[dict]:
    return db.execute(
        """
        SELECT *
        FROM sul.generate_users(%s, %s, %s, %s)
        ORDER BY row_index
        """,
        (locale, seed, batch_index, batch_size),
    ).fetchall()


def generate_one(
    db: psycopg.Connection,
    locale: str = "en_US",
    seed: int = 42,
    batch_index: int = 0,
    row_index: int = 0,
) -> dict:
    return db.execute(
        "SELECT * FROM sul.generate_user(%s, %s, %s, %s)",
        (locale, seed, batch_index, row_index),
    ).fetchone()


def test_same_identity_returns_identical_record(db) -> None:
    first = generate_one(db, "en_US", 42, 0, 0)
    second = generate_one(db, "en_US", 42, 0, 0)
    assert first == second


def test_direct_user_regeneration_matches_batch(db) -> None:
    batch = generate(db, "de_DE", 777, 12, 10)
    rebuilt = generate_one(db, "de_DE", 777, 12, 7)
    assert rebuilt == batch[7]


def test_changing_seed_changes_fields(db) -> None:
    a = generate_one(db, "en_US", 100, 0, 0)
    b = generate_one(db, "en_US", 101, 0, 0)
    ignored = {"seed"}
    assert any(a[key] != b[key] for key in a if key not in ignored)


def test_changing_locale_produces_locale_appropriate_data(db) -> None:
    us = generate_one(db, "en_US", 42, 0, 0)
    de = generate_one(db, "de_DE", 42, 0, 0)
    assert us["country"] == "United States"
    assert de["country"] == "Germany"
    assert "555-01" in us["phone"]
    assert re.match(r"^(030|\(030\)|\+49 30) ", de["phone"])
    assert us["eye_color"] in {"Brown", "Blue", "Green", "Hazel", "Gray"}
    assert de["eye_color"] in {"Braun", "Blau", "Grün", "Haselnuss", "Grau"}
    assert us["email"] != de["email"]


def test_rows_in_a_batch_are_not_all_identical(db) -> None:
    rows = generate(db, "en_US", 42, 0, 8)
    assert len({(r["first_name"], r["last_name"], r["email"]) for r in rows}) > 1
    assert len({r["email"] for r in rows}) == len(rows)


def test_batch_size_does_not_renumber_existing_rows(db) -> None:
    short = generate(db, "de_DE", 88, 3, 5)
    long = generate(db, "de_DE", 88, 3, 10)
    assert short == long[:5]


def test_different_batch_indexes_produce_different_batches(db) -> None:
    first = generate(db, "en_US", 42, 0, 5)
    second = generate(db, "en_US", 42, 1, 5)
    assert [r["email"] for r in first] != [r["email"] for r in second]


def test_batch_order_does_not_affect_results(db) -> None:
    reference = generate(db, "en_US", 909, 4, 6)
    generate(db, "en_US", 909, 99, 6)
    generate(db, "de_DE", 909, 4, 6)
    assert generate(db, "en_US", 909, 4, 6) == reference


def test_different_row_indexes_use_different_identities(db) -> None:
    rows = [generate_one(db, "en_US", 42, 0, index) for index in range(5)]
    assert [row["row_index"] for row in rows] == [0, 1, 2, 3, 4]
    assert len({row["email"] for row in rows}) == 5


@pytest.mark.parametrize("locale", ["en_US", "de_DE"])
def test_data_quality_for_large_sample(db, locale: str) -> None:
    rows = generate(db, locale, 314159, 2, 300)
    assert len(rows) == 300
    assert len({row["email"] for row in rows}) == 300

    locale_config = db.execute(
        "SELECT * FROM sul.locales WHERE locale_code = %s", (locale,)
    ).fetchone()
    stats = {
        row["gender"]: row
        for row in db.execute(
            "SELECT * FROM sul.body_statistics WHERE locale_code = %s", (locale,)
        ).fetchall()
    }
    eye_colors = {
        row["color_name"]
        for row in db.execute(
            "SELECT color_name FROM sul.eye_colors WHERE locale_code = %s", (locale,)
        ).fetchall()
    }
    first_names = {
        (row["name"], row["gender"])
        for row in db.execute(
            "SELECT name, gender FROM sul.first_names WHERE locale_code = %s", (locale,)
        ).fetchall()
    }
    last_names = {
        row["name"]
        for row in db.execute(
            "SELECT name FROM sul.last_names WHERE locale_code = %s", (locale,)
        ).fetchall()
    }

    postal_regex = re.compile(locale_config["postal_code_regex"])
    email_regex = re.compile(r"^[a-z0-9._-]{1,64}@example\.(com|net|org)$")
    phone_regex = (
        re.compile(r"^(\(\d{3}\) 555-01\d{2}|\d{3}-555-01\d{2}|\+1 \d{3}-555-01\d{2})$")
        if locale == "en_US"
        else re.compile(r"^(030 23125\d{3}|\(030\) 23125\d{3}|\+49 30 23125\d{3})$")
    )

    for row in rows:
        for field in (
            "locale_code",
            "gender",
            "first_name",
            "last_name",
            "full_name",
            "street_name",
            "street_address",
            "city",
            "region_name",
            "region_code",
            "postal_code",
            "country",
            "full_address",
            "eye_color",
            "hair_color",
            "phone",
            "email",
        ):
            assert row[field] not in (None, ""), (field, row)
        assert row["locale_code"] == locale
        assert row["seed"] == 314159
        assert row["batch_index"] == 2
        assert row["gender"] in {"F", "M"}
        assert (row["first_name"], row["gender"]) in first_names
        assert row["last_name"] in last_names
        assert row["eye_color"] in eye_colors
        assert postal_regex.fullmatch(row["postal_code"])
        assert email_regex.fullmatch(row["email"])
        assert phone_regex.fullmatch(row["phone"])
        assert -90.0 <= row["latitude"] <= 90.0
        assert -180.0 <= row["longitude"] <= 180.0

        body = stats[row["gender"]]
        assert isinstance(row["height_cm"], Decimal)
        assert isinstance(row["weight_kg"], Decimal)
        assert body["height_min_cm"] <= row["height_cm"] <= body["height_max_cm"]
        assert body["weight_min_kg"] <= row["weight_kg"] <= body["weight_max_kg"]
        assert row["country"] == locale_config["country_name"]
        assert row["city"] in row["full_address"]
        assert row["street_address"] in row["full_address"]

    assert any(row["middle_name"] is None for row in rows)
    assert any(row["middle_name"] is not None for row in rows)
    assert any(row["title"] is None for row in rows)
    assert any(row["title"] is not None for row in rows)


def test_optional_field_probabilities_are_respected(db) -> None:
    rows = generate(db, "en_US", 123, 0, 500)
    middle_present = sum(row["middle_name"] is not None for row in rows)
    title_present = sum(row["title"] is not None for row in rows)
    assert 0.5 < middle_present / len(rows) < 0.8
    assert 0.15 < title_present / len(rows) < 0.42


@pytest.mark.parametrize(
    ("locale", "seed", "batch_index", "size"),
    [
        ("xx_XX", 1, 0, 1),
        ("en_US", -1, 0, 1),
        ("en_US", 1, -1, 1),
        ("en_US", 1, 0, 0),
        ("en_US", 1, 0, 10001),
    ],
)
def test_sql_rejects_invalid_batch_parameters(
    db, locale: str, seed: int, batch_index: int, size: int
) -> None:
    with pytest.raises(psycopg.errors.InvalidParameterValue):
        db.execute(
            "SELECT * FROM sul.generate_users(%s, %s, %s, %s)",
            (locale, seed, batch_index, size),
        )


def test_sql_rejects_invalid_row_index(db) -> None:
    with pytest.raises(psycopg.errors.InvalidParameterValue):
        db.execute("SELECT * FROM sul.generate_user('en_US', 1, 0, 10000)")
