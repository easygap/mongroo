"""P0 데모 시나리오: 가입 → 기록 → 성장 → 수확 → 대화 → 리포트 (design.md 12.3)."""

import uuid
from datetime import timedelta

import sqlalchemy as sa

from app.models.plant import Plant
from app.services.plants import refresh_active_plant_growth
from app.workers.ai_worker import run_pending_once
from tests.conftest import auth_headers, signup


async def test_full_p0_flow(client, session_factory):
    tokens = await signup(client)

    # 1) 감정 기록 (기분만) → 첫 기록 보상
    res = await client.post(
        "/moods",
        json={"mood_level": 4, "emotion_tags": ["설렘"]},
        headers=auth_headers(tokens, idem=True),
    )
    assert res.status_code == 201
    assert res.json()["reward"]["plant"]["exp"] == 10

    # 2) 직접 감정 체크 없이 일기 세 편 → 본문 분석과 성장 분기
    mood_id = None
    for index in range(3):
        res = await client.post(
            "/moods",
            json={
                "content": f"회사 일이 많아서 불안하고 걱정이 됐다. 산책 후에는 조금 나아졌다. {index}"
            },
            headers=auth_headers(tokens, idem=True),
        )
        mood_id = res.json()["mood"]["id"]
    await run_pending_once(session_factory)
    res = await client.get(f"/moods/{mood_id}", headers=auth_headers(tokens))
    assert res.json()["analysis_status"] == "succeeded"
    assert res.json()["ai_emotion"] == "불안"

    # 3) 캘린더 집계
    year, month = res.json()["local_date"].split("-")[:2]
    res = await client.get(
        f"/moods/calendar?year={year}&month={int(month)}", headers=auth_headers(tokens)
    )
    day = res.json()["days"][0]
    assert day["entry_count"] == 4

    # 4) 식물 대화 (fake LLM) → 응답 수신
    res = await client.post("/chat/sessions", json={}, headers=auth_headers(tokens))
    session_id = res.json()["session"]["id"]
    res = await client.post(
        f"/chat/sessions/{session_id}/messages",
        json={
            "content": "오늘 하루가 길게 느껴졌어",
            "client_message_id": uuid.uuid4().hex,
        },
        headers=auth_headers(tokens, idem=True),
    )
    run_id = res.json()["run_id"]
    await run_pending_once(session_factory)
    res = await client.get(f"/chat/runs/{run_id}", headers=auth_headers(tokens))
    assert res.json()["status"] == "succeeded"

    # 5) 수확: 경험치를 직접 채워 만개 상태로 만든 뒤 수확
    async with session_factory() as db:
        active = await db.scalar(sa.select(Plant).where(Plant.status == "active"))
        active.exp = 1000
        await refresh_active_plant_growth(
            db, active.user_id, plant=active, rebuild_profile=False
        )
        await db.commit()
    res = await client.get("/plants/me", headers=auth_headers(tokens))
    plant = res.json()["plant"]
    assert plant["stage"] == 5 and plant["harvestable"]
    assert plant["growth_branch"] == "anxiety"

    res = await client.post(
        f"/plants/{plant['id']}/harvest", headers=auth_headers(tokens, idem=True)
    )
    assert res.status_code == 200
    assert res.json()["plant"]["status"] == "harvested"

    # 수확 재시도(새 멱등키) → 이미 수확됨
    res = await client.post(
        f"/plants/{plant['id']}/harvest", headers=auth_headers(tokens, idem=True)
    )
    assert res.status_code == 409

    # 6) 갤러리에 전시되고, 새 식물을 심을 수 있다
    res = await client.get("/plants?status=harvested", headers=auth_headers(tokens))
    assert len(res.json()["items"]) == 1
    res = await client.get("/plants/me", headers=auth_headers(tokens))
    assert res.json()["plant"] is None
    res = await client.post(
        "/plants", json={"name": "초록이"}, headers=auth_headers(tokens)
    )
    assert res.status_code == 201
    assert res.json()["stage"] == 1

    # 7) 주간 리포트 생성 → 요약까지
    from app.core.timeutil import KST, utcnow
    from datetime import timezone

    today = utcnow().replace(tzinfo=timezone.utc).astimezone(KST).date()
    monday = (today - timedelta(days=today.weekday())).isoformat()
    res = await client.post(
        "/reports",
        json={"period_type": "weekly", "period_start": monday},
        headers=auth_headers(tokens, idem=True),
    )
    report_id = res.json()["report"]["id"]
    await run_pending_once(session_factory)
    res = await client.get(f"/reports/{report_id}", headers=auth_headers(tokens))
    body = res.json()
    assert body["status"] == "succeeded"
    assert body["summary"]["overview"]
    assert body["stats"]["total_entries"] == 4


async def test_alpha_flow_without_ai(client, session_factory, monkeypatch):
    """AI_MODE=disabled에서도 기록·성장·수확 코어 루프가 완주된다 (design.md 2.2)."""
    from app.core.config import get_settings

    monkeypatch.setenv("AI_MODE", "disabled")
    get_settings.cache_clear()
    try:
        tokens = await signup(client)
        res = await client.post(
            "/moods",
            json={"mood_level": 5, "content": "AI 없이 기록"},
            headers=auth_headers(tokens, idem=True),
        )
        assert res.status_code == 201
        assert res.json()["mood"]["analysis_status"] == "not_requested"
        assert res.json()["reward"]["plant"]["exp"] == 10

        # 대화는 degraded로 명시적 실패
        res = await client.post("/chat/sessions", json={}, headers=auth_headers(tokens))
        session_id = res.json()["session"]["id"]
        res = await client.post(
            f"/chat/sessions/{session_id}/messages",
            json={"content": "안녕", "client_message_id": uuid.uuid4().hex},
            headers=auth_headers(tokens, idem=True),
        )
        assert res.status_code == 503
        assert res.json()["code"] == "SERVICE_DEGRADED"

        # 리포트는 통계만으로 즉시 succeeded
        from app.core.timeutil import KST, utcnow
        from datetime import timezone

        today = utcnow().replace(tzinfo=timezone.utc).astimezone(KST).date()
        monday = (today - timedelta(days=today.weekday())).isoformat()
        res = await client.post(
            "/reports",
            json={"period_type": "weekly", "period_start": monday},
            headers=auth_headers(tokens, idem=True),
        )
        assert res.json()["report"]["status"] == "succeeded"
        assert res.json()["report"]["summary"] is None
    finally:
        monkeypatch.setenv("AI_MODE", "fake")
        get_settings.cache_clear()


async def test_mood_safety_path_saves_entry_and_rewards(client, session_factory):
    """안전 경로에서도 기록은 저장되고 보상은 동일 지급 (design.md 6.3)."""
    tokens = await signup(client)
    res = await client.post(
        "/moods",
        json={"mood_level": 1, "content": "요즘 계속 죽고 싶다는 생각이 든다"},
        headers=auth_headers(tokens, idem=True),
    )
    assert res.status_code == 201
    body = res.json()
    assert body["safety_action"] is not None
    assert body["safety_action"]["severity"] == "concern"
    assert body["mood"]["analysis_status"] == "not_requested"  # 분석 job 미생성
    assert body["reward"] is not None  # 보상은 동일하게

    processed = await run_pending_once(session_factory)
    assert processed == 0
