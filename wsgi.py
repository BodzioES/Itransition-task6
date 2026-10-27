"""WSGI entry point used by Gunicorn and production hosts."""

from app import create_app

app = create_app()
