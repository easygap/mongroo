from datetime import timedelta

import sqlalchemy as sa

from app.models.mood import MoodEntry
from app.models.enums import AnalysisStatus
from app.models.plant import Plant
from app.models.ops import AiJob
from app.services.reports import compute_stats
from app.services.plants import refresh_active_plant_growth
from app.core.timeutil import utcnow
from app.workers.ai_worker import _today_mood_summary
from app.workers.ai_worker import run_pending_once
from tests.conftest import auth_headers, signup


async def _mature_plant(session_factory, user_id: int) -> int:
    async with session_factory() as db:
        plant = await db.scalar(
            sa.select(Plant).where(Plant.user_id == user_id, Plant.status == "active")
        )
        plant.exp = 1000
        await db.commit()
        return plant.id


async def test_content_only_mood_is_accepted_but_empty_request_is_rejected(
    client, session_factory
):
    tokens = await signup(client)
    empty = await client.post(
        "/moods", json={}, headers=auth_headers(tokens, idem=True)
    )
    assert empty.status_code == 422

    created = await client.post(
        "/moods",
        json={"content": "직접 감정을 고르지 않고 행복하고 즐거웠던 일을 적었다."},
        headers=auth_headers(tokens, idem=True),
    )
    assert created.status_code == 201, created.text
    assert created.json()["mood"]["mood_level"] == 3
    assert created.json()["mood"]["mood_level_explicit"] is False
    assert created.json()["mood"]["analysis_status"] == "pending"
    assert created.json()["reward"]["plant"]["growth_profile"]["pending_count"] == 1

    await run_pending_once(session_factory)
    plant = (await client.get("/plants/me", headers=auth_headers(tokens))).json()[
        "plant"
    ]
    assert plant["growth_profile"]["counts"]["joy"] == 1
    assert plant["growth_profile"]["total"] == 1
    assert plant["profile_state"] == "limited"

    local_date = created.json()["mood"]["local_date"]
    year, month, _ = local_date.split("-")
    calendar = await client.get(
        f"/moods/calendar?year={year}&month={int(month)}",
        headers=auth_headers(tokens),
    )
    day = calendar.json()["days"][0]
    assert day["last_mood_level"] is None
    assert day["last_mood_level_explicit"] is False
    assert day["last_ai_emotion"] == "기쁨"
    assert day["last_analysis_status"] == "succeeded"

    async with session_factory() as db:
        entries = list((await db.execute(sa.select(MoodEntry))).scalars())
        stats, _ = compute_stats(entries, entries[0].local_date, entries[0].local_date)
        assert stats["explicit_mood_entries"] == 0
        assert stats["mood_daily"] == []
        # 채팅 문맥에도 내부 호환값 '보통' 대신 본문 분석 라벨만 들어간다.
        assert await _today_mood_summary(db, tokens["user"]["id"]) == "기쁨"

        analysis_version = entries[0].analysis_version
        input_version = entries[0].input_version
        job_count = int(await db.scalar(sa.select(sa.func.count(AiJob.id))) or 0)

    patched = await client.patch(
        f"/moods/{created.json()['mood']['id']}",
        # 내부값과 같은 3이어도 사용자가 명시한 값으로 전환되므로 report 입력은 바뀐다.
        json={"mood_level": 3},
        headers=auth_headers(tokens),
    )
    assert patched.status_code == 200
    assert patched.json()["mood"]["mood_level_explicit"] is True
    async with session_factory() as db:
        row = await db.get(MoodEntry, created.json()["mood"]["id"])
        assert row.analysis_version == analysis_version
        assert row.input_version == input_version + 1
        assert (
            int(await db.scalar(sa.select(sa.func.count(AiJob.id))) or 0) == job_count
        )


async def test_harvest_waits_for_pending_and_three_analyzed_diaries(
    client, session_factory
):
    tokens = await signup(client)
    user_id = tokens["user"]["id"]
    await client.post(
        "/moods",
        json={
            "mood_level": 1,
            "emotion_tags": ["슬픔"],
            "content": "오늘은 행복하고 즐거운 일이 있어 오래 웃었다.",
        },
        headers=auth_headers(tokens, idem=True),
    )
    plant_id = await _mature_plant(session_factory, user_id)

    pending = await client.post(
        f"/plants/{plant_id}/harvest", headers=auth_headers(tokens, idem=True)
    )
    assert pending.status_code == 409
    assert pending.json()["code"] == "PLANT_ANALYSIS_PENDING"
    assert pending.json()["details"] == {"pending_count": 1}

    await run_pending_once(session_factory)
    insufficient = await client.post(
        f"/plants/{plant_id}/harvest", headers=auth_headers(tokens, idem=True)
    )
    assert insufficient.status_code == 409
    assert insufficient.json()["code"] == "PLANT_EMOTION_EVIDENCE_REQUIRED"
    assert insufficient.json()["details"] == {"analyzed_count": 1, "required_count": 3}

    for index in range(2):
        await client.post(
            "/moods",
            json={
                "mood_level": 1,
                "emotion_tags": ["분노"],
                "content": f"오늘은 행복하고 즐거운 장면을 떠올리며 웃었다 {index}",
            },
            headers=auth_headers(tokens, idem=True),
        )
    await run_pending_once(session_factory)

    active = (await client.get("/plants/me", headers=auth_headers(tokens))).json()[
        "plant"
    ]
    assert active["harvestable"] is True
    assert active["growth_branch"] == "joy"
    assert active["growth_form"] == "sunny"
    assert active["growth_persona"]["persona_name"] == "햇살결"
    assert active["growth_profile"]["counts"]["sadness"] == 0
    assert active["growth_profile"]["counts"]["anger"] == 0

    harvested = await client.post(
        f"/plants/{plant_id}/harvest", headers=auth_headers(tokens, idem=True)
    )
    assert harvested.status_code == 200, harvested.text
    assert harvested.json()["plant"]["final_form"] == "sunny"


