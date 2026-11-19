"""Create realistic finished tickets so the AI wait-time estimate has data to learn from.

Run from the backend folder:   python -m scripts.seed_history
Safe to run twice: a service that already has 30+ finished tickets is skipped.
History tickets use number 0, so your live tickets still start at 1.
"""
import random
from datetime import datetime, timedelta

from app.database import models
from app.database.session import Base, SessionLocal, engine

DAYS = 14
PER_DAY = 12
# average seconds to serve one person, by hour (slower at the 11am and 4pm rushes)
PEAK_HOURS = {11: 1.45, 16: 1.35}

BASE_SECONDS = {"doctor": 600, "pharmacy": 150, "billing": 300}


def base_for(service, rng):
    name = service.name.lower()
    for key, value in BASE_SECONDS.items():
        if key in name:
            return value
    return rng.choice([240, 300, 360])

def seed_service(db, service, rng):
    base = base_for(service, rng)   
    made = 0
    for day in range(1, DAYS + 1):
        for _ in range(PER_DAY):
            hour = rng.choice([9, 10, 11, 11, 12, 13, 14, 15, 16, 16, 17])
            called = (datetime.now() - timedelta(days=day)).replace(
                hour=hour, minute=rng.randint(0, 59), second=rng.randint(0, 59), microsecond=0
            )
            weekend = 0.9 if called.weekday() >= 5 else 1.0
            seconds = max(45, min(1500, rng.gauss(base * PEAK_HOURS.get(hour, 1.0) * weekend, 40)))
            db.add(
                models.Ticket(
                    service_id=service.id,
                    number=0,
                    status="done",
                    created_at=called - timedelta(minutes=rng.randint(3, 25)),
                    called_at=called,
                    completed_at=called + timedelta(seconds=seconds),
                )
            )
            made += 1
    return made


def main():
    Base.metadata.create_all(bind=engine)
    rng = random.Random(7)
    with SessionLocal() as db:
        if not db.query(models.Service).count():
            for name in ("Billing", "Registration", "Pharmacy"):
                db.add(models.Service(name=name))
            db.commit()
        for s in db.query(models.Service).order_by(models.Service.id).all():
            done = db.query(models.Ticket).filter_by(service_id=s.id, status="done").count()
            if done >= 30:
                print(f"{s.name}: already has {done} finished tickets, skipped")
                continue
            print(f"{s.name}: added {seed_service(db, s, rng)} history tickets")
        db.commit()


if __name__ == "__main__":
    main()