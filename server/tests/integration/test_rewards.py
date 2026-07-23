import asyncio
import uuid
from datetime import timedelta

import pytest
import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.timeutil import local_date_of, utcnow
from app.models.enums import AnalysisStatus, PlantStatus
from app.models.mood import MoodEntry
from app.models.plant import Plant
from app.models.reward import RewardEvent
from app.models.user import User
from tests.conftest import auth_headers, signup


async def test_first_record_grants_exp_once(client):
    tokens = await signup(client)

    res = await client.post(
        "/moods", json={"mood_level": 4}, headers=auth_headers(tokens, idem=True)
    )
    assert res.status_code == 201
    body = res.json()
    assert body["reward"] is not None
    events = {e["event_type"] for e in body["reward"]["events"]}
    assert "mood_first_daily" in events
    assert body["reward"]["plant"]["exp"] == 20

    # 같은 날 두 번째 기록은 기록만 되고 보상은 없다
    res = await client.post(
        "/moods", json={"mood_level": 2}, headers=auth_headers(tokens, idem=True)
    )
    assert res.status_code == 201
    assert res.json()["reward"] is None


async def test_reward_without_active_plant_does_not_consume_exp_cap(
    client, session_factory
):
    tokens = await signup(client)
    user_id = tokens["user"]["id"]

    async with session_factory() as db:
        active_plant = await db.scalar(
            sa.select(Plant).where(
                Plant.user_id == user_id,
                Plant.status == PlantStatus.ACTIVE,
            )
        )
        assert active_plant is not None
        active_plant.status = PlantStatus.HARVESTED
        active_plant.harvested_at = utcnow()
        await db.commit()

    assigned = await client.get("/quests/today", headers=auth_headers(tokens))
    assert assigned.status_code == 200
    user_quest_id = assigned.json()["items"][0]["id"]
    completed = await client.post(
        f"/user-quests/{user_quest_id}/complete",
        headers=auth_headers(tokens, idem=True),
    )
    assert completed.status_code == 200
    reward = completed.json()["reward"]
    assert reward["events"] == [
        {"event_type": "quest_completed", "exp_delta": 0, "seed_delta": 5}
    ]
    assert reward["plant"] is None
    assert reward["daily_exp_granted"] == 0
    assert reward["seed_balance"] == 5

    async with session_factory() as db:
        quest_event = await db.scalar(
            sa.select(RewardEvent).where(
                RewardEvent.user_id == user_id,
                RewardEvent.event_type == "quest_completed",
            )
        )
        assert quest_event is not None
        assert quest_event.plant_id is None
        assert quest_event.exp_delta == 0
        assert quest_event.seed_delta == 5

    planted = await client.post(
        "/plants", json={"name": "다시 심은 식물"}, headers=auth_headers(tokens)
    )
    assert planted.status_code == 201

    long_diary = (
        "새로 심은 식물을 보며 오늘 하루의 마음과 생각을 천천히 "
        "돌아보고, 기억하고 싶은 일들을 하나씩 길게 적어 본다."
    )
    recorded = await client.post(
        "/moods",
        json={"mood_level": 3, "content": long_diary},
        headers=auth_headers(tokens, idem=True),
    )
    assert recorded.status_code == 201
    recorded_reward = recorded.json()["reward"]
    assert recorded_reward["daily_exp_granted"] == 30
    assert recorded_reward["plant"]["exp"] == 30
    assert recorded_reward["seed_balance"] == 5


