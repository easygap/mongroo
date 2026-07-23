from datetime import timedelta

from app.workers.ai_worker import run_pending_once
from tests.conftest import auth_headers, signup


def _this_monday() -> str:
    from app.core.timeutil import KST, utcnow
    from datetime import timezone

    today = utcnow().replace(tzinfo=timezone.utc).astimezone(KST).date()
    return (today - timedelta(days=today.weekday())).isoformat()


async def test_report_create_and_summary(client, session_factory):
    tokens = await signup(client)
    await client.post(
        "/moods",
        json={"mood_level": 4, "emotion_tags": ["뿌듯함"], "content": "오늘 행복하고 즐거운 하루"},
        headers=auth_headers(tokens, idem=True),
    )
    await run_pending_once(session_factory)  # 감정 분석 처리

    res = await client.post(
        "/reports",
        json={"period_type": "weekly", "period_start": _this_monday()},
        headers=auth_headers(tokens, idem=True),
    )
    assert res.status_code == 202
    report = res.json()["report"]
    assert report["status"] == "pending"
    stats = report["stats"]
    assert stats["total_entries"] == 1
    assert stats["tag_distribution"][0]["tag"] == "뿌듯함"
    assert stats["ai_emotion_distribution"][0]["emotion"] == "기쁨"
    assert report["analysis_coverage"] == 1.0

    await run_pending_once(session_factory)  # 요약 생성

    res = await client.get(f"/reports/{report['id']}", headers=auth_headers(tokens))
    body = res.json()
    assert body["status"] == "succeeded"
    assert body["summary"]["overview"]
    assert body["stale"] is False


async def test_report_same_input_returns_existing(client, session_factory):
    tokens = await signup(client)
    await client.post(
        "/moods", json={"mood_level": 3}, headers=auth_headers(tokens, idem=True)
    )
    monday = _this_monday()

    res1 = await client.post(
        "/reports",
        json={"period_type": "weekly", "period_start": monday},
        headers=auth_headers(tokens, idem=True),
    )
    assert res1.status_code == 202
    res2 = await client.post(
        "/reports",
        json={"period_type": "weekly", "period_start": monday},
        headers=auth_headers(tokens, idem=True),
    )
    assert res2.status_code == 200
    assert res2.json()["report"]["id"] == res1.json()["report"]["id"]


async def test_report_stale_after_entry_deleted(client, session_factory):
    tokens = await signup(client)
    res = await client.post(
        "/moods", json={"mood_level": 5}, headers=auth_headers(tokens, idem=True)
    )
    mood_id = res.json()["mood"]["id"]

    res = await client.post(
        "/reports",
        json={"period_type": "weekly", "period_start": _this_monday()},
        headers=auth_headers(tokens, idem=True),
    )
    report_id = res.json()["report"]["id"]

    await client.delete(f"/moods/{mood_id}", headers=auth_headers(tokens))

    res = await client.get(f"/reports/{report_id}", headers=auth_headers(tokens))
    assert res.json()["stale"] is True


async def test_safety_flagged_content_excluded_from_keywords(client, session_factory):
    """안전 신호 기록의 자유본문은 키워드·LLM 입력에서 제외 (docs/safety.md 6절)."""
    tokens = await signup(client)
    await client.post(
        "/moods",
        json={"mood_level": 1, "content": "산책 산책 산책 요즘 계속 죽고 싶다는 생각이 든다"},
        headers=auth_headers(tokens, idem=True),
    )
    res = await client.post(
        "/reports",
        json={"period_type": "weekly", "period_start": _this_monday()},
        headers=auth_headers(tokens, idem=True),
    )
    stats = res.json()["report"]["stats"]
    assert stats["total_entries"] == 1  # 기분 집계에는 포함
    assert stats["entries_with_text"] == 0  # 본문은 텍스트 분석에서 제외
    assert stats["keywords"] == []


async def test_invalid_period(client, user_tokens):
    res = await client.post(
        "/reports",
        json={"period_type": "weekly", "period_start": "2026-07-08"},  # 수요일
        headers=auth_headers(user_tokens, idem=True),
    )
    assert res.status_code == 400
    assert res.json()["code"] == "REPORT_PERIOD_INVALID"


async def test_hidden_ai_label_excluded_from_stats(client, session_factory):
    tokens = await signup(client)
    res = await client.post(
        "/moods",
        json={"mood_level": 4, "content": "행복하고 즐거운 시간"},
        headers=auth_headers(tokens, idem=True),
    )
    mood_id = res.json()["mood"]["id"]
    await run_pending_once(session_factory)

    # AI 라벨 숨김
    res = await client.patch(
        f"/moods/{mood_id}", json={"ai_label_hidden": True}, headers=auth_headers(tokens)
    )
    assert res.json()["mood"]["ai_label_hidden"] is True
    # 분석 결과는 유지된다 (라벨 설정만 변경)
    assert res.json()["mood"]["analysis_status"] == "succeeded"

    res = await client.post(
        "/reports",
        json={"period_type": "weekly", "period_start": _this_monday()},
        headers=auth_headers(tokens, idem=True),
    )
    stats = res.json()["report"]["stats"]
    assert stats["ai_emotion_distribution"] == []


async def test_report_stale_and_regenerated_after_label_settings_change(
    client, session_factory
):
    """라벨 override/hide는 분석 입력 버전을 바꾸지 않아도 리포트 입력은 바꾼다."""
    tokens = await signup(client)
    created = await client.post(
        "/moods",
        json={"mood_level": 4, "content": "행복하고 즐거운 시간"},
        headers=auth_headers(tokens, idem=True),
    )
    mood_id = created.json()["mood"]["id"]
    await run_pending_once(session_factory)

    first = await client.post(
        "/reports",
        json={"period_type": "weekly", "period_start": _this_monday()},
        headers=auth_headers(tokens, idem=True),
    )
    first_report = first.json()["report"]
    assert first_report["stats"]["ai_emotion_distribution"][0]["emotion"] == "기쁨"

    overridden = await client.patch(
        f"/moods/{mood_id}",
        json={"ai_emotion_override": "평온"},
        headers=auth_headers(tokens),
    )
    assert overridden.status_code == 200
    assert overridden.json()["mood"]["analysis_status"] == "succeeded"

    stale = await client.get(
        f"/reports/{first_report['id']}", headers=auth_headers(tokens)
    )
    assert stale.json()["stale"] is True

    second = await client.post(
        "/reports",
        json={"period_type": "weekly", "period_start": _this_monday()},
        headers=auth_headers(tokens, idem=True),
    )
    second_report = second.json()["report"]
    assert second_report["id"] != first_report["id"]
    assert second_report["stats"]["ai_emotion_distribution"][0]["emotion"] == "평온"

    hidden = await client.patch(
        f"/moods/{mood_id}",
        json={"ai_label_hidden": True},
        headers=auth_headers(tokens),
    )
    assert hidden.status_code == 200

    stale = await client.get(
        f"/reports/{second_report['id']}", headers=auth_headers(tokens)
    )
    assert stale.json()["stale"] is True

    third = await client.post(
        "/reports",
        json={"period_type": "weekly", "period_start": _this_monday()},
        headers=auth_headers(tokens, idem=True),
    )
    third_report = third.json()["report"]
    assert third_report["id"] not in {first_report["id"], second_report["id"]}
    assert third_report["stats"]["ai_emotion_distribution"] == []