async def test_harvest_rebuilds_locked_lifecycle_instead_of_trusting_cached_profile(
    client, session_factory
):
    tokens = await signup(client)
    user_id = tokens["user"]["id"]
    now = utcnow()
    async with session_factory() as db:
        plant = await db.scalar(sa.select(Plant).where(Plant.user_id == user_id))
        plant.exp = 1000
        # 의도적으로 오래된 '준비 완료' 캐시를 만든다.
        plant.emotion_profile = {
            "version": 2,
            "source": "diary_text_analysis",
            "total": 3,
            "pending_count": 0,
            "unavailable_count": 0,
            "empty_count": 0,
            "counts": {
                "joy": 3,
                "sadness": 0,
                "anger": 0,
                "anxiety": 0,
                "surprise": 0,
                "mixed": 0,
            },
            "ratios": {
                "joy": 1.0,
                "sadness": 0.0,
                "anger": 0.0,
                "anxiety": 0.0,
                "surprise": 0.0,
                "mixed": 0.0,
            },
        }
        db.add(
            MoodEntry(
                user_id=user_id,
                local_date=now.date(),
                recorded_at_utc=now,
                mood_level=3,
                mood_level_explicit=False,
                emotion_tags=[],
                content="아직 worker가 읽고 있는 일기",
                analysis_status=AnalysisStatus.PENDING,
            )
        )
        await db.commit()
        plant_id = plant.id

    result = await client.post(
        f"/plants/{plant_id}/harvest", headers=auth_headers(tokens, idem=True)
    )
    assert result.status_code == 409
    assert result.json()["code"] == "PLANT_ANALYSIS_PENDING"
    assert result.json()["details"] == {"pending_count": 1}


async def test_safety_skipped_diary_does_not_trap_a_mature_plant(
    client, session_factory
):
    tokens = await signup(client)
    user_id = tokens["user"]["id"]
    created = await client.post(
        "/moods",
        json={"content": "요즘 계속 죽고 싶다는 생각이 든다"},
        headers=auth_headers(tokens, idem=True),
    )
    assert created.status_code == 201
    assert created.json()["mood"]["analysis_status"] == "not_requested"
    assert created.json()["safety_action"] is not None

    plant_id = await _mature_plant(session_factory, user_id)
    active = (await client.get("/plants/me", headers=auth_headers(tokens))).json()[
        "plant"
    ]
    assert active["growth_profile"]["unavailable_count"] == 1
    assert active["harvestable"] is True

    harvested = await client.post(
        f"/plants/{plant_id}/harvest", headers=auth_headers(tokens, idem=True)
    )
    assert harvested.status_code == 200, harvested.text
    assert harvested.json()["plant"]["final_form"] == "mosaic"
    assert harvested.json()["plant"]["growth_persona"]["persona_name"] == "모아결"


async def test_whitespace_only_legacy_diary_cannot_bypass_harvest_evidence(
    client, session_factory
):
    tokens = await signup(client)
    created = await client.post(
        "/moods",
        json={"mood_level": 3, "content": "\n\t\u3000"},
        headers=auth_headers(tokens, idem=True),
    )
    assert created.status_code == 201, created.text
    assert created.json()["mood"]["analysis_status"] == "not_requested"

    plant_id = await _mature_plant(session_factory, tokens["user"]["id"])
    active = (await client.get("/plants/me", headers=auth_headers(tokens))).json()[
        "plant"
    ]
    assert active["growth_profile"]["empty_count"] == 1
    assert active["growth_profile"]["unavailable_count"] == 0
    assert active["harvestable"] is False

    harvested = await client.post(
        f"/plants/{plant_id}/harvest", headers=auth_headers(tokens, idem=True)
    )
    assert harvested.status_code == 409
    assert harvested.json()["code"] == "PLANT_EMOTION_EVIDENCE_REQUIRED"


async def test_growth_lifecycle_keeps_same_second_microsecond_boundary(
    client, session_factory
):
    tokens = await signup(client)
    user_id = tokens["user"]["id"]
    boundary = utcnow() - timedelta(seconds=1)
    async with session_factory() as db:
        plant = await db.scalar(sa.select(Plant).where(Plant.user_id == user_id))
        plant.exp = 300
        plant.planted_at = boundary
        db.add_all(
            [
                MoodEntry(
                    user_id=user_id,
                    local_date=boundary.date(),
                    recorded_at_utc=boundary - timedelta(microseconds=200_000),
                    mood_level=3,
                    mood_level_explicit=False,
                    emotion_tags=[],
                    content="이전 식물에 속한 행복한 일기",
                    analysis_status=AnalysisStatus.SUCCEEDED,
                    ai_emotion="기쁨",
                ),
                MoodEntry(
                    user_id=user_id,
                    local_date=boundary.date(),
                    recorded_at_utc=boundary + timedelta(microseconds=200_000),
                    mood_level=3,
                    mood_level_explicit=False,
                    emotion_tags=[],
                    content="새 식물에 속한 슬픈 일기",
                    analysis_status=AnalysisStatus.SUCCEEDED,
                    ai_emotion="슬픔",
                ),
            ]
        )
        await db.commit()
        await refresh_active_plant_growth(db, user_id)
        await db.commit()

    active = (await client.get("/plants/me", headers=auth_headers(tokens))).json()[
        "plant"
    ]
    assert active["growth_profile"]["total"] == 1
    assert active["growth_profile"]["counts"]["joy"] == 0
    assert active["growth_profile"]["counts"]["sadness"] == 1
