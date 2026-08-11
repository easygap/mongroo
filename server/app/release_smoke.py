"""배포 DB와 실제 API 계약을 함께 확인하는 합성 계정 smoke test."""

from __future__ import annotations

import asyncio
import uuid
from datetime import date, timedelta

import sqlalchemy as sa
from httpx import ASGITransport, AsyncClient

from app.core.config import get_settings
from app.core.db import get_engine, get_session_factory
from app.core.timeutil import utcnow
from app.main import create_app
from app.models.adventure import AdventurePatrol, DungeonRun, UserDungeon
from app.models.expedition import ExpeditionAction, ExpeditionPartyMember, ExpeditionRun


async def run() -> None:
    settings = get_settings()
    if settings.app_env != "production" or settings.data_profile != "real-data":
        raise RuntimeError("release smoke requires production real-data settings")

    app = create_app()
    transport = ASGITransport(app=app)
    email = f"release-smoke-{uuid.uuid4().hex}@example.com"
    password = f"Smoke-{uuid.uuid4().hex}!"
    async with AsyncClient(
        transport=transport,
        base_url="https://api.mongroo.test/api/v1",
    ) as client:
        ready = await client.get("/health/ready")
        if ready.status_code != 200 or ready.json()["status"] != "ok":
            raise RuntimeError(f"readiness failed: {ready.text}")

        signup = await client.post(
            "/auth/signup",
            json={
                "email": email,
                "password": password,
                "nickname": "릴리스 점검",
                "terms_accepted": True,
                "privacy_accepted": True,
                "sensitive_data_consent": True,
                "age_over_18": True,
                "terms_version": settings.terms_version,
                "privacy_version": settings.privacy_version,
                "sensitive_consent_version": settings.sensitive_consent_version,
            },
        )
        if signup.status_code != 201:
            raise RuntimeError(f"signup failed: {signup.text}")
        body = signup.json()
        token = body["access_token"]
        user_id = body["user"]["id"]
        auth = {"Authorization": f"Bearer {token}"}

        diary_text = "릴리스 과정에서 암호화와 계정 생명주기를 확인하는 합성 마음 일기입니다. " * 2
        mood = await client.post(
            "/moods",
            json={"content": diary_text},
            headers={**auth, "Idempotency-Key": uuid.uuid4().hex},
        )
        if mood.status_code != 201:
            raise RuntimeError(f"mood creation failed: {mood.text}")

        factory = get_session_factory()
        expedition_id = 0
        async with factory() as db:
            stored_content = await db.scalar(
                sa.text(
                    "SELECT content FROM mood_entries WHERE user_id = :user_id LIMIT 1"
                ),
                {"user_id": user_id},
            )
            stored_name = await db.scalar(
                sa.text("SELECT name FROM plants WHERE user_id = :user_id LIMIT 1"),
                {"user_id": user_id},
            )
            if not str(stored_content).startswith("enc:v1:"):
                raise RuntimeError("mood content was stored without field encryption")
            if not str(stored_name).startswith("enc:v1:"):
                raise RuntimeError("plant name was stored without field encryption")
            plant_id = int(
                await db.scalar(
                    sa.text("SELECT id FROM plants WHERE user_id = :user_id LIMIT 1"),
                    {"user_id": user_id},
                )
            )
            now = utcnow()
            dungeon = UserDungeon(
                user_id=user_id,
                dungeon_code="release_smoke_dungeon",
                discovered_at=now,
            )
            db.add_all(
                [
                    AdventurePatrol(
                        user_id=user_id,
                        plant_id=plant_id,
                        route_code="release_smoke_route",
                        local_date=date.today(),
                        status="active",
                        started_at=now,
                        returns_at=now + timedelta(minutes=5),
                        reward_exp=0,
                        reward_seeds=0,
                        reaction_speaker="릴리스 캐릭터",
                        reaction_text="안전하게 돌아왔어요.",
                        found_item_code="release_smoke_item",
                        found_quantity=1,
                        performance_score=1,
                    ),
                    dungeon,
                ]
            )
            await db.flush()
            db.add(
                DungeonRun(
                    user_id=user_id,
                    plant_id=plant_id,
                    user_dungeon_id=dungeon.id,
                    local_date=date.today(),
                    created_at=now,
                    reward_exp=0,
                    reward_seeds=0,
                    found_item_code="release_smoke_item",
                    found_quantity=1,
                    performance_score=1,
                )
            )
            expedition = ExpeditionRun(
                user_id=user_id,
                region_code="release_smoke_region",
                mode="tutorial",
                status="active",
                phase="exploring",
                local_date=date.today(),
                content_version="release-smoke-v1",
                map_seed=uuid.uuid4().hex,
                map_snapshot={},
                run_thread_snapshot={},
                run_memory_snapshot={},
                spotlight_snapshot=[],
                runtime_effects_snapshot={},
                current_node_code="home",
                summary_snapshot={"party_names": ["릴리스 캐릭터"]},
            )
            db.add(expedition)
            await db.flush()
            expedition_id = expedition.id
            db.add_all(
                [
                    ExpeditionPartyMember(
                        run_id=expedition.id,
                        position=0,
                        plant_id=plant_id,
                        snapshot={"name": "릴리스 캐릭터"},
                    ),
                    ExpeditionAction(
                        run_id=expedition.id,
                        action_index=1,
                        client_action_id=uuid.uuid4().hex,
                        expected_revision=0,
                        action_type="move",
                        request_payload={"node_code": "home"},
                        result_payload={"party_names": ["릴리스 캐릭터"]},
                    ),
                ]
            )
            await db.commit()

            protected_duplicates = (
                await db.execute(
                    sa.text(
                        "SELECT "
                        "(SELECT reaction_speaker FROM adventure_patrols "
                        " WHERE user_id = :user_id LIMIT 1), "
                        "(SELECT summary_snapshot FROM expedition_runs "
                        " WHERE id = :run_id), "
                        "(SELECT snapshot FROM expedition_party_members "
                        " WHERE run_id = :run_id LIMIT 1), "
                        "(SELECT result_payload FROM expedition_actions "
                        " WHERE run_id = :run_id LIMIT 1)"
                    ),
                    {"user_id": user_id, "run_id": expedition.id},
                )
            ).one()
            if not all(
                str(value).startswith("enc:v1:") for value in protected_duplicates
            ):
                raise RuntimeError(
                    "derived character snapshots were stored without encryption"
                )

        exported = await client.get("/users/me/export", headers=auth)
        if exported.status_code != 200:
            raise RuntimeError(f"account export failed: {exported.text}")
        exported_moods = exported.json()["data"]["mood_entries"]
        if not exported_moods or exported_moods[0]["content"] != diary_text:
            raise RuntimeError("account export did not decrypt the owned diary")

        deleted = await client.request(
            "DELETE",
            "/users/me",
            headers=auth,
            json={"password": password, "confirmation": "몽그루 탈퇴"},
        )
        if deleted.status_code != 204:
            raise RuntimeError(f"account deletion failed: {deleted.text}")

        async with factory() as db:
            remaining = int(
                await db.scalar(
                    sa.text("SELECT COUNT(*) FROM users WHERE id = :user_id"),
                    {"user_id": user_id},
                )
                or 0
            )
            if remaining:
                raise RuntimeError("account cascade deletion left the synthetic user")
            restricting_history = int(
                await db.scalar(
                    sa.text(
                        "SELECT COUNT(*) FROM expedition_party_members "
                        "WHERE run_id = :run_id"
                    ),
                    {"run_id": expedition_id},
                )
                or 0
            )
            if restricting_history:
                raise RuntimeError("account deletion left plant-referencing history")

    await get_engine().dispose()
    print("release-smoke=ok")


if __name__ == "__main__":
    asyncio.run(run())