async def test_seventh_recorded_day_grants_cumulative_week_reward(
    client, session_factory
):
    tokens = await signup(client)
    user_id = tokens["user"]["id"]
    today = local_date_of(utcnow())

    async with session_factory() as db:
        for day_offset in (2, 4, 6, 8, 10, 12):
            db.add(
                MoodEntry(
                    user_id=user_id,
                    local_date=today - timedelta(days=day_offset),
                    recorded_at_utc=utcnow() - timedelta(days=day_offset),
                    mood_level=3,
                    mood_level_explicit=False,
                    emotion_tags=[],
                    content="연속 출석이 아니어도 쌓이는 기록",
                    analysis_status=AnalysisStatus.NOT_REQUESTED,
                )
            )
        await db.execute(
            sa.update(User)
            .where(User.id == user_id)
            .values(
                streak_days=1,
                last_recorded_local_date=today - timedelta(days=2),
            )
        )
        await db.commit()

    seventh = await client.post(
        "/moods",
        json={"mood_level": 3},
        headers=auth_headers(tokens, idem=True),
    )
    assert seventh.status_code == 201
    assert {
        "event_type": "streak_week",
        "exp_delta": 0,
        "seed_delta": 30,
    } in seventh.json()["reward"]["events"]
    assert seventh.json()["reward"]["seed_balance"] == 30

    async with session_factory() as db:
        user = await db.get(User, user_id)
        milestone_events = list(
            (
                await db.execute(
                    sa.select(RewardEvent).where(
                        RewardEvent.user_id == user_id,
                        RewardEvent.event_type == "streak_week",
                    )
                )
            ).scalars()
        )
    assert user.streak_days == 1
    assert len(milestone_events) == 1
    assert milestone_events[0].dedupe_key == f"record_week:{user_id}:7"
    assert milestone_events[0].source_type == "record_milestone"
    assert milestone_events[0].source_id is None

    same_day = await client.post(
        "/moods",
        json={"mood_level": 4},
        headers=auth_headers(tokens, idem=True),
    )
    assert same_day.status_code == 201
    assert same_day.json()["reward"] is None

    async with session_factory() as db:
        milestone_count = await db.scalar(
            sa.select(sa.func.count())
            .select_from(RewardEvent)
            .where(
                RewardEvent.user_id == user_id,
                RewardEvent.event_type == "streak_week",
            )
        )
    assert milestone_count == 1


async def test_diary_bonus_and_daily_cap(client):
    tokens = await signup(client)
    long_diary = "오늘 하루를 돌아보며 느낀 점을 오십자 이상으로 길게 적어보는 일기입니다. 산책도 하고 책도 읽었다."
    assert len(long_diary) >= 50

    res = await client.post(
        "/moods",
        json={"mood_level": 4, "content": long_diary},
        headers=auth_headers(tokens, idem=True),
    )
    body = res.json()
    events = {e["event_type"] for e in body["reward"]["events"]}
    assert events == {"mood_first_daily", "diary_first_daily"}
    # 일일 상한 50 안에서 첫 기록 20 + 긴 일기 10 = 30 지급
    assert body["reward"]["daily_exp_granted"] == 30
    assert body["reward"]["daily_exp_cap"] == 50


async def test_mood_idempotency_retry_returns_same_response(client):
    tokens = await signup(client)
    key = uuid.uuid4().hex
    headers = {**auth_headers(tokens), "Idempotency-Key": key}
    payload = {"mood_level": 3, "content": "같은 요청 재시도"}

    first = await client.post("/moods", json=payload, headers=headers)
    assert first.status_code == 201
    for _ in range(19):
        retry = await client.post("/moods", json=payload, headers=headers)
        assert retry.status_code == 201
        assert retry.json()["mood"]["id"] == first.json()["mood"]["id"]

    # 기록도 보상도 1건만 존재
    res = await client.get(
        f"/moods?date={first.json()['mood']['local_date']}",
        headers=auth_headers(tokens),
    )
    assert len(res.json()["items"]) == 1


