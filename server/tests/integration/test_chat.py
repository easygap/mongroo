import asyncio
import uuid

import pytest
import sqlalchemy as sa

from app.core.config import get_settings
from app.models.plant import Plant
from app.services.plants import refresh_active_plant_growth
from app.workers.ai_worker import run_pending_once
from tests.conftest import auth_headers, signup


async def _start_session(client, tokens):
    res = await client.post("/chat/sessions", json={}, headers=auth_headers(tokens))
    assert res.status_code == 201, res.text
    return res.json()


async def _send(client, tokens, session_id, content):
    return await client.post(
        f"/chat/sessions/{session_id}/messages",
        json={"content": content, "client_message_id": uuid.uuid4().hex},
        headers=auth_headers(tokens, idem=True),
    )


async def _create_guard_rejected_run(client, session_factory, monkeypatch):
    """Create a confirmed failed run through the same worker path used in production."""
    from app.ai import llm as llm_module
    from app.workers import ai_worker

    class GuardRejectedLlm:
        model_version = "retry-precondition"

        async def chat(self, messages):
            return "너는 우울증이야. 병원 갈 필요 없어."

    llm = GuardRejectedLlm()
    monkeypatch.setattr(llm_module, "get_llm", lambda: llm)
    monkeypatch.setattr(ai_worker, "get_llm", lambda: llm)

    tokens = await signup(client)
    session_id = (await _start_session(client, tokens))["session"]["id"]
    client_message_id = uuid.uuid4().hex
    content = "첫 답변을 실패 상태로 만들어 줘"
    first = await client.post(
        f"/chat/sessions/{session_id}/messages",
        json={"content": content, "client_message_id": client_message_id},
        headers=auth_headers(tokens, idem=True),
    )
    assert first.status_code == 202
    run_id = first.json()["run_id"]
    await run_pending_once(session_factory)
    failed = await client.get(f"/chat/runs/{run_id}", headers=auth_headers(tokens))
    assert failed.status_code == 200
    assert failed.json()["status"] == "failed"
    return tokens, session_id, run_id, client_message_id, content


async def test_chat_flow_with_fake_llm(client, session_factory):
    tokens = await signup(client)
    body = await _start_session(client, tokens)
    session_id = body["session"]["id"]
    assert body["greeting"]["role"] == "plant"
    assert body["reward"] is not None  # 하루 첫 채팅 시작 +5
    # 한도는 거절을 판정하는 쪽이 알려 준다. 앱이 따로 들고 있으면 운영에서
    # 값을 바꿨을 때 화면의 `최대 10번`과 실제 거절 시점이 어긋난다.
    assert (
        body["session"]["max_user_turns"]
        == get_settings().chat_session_max_user_turns
    )

    res = await _send(client, tokens, session_id, "오늘 좀 힘든 하루였어")
    assert res.status_code == 202
    run_id = res.json()["run_id"]

    await run_pending_once(session_factory)

    res = await client.get(f"/chat/runs/{run_id}", headers=auth_headers(tokens))
    body = res.json()
    assert body["status"] == "succeeded"
    assert body["message"]["role"] == "plant"
    assert body["message"]["content"]

    res = await client.get(
        f"/chat/sessions/{session_id}/messages", headers=auth_headers(tokens)
    )
    roles = [m["role"] for m in res.json()["items"]]
    assert roles == ["plant", "user", "plant"]  # greeting, user, reply


