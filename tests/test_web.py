"""Flask route, template and graceful-failure tests."""

from __future__ import annotations

from app import create_app

VALID_FORM = {
    "locale": "en_US",
    "seed": "42",
    "batch_index": "0",
    "batch_size": "5",
}


def test_homepage_renders_with_locale_options(client) -> None:
    response = client.get("/")
    text = response.get_data(as_text=True)
    assert response.status_code == 200
    assert "Synthetic User Lab" in text
    assert 'value="en_US"' in text
    assert 'value="de_DE"' in text
    assert "English" in text
    assert "German" in text
    assert "Your next batch appears here" in text
    assert "Generate users" in text


def test_docs_and_health_render(client) -> None:
    docs = client.get("/docs")
    assert docs.status_code == 200
    assert "Public SQL API" in docs.get_data(as_text=True)

    health = client.get("/health")
    assert health.status_code == 200
    assert health.json["status"] == "ok"
    assert health.json["database"]["schema_ready"] is True


def test_valid_generation_displays_table(client) -> None:
    response = client.post("/generate", data=VALID_FORM)
    text = response.get_data(as_text=True)
    assert response.status_code == 200
    assert "robert.thomas.001@example.com" in text
    assert "Robert Marie Thomas" in text
    assert "Generation duration" in text
    assert "Throughput" in text
    assert "users/s" in text
    assert "lat" in text
    assert "lon" in text
    assert "Reproducibility" in text
    assert "seed 42" in text


def test_next_batch_increments_and_changes_records(client) -> None:
    first = client.post("/generate", data=VALID_FORM)
    assert b"robert.thomas.001@example.com" in first.data
    assert b"Zero-based batch 0" in first.data

    response = client.post("/next", data=VALID_FORM)
    text = response.get_data(as_text=True)
    assert response.status_code == 200
    assert "Zero-based batch 1" in text
    assert "robert.thomas.001@example.com" not in text

    previous = client.post(
        "/previous",
        data={**VALID_FORM, "batch_index": "1"},
    )
    assert previous.status_code == 200
    assert "robert.thomas.001@example.com" in previous.get_data(as_text=True)


def test_previous_batch_at_zero_is_rejected(client) -> None:
    response = client.post("/previous", data=VALID_FORM)
    assert response.status_code == 400
    assert "There is no previous batch before batch 0" in response.get_data(as_text=True)


def test_generation_validation_errors_are_visible(client) -> None:
    cases = [
        ({"locale": "fr_FR"}, "Unsupported locale"),
        ({"seed": "-1"}, "digits only"),
        ({"batch_index": "1000001"}, "at most"),
        ({"batch_size": "0"}, "at least 1"),
        ({"batch_size": "101"}, "at most 100"),
    ]
    for change, message in cases:
        response = client.post("/generate", data={**VALID_FORM, **change})
        assert response.status_code == 400, change
        text = response.get_data(as_text=True)
        assert message in text
        assert "Generate batch" in text


def test_api_returns_generated_rows_and_metadata(client) -> None:
    response = client.get(
        "/api/users?locale=de_DE&seed=42&batch_index=0&batch_size=3"
    )
    assert response.status_code == 200
    payload = response.json
    assert payload["locale"] == "de_DE"
    assert payload["seed"] == 42
    assert payload["batch_size"] == 3
    assert len(payload["users"]) == 3
    assert payload["meta"]["count"] == 3
    assert payload["meta"]["duration_ms"] >= 0
    assert payload["users"][0]["email"].endswith(
        ("@example.com", "@example.net", "@example.org")
    )
    assert isinstance(payload["users"][0]["height_cm"], float)
    assert isinstance(payload["users"][0]["latitude"], float)
    assert "disclaimer" in payload
    assert response.headers["Cache-Control"] == "no-store"


def test_api_validation_and_maximum_batch_size(client) -> None:
    bad = client.get("/api/users?locale=nope&seed=1&batch_index=0&batch_size=1")
    assert bad.status_code == 400
    assert bad.json["error"]["code"] == "validation_error"
    assert "locale" in bad.json["error"]["fields"]

    too_large = client.get("/api/users?locale=en_US&seed=1&batch_index=0&batch_size=101")
    assert too_large.status_code == 400
    assert "batch_size" in too_large.json["error"]["fields"]

    injection = client.get("/api/users?locale=en_US&seed=1%3BDROP+TABLE+sul.locales&batch_index=0&batch_size=1")
    assert injection.status_code == 400
    assert injection.json["error"]["code"] == "validation_error"


def test_not_found_page_and_security_headers(client) -> None:
    response = client.get("/does-not-exist")
    assert response.status_code == 404
    assert "Page not found" in response.get_data(as_text=True)
    assert response.headers["X-Content-Type-Options"] == "nosniff"
    assert response.headers["X-Frame-Options"] == "DENY"
    assert "default-src 'self'" in response.headers["Content-Security-Policy"]


def test_database_failure_is_graceful_and_does_not_leak() -> None:
    application = create_app(
        {
            "TESTING": True,
            "DATABASE_URL": "postgresql://sul:topsecret@127.0.0.1:1/missing",
            "SECRET_KEY": "test",
            "DB_CONNECT_TIMEOUT": 1,
            "DB_STATEMENT_TIMEOUT_MS": 5_000,
        }
    )
    test_client = application.test_client()

    response = test_client.post("/generate", data=VALID_FORM)
    text = response.get_data(as_text=True)
    assert response.status_code == 503
    assert "temporarily unavailable" in text
    assert "Traceback" not in text
    assert "topsecret" not in text
    assert "psycopg" not in text

    health = test_client.get("/health")
    assert health.status_code == 503
    assert health.json["status"] == "degraded"
    assert health.json["database"]["status"] == "unavailable"
    assert "topsecret" not in health.get_data(as_text=True)

    api = test_client.get("/api/users?locale=en_US&seed=1&batch_index=0&batch_size=1")
    assert api.status_code == 503
    assert api.json["error"]["code"] == "database_unavailable"
    assert "topsecret" not in api.get_data(as_text=True)
