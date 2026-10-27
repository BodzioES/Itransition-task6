"""Database schema, seed and metadata tests."""

from __future__ import annotations

import pytest

pytestmark = pytest.mark.integration


def test_all_migrations_are_recorded(db) -> None:
    row = db.execute("SELECT count(*) AS count FROM public.schema_migrations").fetchone()
    assert row["count"] == 6


def test_schema_contains_required_objects(db) -> None:
    required_tables = {
        "locales",
        "regions",
        "cities",
        "first_names",
        "middle_names",
        "last_names",
        "titles",
        "street_names",
        "email_domains",
        "email_patterns",
        "phone_formats",
        "eye_colors",
        "hair_colors",
        "body_statistics",
    }
    rows = db.execute(
        """
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = 'sul' AND table_type = 'BASE TABLE'
        """
    ).fetchall()
    assert required_tables <= {row["table_name"] for row in rows}


def test_both_locales_have_lookup_coverage(db) -> None:
    rows = db.execute("SELECT * FROM sul.lookup_coverage").fetchall()
    coverage = {row["locale_code"]: row for row in rows}
    assert set(coverage) == {"en_US", "de_DE"}
    for locale in ("en_US", "de_DE"):
        row = coverage[locale]
        assert row["first_names"] >= 100
        assert row["last_names"] >= 90
        assert row["middle_names"] >= 45
        assert row["titles"] >= 4
        assert row["street_names"] >= 90
        assert row["cities"] >= 20
        assert row["regions"] >= 8
        assert row["email_domains"] >= 3
        assert row["email_patterns"] >= 4
        assert row["phone_formats"] >= 3
        assert row["eye_colors"] >= 5
        assert row["hair_colors"] >= 5


def test_required_indexes_exist(db) -> None:
    expected = {
        "first_names_lookup_idx",
        "middle_names_lookup_idx",
        "last_names_lookup_idx",
        "titles_lookup_idx",
        "street_names_lookup_idx",
        "cities_lookup_idx",
        "email_domains_lookup_idx",
        "email_patterns_lookup_idx",
        "phone_formats_lookup_idx",
        "eye_colors_lookup_idx",
        "hair_colors_lookup_idx",
    }
    rows = db.execute(
        "SELECT indexname FROM pg_indexes WHERE schemaname = 'sul'"
    ).fetchall()
    assert expected <= {row["indexname"] for row in rows}


def test_primary_foreign_key_and_check_constraints_exist(db) -> None:
    constraints = db.execute(
        """
        SELECT conname, contype
        FROM pg_constraint
        WHERE connamespace = 'sul'::regnamespace
        """
    ).fetchall()
    by_type: dict[str, set[str]] = {"p": set(), "f": set(), "c": set(), "u": set()}
    for row in constraints:
        by_type.setdefault(row["contype"], set()).add(row["conname"])
    assert "locales_pkey" in by_type["p"]
    assert "first_names_gender_check" in by_type["c"]
    assert "cities_region_fk" in by_type["f"]
    assert "first_names_unique" in by_type["u"]
    assert "phone_formats_hash" in by_type["c"]


def test_pgcrypto_is_installed(db) -> None:
    row = db.execute(
        "SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pgcrypto') AS installed"
    ).fetchone()
    assert row["installed"] is True


def test_public_sql_api_signatures_exist(db) -> None:
    expected = [
        "sul.deterministic_uniform(text,bigint,integer,integer,text)",
        "sul.deterministic_integer(text,bigint,integer,integer,text,integer,integer)",
        "sul.deterministic_normal(text,bigint,integer,integer,text,double precision,double precision)",
        "sul.select_lookup_value(text,text,double precision,character)",
        "sul.format_full_name(text,text,text,text)",
        "sul.format_address(text,text,text,text,text,text,text)",
        "sul.format_phone(text,text,bigint,integer,integer)",
        "sul.format_email(text,text,text,text,text)",
        "sul.generate_user(text,bigint,integer,integer)",
        "sul.generate_users(text,bigint,integer,integer)",
    ]
    for signature in expected:
        row = db.execute(
            "SELECT to_regprocedure(%s) AS exists", (signature,)
        ).fetchone()
        assert row["exists"] is not None, signature


def test_volatility_declarations_are_safe(db) -> None:
    rows = db.execute(
        """
        SELECT p.proname, p.provolatile
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'sul'
          AND p.proname IN (
              'deterministic_uniform', 'deterministic_normal',
              'generate_user', 'generate_users', 'select_lookup_value'
          )
        """
    ).fetchall()
    volatility = {row["proname"]: row["provolatile"] for row in rows}
    assert volatility["deterministic_uniform"] == "i"
    assert volatility["deterministic_normal"] == "i"
    assert volatility["select_lookup_value"] == "s"
    assert volatility["generate_user"] == "s"
    assert volatility["generate_users"] == "s"


def test_only_example_email_domains_are_seeded(db) -> None:
    rows = db.execute("SELECT DISTINCT domain FROM sul.email_domains").fetchall()
    assert {row["domain"] for row in rows} == {
        "example.com",
        "example.net",
        "example.org",
    }


def test_lookup_combination_space_is_large(db) -> None:
    row = db.execute(
        """
        SELECT l.locale_code,
               (SELECT count(*) FROM sul.first_names x WHERE x.locale_code = l.locale_code)
             * (SELECT count(*) FROM sul.last_names x WHERE x.locale_code = l.locale_code)
             * ((SELECT count(*) FROM sul.middle_names x WHERE x.locale_code = l.locale_code) + 1)
             * (SELECT count(*) FROM sul.street_names x WHERE x.locale_code = l.locale_code)
             * (SELECT count(*) FROM sul.cities x WHERE x.locale_code = l.locale_code)
             AS base_combinations
        FROM sul.locales l
        """
    ).fetchall()
    assert all(item["base_combinations"] > 100_000_000 for item in row)