async def test_revealed_growth_persona_shapes_greeting_and_generated_prompt(
    client, session_factory, monkeypatch
):
    from app.workers import ai_worker

    class CapturingLlm:
        model_version = "capture-growth-persona"

        def __init__(self):
            self.messages = None

        async def chat(self, messages):
            self.messages = messages
            return "햇살결답게 잎을 펼쳐볼게. 오늘은 어땠어?"

    tokens = await signup(client)
    for index in range(3):
        await client.post(
            "/moods",
            json={"content": f"행복하고 즐거워서 오래 웃었던 하루 {index}"},
            headers=auth_headers(tokens, idem=True),
        )
    await run_pending_once(session_factory)
    async with session_factory() as db:
        plant = await db.scalar(
            sa.select(Plant).where(Plant.user_id == tokens["user"]["id"])
        )
        plant.exp = 300
        await refresh_active_plant_growth(
            db, plant.user_id, plant=plant, rebuild_profile=False
        )
        await db.commit()

    started = await _start_session(client, tokens)
    assert "햇빛 자리 찾았어" in started["greeting"]["content"]

    llm = CapturingLlm()
    monkeypatch.setattr(ai_worker, "get_llm", lambda: llm)
    sent = await _send(
        client, tokens, started["session"]["id"], "오늘 이야기를 들려줄게"
    )
    assert sent.status_code == 202
    await run_pending_once(session_factory)
    assert "햇살결" in llm.messages[0]["content"]
    assert "다정함·나눔" in llm.messages[0]["content"]
    assert "현재 성장 단계: 4 (bloom)" in llm.messages[0]["content"]
    assert "식물 기질 연출:" in llm.messages[0]["content"]


async def test_unrevealed_early_stage_keeps_species_greeting(client):
    tokens = await signup(client)
    started = await _start_session(client, tokens)
    assert started["greeting"]["content"].startswith("새싹몬이 ")
    assert "햇살 자리" not in started["greeting"]["content"]


async def test_chat_safety_path_blocks_llm(client, session_factory):
    tokens = await signup(client)
    body = await _start_session(client, tokens)
    session_id = body["session"]["id"]

    res = await _send(client, tokens, session_id, "요즘 계속 죽고 싶다는 생각만 들어")
    assert res.status_code == 200
    body = res.json()
    assert body["run_id"] is None
    action = body["safety_action"]
    assert action["action"] == "show_support_screen"
    assert any(r["phone"] == "109" for r in action["resources"])

    # LLM job이 만들어지지 않았다
    processed = await run_pending_once(session_factory)
    assert processed == 0


async def test_chat_safety_state_blocks_later_soft_message_from_llm(
    client, session_factory
):
    tokens = await signup(client)
    body = await _start_session(client, tokens)
    session_id = body["session"]["id"]

    concern = await _send(
        client, tokens, session_id, "요즘 계속 죽고 싶다는 생각만 들어"
    )
    assert concern.status_code == 200
    assert concern.json()["run_id"] is None

    # 현재 문장만 보면 평범하지만, 같은 세션의 concern은 안전 하한으로 유지된다.
    follow_up = await _send(client, tokens, session_id, "괜찮지만 아직 힘들어")
    assert follow_up.status_code == 200
    assert follow_up.json()["run_id"] is None
    assert follow_up.json()["safety_action"]["action"] == "show_support_screen"

    # 두 입력 모두 지원 경로로 끝나 AI 생성 job이 하나도 없어야 한다.
    assert await run_pending_once(session_factory) == 0


async def test_duplicate_client_message_id_returns_same_run(client, session_factory):
    tokens = await signup(client)
    body = await _start_session(client, tokens)
    session_id = body["session"]["id"]
    cmid = uuid.uuid4().hex

    res1 = await client.post(
        f"/chat/sessions/{session_id}/messages",
        json={"content": "안녕", "client_message_id": cmid},
        headers=auth_headers(tokens, idem=True),
    )
    await run_pending_once(session_factory)
    res2 = await client.post(
        f"/chat/sessions/{session_id}/messages",
        json={"content": "안녕", "client_message_id": cmid},
        headers=auth_headers(tokens, idem=True),
    )
    assert res1.json()["run_id"] == res2.json()["run_id"]


async def test_client_message_id_never_leaks_another_request(client):
    tokens_a = await signup(client)
    tokens_b = await signup(client)
    session_a = (await _start_session(client, tokens_a))["session"]["id"]
    session_b = (await _start_session(client, tokens_b))["session"]["id"]
    cmid = uuid.uuid4().hex

    first = await client.post(
        f"/chat/sessions/{session_a}/messages",
        json={"content": "A의 비공개 메시지", "client_message_id": cmid},
        headers=auth_headers(tokens_a, idem=True),
    )
    assert first.status_code == 202

    other_user = await client.post(
        f"/chat/sessions/{session_b}/messages",
        json={"content": "B의 메시지", "client_message_id": cmid},
        headers=auth_headers(tokens_b, idem=True),
    )
    assert other_user.status_code == 409
    assert other_user.json()["code"] == "CLIENT_MESSAGE_ID_CONFLICT"
    assert "run_id" not in other_user.json()

    changed_retry = await client.post(
        f"/chat/sessions/{session_a}/messages",
        json={"content": "다른 내용", "client_message_id": cmid},
        headers=auth_headers(tokens_a, idem=True),
    )
    assert changed_retry.status_code == 409
    assert changed_retry.json()["code"] == "CLIENT_MESSAGE_ID_CONFLICT"


