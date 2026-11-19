"""API tests. Run from the backend folder:  python -m pytest -q
Uses a throwaway SQLite database, never your Neon data."""
import os
import tempfile

_tmp = tempfile.mkdtemp()
os.environ["DATABASE_URL"] = f"sqlite:///{_tmp}/test.db"
os.environ["SECRET_KEY"] = "test-secret"
os.environ["ADMIN_USERNAME"] = "admin"
os.environ["ADMIN_PASSWORD"] = "pass12345"

import pytest
from fastapi.testclient import TestClient

from app.api import routes_auth
from app.core import security
from app.main import app


@pytest.fixture()
def client():
    routes_auth._failures.clear()
    with TestClient(app) as c:
        yield c


@pytest.fixture()
def staff(client):
    r = client.post("/auth/login", json={"username": "admin", "password": "pass12345"})
    assert r.status_code == 200
    return {"Authorization": f"Bearer {r.json()['token']}"}


def new_service(client, staff, name="Billing"):
    r = client.post("/services", json={"name": name}, headers=staff)
    assert r.status_code == 201
    return r.json()["id"]


def test_staff_routes_need_login(client):
    assert client.post("/services", json={"name": "X"}).status_code == 401
    assert client.post("/services/1/call-next").status_code == 401
    assert client.get("/services/1/analytics").status_code == 401
    assert client.post("/tickets/1/skip").status_code == 401


def test_bad_token_rejected(client):
    r = client.post("/services", json={"name": "X"}, headers={"Authorization": "Bearer nope"})
    assert r.status_code == 401


def test_expired_token_rejected(client):
    old = security.create_token("admin", ttl_seconds=-10)
    r = client.post("/services", json={"name": "X"}, headers={"Authorization": f"Bearer {old}"})
    assert r.status_code == 401


def test_wrong_password_and_lockout(client):
    for _ in range(5):
        assert client.post("/auth/login", json={"username": "admin", "password": "bad"}).status_code == 401
    assert client.post("/auth/login", json={"username": "admin", "password": "pass12345"}).status_code == 429


def test_customer_flow_needs_no_login(client, staff):
    sid = new_service(client, staff)
    t1 = client.post("/tickets", json={"service_id": sid}).json()
    t2 = client.post("/tickets", json={"service_id": sid}).json()
    assert (t1["number"], t2["number"]) == (1, 2) and t1["key"]
    q = client.get(f"/services/{sid}/queue").json()
    assert [w["position"] for w in q["waiting"]] == [1, 2]
    assert client.get(f"/tickets/{t1['id']}").json()["status"] == "waiting"


def test_cancel_requires_own_key(client, staff):
    sid = new_service(client, staff)
    t = client.post("/tickets", json={"service_id": sid}).json()
    assert client.post(f"/tickets/{t['id']}/cancel", json={"key": "wrong"}).status_code == 403
    r = client.post(f"/tickets/{t['id']}/cancel", json={"key": t["key"]})
    assert r.status_code == 200 and r.json()["status"] == "cancelled"


def test_call_next_skip_complete(client, staff):
    sid = new_service(client, staff)
    a = client.post("/tickets", json={"service_id": sid}).json()
    b = client.post("/tickets", json={"service_id": sid}).json()
    assert client.post(f"/services/{sid}/call-next", headers=staff).json() == {"called": 1}
    q = client.get(f"/services/{sid}/queue").json()
    assert q["now_serving"] == 1 and q["serving_id"] == a["id"] and len(q["waiting"]) == 1
    assert client.post(f"/tickets/{a['id']}/complete", headers=staff).json()["status"] == "done"
    assert client.post(f"/tickets/{b['id']}/complete", headers=staff).status_code == 409
    assert client.post(f"/tickets/{b['id']}/skip", headers=staff).json()["status"] == "skipped"
    assert client.post(f"/services/{sid}/call-next", headers=staff).json() == {"called": None}


def test_unknown_ids(client, staff):
    assert client.get("/tickets/9999").status_code == 404
    assert client.post("/tickets", json={"service_id": 9999}).status_code == 404
    assert client.get("/services/9999/analytics", headers=staff).status_code == 404


def test_websocket_pushes_live_updates(client, staff):
    sid = new_service(client, staff)
    with client.websocket_connect(f"/ws/{sid}") as ws:
        assert ws.receive_json()["waiting"] == []
        t = client.post("/tickets", json={"service_id": sid}).json()
        assert ws.receive_json()["waiting"][0]["id"] == t["id"]
        client.post(f"/services/{sid}/call-next", headers=staff)
        msg = ws.receive_json()
        assert msg["now_serving"] == 1 and msg["serving_id"] == t["id"]


def test_analytics_shape(client, staff):
    sid = new_service(client, staff)
    data = client.get(f"/services/{sid}/analytics", headers=staff).json()
    assert len(data["by_hour"]) == 24 and len(data["wait_by_hour"]) == 24 and data["samples"] == 0