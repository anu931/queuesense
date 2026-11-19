"""Manager analytics: average wait, busiest hour, service-time trend."""
from collections import defaultdict
from datetime import datetime, timedelta

from app.database import models


def service_analytics(db, service_id: int) -> dict:
    since = datetime.now() - timedelta(days=14)
    rows = (
        db.query(models.Ticket)
        .filter(
            models.Ticket.service_id == service_id,
            models.Ticket.status == "done",
            models.Ticket.called_at.isnot(None),
            models.Ticket.completed_at.isnot(None),
            models.Ticket.called_at >= since,
        )
        .all()
    )
    waits, services = [], []
    served_by_hour = [0] * 24
    wait_hours = defaultdict(list)
    by_day = defaultdict(list)
    for t in rows:
        svc = (t.completed_at - t.called_at).total_seconds()
        if not (10 <= svc <= 1800):
            continue
        services.append(svc)
        served_by_hour[t.called_at.hour] += 1
        by_day[t.called_at.date()].append(svc)
        if t.created_at:
            w = (t.called_at - t.created_at).total_seconds()
            if 0 <= w <= 7200:
                waits.append(w)
                wait_hours[t.called_at.hour].append(w)

    def avg_min(xs):
        return round(sum(xs) / len(xs) / 60, 1) if xs else 0

    wait_by_hour = [avg_min(wait_hours[h]) for h in range(24)]
    days = sorted(by_day)[-7:]
    return {
        "samples": len(services),
        "avg_wait_min": avg_min(waits),
        "avg_service_min": avg_min(services),
        "peak_hour": max(range(24), key=lambda h: wait_by_hour[h]) if waits else None,
        "by_hour": served_by_hour,
        "wait_by_hour": wait_by_hour,
        "trend": [
            {"day": d.strftime("%d %b"), "avg_service_min": avg_min(by_day[d])}
            for d in days
        ],
    }