@pytest.mark.parametrize("operation", ["mood_create", "plant_harvest"])
async def test_idempotent_posts_lock_user_before_claim_flush(
    client, monkeypatch, operation
):
    """FOR UPDATE를 무시하는 SQLite에서는 lock/flush 호출 순서를 직접 확인한다."""
    from app.api import idempotency
    from app.models.ops import IdempotencyKey

    tokens = await signup(client)
    events = []
    original_lock = idempotency._lock_user_before_claim
    original_flush = AsyncSession.flush

    async def observed_lock(db, user_id):
        await original_lock(db, user_id)
        events.append("user_lock")

    async def observed_flush(self, objects=None):
        if any(isinstance(item, IdempotencyKey) for item in self.new):
            events.append("idempotency_flush")
        return await original_flush(self, objects)

    monkeypatch.setattr(idempotency, "_lock_user_before_claim", observed_lock)
    monkeypatch.setattr(AsyncSession, "flush", observed_flush)

    if operation == "mood_create":
        response = await client.post(
            "/moods",
            json={"mood_level": 3},
            headers=auth_headers(tokens, idem=True),
        )
        assert response.status_code == 201
    else:
        active = await client.get("/plants/me", headers=auth_headers(tokens))
        plant_id = active.json()["plant"]["id"]
        response = await client.post(
            f"/plants/{plant_id}/harvest",
            headers=auth_headers(tokens, idem=True),
        )
        assert response.status_code == 409

    assert events.count("user_lock") == 1
    assert events.count("idempotency_flush") == 1
    assert events.index("user_lock") < events.index("idempotency_flush")


async def test_same_key_different_body_conflicts(client):
    tokens = await signup(client)
    key = uuid.uuid4().hex
    headers = {**auth_headers(tokens), "Idempotency-Key": key}
    res = await client.post("/moods", json={"mood_level": 3}, headers=headers)
    assert res.status_code == 201
    res = await client.post("/moods", json={"mood_level": 5}, headers=headers)
    assert res.status_code == 409
    assert res.json()["code"] == "IDEMPOTENCY_KEY_CONFLICT"


async def test_missing_idempotency_key(client):
    tokens = await signup(client)
    res = await client.post(
        "/moods", json={"mood_level": 3}, headers=auth_headers(tokens)
    )
    assert res.status_code == 400
    assert res.json()["code"] == "IDEMPOTENCY_KEY_REQUIRED"


async def test_mood_patch_can_clear_diary_content(client):
    tokens = await signup(client)
    created = await client.post(
        "/moods",
        json={"mood_level": 3, "content": "지우고 싶은 일기"},
        headers=auth_headers(tokens, idem=True),
    )
    mood_id = created.json()["mood"]["id"]

    cleared = await client.patch(
        f"/moods/{mood_id}", json={"content": None}, headers=auth_headers(tokens)
    )
    assert cleared.status_code == 200
    assert cleared.json()["mood"]["content"] is None
    assert cleared.json()["mood"]["analysis_status"] == "not_requested"


async def test_mood_patch_expected_version_rejects_concurrent_edit(client):
    tokens = await signup(client)
    created = await client.post(
        "/moods",
        json={"mood_level": 3, "content": "처음 기록"},
        headers=auth_headers(tokens, idem=True),
    )
    mood = created.json()["mood"]
    expected_version = mood["edit_version"]

    async def patch(content: str):
        return await client.patch(
            f"/moods/{mood['id']}",
            json={"expected_version": expected_version, "content": content},
            headers=auth_headers(tokens),
        )

    first, second = await asyncio.gather(patch("첫 번째 수정"), patch("두 번째 수정"))
    statuses = sorted([first.status_code, second.status_code])
    assert statuses == [200, 409]

    success = first if first.status_code == 200 else second
    conflict = second if first.status_code == 200 else first
    assert success.json()["mood"]["edit_version"] == expected_version + 1
    assert conflict.json()["code"] == "MOOD_VERSION_CONFLICT"
    assert conflict.json()["details"] == {
        "expected_version": expected_version,
        "current_version": success.json()["mood"]["edit_version"],
    }

    current = await client.get(f"/moods/{mood['id']}", headers=auth_headers(tokens))
    assert current.json()["content"] == success.json()["mood"]["content"]


