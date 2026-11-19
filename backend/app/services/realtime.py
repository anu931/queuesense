"""WebSocket rooms: one room per service. Used to push live queue updates."""
from fastapi import WebSocket


class ConnectionManager:
    def __init__(self):
        self.rooms: dict[int, set[WebSocket]] = {}

    async def connect(self, service_id: int, ws: WebSocket):
        await ws.accept()
        self.rooms.setdefault(service_id, set()).add(ws)

    def disconnect(self, service_id: int, ws: WebSocket):
        self.rooms.get(service_id, set()).discard(ws)

    async def broadcast(self, service_id: int, message: dict):
        for ws in list(self.rooms.get(service_id, [])):
            try:
                await ws.send_json(message)
            except Exception:
                self.disconnect(service_id, ws)
                
    async def close_room(self, service_id: int, message: dict):
        """Tell everyone in the room, then close their sockets (used when a service is deleted)."""
        for ws in list(self.rooms.pop(service_id, [])):
            try:
                await ws.send_json(message)
                await ws.close()
            except Exception:
                pass

manager = ConnectionManager()