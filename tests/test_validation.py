"""Input validation unit tests that do not require PostgreSQL."""

from __future__ import annotations

import pytest

from app.validation import GenerationRequest, ValidationError, validate_generation_request


def test_valid_request_is_normalised() -> None:
    request = validate_generation_request(
        {
            "locale": "en_US",
            "seed": " 42 ",
            "batch_index": "0",
            "batch_size": "10",
        },
        allowed_locales={"en_US", "de_DE"},
        max_batch_size=100,
    )
    assert request == GenerationRequest(
        locale="en_US", seed=42, batch_index=0, batch_size=10
    )


@pytest.mark.parametrize(
    ("field", "value", "message_fragment"),
    [
        ("locale", "fr_FR", "Unsupported locale"),
        ("locale", "", "Choose a locale"),
        ("seed", "-1", "digits only"),
        ("seed", "1.5", "digits only"),
        ("seed", "9223372036854775808", "at most"),
        ("batch_index", "-1", "digits only"),
        ("batch_index", "1000001", "at most"),
        ("batch_size", "0", "at least 1"),
        ("batch_size", "101", "at most 100"),
    ],
)
def test_invalid_fields_are_rejected(
    field: str, value: str, message_fragment: str
) -> None:
    values = {
        "locale": "en_US",
        "seed": "42",
        "batch_index": "0",
        "batch_size": "10",
    }
    values[field] = value
    with pytest.raises(ValidationError) as exc_info:
        validate_generation_request(
            values,
            allowed_locales={"en_US", "de_DE"},
            max_batch_size=100,
        )
    assert message_fragment in exc_info.value.errors[field]


def test_all_missing_fields_report_errors() -> None:
    with pytest.raises(ValidationError) as exc_info:
        validate_generation_request(
            {},
            allowed_locales={"en_US"},
            max_batch_size=100,
        )
    assert set(exc_info.value.errors) == {
        "locale",
        "seed",
        "batch_index",
        "batch_size",
    }