async def test_active_run_conflict(client):
    tokens = await signup(client)
    body = await _start_session(client, tokens)
    session_id = body["session"]["id"]

    res = await _send(client, tokens, session_id, "첫 메시지")
    assert res.status_code == 202
    # 처리 전 두 번째 메시지 → 진행 중 run 존재
    res = await _send(client, tokens, session_id, "두 번째 메시지")
    assert res.status_code == 409
    assert res.json()["code"] == "CHAT_RUN_ACTIVE_EXISTS"


async def test_guard_rejected_reply_not_delivered(client, session_factory, monkeypatch):
    from app.ai import llm as llm_module

    class BadLlm:
        model_version = "bad-llm"

        async def chat(self, messages):
            return "너는 우울증이야. 병원 갈 필요 없어."

    monkeypatch.setattr(llm_module, "get_llm", lambda: BadLlm())
    # worker 모듈이 참조하는 심볼도 교체
    from app.workers import ai_worker

    monkeypatch.setattr(ai_worker, "get_llm", lambda: BadLlm())

    tokens = await signup(client)
    body = await _start_session(client, tokens)
    res = await _send(client, tokens, body["session"]["id"], "요즘 기분이 가라앉아")
    run_id = res.json()["run_id"]

    await run_pending_once(session_factory)

    res = await client.get(f"/chat/runs/{run_id}", headers=auth_headers(tokens))
    body = res.json()
    assert body["status"] == "failed"
    assert body["error_code"] == "GUARD_REJECTED"
    assert body["message"] is None


async def test_confirmed_failed_run_can_retry_without_duplicate_user_message(
    client, session_factory, monkeypatch
):
    from app.ai import llm as llm_module
    from app.workers import ai_worker

    class FailThenRecoverLlm:
        model_version = "retry-llm"

        def __init__(self):
            self.calls = 0

        async def chat(self, messages):
            self.calls += 1
            if self.calls == 1:
                return "너는 우울증이야. 병원 갈 필요 없어."
            return "그랬구나. 오늘 마음을 한 문장으로 천천히 돌아볼까?"

    llm = FailThenRecoverLlm()
    monkeypatch.setattr(llm_module, "get_llm", lambda: llm)
    monkeypatch.setattr(ai_worker, "get_llm", lambda: llm)

    tokens = await signup(client)
    session = await _start_session(client, tokens)
    session_id = session["session"]["id"]
    client_message_id = uuid.uuid4().hex
    content = "요즘 기분이 가라앉아"

    first_headers = auth_headers(tokens)
    first_headers["Idempotency-Key"] = uuid.uuid4().hex
    first = await client.post(
        f"/chat/sessions/{session_id}/messages",
        json={"content": content, "client_message_id": client_message_id},
        headers=first_headers,
    )
    assert first.status_code == 202
    run_id = first.json()["run_id"]

    await run_pending_once(session_factory)
    failed = await client.get(f"/chat/runs/{run_id}", headers=auth_headers(tokens))
    assert failed.json()["status"] == "failed"

    retry_headers = auth_headers(tokens)
    retry_headers["Idempotency-Key"] = uuid.uuid4().hex
    retry = await client.post(
        f"/chat/sessions/{session_id}/messages",
        json={
            "content": content,
            "client_message_id": client_message_id,
            "retry_failed": True,
        },
        headers=retry_headers,
    )
    assert retry.status_code == 202
    assert retry.json()["run_id"] == run_id
    assert retry.json()["status"] == "queued"

    await run_pending_once(session_factory)
    recovered = await client.get(f"/chat/runs/{run_id}", headers=auth_headers(tokens))
    assert recovered.json()["status"] == "succeeded"
    assert recovered.json()["message"]["content"]

    messages = await client.get(
        f"/chat/sessions/{session_id}/messages", headers=auth_headers(tokens)
    )
    assert [message["role"] for message in messages.json()["items"]] == [
        "plant",
        "user",
        "plant",
    ]
    assert llm.calls == 2


