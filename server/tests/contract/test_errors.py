from app.api.routers.health import EXPECTED_SCHEMA_REVISION
from app.protect_sensitive_data import PROTECTION_SCHEMA_REVISION
from tests.conftest import auth_headers, signup


async def test_error_envelope_shape(client):
    tokens = await signup(client)
    res = await client.get("/moods/999999", headers=auth_headers(tokens))
    assert res.status_code == 404
    body = res.json()
    assert set(body.keys()) == {"code", "message", "details", "request_id"}
    assert body["code"] == "MOOD_NOT_FOUND"
    assert body["request_id"]


async def test_request_id_echo(client):
    res = await client.get("/health/live", headers={"X-Request-ID": "test-rid-123"})
    assert res.headers["X-Request-ID"] == "test-rid-123"


async def test_api_security_headers(client):
    res = await client.get("/health/live")

    assert res.headers["X-Content-Type-Options"] == "nosniff"
    assert res.headers["X-Frame-Options"] == "DENY"
    assert res.headers["Referrer-Policy"] == "no-referrer"
    assert res.headers["Cache-Control"] == "no-store"


async def test_validation_error_shape(client, user_tokens):
    res = await client.post(
        "/moods", json={"mood_level": 9}, headers=auth_headers(user_tokens, idem=True)
    )
    assert res.status_code == 422
    body = res.json()
    assert body["code"] == "VALIDATION_ERROR"
    assert body["details"]["errors"]


async def test_unauthorized_without_token(client):
    res = await client.get("/users/me")
    assert res.status_code == 401
    assert res.json()["code"] == "AUTH_TOKEN_INVALID"


async def test_ownership_forbidden(client):
    tokens_a = await signup(client)
    tokens_b = await signup(client)
    res = await client.post(
        "/moods", json={"mood_level": 3}, headers=auth_headers(tokens_a, idem=True)
    )
    mood_id = res.json()["mood"]["id"]
    res = await client.get(f"/moods/{mood_id}", headers=auth_headers(tokens_b))
    assert res.status_code == 403
    assert res.json()["code"] == "FORBIDDEN"


async def test_health_ready_shape(client):
    res = await client.get("/health/ready")
    body = res.json()
    assert body["status"] in ("ok", "degraded", "down")
    assert set(body["checks"].keys()) == {
        "database",
        "schema",
        "sensitive_storage",
        "consent_contract",
        "ai_worker",
        "classifier",
        "ollama",
    }


def test_health_tracks_database_head_separately_from_protection_contract():
    assert EXPECTED_SCHEMA_REVISION == "0030_ai_job_ownership"
    assert PROTECTION_SCHEMA_REVISION == "0029_real_data_protection"
