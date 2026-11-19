from pydantic import BaseModel, Field


class LoginIn(BaseModel):
    username: str = Field(min_length=1, max_length=50)
    password: str = Field(min_length=1, max_length=200)


class ServiceIn(BaseModel):
    name: str = Field(min_length=1, max_length=60)


class TicketIn(BaseModel):
    service_id: int
    device_token: str | None = None


class CancelIn(BaseModel):
    key: str