async def test_retry_failed_coalesces_non_failed_run_without_duplicate_turn(client):
    tokens = await signup(client)
    session_id = (await _start_session(client, tokens))["session"]["id"]
    client_message_id = uuid.uuid4().hex
    content = "답변을 기다리는 중이야"

    first = await client.post(
        f"/chat/sessions/{session_id}/messages",
        json={"content": content, "client_message_id": client_message_id},
        headers=auth_headers(tokens, idem=True),
    )
    assert first.status_code == 202

    retry = await client.post(
        f"/chat/sessions/{session_id}/messages",
        json={
            "content": content,
            "client_message_id": client_message_id,
            "retry_failed": True,
        },
        headers=auth_headers(tokens, idem=True),
    )
    assert retry.status_code == 202
    assert retry.json()["run_id"] == first.json()["run_id"]
    assert retry.json()["status"] == "queued"

    messages = await client.get(
        f"/chat/sessions/{session_id}/messages", headers=auth_headers(tokens)
    )
    assert [message["role"] for message in messages.json()["items"]] == [
        "plant",
        "user",
    ]


async def test_failed_retry_cannot_bypass_newer_or_active_turn(
    client, session_factory, monkeypatch
):
    from app.ai import llm as llm_module
    from app.workers import ai_worker

    class GuardRejectedLlm:
        model_version = "always-rejected"

        async def chat(self, messages):
            return "너는 우울증이야. 병원 갈 필요 없어."

    llm = GuardRejectedLlm()
    monkeypatch.setattr(llm_module, "get_llm", lambda: llm)
    monkeypatch.setattr(ai_worker, "get_llm", lambda: llm)

    tokens = await signup(client)
    session_id = (await _start_session(client, tokens))["session"]["id"]
    first_client_id = uuid.uuid4().hex
    first_content = "첫 번째 이야기"
    first = await client.post(
        f"/chat/sessions/{session_id}/messages",
        json={"content": first_content, "client_message_id": first_client_id},
        headers=auth_headers(tokens, idem=True),
    )
    await run_pending_once(session_factory)
    assert (
        await client.get(
            f"/chat/runs/{first.json()['run_id']}", headers=auth_headers(tokens)
        )
    ).json()["status"] == "failed"

    second = await _send(client, tokens, session_id, "그 뒤에 이어진 이야기")
    assert second.status_code == 202

    active_retry = await client.post(
        f"/chat/sessions/{session_id}/messages",
        json={
            "content": first_content,
            "client_message_id": first_client_id,
            "retry_failed": True,
        },
        headers=auth_headers(tokens, idem=True),
    )
    assert active_retry.status_code == 409
    assert active_retry.json()["code"] == "CHAT_RUN_ACTIVE_EXISTS"

    await run_pending_once(session_factory)
    stale_retry = await client.post(
        f"/chat/sessions/{session_id}/messages",
        json={
            "content": first_content,
            "client_message_id": first_client_id,
            "retry_failed": True,
        },
        headers=auth_headers(tokens, idem=True),
    )
    assert stale_retry.status_code == 409
    assert stale_retry.json()["code"] == "CHAT_RETRY_STALE"


