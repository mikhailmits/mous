"""Oxyde ORM configuration."""

from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent

# List of Python modules containing Model classes
MODELS = ["mous.db.models"]

# Database dialect: "postgres", "sqlite", or "mysql"
DIALECT = "sqlite"

# Directory for migration files
MIGRATIONS_DIR = "migrations"

# Database connections
# Keys are connection aliases, values are connection URLs
DATABASES = {
    "default": f"sqlite:///{BASE_DIR / 'data.db'}",
}
