"""Application factory for Synthetic User Lab."""

from __future__ import annotations

import logging
import os
import secrets
from decimal import Decimal
from typing import Any

from flask import Flask, jsonify, render_template, request

from .config import load_config
from .db import Database
from .routes import bp
from .validation import MAX_BATCH_INDEX, MAX_SEED


def create_app(test_config: dict[str, Any] | None = None) -> Flask:
    """Create and configure the Flask application.

    Args:
        test_config: Optional mapping that overrides environment-derived
            configuration. Used by pytest and not exposed to end users.
    """
    app = Flask(__name__)

    config = load_config()
    if not config.get("SECRET_KEY"):
        config["SECRET_KEY"] = secrets.token_hex(32)
    app.config.from_mapping(config)

    if test_config:
        app.config.update(test_config)

    _configure_logging(app)

    database = Database(
        dsn=app.config.get("DATABASE_URL"),
        connect_timeout=app.config["DB_CONNECT_TIMEOUT"],
        statement_timeout_ms=app.config["DB_STATEMENT_TIMEOUT_MS"],
    )
    app.extensions["sul_database"] = database
    app.extensions["sul_started_at"] = None

    app.register_blueprint(bp)

    @app.template_filter("coord")
    def format_coord(value: Decimal | float | None) -> str:
        if value is None:
            return "—"
        return f"{float(value):.6f}"

    @app.template_filter("measure")
    def format_measure(value: Decimal | float | None, suffix: str = "") -> str:
        if value is None:
            return "—"
        return f"{float(value):.1f}{suffix}"

    @app.template_filter("thousands")
    def format_thousands(value: Decimal | float | int) -> str:
        return f"{float(value):,.1f}"

    @app.context_processor
    def inject_globals() -> dict[str, Any]:
        return {
            "app_version": app.config["APP_VERSION"],
            "max_batch_size": app.config["WEB_MAX_BATCH_SIZE"],
            "sql_max_batch_size": app.config["SQL_MAX_BATCH_SIZE"],
            "max_batch_index": MAX_BATCH_INDEX,
            "max_seed": MAX_SEED,
        }

    @app.errorhandler(404)
    def not_found(error: Exception):
        if request.path.startswith("/api/"):
            return jsonify(error={"code": "not_found", "message": "Endpoint not found."}), 404
        return render_template(
            "error.html",
            page_title="Page not found",
            heading="Page not found",
            message="That page does not exist. Return to the generator to continue.",
            status_code=404,
        ), 404

    @app.errorhandler(413)
    def payload_too_large(error: Exception):
        if request.path.startswith("/api/"):
            return jsonify(error={"code": "payload_too_large", "message": "Request is too large."}), 413
        return render_template(
            "error.html",
            page_title="Request too large",
            heading="Request too large",
            message="The submitted request exceeded the allowed size.",
            status_code=413,
        ), 413

    @app.errorhandler(500)
    def internal_error(error: Exception):
        app.logger.exception("Unhandled server error")
        if request.path.startswith("/api/"):
            return jsonify(
                error={"code": "internal_error", "message": "An internal error occurred."}
            ), 500
        return render_template(
            "error.html",
            page_title="Unexpected error",
            heading="Unexpected error",
            message="The request could not be completed. Please try again.",
            status_code=500,
        ), 500

    return app


def _configure_logging(app: Flask) -> None:
    level_name = str(app.config.get("LOG_LEVEL", "INFO")).upper()
    level = getattr(logging, level_name, logging.INFO)
    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    app.logger.setLevel(level)
