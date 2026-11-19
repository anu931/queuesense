from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.api.deps import current_staff
from app.api.schemas import CancelIn, ServiceIn, TicketIn
from app.core.security import check_ticket_key, ticket_key
from app.database import models
from app.database.session import get_db
from app.services import analytics, queue_engine
from app.services.realtime import manager

router = APIRouter(tags=["queue"])


async def _push(db: Session, service_id: int):
    """Send the fresh queue snapshot to every phone watching this service."""
    await manager.broadcast(service_id, queue_engine.snapshot(db, service_id))


def _ticket_json(t: models.Ticket) -> dict:
    return {"id": t.id, "number": t.number, "service_id": t.service_id, "status": t.status}


# ---------- public (customers) ----------
@router.get("/services")
def list_services(db: Session = Depends(get_db)):
    return queue_engine.services_overview(db)


@router.get("/services/{service_id}/queue")
def get_queue(service_id: int, db: Session = Depends(get_db)):
    return queue_engine.snapshot(db, service_id)


@router.post("/tickets")
async def join_queue(body: TicketIn, db: Session = Depends(get_db)):
    t = queue_engine.join(db, body.service_id, body.device_token)
    await _push(db, t.service_id)
    return {**_ticket_json(t), "key": ticket_key(t.id)}


@router.get("/tickets/{ticket_id}")
def get_ticket(ticket_id: int, db: Session = Depends(get_db)):
    return _ticket_json(queue_engine.get_ticket(db, ticket_id))


@router.post("/tickets/{ticket_id}/cancel")
async def cancel_ticket(ticket_id: int, body: CancelIn, db: Session = Depends(get_db)):
    if not check_ticket_key(ticket_id, body.key):
        raise HTTPException(403, "Not your ticket")
    t = queue_engine.cancel(db, ticket_id)
    await _push(db, t.service_id)
    return _ticket_json(t)


# ---------- staff only ----------
@router.post("/services", status_code=201)
def create_service(
    body: ServiceIn, db: Session = Depends(get_db), _: models.StaffUser = Depends(current_staff)
):
    s = queue_engine.create_service(db, body.name.strip())
    return {"id": s.id, "name": s.name}

@router.delete("/services/{service_id}")
async def delete_service(
    service_id: int,
    force: bool = False,
    db: Session = Depends(get_db),
    _: models.StaffUser = Depends(current_staff),
):
    queue_engine.delete_service(db, service_id, force)
    await manager.close_room(service_id, {"type": "service_deleted", "service_id": service_id})
    return {"deleted": service_id}

@router.post("/services/{service_id}/call-next")
async def call_next(
    service_id: int, db: Session = Depends(get_db), _: models.StaffUser = Depends(current_staff)
):
    nxt = queue_engine.call_next(db, service_id)
    await _push(db, service_id)
    return {"called": nxt.number if nxt else None}


@router.post("/tickets/{ticket_id}/skip")
async def skip_ticket(
    ticket_id: int, db: Session = Depends(get_db), _: models.StaffUser = Depends(current_staff)
):
    t = queue_engine.skip(db, ticket_id)
    await _push(db, t.service_id)
    return _ticket_json(t)


@router.post("/tickets/{ticket_id}/complete")
async def complete_ticket(
    ticket_id: int, db: Session = Depends(get_db), _: models.StaffUser = Depends(current_staff)
):
    t = queue_engine.complete(db, ticket_id)
    await _push(db, t.service_id)
    return _ticket_json(t)


@router.get("/services/{service_id}/analytics")
def service_analytics(
    service_id: int, db: Session = Depends(get_db), _: models.StaffUser = Depends(current_staff)
):
    if not db.get(models.Service, service_id):
        raise HTTPException(404, "Service not found")
    return analytics.service_analytics(db, service_id)