"""식물 대화 서비스 (design.md 5.5, 6.2, 6.3)."""

import asyncio
import threading
import weakref
from datetime import timedelta

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.errors import AppError
from app.core.config import get_settings
from app.core.timeutil import local_date_of, to_utc_iso, utcnow
from app.ai import safety
from app.ai.prompts import greeting_line
from app.models.chat import ChatMessage, ChatRun, ChatSession
from app.models.enums import (
    ChatSessionStatus,
    JobStatus,
    JobType,
    ReflectionStage,
    RewardEventType,
    RunStatus,
    SafetyState,
)
from app.models.ops import AiJob
from app.models.plant import Plant, PlantSpecies
from app.models.enums import PlantStatus
from app.services import plants as plant_service, rewards
from app.services.moods import record_safety_event
from app.services.rewards import RewardOutcome


_session_locks_guard = threading.Lock()
_session_locks: weakref.WeakValueDictionary[int, asyncio.Lock] = (
    weakref.WeakValueDictionary()
)


def session_lock(session_id: int) -> asyncio.Lock:
    """SQLite에서도 세션의 turn/run 검사를 MySQL 행 잠금처럼 직렬화한다."""
    with _session_locks_guard:
        lock = _session_locks.get(session_id)
        if lock is None:
            lock = asyncio.Lock()
            _session_locks[session_id] = lock
        return lock


def session_payload(session: ChatSession) -> dict:
    return {
        "id": session.id,
        "plant_id": session.plant_id,
        "reflection_stage": session.reflection_stage,
        "status": session.status,
        "started_at": to_utc_iso(session.started_at),
        "last_message_at": to_utc_iso(session.last_message_at),
        # 한도를 앱이 따로 들고 있으면 운영에서 이 값을 바꾸는 순간 화면의
        # `최대 10번`과 실제 거절 시점이 어긋난다. 판정하는 쪽이 알려 준다.
        "max_user_turns": get_settings().chat_session_max_user_turns,
    }


def message_payload(message: ChatMessage) -> dict:
    return {
        "id": message.id,
        "role": message.role,
        "content": message.content,
        "created_at": to_utc_iso(message.created_at),
    }


async def start_session(
    db: AsyncSession, user_id: int, plant_id: int | None
) -> tuple[ChatSession, ChatMessage, RewardOutcome]:
    # 사용자 row를 기준으로 동시 시작을 직렬화해 활성 세션을 하나로 유지한다.
    user = await rewards.lock_user(db, user_id)
    if plant_id is None:
        plant = await rewards.lock_active_plant(db, user_id)
        if plant is None:
            raise AppError(404, "PLANT_NOT_FOUND", "키우고 있는 식물이 없습니다.")
    else:
        result = await db.execute(sa.select(Plant).where(Plant.id == plant_id))
        plant = result.scalar_one_or_none()
        if plant is None or plant.user_id != user_id:
            raise AppError(404, "PLANT_NOT_FOUND", "식물을 찾을 수 없습니다.")

    # 같은 사용자의 기존 활성 세션은 닫는다 (활성 세션 1개 유지)
    await db.execute(
        sa.update(ChatSession)
        .where(
            ChatSession.user_id == user_id,
            ChatSession.status == ChatSessionStatus.ACTIVE,
        )
        .values(status=ChatSessionStatus.CLOSED, ended_at=utcnow())
    )

    session = ChatSession(
        user_id=user_id,
        plant_id=plant.id,
        reflection_stage=ReflectionStage.GREETING,
        status=ChatSessionStatus.ACTIVE,
    )
    db.add(session)
    await db.flush()

    species = await db.get(PlantSpecies, plant.species_id)
    growth_state = plant_service.growth_state_payload(plant)
    growth_persona = growth_state["growth_persona"]
    greeting = ChatMessage(
        session_id=session.id,
        role="plant",
        content=greeting_line(
            species.persona_key,
            plant.name,
            growth_persona,
            growth_state,
        ),
        model_version="template",
    )
    db.add(greeting)
    session.last_message_at = utcnow()
    session.reflection_stage = ReflectionStage.EMOTION_CHECK
    await db.flush()

    # 하루 첫 채팅 시작 보상은 이후 대화 내용·안전 분기와 무관 (design.md 6.3)
    now_local = local_date_of(utcnow())
    outcome = RewardOutcome(seed_balance=user.seed_balance)
    await rewards.grant(
        db,
        user,
        plant if plant.status == PlantStatus.ACTIVE else None,
        RewardEventType.CHAT_FIRST_DAILY,
        rewards.dedupe_key(
            RewardEventType.CHAT_FIRST_DAILY, user_id=user_id, local_date=now_local
        ),
        "chat_session",
        session.id,
        now_local,
        outcome,
    )
    return session, greeting, outcome