async def test_safety_turn_permanently_blocks_failed_run_retry(
    client, session_factory, monkeypatch
):
    from app.ai import llm as llm_module
    from app.models.enums import JobType
    from app.models.ops import AiJob
    from app.workers import ai_worker
    import sqlalchemy as sa

    class GuardRejectedLlm:
        model_version = "always-rejected"

        async def chat(self, messages):
            return "너는 우울증이야. 병원 갈 필요 없어."

    llm = GuardRejectedLlm()
    monkeypatch.setattr(llm_module, "get_llm", lambda: llm)
    monkeypatch.setattr(ai_worker, "get_llm", lambda: llm)

    tokens = await signup(client)
    session_id = (await _start_session(client, tokens))["session"]["id"]
    client_message_id = uuid.uuid4().hex
    content = "첫 답변은 실패하게 해줘"
    first = await client.post(
        f"/chat/sessions/{session_id}/messages",
        json={"content": content, "client_message_id": client_message_id},
        headers=auth_headers(tokens, idem=True),
    )
    await run_pending_once(session_factory)
    assert first.status_code == 202

    safety_turn = await _send(
        client, tokens, session_id, "요즘 계속 죽고 싶다는 생각만 들어"
    )
    assert safety_turn.status_code == 200

    async with session_factory() as db:
        jobs_before = await db.scalar(
            sa.select(sa.func.count())
            .select_from(AiJob)
            .where(AiJob.job_type == JobType.CHAT_GENERATION)
        )

    retry = await client.post(
        f"/chat/sessions/{session_id}/messages",
        json={
            "content": content,
            "client_message_id": client_message_id,
            "retry_failed": True,
        },
        headers=auth_headers(tokens, idem=True),
    )
    assert retry.status_code == 409
    assert retry.json()["code"] == "CHAT_RETRY_SAFETY_BLOCKED"

    async with session_factory() as db:
        jobs_after = await db.scalar(
            sa.select(sa.func.count())
            .select_from(AiJob)
            .where(AiJob.job_type == JobType.CHAT_GENERATION)
        )
    assert jobs_after == jobs_before


async def test_simultaneous_failed_retries_queue_once_on_sqlite(
    client, session_factory, monkeypatch
):
    from app.ai import llm as llm_module
    from app.workers import ai_worker

    class FailThenRecoverLlm:
        model_version = "concurrent-retry"

        def __init__(self):
            self.calls = 0

        async def chat(self, messages):
            self.calls += 1
            if self.calls == 1:
                return "너는 우울증이야. 병원 갈 필요 없어."
            return "한 번에 하나씩 차분히 이어가 볼까?"

    llm = FailThenRecoverLlm()
    monkeypatch.setattr(llm_module, "get_llm", lambda: llm)
    monkeypatch.setattr(ai_worker, "get_llm", lambda: llm)

    tokens = await signup(client)
    session_id = (await _start_session(client, tokens))["session"]["id"]
    client_message_id = uuid.uuid4().hex
    content = "동시에 다시 시도해 볼게"
    first = await client.post(
        f"/chat/sessions/{session_id}/messages",
        json={"content": content, "client_message_id": client_message_id},
        headers=auth_headers(tokens, idem=True),
    )
    await run_pending_once(session_factory)
    assert first.status_code == 202

    async def retry():
        return await client.post(
            f"/chat/sessions/{session_id}/messages",
            json={
                "content": content,
                "client_message_id": client_message_id,
                "retry_failed": True,
            },
            headers=auth_headers(tokens, idem=True),
        )

    one, two = await asyncio.gather(retry(), retry())
    assert [one.status_code, two.status_code] == [202, 202]
    assert one.json()["run_id"] == two.json()["run_id"] == first.json()["run_id"]

    from app.models.enums import JobType
    from app.models.ops import AiJob
    import sqlalchemy as sa

    async with session_factory() as db:
        input_versions = list(
            (
                await db.execute(
                    sa.select(AiJob.input_version)
                    .where(
                        AiJob.job_type == JobType.CHAT_GENERATION,
                        AiJob.resource_type == "chat_run",
                        AiJob.resource_id == first.json()["run_id"],
                    )
                    .order_by(AiJob.input_version)
                )
            ).scalars()
        )
    assert input_versions == [1, 2]

    await run_pending_once(session_factory)
    messages = await client.get(
        f"/chat/sessions/{session_id}/messages", headers=auth_headers(tokens)
    )
    assert [message["role"] for message in messages.json()["items"]] == [
        "plant",
        "user",
        "plant",
    ]
    assert llm.calls == 2


