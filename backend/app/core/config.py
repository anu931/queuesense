"""All settings come from environment variables (or the .env file)."""
import os

from dotenv import load_dotenv

load_dotenv()


def _normalize_db_url(url: str) -> str:
    """Make 'postgresql://' work with the psycopg2 driver we install."""
    if url.startswith("postgres://"):
        url = "postgresql://" + url[len("postgres://"):]
    if url.startswith("postgresql://"):
        url = "postgresql+psycopg2://" + url[len("postgresql://"):]
    return url


DATABASE_URL = _normalize_db_url(os.getenv("DATABASE_URL", "sqlite:///./queuesense.db"))

_DEV_SECRET = "dev-insecure-secret-change-me"
SECRET_KEY = os.getenv("SECRET_KEY") or _DEV_SECRET
USING_DEV_SECRET = SECRET_KEY == _DEV_SECRET

TOKEN_TTL_HOURS = int(os.getenv("TOKEN_TTL_HOURS", "12"))

# Optional: create the first staff account automatically on startup.
ADMIN_USERNAME = os.getenv("ADMIN_USERNAME")
ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD")