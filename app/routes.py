"""HTTP routes: validation, database invocation and presentation only."""

from __future__ import annotations

import time
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any

from flask import Blueprint, Response, current_app, jsonify, render_template, request

from .db import Database, DatabaseQueryError, DatabaseUnavailable
from .validation import (
    MAX_BATCH_INDEX,
    GenerationRequest,
    ValidationError,
    validate_generation_request,
)

bp = Blueprint("main", __name__)

DB_ERROR_MESSAGE = (
    "The generator database is unavailable or has not been initialised. "
    "Check /health and the server logs, then try again."
)


def _database() -> Database:
    return current_app.extensions["sul_database"]


def _locales() -> tuple[list[dict[str, Any]], str | None]:
    try:
        return _database().list_locales(), None
    except (DatabaseUnavailable, DatabaseQueryError):
        current_app.logger.exception("Unable to load locale metadata")
        return [], DB_ERROR_MESSAGE


def _default_form() -> dict[str, str]:
    return {
        "locale": current_app.config["DEFAULT_LOCALE"],
        "seed": str(current_app.config["DEFAULT_SEED"]),
        "batch_index": "0",
        "batch_size": str(min(10, current_app.config["WEB_MAX_BATCH_SIZE"])),
    }


def _posted_form() -> dict[str, str]:
    return {
        field: str(request.form.get(field, "")).strip()
        for field in ("locale", "seed", "batch_index", "batch_size")
    }


def _render_dashboard(
    *,
    locales: list[dict[str, Any]],
    form: dict[str, str],
    users: list[dict[str, Any]] | None = None,
    meta: dict[str, Any] | None = None,
    errors: dict[str, str] | None = None,
    general_error: str | None = None,
    status: int = 200,
) -> tuple[str, int] | Response:
    return (
        render_template(
            "index.html",
            active_page="generator",
            locales=locales,
            form=form,
            users=users,
            meta=meta,
            errors=errors or {},
            general_error=general_error,
            can_previous=bool(meta and meta["batch_index"] > 0),
            can_next=bool(meta and meta["batch_index"] < MAX_BATCH_INDEX),
        ),
        status,
    )


def _request_from_form(
    form: dict[str, str], allowed_locales: set[str]
) -> GenerationRequest:
    return validate_generation_request(
        form,
        allowed_locales=allowed_locales,
        max_batch_size=current_app.config["WEB_MAX_BATCH_SIZE"],
    )


def _execute_request(
    generation: GenerationRequest,
    locales: list[dict[str, Any]],
) -> tuple[str, int] | Response:
    started = time.perf_counter()
    try:
        users = _database().generate_users(
            generation.locale,
            generation.seed,
            generation.batch_index,
            generation.batch_size,
        )
    except (DatabaseUnavailable, DatabaseQueryError):
        current_app.logger.exception(
            "Generation failed for locale=%s seed=%s batch=%s size=%s",
            generation.locale,
            generation.seed,
            generation.batch_index,
            generation.batch_size,
        )
        return _render_dashboard(
            locales=locales,
            form={
                "locale": generation.locale,
                "seed": str(generation.seed),
                "batch_index": str(generation.batch_index),
                "batch_size": str(generation.batch_size),
            },
            general_error=DB_ERROR_MESSAGE,
            status=503,
        )

    elapsed = max(time.perf_counter() - started, 1e-9)
    meta = {
        "locale": generation.locale,
        "seed": generation.seed,
        "batch_index": generation.batch_index,
        "batch_size": generation.batch_size,
        "count": len(users),
        "duration_ms": elapsed * 1000.0,
        "users_per_second": len(users) / elapsed,
    }
    return _render_dashboard(
        locales=locales,
        form={
            "locale": generation.locale,
            "seed": str(generation.seed),
            "batch_index": str(generation.batch_index),
            "batch_size": str(generation.batch_size),
        },
        users=users,
        meta=meta,
    )


@bp.get("/")
def index() -> tuple[str, int] | Response:
    locales, error = _locales()
    return _render_dashboard(
        locales=locales,
        form=_default_form(),
        general_error=error,
        status=200,
    )


@bp.post("/generate")
def generate() -> tuple[str, int] | Response:
    locales, database_error = _locales()
    form = _posted_form()
    if database_error:
        return _render_dashboard(
            locales=locales,
            form=form,
            general_error=database_error,
            status=503,
        )

    try:
        generation = _request_from_form(form, {item["locale_code"] for item in locales})
    except ValidationError as exc:
        return _render_dashboard(
            locales=locales,
            form=form,
            errors=exc.errors,
            status=400,
        )

    return _execute_request(generation, locales)


