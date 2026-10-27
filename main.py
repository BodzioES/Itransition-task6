"""Convenience development entry point.

Production uses Gunicorn: ``gunicorn wsgi:app``. This file is intentionally
small so the assignment architecture stays easy to follow.
"""

from __future__ import annotations

import os

from app import create_app

app = create_app()

if __name__ == "__main__":
    app.run(
        host=os.getenv("HOST", "127.0.0.1"),
        port=int(os.getenv("PORT", "5000")),
        debug=os.getenv("FLASK_DEBUG", "0") == "1",
    )
