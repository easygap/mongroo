from datetime import date, timedelta

import sqlalchemy as sa

from app.core.timeutil import utcnow
from app.models.adventure import AdventurePatrol, DungeonRun, UserDungeon
from app.models.expedition import (
    ExpeditionPartyMember,
    ExpeditionRun,
    UserActiveExpedition,
)
from app.models.ops import AiJob
from app.models.plant import Plant
from app.models.user import LoginRateLimit, User
from tests.conftest import auth_headers, signup


async def test_account_export_contains_user_data_but_never_credentials(client):
    tokens = await signup(client, email="export-owner@example.com")
    created = await client.post(
        "/moods",
        json={"content": "내가 직접 확인할 수 있어야 하는 마음 일기 내용입니다." * 2},
        headers=auth_headers(tokens, idem=True),
    )
    assert created.status_code == 201

    response = await client.get("/users/me/export", headers=auth_headers(tokens))

    assert response.status_code == 200
    assert response.headers["content-disposition"] == (
        'attachment; filename="mongroo-account-export.json"'
    )
    body = response.json()
    assert body["format_version"] == 1
    assert body["profile"]["email"] == "export-owner@example.com"
    assert "password_hash" not in body["profile"]
    assert body["data"]["mood_entries"][0]["content"].startswith("내가 직접")
    serialized = response.text.lower()
    assert "refresh_token" not in serialized
    assert "password_hash" not in serialized


async def test_account_delete_requires_password_and_exact_confirmation(client):
    tokens = await signup(client, email="delete-owner@example.com")

    rejected = await client.request(
        "DELETE",
        "/users/me",
        json={"password": "wrong-password", "confirmation": "몽그루 탈퇴"},
        headers=auth_headers(tokens),
    )
    assert rejected.status_code == 422
    assert rejected.json()["code"] == "ACCOUNT_DELETE_CONFIRMATION_INVALID"

    deleted = await client.request(
        "DELETE",
        "/users/me",
        json={"password": "password123", "confirmation": "몽그루 탈퇴"},
        headers=auth_headers(tokens),
    )
    assert deleted.status_code == 204
    assert (
        await client.get("/users/me", headers=auth_headers(tokens))
    ).status_code == 401
    login = await client.post(
        "/auth/login",
        json={"email": "delete-owner@example.com", "password": "password123"},
    )
    assert login.status_code == 401


async def test_account_delete_orders_restricting_plant_history_cleanup(
    client, session_factory
):
    tokens = await signup(client, email="delete-history@example.com")
    user_id = tokens["user"]["id"]
    now = utcnow()
    async with session_factory() as db:
        plant_id = await db.scalar(sa.select(Plant.id).where(Plant.user_id == user_id))
        assert plant_id is not None
        patrol = AdventurePatrol(
            user_id=user_id,
            plant_id=plant_id,
            route_code="garden_edge",
            local_date=date.today(),
            status="active",
            started_at=now,
            returns_at=now + timedelta(minutes=10),
            reward_exp=1,
            reward_seeds=1,
            found_item_code="dew_sample",
            found_quantity=1,
            performance_score=1,
        )
        dungeon = UserDungeon(
            user_id=user_id,
            dungeon_code="test_dungeon",
            discovered_at=now,
        )
        db.add_all([patrol, dungeon])
        await db.flush()
        db.add(
            DungeonRun(
                user_id=user_id,
                plant_id=plant_id,
                user_dungeon_id=dungeon.id,
                local_date=date.today(),
                created_at=now,
                found_item_code="dew_sample",
                performance_score=1,
            )
        )
        expedition = ExpeditionRun(
            user_id=user_id,
            region_code="garden_border",
            mode="tutorial",
            status="active",
            phase="exploring",
            local_date=date.today(),
            content_version="test-v1",
            map_seed="delete-history",
            map_snapshot={},
            run_thread_snapshot={},
            run_memory_snapshot={},
            spotlight_snapshot=[],
            runtime_effects_snapshot={},
            current_node_code="home",
        )
        db.add(expedition)
        await db.flush()
        db.add_all(
            [
                ExpeditionPartyMember(
                    run_id=expedition.id,
                    position=0,
                    plant_id=plant_id,
                    snapshot={},
                ),
                UserActiveExpedition(user_id=user_id, run_id=expedition.id),
            ]
        )
        db.add(
            AiJob(
                user_id=user_id,
                job_type="mood_analysis",
                resource_type="mood_entry",
                resource_id=999_999,
                input_version=1,
                status="succeeded",
                available_at=now,
            )
        )
        await db.commit()

    deleted = await client.request(
        "DELETE",
        "/users/me",
        json={"password": "password123", "confirmation": "몽그루 탈퇴"},
        headers=auth_headers(tokens),
    )

    assert deleted.status_code == 204, deleted.text
    async with session_factory() as db:
        assert await db.get(User, user_id) is None
        assert (
            await db.scalar(
                sa.select(sa.func.count(AdventurePatrol.id)).where(
                    AdventurePatrol.user_id == user_id
                )
            )
            == 0
        )
        assert (
            await db.scalar(
                sa.select(sa.func.count(DungeonRun.id)).where(
                    DungeonRun.user_id == user_id
                )
            )
            == 0
        )
        assert (
            await db.scalar(
                sa.select(sa.func.count(ExpeditionRun.id)).where(
                    ExpeditionRun.user_id == user_id
                )
            )
            == 0
        )
        assert (
            await db.scalar(
                sa.select(sa.func.count(AiJob.id)).where(AiJob.user_id == user_id)
            )
            == 0
        )


