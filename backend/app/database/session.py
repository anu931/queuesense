"""Database connection. Works with SQLite (dev) and PostgreSQL (Neon / local)."""
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

from app.core import config

_url = config.DATABASE_URL
_connect_args = (
    {"check_same_thread": False} if _url.startswith("sqlite") else {"connect_timeout": 10}
)

engine = create_engine(
    _url, connect_args=_connect_args, pool_pre_ping=True, pool_recycle=280
)
SessionLocal = sessionmaker(bind=engine, autoflush=False)
Base = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()