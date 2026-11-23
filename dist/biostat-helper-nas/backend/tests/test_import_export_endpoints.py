"""End-to-end smoke test: boots the real FastAPI app (app.main) against a
throwaway SQLite DB and exercises GET /api/v1/gtd/export and POST
/api/v1/gtd/import through the HTTP + auth layer — proving the endpoints are
registered, authenticated, and functional, not just the crud functions.

The app's database dependency is overridden so this test never touches the
working tree's persistent database.
"""
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.db.database import Base, get_db


def test_gtd_import_export_endpoints(tmp_path):
    from app.main import app

    # conftest imports the database module before this test runs, so changing
    # DATABASE_URL here would leave the app bound to the shared local DB.
    # Override only this test's dependency with an isolated SQLite database.
    engine = create_engine(
        f"sqlite:///{tmp_path / 'smoke.db'}",
        connect_args={"check_same_thread": False},
    )
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)

    def override_get_db():
        db = Session()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    client = TestClient(app)

    try:
        # Route is mounted + auth applied: unauthenticated access is rejected.
        assert client.get("/api/v1/gtd/export").status_code in (401, 403)

        # Register + login.
        r = client.post("/api/v1/auth/register", json={
            "username": "smoke", "email": "smoke@example.com", "password": "secret123",
        })
        assert r.status_code in (200, 201), r.text
        r = client.post("/api/v1/auth/login",
                        json={"username": "smoke", "password": "secret123"})
        assert r.status_code == 200, r.text
        token = r.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        # Fresh export is an empty-but-valid backup.
        r = client.get("/api/v1/gtd/export", headers=headers)
        assert r.status_code == 200, r.text
        doc = r.json()
        assert doc["projects"] == [] and doc["inbox"] == []

        # Merge-import a small backup carrying a project/todo/attachment/filter.
        payload = {
            "app": "biostat-helper", "kind": "gtd-backup", "version": 1,
            "exported_at": "2026-09-21T00:00:00",
            "saved_filters": [{"name": "f1", "criteria": {"status": "next"}}],
            "inbox": [{"title": "inj", "status": "inbox"}],
            "projects": [{
                "name": "P1", "project_type": "other", "phases": [], "members": [],
                "todos": [{"title": "T1", "status": "next",
                           "attachments": [{"filename": "a.txt",
                                            "content_type": "text/plain",
                                            "content_base64": "aGk="}]}],
            }],
        }
        r = client.post("/api/v1/gtd/import?mode=merge", json=payload, headers=headers)
        assert r.status_code == 200, r.text
        imported = r.json()["imported"]
        assert imported["projects"] == 1
        assert imported["inbox"] == 1
        assert imported["attachments"] == 1
        assert imported["saved_filters"] == 1

        # Export reflects the imported data (round-trip through HTTP).
        r = client.get("/api/v1/gtd/export", headers=headers)
        doc = r.json()
        assert len(doc["projects"]) == 1
        assert doc["projects"][0]["todos"][0]["attachments"][0]["content_base64"] == "aGk="
        assert len(doc["inbox"]) == 1

        # A malformed/foreign doc is a clean 400 (structural validation), not a 500.
        r = client.post("/api/v1/gtd/import?mode=merge",
                        json={"app": "other", "kind": "x"},
                        headers=headers)
        assert r.status_code == 400, r.text

        # Replace-import of an empty backup wipes the user's GTD data.
        r = client.post("/api/v1/gtd/import?mode=replace", json={
            "app": "biostat-helper", "kind": "gtd-backup", "version": 1,
            "exported_at": "2026-09-21T00:00:00",
            "saved_filters": [], "inbox": [], "projects": [],
        }, headers=headers)
        assert r.status_code == 200, r.text
        r = client.get("/api/v1/gtd/export", headers=headers)
        assert r.json()["projects"] == [] and r.json()["inbox"] == []
    finally:
        app.dependency_overrides.pop(get_db, None)
        engine.dispose()