def _navigate(delta: int) -> tuple[str, int] | Response:
    locales, database_error = _locales()
    form = _posted_form()
    if database_error:
        return _render_dashboard(
            locales=locales,
            form=form,
            general_error=database_error,
            status=503,
        )

    try:
        current = _request_from_form(form, {item["locale_code"] for item in locales})
    except ValidationError as exc:
        return _render_dashboard(
            locales=locales,
            form=form,
            errors=exc.errors,
            status=400,
        )

    new_index = current.batch_index + delta
    if new_index < 0:
        errors = {"batch_index": "There is no previous batch before batch 0."}
    elif new_index > MAX_BATCH_INDEX:
        errors = {"batch_index": f"Batch index cannot exceed {MAX_BATCH_INDEX:,}."}
    else:
        errors = {}

    if errors:
        return _render_dashboard(
            locales=locales,
            form=form,
            errors=errors,
            status=400,
        )

    return _execute_request(
        GenerationRequest(
            locale=current.locale,
            seed=current.seed,
            batch_index=new_index,
            batch_size=current.batch_size,
        ),
        locales,
    )


@bp.post("/next")
def next_batch() -> tuple[str, int] | Response:
    return _navigate(1)


@bp.post("/previous")
def previous_batch() -> tuple[str, int] | Response:
    return _navigate(-1)


@bp.get("/api/users")
def api_users() -> tuple[Response, int] | Response:
    locales, database_error = _locales()
    if database_error:
        return (
            jsonify(
                error={
                    "code": "database_unavailable",
                    "message": "The generator database is unavailable.",
                }
            ),
            503,
        )

    default_size = min(
        current_app.config["DEFAULT_BATCH_SIZE"],
        current_app.config["WEB_MAX_BATCH_SIZE"],
    )
    values = {
        "locale": request.args.get("locale", current_app.config["DEFAULT_LOCALE"]),
        "seed": request.args.get("seed", str(current_app.config["DEFAULT_SEED"])),
        "batch_index": request.args.get("batch_index", "0"),
        "batch_size": request.args.get("batch_size", str(default_size)),
    }
    try:
        generation = _request_from_form(
            {key: str(value) for key, value in values.items()},
            {item["locale_code"] for item in locales},
        )
    except ValidationError as exc:
        return (
            jsonify(
                error={
                    "code": "validation_error",
                    "message": "Invalid generation parameters.",
                    "fields": exc.errors,
                }
            ),
            400,
        )

    started = time.perf_counter()
    try:
        users = _database().generate_users(
            generation.locale,
            generation.seed,
            generation.batch_index,
            generation.batch_size,
        )
    except (DatabaseUnavailable, DatabaseQueryError):
        current_app.logger.exception("API generation failed")
        return (
            jsonify(
                error={
                    "code": "database_error",
                    "message": "The generator database could not complete the request.",
                }
            ),
            503,
        )

    elapsed = max(time.perf_counter() - started, 1e-9)
    payload = {
        "locale": generation.locale,
        "seed": generation.seed,
        "batch_index": generation.batch_index,
        "batch_size": generation.batch_size,
        "users": [_json_row(row) for row in users],
        "meta": {
            "count": len(users),
            "duration_ms": round(elapsed * 1000.0, 3),
            "users_per_second": round(len(users) / elapsed, 3),
            "measurement": "database call plus row transfer to Python",
            "generated_at": datetime.now(timezone.utc).isoformat(),
        },
        "disclaimer": (
            "Synthetic data only. Emails use RFC 2606 example domains and "
            "coordinates are independent of the generated address."
        ),
    }
    response = jsonify(payload)
    response.headers["Cache-Control"] = "no-store"
    return response


def _json_row(row: dict[str, Any]) -> dict[str, Any]:
    return {
        key: float(value) if isinstance(value, Decimal) else value
        for key, value in row.items()
    }


@bp.get("/health")
def health() -> tuple[Response, int]:
    database_status = _database().health()
    healthy = database_status.get("status") == "ok"
    payload = {
        "status": "ok" if healthy else "degraded",
        "service": "synthetic-user-lab",
        "version": current_app.config["APP_VERSION"],
        "database": database_status,
    }
    response = jsonify(payload)
    response.headers["Cache-Control"] = "no-store"
    return response, (200 if healthy else 503)


@bp.get("/docs")
def docs() -> str:
    return render_template(
        "docs.html",
        active_page="docs",
        page_title="SQL library guide",
    )


@bp.after_app_request
def add_security_headers(response: Response) -> Response:
    response.headers.setdefault("X-Content-Type-Options", "nosniff")
    response.headers.setdefault("X-Frame-Options", "DENY")
    response.headers.setdefault("Referrer-Policy", "strict-origin-when-cross-origin")
    response.headers.setdefault(
        "Content-Security-Policy",
        "default-src 'self'; img-src 'self' data:; style-src 'self'; "
        "script-src 'self'; connect-src 'self'; base-uri 'self'; "
        "form-action 'self'; frame-ancestors 'none'",
    )
    if request.path.startswith("/api/") or request.method == "POST":
        response.headers.setdefault("Cache-Control", "no-store")
    if request.is_secure:
        response.headers.setdefault(
            "Strict-Transport-Security", "max-age=31536000; includeSubDomains"
        )
    return response
