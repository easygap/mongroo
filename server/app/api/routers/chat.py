import asyncio
import json

import sqlalchemy as sa
from fastapi import APIRouter, Depends, Request
from fastapi.responses import StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.api import idempotency
from app.api.deps import decode_cursor, get_current_user, get_owned
from app.api.errors import AppError, error_body
from app.core.db import get_db, get_session_factory
from app.models.chat import ChatMessage, ChatRun, ChatSession
from app.models.enums import RunStatus
from app.models.user import User
from app.schemas.requests import ChatMessageRequest, ChatSessionCreateRequest
from app.services import chats as chat_service

router = APIRouter(tags=["chat"])

PAGE_SIZE = 30
SSE_HEARTBEAT_SECONDS = 15
SSE_MAX_SECONDS = 90
SSE_POLL_SECONDS = 0.7


@router.post("/chat/sessions", status_code=201)
async def create_session(
    body: ChatSessionCreateRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    session, greeting, outcome = await chat_service.start_session(db, user.id, body.plant_id)
    await db.commit()
    return {
        "session": chat_service.session_payload(session),
        "greeting": chat_service.message_payload(greeting),
        "reward": outcome.payload(),
    }


@router.get("/chat/sessions/{session_id}/messages")
async def list_messages(
    session_id: int,
    cursor: str | None = None,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await get_owned(db, ChatSession, session_id, user.id, "CHAT_SESSION_NOT_FOUND")
    query = (
        sa.select(ChatMessage)
        .where(ChatMessage.session_id == session_id)
        .order_by(ChatMessage.id)
        .limit(PAGE_SIZE + 1)
    )
    cursor_id = decode_cursor(cursor)
    if cursor_id is not None:
        query = query.where(ChatMessage.id > cursor_id)
    rows = list((await db.execute(query)).scalars())
    next_cursor = str(rows[PAGE_SIZE - 1].id) if len(rows) > PAGE_SIZE else None
    return {
        "items": [chat_service.message_payload(m) for m in rows[:PAGE_SIZE]],
        "next_cursor": next_cursor,
    }


@router.post("/chat/sessions/{session_id}/messages")
async def post_message(
    session_id: int,
    body: ChatMessageRequest,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    key = idempotency.require_key(request)
    session = await get_owned(db, ChatSession, session_id, user.id, "CHAT_SESSION_NOT_FOUND")

    async def handler():
        try:
            result = await chat_service.post_message(
                db,
                user.id,
                session,
                body.content,
                body.client_message_id,
                retry_failed=body.retry_failed,
            )
        except AppError as exc:
            if exc.code != "CHAT_SESSION_CLOSED":
                raise
            # 만료/턴 제한은 session을 CLOSED로 바꾼다. 예외를 라우터 밖으로
            # 그대로 던지면 멱등 트랜잭션 전체가 rollback되어 DB가 active로 남으므로,
            # 409도 저장 가능한 정상 멱등 응답으로 만들어 상태와 함께 commit한다.
            return exc.http_status, error_body(
                request, exc.code, exc.message, exc.details
            )
        await db.flush()
        if result["kind"] == "safety":
            return 200, {
                "run_id": None,
                "user_message": chat_service.message_payload(result["user_message"]),
                "safety_action": result["safety_action"],
            }
        return 202, {
            "run_id": result["run"].id,
            "status": result["run"].status,
            "user_message": chat_service.message_payload(result["user_message"]),
        }

    # SQLite의 로컬 잠금은 멱등 claim과 도메인 변경이 commit될 때까지 유지해야
    # 두 번째 요청이 첫 retry job을 보지 못하고 다시 큐잉하는 틈이 생기지 않는다.
    async with chat_service.session_lock(session_id):
        return await idempotency.run_idempotent(
            db, user.id, "chat_message", key,
            {"session_id": session_id, **body.model_dump()}, handler,
        )


async def _load_run(db: AsyncSession, run_id: int, user_id: int) -> tuple[ChatRun, ChatMessage | None]:
    run = await db.get(ChatRun, run_id)
    if run is None:
        raise AppError(404, "CHAT_RUN_NOT_FOUND", "요청을 찾을 수 없습니다.")
    session = await db.get(ChatSession, run.session_id)
    if session is None or session.user_id != user_id:
        raise AppError(403, "FORBIDDEN", "접근 권한이 없습니다.")
    message = None
    if run.assistant_message_id is not None:
        message = await db.get(ChatMessage, run.assistant_message_id)
    return run, message


@router.get("/chat/runs/{run_id}")
async def get_run(
    run_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    run, message = await _load_run(db, run_id, user.id)
    return chat_service.run_payload(run, message)


def _sse(event: str, data: dict) -> str:
    return f"event: {event}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"


@router.get("/chat/runs/{run_id}/events")
async def run_events(
    run_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # 접근 검증은 요청 세션에서 먼저 수행한다
    await _load_run(db, run_id, user.id)
    factory = get_session_factory()

    async def stream():
        last_status = None
        waited = 0.0
        last_beat = 0.0
        while True:
            async with factory() as poll_db:
                run = await poll_db.get(ChatRun, run_id)
                message = None
                if run is not None and run.assistant_message_id is not None:
                    message = await poll_db.get(ChatMessage, run.assistant_message_id)
            if run is None:
                yield _sse("error", {"run_id": run_id, "error_code": "CHAT_RUN_NOT_FOUND"})
                return
            if run.status != last_status:
                last_status = run.status
                yield _sse("status", {"run_id": run.id, "status": run.status})
            if run.status == RunStatus.SUCCEEDED and message is not None:
                yield _sse("message", {
                    "message_id": message.id, "content": message.content,
                })
                yield _sse("done", {"run_id": run.id})
                return
            if run.status == RunStatus.FAILED:
                yield _sse("error", {"run_id": run.id, "error_code": run.error_code})
                return
            if waited >= SSE_MAX_SECONDS:
                # 생성은 계속된다. 클라이언트는 run 조회로 복구한다 (design.md 5.5)
                yield _sse("error", {"run_id": run.id, "error_code": "SSE_TIMEOUT"})
                return
            if waited - last_beat >= SSE_HEARTBEAT_SECONDS:
                last_beat = waited
                yield ": hb\n\n"
            await asyncio.sleep(SSE_POLL_SECONDS)
            waited += SSE_POLL_SECONDS

    return StreamingResponse(
        stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
