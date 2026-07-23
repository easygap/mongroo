import asyncio
import threading

import sqlalchemy as sa

from app.models.enums import AnalysisStatus, JobStatus
from app.models.mood import MoodEntry
from app.models.ops import AiJob
from app.models.plant import Plant
from app.workers.ai_worker import (
    fail_jobs_for_disabled_mode,
    recover_stale_jobs,
    run_pending_once,
)
from tests.conftest import auth_headers, signup


async def test_mood_analysis_job(client, session_factory):
    tokens = await signup(client)
    res = await client.post(
        "/moods",
        json={"mood_level": 4, "content": "오늘 정말 행복하고 즐거운 하루였다"},
        headers=auth_headers(tokens, idem=True),
    )
    mood_id = res.json()["mood"]["id"]
    assert res.json()["mood"]["analysis_status"] == "pending"

    processed = await run_pending_once(session_factory)
    assert processed == 1

    res = await client.get(f"/moods/{mood_id}", headers=auth_headers(tokens))
    body = res.json()
    assert body["analysis_status"] == "succeeded"
    assert body["ai_emotion"] == "기쁨"
    assert body["analysis_model_version"] == "fake-clf-3"


async def test_stale_input_version_not_applied(client, session_factory):
    tokens = await signup(client)
    res = await client.post(
        "/moods",
        json={"mood_level": 2, "content": "오늘은 슬픈 하루였다 눈물이 났다"},
        headers=auth_headers(tokens, idem=True),
    )
    mood_id = res.json()["mood"]["id"]

    # job 처리 전에 본문을 수정 → input_version 증가
    res = await client.patch(
        f"/moods/{mood_id}",
        json={"content": "수정했더니 화가 나고 짜증이 폭발했다"},
        headers=auth_headers(tokens),
    )
    assert res.json()["mood"]["analysis_status"] == "pending"

    await run_pending_once(session_factory)

    res = await client.get(f"/moods/{mood_id}", headers=auth_headers(tokens))
    body = res.json()
    # v1 job 결과는 버려지고 v2 결과만 반영된다
    assert body["analysis_status"] == "succeeded"
    assert body["ai_emotion"] == "분노"


async def test_classifier_error_does_not_restore_pending_on_newer_empty_version(
    client, session_factory, monkeypatch
):
    from app.ai.classifier import ClassifierError
    from app.workers import ai_worker

    started = threading.Event()
    release = threading.Event()

    class BlockingBrokenClassifier:
        model_version = "blocking-broken"

        def classify(self, text):
            started.set()
            if not release.wait(timeout=5):
                raise AssertionError("test did not release classifier")
            raise ClassifierError("broken")

    monkeypatch.setattr(ai_worker, "get_classifier", lambda: BlockingBrokenClassifier())
    tokens = await signup(client)
    created = await client.post(
        "/moods",
        json={"mood_level": 4, "content": "분석 중 수정할 구 버전 일기"},
        headers=auth_headers(tokens, idem=True),
    )
    mood_id = created.json()["mood"]["id"]

    worker_task = asyncio.create_task(run_pending_once(session_factory))
    assert await asyncio.to_thread(started.wait, 2)
    try:
        patched = await client.patch(
            f"/moods/{mood_id}",
            json={"content": ""},
            headers=auth_headers(tokens),
        )
        assert patched.status_code == 200, patched.text
        assert patched.json()["mood"]["analysis_status"] == "not_requested"
    finally:
        release.set()
    await worker_task

    mood = await client.get(f"/moods/{mood_id}", headers=auth_headers(tokens))
    assert mood.json()["analysis_status"] == "not_requested"
    async with session_factory() as db:
        entry = await db.get(MoodEntry, mood_id)
        job = await db.scalar(sa.select(AiJob).where(AiJob.resource_id == mood_id))
        plant = await db.scalar(
            sa.select(Plant).where(Plant.user_id == tokens["user"]["id"])
        )
        assert entry.analysis_version == 2
        assert job.status == JobStatus.SUCCEEDED
        assert plant.emotion_profile["pending_count"] == 0


async def test_recover_stale_running_jobs(client, session_factory):
    tokens = await signup(client)
    await client.post(
        "/moods",
        json={"mood_level": 3, "content": "불안하고 걱정되는 하루"},
        headers=auth_headers(tokens, idem=True),
    )
    from datetime import timedelta

    from app.core.timeutil import utcnow

    async with session_factory() as db:
        await db.execute(
            sa.update(AiJob).values(
                status=JobStatus.RUNNING, locked_at=utcnow() - timedelta(hours=1)
            )
        )
        await db.commit()
        recovered = await recover_stale_jobs(db)
        assert recovered == 1

    processed = await run_pending_once(session_factory)
    assert processed == 1


