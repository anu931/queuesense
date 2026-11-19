"""App entry point: wires the layers together.

  api/       HTTP + WebSocket routes (thin)
  services/  business logic: queue engine, prediction, analytics, realtime
  database/  engine, session, tables
  core/      settings and security
"""
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from app.api import routes_auth, routes_queue, routes_ws
from app.core import config
from app.core.security import hash_password
from app.database import models
from app.database.session import Base, SessionLocal, engine
from app.services.queue_engine import QueueError


def _bootstrap_admin():
    if not (config.ADMIN_USERNAME and config.ADMIN_PASSWORD):
        return
    with SessionLocal() as db:
        exists = db.query(models.StaffUser).filter_by(username=config.ADMIN_USERNAME).first()
        if not exists:
            db.add(
                models.StaffUser(
                    username=config.ADMIN_USERNAME,
                    password_hash=hash_password(config.ADMIN_PASSWORD),
                )
            )
            db.commit()
            print(f"Created staff account '{config.ADMIN_USERNAME}'")


@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(bind=engine)
    _bootstrap_admin()
    if config.USING_DEV_SECRET:
        print("WARNING: SECRET_KEY is not set. Set it in .env before sharing this server.")
    yield


app = FastAPI(title="QueueSense", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"]
)


@app.exception_handler(QueueError)
async def queue_error_handler(_: Request, exc: QueueError):
    return JSONResponse(status_code=exc.status_code, content={"detail": str(exc)})


@app.get("/health", tags=["meta"])
def health():
    return {"status": "ok"}


app.include_router(routes_auth.router)
app.include_router(routes_queue.router)
app.include_router(routes_ws.router)

# Optional: if you ran `flutter build web`, the backend serves the web app too,
# so one address (http://<laptop-ip>:8000) is enough for phones.
_WEB_DIR = Path(__file__).resolve().parents[2] / "app" / "build" / "web"
if _WEB_DIR.is_dir():
    app.mount("/", StaticFiles(directory=str(_WEB_DIR), html=True), name="web")