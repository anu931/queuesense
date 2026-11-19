"""AI wait-time prediction.

< 3 finished tickets   -> flat default (5 min per person)
3..29 finished tickets -> simple average
>= 30 finished tickets -> scikit-learn RandomForest on (hour, weekday), retrained every 5 min
"""
import time
from datetime import datetime

from app.database import models

DEFAULT_SECONDS = 300
MIN_SAMPLES = 30
RETRAIN_EVERY = 300  # seconds
_cache: dict[int, tuple[float, object, float]] = {}  # service_id -> (time, model, avg)


def _history(db, service_id: int):
    rows = (
        db.query(models.Ticket)
        .filter(
            models.Ticket.service_id == service_id,
            models.Ticket.status == "done",
            models.Ticket.called_at.isnot(None),
            models.Ticket.completed_at.isnot(None),
        )
        .all()
    )
    X, y = [], []
    for t in rows:
        d = (t.completed_at - t.called_at).total_seconds()
        if 10 <= d <= 1800:  # ignore junk outliers
            X.append([t.called_at.hour, t.called_at.weekday()])
            y.append(d)
    return X, y


def _state(db, service_id: int):
    now = time.time()
    cached = _cache.get(service_id)
    if cached and now - cached[0] < RETRAIN_EVERY:
        return cached[1], cached[2]

    X, y = _history(db, service_id)
    avg = sum(y) / len(y) if len(y) >= 3 else DEFAULT_SECONDS
    model = None
    if len(y) >= MIN_SAMPLES:
        try:
            from sklearn.ensemble import RandomForestRegressor

            model = RandomForestRegressor(
                n_estimators=40, min_samples_leaf=3, random_state=0
            ).fit(X, y)
        except ImportError:
            model = None  # scikit-learn missing -> fall back to the average
    _cache[service_id] = (now, model, avg)
    return model, avg


def predicted_seconds(db, service_id: int, when: datetime | None = None) -> float:
    """Predicted service time for ONE person at the given time of day."""
    when = when or datetime.now()
    model, avg = _state(db, service_id)
    if model is None:
        return avg
    try:
        return float(model.predict([[when.hour, when.weekday()]])[0])
    except Exception:
        return avg

def forget(service_id: int) -> None:
    """Drop cached model for a deleted service."""
    _cache.pop(service_id, None)