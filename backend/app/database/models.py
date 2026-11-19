"""Tables. Service and Ticket are unchanged, so your existing Neon data keeps working.
StaffUser is new; create_all adds it automatically on startup."""
from datetime import datetime

from sqlalchemy import Column, DateTime, ForeignKey, Integer, String

from app.database.session import Base


class Service(Base):
    __tablename__ = "services"
    id = Column(Integer, primary_key=True)
    name = Column(String, nullable=False)


class Ticket(Base):
    __tablename__ = "tickets"
    id = Column(Integer, primary_key=True)
    service_id = Column(Integer, ForeignKey("services.id"), index=True)
    number = Column(Integer, nullable=False)            # 1, 2, 3 ... per service
    # waiting | serving | done | skipped | cancelled
    status = Column(String, default="waiting")
    device_token = Column(String, nullable=True)        # reserved for push notifications
    created_at = Column(DateTime, default=datetime.now)
    called_at = Column(DateTime, nullable=True)
    completed_at = Column(DateTime, nullable=True)


class StaffUser(Base):
    __tablename__ = "staff_users"
    id = Column(Integer, primary_key=True)
    username = Column(String, unique=True, nullable=False, index=True)
    password_hash = Column(String, nullable=False)
    created_at = Column(DateTime, default=datetime.now)