async def test_mood_edit_version_changes_only_for_user_patch(client, session_factory):
    tokens = await signup(client)
    created = await client.post(
        "/moods",
        json={"mood_level": 4, "content": "분석할 수 있는 감정 기록"},
        headers=auth_headers(tokens, idem=True),
    )
    mood = created.json()["mood"]
    assert mood["edit_version"] == 1

    # AI worker의 running/succeeded 메타데이터 갱신은 사용자 편집 버전과 무관하다.
    from app.workers.ai_worker import run_pending_once

    await run_pending_once(session_factory)
    analyzed = await client.get(f"/moods/{mood['id']}", headers=auth_headers(tokens))
    assert analyzed.json()["edit_version"] == 1

    patched = await client.patch(
        f"/moods/{mood['id']}",
        json={"expected_version": 1, "content": "사용자가 직접 고친 기록"},
        headers=auth_headers(tokens),
    )
    assert patched.status_code == 200
    assert patched.json()["mood"]["edit_version"] == 2

    # expected_version을 생략한 호환 PATCH도 수락되면 정확히 한 번 증가한다.
    hidden = await client.patch(
        f"/moods/{mood['id']}",
        json={"ai_label_hidden": True},
        headers=auth_headers(tokens),
    )
    assert hidden.status_code == 200
    assert hidden.json()["mood"]["edit_version"] == 3

    await run_pending_once(session_factory)
    after_worker = await client.get(
        f"/moods/{mood['id']}", headers=auth_headers(tokens)
    )
    assert after_worker.json()["edit_version"] == 3


async def test_empty_mood_patch_keeps_edit_version(client):
    tokens = await signup(client)
    created = await client.post(
        "/moods",
        json={"mood_level": 3, "content": "비어 있는 수정 요청 테스트"},
        headers=auth_headers(tokens, idem=True),
    )
    mood = created.json()["mood"]

    patched = await client.patch(
        f"/moods/{mood['id']}", json={}, headers=auth_headers(tokens)
    )
    assert patched.status_code == 200
    assert patched.json()["mood"]["edit_version"] == mood["edit_version"]

    current = await client.get(f"/moods/{mood['id']}", headers=auth_headers(tokens))
    assert current.json()["edit_version"] == mood["edit_version"]
    assert current.json()["content"] == mood["content"]


async def test_failed_mood_patch_rolls_back_edit_version(
    client, session_factory, monkeypatch
):
    from app.api.errors import AppError
    from app.models.mood import MoodEntry
    from app.services import moods as mood_service

    tokens = await signup(client)
    created = await client.post(
        "/moods",
        json={"mood_level": 3, "content": "롤백 전 원본"},
        headers=auth_headers(tokens, idem=True),
    )
    mood = created.json()["mood"]

    async def fail_after_version_advance(db, entry, fields):
        raise AppError(503, "PATCH_TEST_FAILURE", "패치 트랜잭션 롤백 테스트")

    monkeypatch.setattr(mood_service, "patch_mood", fail_after_version_advance)
    failed = await client.patch(
        f"/moods/{mood['id']}",
        json={
            "expected_version": mood["edit_version"],
            "content": "저장되면 안 되는 수정",
        },
        headers=auth_headers(tokens),
    )
    assert failed.status_code == 503
    assert failed.json()["code"] == "PATCH_TEST_FAILURE"

    # advance_edit_version()의 CAS UPDATE까지 실행된 뒤 실패했어도 요청 트랜잭션
    # 전체가 rollback되어 버전과 사용자 데이터가 함께 원상복구되어야 한다.
    async with session_factory() as db:
        persisted = await db.get(MoodEntry, mood["id"])
        assert persisted is not None
        assert persisted.edit_version == mood["edit_version"]
        assert persisted.content == mood["content"]


async def test_visible_plant_name_rejects_whitespace_only(client):
    tokens = await signup(client)
    response = await client.post(
        "/plants", json={"name": "   "}, headers=auth_headers(tokens)
    )
    assert response.status_code == 422
    assert response.json()["code"] == "VALIDATION_ERROR"
