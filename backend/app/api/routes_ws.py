from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from app.database import models
from app.database.session import SessionLocal
from app.services import queue_engine
from app.services.realtime import manager

router = APIRouter()


@router.websocket("/ws/{service_id}")
async def ws_queue(ws: WebSocket, service_id: int):
    # Open the DB only for the first snapshot, then release the connection.
    # (Holding a session for the whole socket lifetime would exhaust the pool.)
    with SessionLocal() as db:
        if not db.get(models.Service, service_id):
            await ws.close(code=4404)  # unknown or deleted service
            return
        first = queue_engine.snapshot(db, service_id)
    await manager.connect(service_id, ws)
    await ws.send_json(first)
    try:
        while True:
            await ws.receive_text()  # clients send "ping" to keep the link alive
    except WebSocketDisconnect:
        manager.disconnect(service_id, ws)