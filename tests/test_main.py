"""Pruebas de la API. La base y CloudWatch se sustituyen: no hace falta AWS."""

import main


class FakeCursor:
    def __init__(self, store):
        self.store = store
        self.lastrowid = 0
        self._rows = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def execute(self, sql, params=None):
        normalized = " ".join(sql.split()).lower()
        if normalized.startswith("create table"):
            return
        if normalized.startswith("select 1"):
            self._rows = [{"ok": 1}]
            return
        if normalized.startswith("select"):
            self._rows = [dict(row) for row in self.store]
            return
        if normalized.startswith("insert"):
            title, done = params
            self.lastrowid = (self.store[-1]["id"] if self.store else 0) + 1
            self.store.append(
                {"id": self.lastrowid, "title": title, "done": int(done)}
            )
            return
        raise AssertionError(sql)

    def fetchall(self):
        return list(self._rows)


class FakeConn:
    def __init__(self, store):
        self.store = store

    def cursor(self):
        return FakeCursor(self.store)

    def close(self):
        return None


def client_with_db(monkeypatch, store=None, fail=False):
    store = [] if store is None else store
    metrics = []

    def connect():
        if fail:
            raise ConnectionError("rds unavailable")
        return FakeConn(store)

    monkeypatch.setattr(main, "connect", connect)
    monkeypatch.setattr(main, "put_metric", lambda name, value=1: metrics.append(name))
    monkeypatch.setenv("APP_VERSION", "v1.2.0")
    return main.app.test_client(), store, metrics


def test_post_and_get_tasks(monkeypatch):
    client, store, metrics = client_with_db(monkeypatch)

    created = client.post(
        "/tasks",
        json={"title": "estudiar para el examen", "done": False},
    )
    assert created.status_code == 201
    body = created.get_json()
    assert body == {"id": 1, "title": "estudiar para el examen", "done": False}
    assert store[0]["title"] == "estudiar para el examen"
    assert metrics == ["TasksCreated"]

    listed = client.get("/tasks")
    assert listed.status_code == 200
    assert listed.get_json() == [body]


def test_post_requires_title(monkeypatch):
    client, store, metrics = client_with_db(monkeypatch)

    missing = client.post("/tasks", json={"done": False})
    blank = client.post("/tasks", json={"title": "   "})

    assert missing.status_code == 400
    assert missing.get_json()["error"] == "title is required"
    assert blank.status_code == 400
    assert store == []
    assert metrics == []


def test_version_reads_environment(monkeypatch):
    client, _, _ = client_with_db(monkeypatch)

    response = client.get("/version")

    assert response.status_code == 200
    assert response.get_json() == {"version": "v1.2.0"}


def test_health_ok_and_fail(monkeypatch):
    client, _, metrics = client_with_db(monkeypatch)

    ok = client.get("/health")
    payload = ok.get_json()
    assert ok.status_code == 200
    assert payload["status"] == "OK"
    assert payload["version"] == "v1.2.0"
    assert payload["timestamp"].endswith("Z")
    assert metrics == []

    failing, _, fail_metrics = client_with_db(monkeypatch, fail=True)
    failed = failing.get("/health")
    assert failed.status_code == 200
    assert failed.get_json()["status"] == "FAIL"
    assert fail_metrics == ["RDSErrors"]


def test_database_error_on_write(monkeypatch):
    client, _, metrics = client_with_db(monkeypatch, fail=True)

    response = client.post("/tasks", json={"title": "no llega a rds", "done": False})

    assert response.status_code == 503
    assert metrics == ["RDSErrors"]