async def test_failed_retry_racing_new_message_creates_one_active_run_and_job(
    client, session_factory, monkeypatch
):
    import sqlalchemy as sa

    from app.models.chat import ChatRun
    from app.models.enums import JobStatus, JobType, RunStatus
    from app.models.ops import AiJob

    (
        tokens,
        session_id,
        failed_run_id,
        client_message_id,
        content,
    ) = await _create_guard_rejected_run(client, session_factory, monkeypatch)

    async def retry_failed():
        return await client.post(
            f"/chat/sessions/{session_id}/messages",
            json={
                "content": content,
                "client_message_id": client_message_id,
                "retry_failed": True,
            },
            headers=auth_headers(tokens, idem=True),
        )

    async def send_new_message():
        return await _send(client, tokens, session_id, "이제 새로운 이야기를 할게")

    retry, new_message = await asyncio.gather(retry_failed(), send_new_message())
    assert sorted([retry.status_code, new_message.status_code]) == [202, 409]

    accepted = retry if retry.status_code == 202 else new_message
    rejected = new_message if retry.status_code == 202 else retry
    assert rejected.json()["code"] == "CHAT_RUN_ACTIVE_EXISTS"

    async with session_factory() as db:
        active_runs = list(
            (
                await db.execute(
                    sa.select(ChatRun).where(
                        ChatRun.session_id == session_id,
                        ChatRun.status.in_([RunStatus.QUEUED, RunStatus.GENERATING]),
                    )
                )
            ).scalars()
        )
        pending_job_run_ids = list(
            (
                await db.execute(
                    sa.select(AiJob.resource_id)
                    .join(ChatRun, AiJob.resource_id == ChatRun.id)
                    .where(
                        AiJob.job_type == JobType.CHAT_GENERATION,
                        AiJob.resource_type == "chat_run",
                        AiJob.status == JobStatus.PENDING,
                        ChatRun.session_id == session_id,
                    )
                )
            ).scalars()
        )

    assert len(active_runs) == 1
    assert active_runs[0].id == accepted.json()["run_id"]
    assert pending_job_run_ids == [active_runs[0].id]
    if retry.status_code == 202:
        assert active_runs[0].id == failed_run_id
    else:
        assert active_runs[0].id != failed_run_id


@pytest.mark.parametrize("session_state", ["closed", "expired"])
async def test_failed_retry_rejects_unavailable_session_without_new_job(
    client, session_factory, monkeypatch, session_state
):
    from datetime import timedelta

    import sqlalchemy as sa

    from app.core.config import get_settings
    from app.core.timeutil import utcnow
    from app.models.chat import ChatSession
    from app.models.enums import ChatSessionStatus, JobType
    from app.models.ops import AiJob

    (
        tokens,
        session_id,
        run_id,
        client_message_id,
        content,
    ) = await _create_guard_rejected_run(client, session_factory, monkeypatch)

    async with session_factory() as db:
        session = await db.get(ChatSession, session_id)
        assert session is not None
        if session_state == "closed":
            session.status = ChatSessionStatus.CLOSED
            session.ended_at = utcnow()
        else:
            session.started_at = utcnow() - timedelta(
                minutes=get_settings().chat_session_max_minutes + 1
            )
        jobs_before = await db.scalar(
            sa.select(sa.func.count())
            .select_from(AiJob)
            .where(
                AiJob.job_type == JobType.CHAT_GENERATION,
                AiJob.resource_type == "chat_run",
                AiJob.resource_id == run_id,
            )
        )
        await db.commit()

    retry = await client.post(
        f"/chat/sessions/{session_id}/messages",
        json={
            "content": content,
            "client_message_id": client_message_id,
            "retry_failed": True,
        },
        headers=auth_headers(tokens, idem=True),
    )
    assert retry.status_code == 409
    assert retry.json()["code"] == "CHAT_SESSION_CLOSED"

    async with session_factory() as db:
        persisted_session = await db.get(ChatSession, session_id)
        assert persisted_session is not None
        assert persisted_session.status == ChatSessionStatus.CLOSED
        assert persisted_session.ended_at is not None
        jobs_after = await db.scalar(
            sa.select(sa.func.count())
            .select_from(AiJob)
            .where(
                AiJob.job_type == JobType.CHAT_GENERATION,
                AiJob.resource_type == "chat_run",
                AiJob.resource_id == run_id,
            )
        )
    assert jobs_after == jobs_before
