from tests.conftest import auth_headers, signup


async def test_refresh_rotation_and_reuse_detection(client):
    tokens = await signup(client)
    refresh1 = tokens["refresh_token"]

    # 정상 회전
    res = await client.post("/auth/refresh", json={"refresh_token": refresh1})
    assert res.status_code == 200
    rotated = res.json()
    assert rotated["refresh_token"] != refresh1

    # 이미 사용한 refresh 재사용 → 재사용 감지 + 패밀리 폐기
    res = await client.post("/auth/refresh", json={"refresh_token": refresh1})
    assert res.status_code == 401
    assert res.json()["code"] == "AUTH_REFRESH_REUSED"

    # 폐기된 패밀리의 회전본도 더 이상 쓸 수 없다
    res = await client.post("/auth/refresh", json={"refresh_token": rotated["refresh_token"]})
    assert res.status_code == 401

    # 폐기된 세션의 access 토큰도 거부된다
    res = await client.get("/users/me", headers=auth_headers(rotated))
    assert res.status_code == 401


async def test_login_and_me(client):
    tokens = await signup(client, email="login-test@example.com")
    res = await client.post(
        "/auth/login", json={"email": "login-test@example.com", "password": "password123"}
    )
    assert res.status_code == 200

    res = await client.post(
        "/auth/login", json={"email": "login-test@example.com", "password": "wrong-password"}
    )
    assert res.status_code == 401
    assert res.json()["code"] == "AUTH_INVALID_CREDENTIALS"

    res = await client.get("/users/me", headers=auth_headers(tokens))
    assert res.status_code == 200
    assert res.json()["email"] == "login-test@example.com"


async def test_logout_revokes_session(client):
    tokens = await signup(client)
    res = await client.post(
        "/auth/logout",
        json={"refresh_token": tokens["refresh_token"]},
        headers=auth_headers(tokens),
    )
    assert res.status_code == 204
    res = await client.post("/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert res.status_code == 401


async def test_signup_creates_default_plant(client):
    tokens = await signup(client)
    res = await client.get("/plants/me", headers=auth_headers(tokens))
    assert res.status_code == 200
    plant = res.json()["plant"]
    assert plant is not None
    assert plant["stage"] == 1
    assert plant["species"]["code"] == "basic_sprout"


async def test_login_rate_limit_counts_failures_only(client, monkeypatch):
    from app.core.config import get_settings

    monkeypatch.setenv("LOGIN_RATE_LIMIT_COUNT", "2")
    get_settings.cache_clear()
    try:
        await signup(client, email="rate-limit@example.com")

        # 정상 로그인을 여러 번 해도 자체로는 제한 횟수를 소진하지 않는다.
        for _ in range(3):
            response = await client.post(
                "/auth/login",
                json={"email": "rate-limit@example.com", "password": "password123"},
            )
            assert response.status_code == 200

        for _ in range(2):
            response = await client.post(
                "/auth/login",
                json={"email": "rate-limit@example.com", "password": "wrong-password"},
            )
            assert response.status_code == 401
        blocked = await client.post(
            "/auth/login",
            json={"email": "rate-limit@example.com", "password": "password123"},
        )
        assert blocked.status_code == 429
        assert blocked.json()["code"] == "RATE_LIMITED"
    finally:
        monkeypatch.delenv("LOGIN_RATE_LIMIT_COUNT", raising=False)
        get_settings.cache_clear()


async def test_signup_normalizes_visible_names(client):
    invalid = await client.post(
        "/auth/signup",
        json={"email": "blank-name@example.com", "password": "password123", "nickname": "   "},
    )
    assert invalid.status_code == 422

    created = await client.post(
        "/auth/signup",
        json={"email": "trim-name@example.com", "password": "password123", "nickname": "  새싹이  "},
    )
    assert created.status_code == 201
    assert created.json()["user"]["nickname"] == "새싹이"
