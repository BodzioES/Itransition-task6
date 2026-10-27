"""HTTP input validation that is independent from user-data generation."""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Mapping

MAX_BATCH_INDEX = 1_000_000
MAX_SEED = 9_223_372_036_854_775_807
_NON_NEGATIVE_INT = re.compile(r"^\d+$")


class ValidationError(ValueError):
    """A user-visible validation failure with per-field messages."""

    def __init__(self, errors: dict[str, str]) -> None:
        super().__init__("Invalid generation parameters.")
        self.errors = errors


@dataclass(frozen=True, slots=True)
class GenerationRequest:
    locale: str
    seed: int
    batch_index: int
    batch_size: int


def _parse_non_negative(
    raw: object,
    *,
    field: str,
    label: str,
    maximum: int,
    minimum: int = 0,
    errors: dict[str, str],
) -> int | None:
    value = "" if raw is None else str(raw).strip()
    if value == "":
        errors[field] = f"{label} is required."
        return None
    if not _NON_NEGATIVE_INT.fullmatch(value):
        errors[field] = f"{label} must be a whole number using digits only."
        return None
    parsed = int(value)
    if parsed < minimum:
        errors[field] = f"{label} must be at least {minimum}."
        return None
    if parsed > maximum:
        errors[field] = f"{label} must be at most {maximum:,}."
        return None
    return parsed


def validate_generation_request(
    values: Mapping[str, object],
    *,
    allowed_locales: set[str],
    max_batch_size: int,
) -> GenerationRequest:
    """Validate and normalise a generation request.

    Args:
        values: Form/query mapping.
        allowed_locales: Locale codes currently present in PostgreSQL.
        max_batch_size: Application-level maximum, itself capped by SQL.

    Raises:
        ValidationError: with one safe message per invalid field.
    """
    errors: dict[str, str] = {}

    locale = str(values.get("locale", "")).strip()
    if not locale:
        errors["locale"] = "Choose a locale."
    elif locale not in allowed_locales:
        choices = ", ".join(sorted(allowed_locales)) or "no locales"
        errors["locale"] = f"Unsupported locale. Available: {choices}."

    seed = _parse_non_negative(
        values.get("seed"),
        field="seed",
        label="Seed",
        maximum=MAX_SEED,
        errors=errors,
    )
    batch_index = _parse_non_negative(
        values.get("batch_index"),
        field="batch_index",
        label="Batch index",
        maximum=MAX_BATCH_INDEX,
        errors=errors,
    )
    batch_size = _parse_non_negative(
        values.get("batch_size"),
        field="batch_size",
        label="Batch size",
        minimum=1,
        maximum=max_batch_size,
        errors=errors,
    )

    if errors:
        raise ValidationError(errors)

    # The branch above guarantees all parsed values are present.
    assert seed is not None and batch_index is not None and batch_size is not None
    return GenerationRequest(
        locale=locale,
        seed=seed,
        batch_index=batch_index,
        batch_size=batch_size,
    )
