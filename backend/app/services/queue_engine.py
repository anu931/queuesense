"""Queue engine: ticket order and status changes. No web code here, only business rules."""
from datetime import datetime

from sqlalchemy import func

from app.database import models
from app.services import prediction


class QueueError(Exception):
    status_code = 400


class NotFound(QueueError):
    status_code = 404


class Conflict(QueueError):
    status_code = 409


def _service(db, service_id: int) -> models.Service:
    s = db.get(models.Service, service_id)
    if not s:
        raise NotFound("Service not found")
    return s


def _ticket(db, ticket_id: int) -> models.Ticket:
    t = db.get(models.Ticket, ticket_id)
    if not t:
        raise NotFound("Ticket not found")
    return t


def create_service(db, name: str) -> models.Service:
    s = models.Service(name=name)
    db.add(s)
    db.commit()
    db.refresh(s)
    return s


def _serving(db, service_id: int):
    return (
        db.query(models.Ticket)
        .filter_by(service_id=service_id, status="serving")
        .order_by(models.Ticket.called_at.desc())
        .first()
    )


def snapshot(db, service_id: int) -> dict:
    """The single source of truth pushed to every connected screen."""
    waiting = (
        db.query(models.Ticket)
        .filter_by(service_id=service_id, status="waiting")
        .order_by(models.Ticket.number)
        .all()
    )
    serving = _serving(db, service_id)
    per_person = prediction.predicted_seconds(db, service_id)
    return {
        "type": "queue_update",
        "service_id": service_id,
        "now_serving": serving.number if serving else None,
        "serving_id": serving.id if serving else None,
        "waiting": [
            {
                "id": t.id,
                "number": t.number,
                "position": i + 1,
                "eta_seconds": int((i + 1) * per_person),
            }
            for i, t in enumerate(waiting)
        ],
    }


def services_overview(db) -> list[dict]:
    out = []
    for s in db.query(models.Service).order_by(models.Service.id).all():
        waiting = (
            db.query(func.count(models.Ticket.id))
            .filter(models.Ticket.service_id == s.id, models.Ticket.status == "waiting")
            .scalar()
            or 0
        )
        serving = _serving(db, s.id)
        out.append(
            {
                "id": s.id,
                "name": s.name,
                "waiting": waiting,
                "now_serving": serving.number if serving else None,
                "minutes_per_person": round(prediction.predicted_seconds(db, s.id) / 60, 1),
            }
        )
    return out


def join(db, service_id: int, device_token: str | None = None) -> models.Ticket:
    _service(db, service_id)
    last = (
        db.query(func.max(models.Ticket.number)).filter_by(service_id=service_id).scalar() or 0
    )
    t = models.Ticket(service_id=service_id, number=last + 1, device_token=device_token)
    db.add(t)
    db.commit()
    db.refresh(t)
    return t


def get_ticket(db, ticket_id: int) -> models.Ticket:
    return _ticket(db, ticket_id)


def call_next(db, service_id: int):
    _service(db, service_id)
    for t in db.query(models.Ticket).filter_by(service_id=service_id, status="serving").all():
        t.status = "done"
        t.completed_at = datetime.now()
    nxt = (
        db.query(models.Ticket)
        .filter_by(service_id=service_id, status="waiting")
        .order_by(models.Ticket.number)
        .first()
    )
    if nxt:
        nxt.status = "serving"
        nxt.called_at = datetime.now()
    db.commit()
    return nxt


def skip(db, ticket_id: int) -> models.Ticket:
    t = _ticket(db, ticket_id)
    if t.status not in ("waiting", "serving"):
        raise Conflict("Ticket is already closed")
    t.status = "skipped"
    db.commit()
    return t


def complete(db, ticket_id: int) -> models.Ticket:
    t = _ticket(db, ticket_id)
    if t.status != "serving":
        raise Conflict("Only the ticket being served can be completed")
    t.status = "done"
    t.completed_at = datetime.now()
    db.commit()
    return t


def cancel(db, ticket_id: int) -> models.Ticket:
    t = _ticket(db, ticket_id)
    if t.status == "waiting":
        t.status = "cancelled"
        db.commit()
    return t

def delete_service(db, service_id: int, force: bool = False) -> None:
    """Remove a service and all its tickets. Refuses while customers are waiting unless forced."""
    _service(db, service_id)
    active = (
        db.query(func.count(models.Ticket.id))
        .filter(
            models.Ticket.service_id == service_id,
            models.Ticket.status.in_(("waiting", "serving")),
        )
        .scalar()
        or 0
    )
    if active and not force:
        raise Conflict(
            f"{active} customer(s) are still in this queue. Clear it first or confirm deletion."
        )
    db.query(models.Ticket).filter_by(service_id=service_id).delete()
    db.query(models.Service).filter_by(id=service_id).delete()
    db.commit()
    prediction.forget(service_id)