async def test_llm_final_failure_marks_run_failed(client, session_factory, monkeypatch):
    """재시도 소진 후 run이 queued로 방치되지 않고 failed로 마감된다."""
    import uuid

    from app.ai.llm import LlmError
    from app.core.config import get_settings
    from app.workers import ai_worker

    class DownLlm:
        model_version = "down"

        async def chat(self, messages):
            raise LlmError("LLM_UNAVAILABLE")

    monkeypatch.setattr(ai_worker, "get_llm", lambda: DownLlm())
    monkeypatch.setenv("JOB_MAX_ATTEMPTS", "1")
    get_settings.cache_clear()
    try:
        tokens = await signup(client)
        res = await client.post("/chat/sessions", json={}, headers=auth_headers(tokens))
        session_id = res.json()["session"]["id"]
        res = await client.post(
            f"/chat/sessions/{session_id}/messages",
            json={"content": "안녕", "client_message_id": uuid.uuid4().hex},
            headers=auth_headers(tokens, idem=True),
        )
        run_id = res.json()["run_id"]

        await run_pending_once(session_factory)

        res = await client.get(f"/chat/runs/{run_id}", headers=auth_headers(tokens))
        assert res.json()["status"] == "failed"
        assert res.json()["error_code"] == "LLM_UNAVAILABLE"
    finally:
        monkeypatch.delenv("JOB_MAX_ATTEMPTS", raising=False)
        get_settings.cache_clear()


async def test_analysis_disabled_mode(client, session_factory, monkeypatch):
    from app.core.config import get_settings

    tokens = await signup(client)
    monkeypatch.setenv("AI_MODE", "disabled")
    get_settings.cache_clear()
    try:
        res = await client.post(
            "/moods",
            json={"mood_level": 4, "content": "AI 없이도 기록은 된다"},
            headers=auth_headers(tokens, idem=True),
        )
        assert res.status_code == 201
        assert res.json()["mood"]["analysis_status"] == "not_requested"
        async with session_factory() as db:
            count = await db.scalar(sa.select(sa.func.count()).select_from(AiJob))
            assert count == 0
    finally:
        monkeypatch.setenv("AI_MODE", "fake")
        get_settings.cache_clear()


async def test_disabled_transition_finishes_existing_pending_and_running_jobs(
    client, session_factory
):
    tokens = await signup(client)
    mood_ids = []
    for index in range(2):
        created = await client.post(
            "/moods",
            json={"content": f"비활성 전환 전에 남은 분석 일기 {index}"},
            headers=auth_headers(tokens, idem=True),
        )
        mood_ids.append(created.json()["mood"]["id"])

    async with session_factory() as db:
        await db.execute(
            sa.update(AiJob)
            .where(AiJob.resource_id == mood_ids[0])
            .values(status=JobStatus.RUNNING)
        )
        await db.commit()
        assert await fail_jobs_for_disabled_mode(db) == 2

    async with session_factory() as db:
        jobs = list(
            (await db.execute(sa.select(AiJob).order_by(AiJob.resource_id))).scalars()
        )
        entries = list(
            (
                await db.execute(sa.select(MoodEntry).where(MoodEntry.id.in_(mood_ids)))
            ).scalars()
        )
        plant = await db.scalar(
            sa.select(Plant).where(Plant.user_id == tokens["user"]["id"])
        )
        assert all(job.status == JobStatus.FAILED for job in jobs)
        assert all(job.last_error_code == "CLASSIFIER_UNAVAILABLE" for job in jobs)
        assert all(entry.analysis_status == AnalysisStatus.FAILED for entry in entries)
        assert plant.emotion_profile["pending_count"] == 0
        assert plant.emotion_profile["unavailable_count"] == 2


async def test_terminal_analysis_failure_updates_job_entry_and_growth_together(
    client, session_factory, monkeypatch
):
    from app.ai.classifier import ClassifierError
    from app.core.config import get_settings
    from app.models.plant import Plant
    from app.workers import ai_worker

    class BrokenClassifier:
        model_version = "broken"

        def classify(self, text):
            raise ClassifierError("broken")

    monkeypatch.setattr(ai_worker, "get_classifier", lambda: BrokenClassifier())
    monkeypatch.setenv("JOB_MAX_ATTEMPTS", "1")
    get_settings.cache_clear()
    try:
        tokens = await signup(client)
        created = await client.post(
            "/moods",
            json={"content": "분석 실패의 원자성을 확인하는 일기"},
            headers=auth_headers(tokens, idem=True),
        )
        mood_id = created.json()["mood"]["id"]
        await run_pending_once(session_factory)

        mood = await client.get(f"/moods/{mood_id}", headers=auth_headers(tokens))
        assert mood.json()["analysis_status"] == "failed"
        assert mood.json()["analysis_error_code"] == "CLASSIFIER_ERROR"
        async with session_factory() as db:
            job = await db.scalar(sa.select(AiJob).where(AiJob.resource_id == mood_id))
            plant = await db.scalar(
                sa.select(Plant).where(Plant.user_id == tokens["user"]["id"])
            )
            assert job.status == JobStatus.FAILED
            assert job.last_error_code == "CLASSIFIER_ERROR"
            assert plant.emotion_profile["pending_count"] == 0
            assert plant.emotion_profile["unavailable_count"] == 1
    finally:
        monkeypatch.delenv("JOB_MAX_ATTEMPTS", raising=False)
        get_settings.cache_clear()