async def _recent_user_messages(
    db: AsyncSession, session_id: int, limit: int = 4
) -> list[str]:
    rows = await db.execute(
        sa.select(ChatMessage.content)
        .where(ChatMessage.session_id == session_id, ChatMessage.role == "user")
        .order_by(ChatMessage.created_at.desc())
        .limit(limit)
    )
    return [r[0] for r in rows]


async def post_message(
    db: AsyncSession,
    user_id: int,
    session: ChatSession,
    content: str,
    client_message_id: str,
    *,
    retry_failed: bool = False,
) -> dict:
    settings = get_settings()
    # 세션 단위로 turn 수·active run 검사와 insert를 직렬화한다.
    session = await db.scalar(
        sa.select(ChatSession)
        .where(ChatSession.id == session.id, ChatSession.user_id == user_id)
        .with_for_update()
        # router의 소유권 검사에서 같은 identity를 먼저 읽었을 수 있다. 로컬 lock을
        # 기다리는 동안 다른 요청이 바꾼 safety/status를 반드시 다시 덮어쓴다.
        .execution_options(populate_existing=True)
    )
    if session is None:
        raise AppError(404, "CHAT_SESSION_NOT_FOUND", "대화를 찾을 수 없습니다.")
    if session.status != ChatSessionStatus.ACTIVE:
        raise AppError(409, "CHAT_SESSION_CLOSED", "이미 종료된 대화입니다.")
    if session.started_at < utcnow() - timedelta(
        minutes=settings.chat_session_max_minutes
    ):
        session.status = ChatSessionStatus.CLOSED
        session.ended_at = utcnow()
        raise AppError(
            409, "CHAT_SESSION_CLOSED", "대화 시간이 끝났어요. 새로 시작해 주세요."
        )

    # 같은 client_message_id 재전송이면 새 사용자 메시지를 만들지 않는다. 확정
    # 실패 후의 명시적 재시도만 기존 run을 새 job으로 되돌리고, 응답 유실 같은
    # 전송 재시도는 기존 상태를 그대로 재생한다.
    existing = await db.scalar(
        sa.select(ChatRun).where(ChatRun.client_message_id == client_message_id)
    )
    if existing is not None:
        message = await db.get(ChatMessage, existing.user_message_id)
        if (
            existing.session_id != session.id
            or message is None
            or message.content != content
        ):
            # client_message_id는 전역 unique이므로 다른 세션의 run을 절대 반환하지 않는다.
            raise AppError(
                409,
                "CLIENT_MESSAGE_ID_CONFLICT",
                "동일한 메시지 ID가 다른 요청에 사용되었습니다.",
            )
        if retry_failed:
            # concern/imminent가 한 번 확인된 세션은 이후 문장이 부드러워져도 LLM
            # 경로로 되돌리지 않는다. 과거 실패 run의 재큐잉도 같은 하한을 따른다.
            if session.safety_state != SafetyState.NORMAL:
                raise AppError(
                    409,
                    "CHAT_RETRY_SAFETY_BLOCKED",
                    "안전 지원 안내가 필요한 대화에서는 답변을 다시 만들 수 없습니다.",
                )
            if existing.status != RunStatus.FAILED:
                # 먼저 도착한 retry가 이미 run을 되살렸거나 끝낸 경우다. 서로 다른
                # HTTP 멱등 키를 쓴 동시 탭도 같은 논리 run으로 합류시킨다.
                return {"kind": "run", "run": existing, "user_message": message}

            # 기존 실패 run을 되살리는 경로도 일반 전송과 같은 세션 불변식을
            # 지켜야 한다. 다른 run이 진행 중이면 두 답변이 같은 문맥을 읽게 된다.
            active_run = await db.scalar(
                sa.select(ChatRun).where(
                    ChatRun.session_id == session.id,
                    ChatRun.id != existing.id,
                    ChatRun.status.in_([RunStatus.QUEUED, RunStatus.GENERATING]),
                )
            )
            if active_run is not None:
                raise AppError(
                    409,
                    "CHAT_RUN_ACTIVE_EXISTS",
                    "식물이 아직 다른 답변을 만들고 있어요.",
                )

            # 이후의 일반 메시지뿐 아니라 run을 만들지 않는 안전 경로 메시지도
            # turn 순서를 바꾼다. 실패 입력이 최신 user turn일 때만 재생성한다.
            latest_user_message_id = await db.scalar(
                sa.select(sa.func.max(ChatMessage.id)).where(
                    ChatMessage.session_id == session.id,
                    ChatMessage.role == "user",
                )
            )
            if latest_user_message_id != message.id:
                raise AppError(
                    409,
                    "CHAT_RETRY_STALE",
                    "이후 대화가 있어 이전 답변은 다시 만들 수 없습니다.",
                    {
                        "run_id": existing.id,
                        "user_message_id": message.id,
                        "latest_user_message_id": latest_user_message_id,
                    },
                )

            latest_input_version = await db.scalar(
                sa.select(sa.func.coalesce(sa.func.max(AiJob.input_version), 0)).where(
                    AiJob.job_type == JobType.CHAT_GENERATION,
                    AiJob.resource_type == "chat_run",
                    AiJob.resource_id == existing.id,
                )
            )
            existing.status = RunStatus.QUEUED
            existing.error_code = None
            existing.finished_at = None
            existing.assistant_message_id = None
            db.add(
                AiJob(
                    user_id=user_id,
                    job_type=JobType.CHAT_GENERATION,
                    resource_type="chat_run",
                    resource_id=existing.id,
                    input_version=int(latest_input_version) + 1,
                    status=JobStatus.PENDING,
                    available_at=utcnow(),
                )
            )
            await db.flush()
        return {"kind": "run", "run": existing, "user_message": message}

    user_turns = await db.scalar(
        sa.select(sa.func.count())
        .select_from(ChatMessage)
        .where(ChatMessage.session_id == session.id, ChatMessage.role == "user")
    )
    if user_turns >= settings.chat_session_max_user_turns:
        session.status = ChatSessionStatus.CLOSED
        session.ended_at = utcnow()
        raise AppError(
            409, "CHAT_SESSION_CLOSED", "오늘 대화는 여기까지예요. 내일 또 이야기해요."
        )

    active_run = await db.scalar(
        sa.select(ChatRun).where(
            ChatRun.session_id == session.id,
            ChatRun.status.in_([RunStatus.QUEUED, RunStatus.GENERATING]),
        )
    )
    if active_run is not None:
        raise AppError(
            409, "CHAT_RUN_ACTIVE_EXISTS", "식물이 아직 답변을 만들고 있어요."
        )

    # 동기식 입력 안전 검사: 현재 입력 + 최근 문맥 + 세션 안전 상태 (design.md 6.3)
    recent = await _recent_user_messages(db, session.id)
    joined_context = content + "\n" + "\n".join(recent)
    result = safety.check_text(joined_context, prior_state=session.safety_state)
    # 현재 입력 단독으로도 평가해 이전 문맥 신호와 구분한다
    current_only = safety.check_text(content)

    now = utcnow()
    message = ChatMessage(
        session_id=session.id,
        role="user",
        content=content,
        safety_status=current_only.route,
    )
    db.add(message)
    session.last_message_at = now
    await db.flush()

    # 결합 판정에는 세션의 이전 안전 상태가 하한으로 반영된다. 현재 문장이
    # 평범해 보여도 같은 세션에서 concern 이상이 확인됐다면 LLM으로 보내지 않는다.
    if result.flagged:
        route = (
            "imminent"
            if "imminent" in (current_only.route, result.route)
            else "concern"
        )
        reason_codes = (
            current_only.reason_codes
            if current_only.route == route
            else result.reason_codes
        )
        session.safety_state = route
        record_safety_event(
            db,
            user_id,
            "chat",
            "chat_message",
            message.id,
            safety.SafetyResult(route, reason_codes),
        )
        return {
            "kind": "safety",
            "user_message": message,
            "safety_action": safety.safety_action_payload(route, reason_codes),
        }

    if settings.ai_mode == "disabled":
        raise AppError(503, "SERVICE_DEGRADED", "지금은 대화 기능을 사용할 수 없어요.")

    run = ChatRun(
        session_id=session.id,
        user_message_id=message.id,
        client_message_id=client_message_id,
        status=RunStatus.QUEUED,
    )
    db.add(run)
    await db.flush()
    db.add(
        AiJob(
            user_id=user_id,
            job_type=JobType.CHAT_GENERATION,
            resource_type="chat_run",
            resource_id=run.id,
            input_version=1,
            status=JobStatus.PENDING,
            available_at=now,
        )
    )
    return {"kind": "run", "run": run, "user_message": message}


def run_payload(run: ChatRun, message: ChatMessage | None) -> dict:
    return {
        "run_id": run.id,
        "status": run.status,
        "message": message_payload(message) if message is not None else None,
        "error_code": run.error_code,
    }