async def test_login_failures_are_persisted_as_hmac_only(client, session_factory):
    await signup(client, email="rate-persist@example.com")
    failed = await client.post(
        "/auth/login",
        json={"email": "rate-persist@example.com", "password": "wrong-password"},
    )
    assert failed.status_code == 401

    async with session_factory() as db:
        rows = list((await db.execute(sa.select(LoginRateLimit))).scalars())
        assert len(rows) == 2
        assert all(len(row.rate_key) == 64 for row in rows)
        assert all("rate-persist" not in row.rate_key for row in rows)
        assert all(row.failure_count == 1 for row in rows)

    success = await client.post(
        "/auth/login",
        json={"email": "rate-persist@example.com", "password": "password123"},
    )
    assert success.status_code == 200
    async with session_factory() as db:
        # 계정 bucket은 성공 시 지우되 IP bucket은 이메일 회전 공격 방지를 위해 남긴다.
        assert await db.scalar(sa.select(sa.func.count(LoginRateLimit.rate_key))) == 1


async def test_real_data_signup_requires_all_current_consents(
    client, session_factory, monkeypatch
):
    from app.core.config import get_settings

    monkeypatch.setenv("DATA_PROFILE", "real-data")
    monkeypatch.setenv(
        "FIELD_ENCRYPTION_KEYS",
        '{"v1":"MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA="}',
    )
    monkeypatch.setenv("ACTIVE_FIELD_ENCRYPTION_KEY_ID", "v1")
    get_settings.cache_clear()
    try:
        missing = await client.post(
            "/auth/signup",
            json={
                "email": "consent-missing@example.com",
                "password": "password123",
                "nickname": "미동의",
            },
        )
        assert missing.status_code == 422
        assert missing.json()["code"] == "CONSENT_REQUIRED"

        accepted = await client.post(
            "/auth/signup",
            json={
                "email": "consent-ok@example.com",
                "password": "password123",
                "nickname": "동의함",
                "terms_accepted": True,
                "privacy_accepted": True,
                "sensitive_data_consent": True,
                "age_over_18": True,
                "terms_version": get_settings().terms_version,
                "privacy_version": get_settings().privacy_version,
                "sensitive_consent_version": (get_settings().sensitive_consent_version),
            },
        )
        assert accepted.status_code == 201
        async with session_factory() as db:
            user = await db.scalar(
                sa.select(User).where(User.email == "consent-ok@example.com")
            )
            assert user is not None
            assert user.terms_version == get_settings().terms_version
            assert user.privacy_version == get_settings().privacy_version
            assert user.sensitive_consent_version == (
                get_settings().sensitive_consent_version
            )
            assert user.age_confirmed_at is not None

        outdated = await client.post(
            "/auth/signup",
            json={
                "email": "consent-outdated@example.com",
                "password": "password123",
                "nickname": "구버전",
                "terms_accepted": True,
                "privacy_accepted": True,
                "sensitive_data_consent": True,
                "age_over_18": True,
                "terms_version": "outdated",
                "privacy_version": get_settings().privacy_version,
                "sensitive_consent_version": (get_settings().sensitive_consent_version),
            },
        )
        assert outdated.status_code == 409
        assert outdated.json()["code"] == "CONSENT_VERSION_OUTDATED"
    finally:
        monkeypatch.delenv("DATA_PROFILE", raising=False)
        monkeypatch.delenv("FIELD_ENCRYPTION_KEYS", raising=False)
        monkeypatch.delenv("ACTIVE_FIELD_ENCRYPTION_KEY_ID", raising=False)
        get_settings.cache_clear()
