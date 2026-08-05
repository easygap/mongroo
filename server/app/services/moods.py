"""감정 기록 서비스 (design.md 3.1-2, 6.3).

저장 직전 동기식 안전 검사 → 기록 저장 → 보상 → (안전 경로가 아니면) 분석 job 등록.
"""

import asyncio
import threading
import weakref

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.errors import AppError
from app.core.config import get_settings
from app.core.text_metadata import diary_content_marker
from app.core.timeutil import local_date_of, to_utc_iso, utcnow
from app.ai import safety
from app.models.enums import AnalysisStatus, JobStatus, JobType, RewardEventType
from app.models.mood import MoodEntry
from app.models.ops import AiJob
from app.models.safety import SafetyEvent
from app.services import plants as plant_service, rewards
from app.services.rewards import RewardOutcome

_edit_locks_guard = threading.Lock()
_edit_locks: weakref.WeakValueDictionary[int, asyncio.Lock] = (
    weakref.WeakValueDictionary()
)


def edit_lock(mood_id: int) -> asyncio.Lock:
    """SQLite 개발 환경에서도 같은 프로세스의 동시 PATCH를 직렬화한다.

    운영 MySQL의 행 잠금이 프로세스 간 경합을 담당하고, 이 잠금은 ``FOR UPDATE``를
    무시하는 SQLite 테스트/로컬 실행에서 동일한 의미를 보완한다.
    """
    with _edit_locks_guard:
        lock = _edit_locks.get(mood_id)
        if lock is None:
            lock = asyncio.Lock()
            _edit_locks[mood_id] = lock
        return lock


async def lock_mood_for_edit(
    db: AsyncSession, mood_id: int, user_id: int, expected_version: int | None
) -> MoodEntry:
    """소유 기록을 행 잠금으로 읽고 선택적 낙관적 버전을 검증한다."""
    entry = await db.scalar(
        sa.select(MoodEntry).where(MoodEntry.id == mood_id).with_for_update()
    )
    if entry is None:
        raise AppError(404, "MOOD_NOT_FOUND", "대상을 찾을 수 없습니다.")
    if entry.user_id != user_id:
        raise AppError(403, "FORBIDDEN", "접근 권한이 없습니다.")

    current_version = entry.edit_version
    if expected_version is not None and expected_version != current_version:
        raise AppError(
            409,
            "MOOD_VERSION_CONFLICT",
            "다른 기기에서 감정 기록이 변경되었습니다.",
            {
                "expected_version": expected_version,
                "current_version": current_version,
            },
        )
    return entry


async def advance_edit_version(db: AsyncSession, entry: MoodEntry) -> None:
    """사용자 PATCH의 편집 버전을 compare-and-swap으로 한 번 증가시킨다.

    MySQL의 행 잠금과 SQLite의 프로세스 로컬 잠금이 정상 경합을 직렬화한다.
    조건부 UPDATE도 함께 사용해 잠금 설정이 바뀌더라도 조용한 lost update 대신
    충돌로 실패하게 한다.
    """
    current_version = entry.edit_version
    result = await db.execute(
        sa.update(MoodEntry)
        .where(
            MoodEntry.id == entry.id,
            MoodEntry.user_id == entry.user_id,
            MoodEntry.edit_version == current_version,
        )
        .values(edit_version=current_version + 1)
        .execution_options(synchronize_session=False)
    )
    if (result.rowcount or 0) != 1:
        raise AppError(
            409,
            "MOOD_VERSION_CONFLICT",
            "다른 기기에서 감정 기록이 변경되었습니다.",
            {"expected_version": current_version},
        )
    # 위 Core UPDATE는 identity map을 동기화하지 않으므로 응답/후속 flush에 반영한다.
    entry.edit_version = current_version + 1


def mood_payload(entry: MoodEntry) -> dict:
    return {
        "id": entry.id,
        "local_date": entry.local_date.isoformat(),
        "recorded_at": to_utc_iso(entry.recorded_at_utc),
        "mood_level": entry.mood_level,
        "mood_level_explicit": entry.mood_level_explicit,
        "emotion_tags": entry.emotion_tags or [],
        "content": entry.content,
        "analysis_status": entry.analysis_status,
        "ai_emotion": entry.ai_emotion,
        "ai_scores": entry.ai_scores,
        "ai_emotion_override": entry.ai_emotion_override,
        "ai_label_hidden": entry.ai_label_hidden,
        "analysis_model_version": entry.analysis_model_version,
        "analyzed_at": to_utc_iso(entry.analyzed_at),
        "analysis_error_code": entry.analysis_error_code,
        "created_at": to_utc_iso(entry.created_at),
        "updated_at": to_utc_iso(entry.updated_at),
        "edit_version": entry.edit_version,
    }


async def enqueue_analysis(db: AsyncSession, entry: MoodEntry) -> None:
    """텍스트가 있고 AI가 켜져 있으면 분석 job을 같은 트랜잭션에 등록한다."""
    if get_settings().ai_mode == "disabled" or not (
        entry.content and entry.content.strip()
    ):
        entry.analysis_status = AnalysisStatus.NOT_REQUESTED
        return
    entry.analysis_status = AnalysisStatus.PENDING
    entry.analysis_error_code = None
    db.add(
        AiJob(
            user_id=entry.user_id,
            job_type=JobType.MOOD_ANALYSIS,
            resource_type="mood_entry",
            resource_id=entry.id,
            input_version=entry.analysis_version,
            status=JobStatus.PENDING,
            available_at=utcnow(),
        )
    )


def record_safety_event(
    db: AsyncSession,
    user_id: int,
    source: str,
    resource_type: str,
    resource_id: int | None,
    result: safety.SafetyResult,
) -> None:
    db.add(
        SafetyEvent(
            user_id=user_id,
            source=source,
            resource_type=resource_type,
            resource_id=resource_id,
            severity=result.route,
            reason_codes=result.reason_codes,
            detector_version=safety.DETECTOR_VERSION,
            action_taken="show_support_screen",
        )
    )


async def create_mood(
    db: AsyncSession,
    user_id: int,
    mood_level: int | None,
    emotion_tags: list[str],
    content: str | None,
) -> tuple[MoodEntry, RewardOutcome, dict | None]:
    safety_result = (
        safety.check_text(content) if content else safety.SafetyResult("normal")
    )

    # 수확과 같은 user → active plant 순서로 직렬화한 뒤 기록 시각을 정한다.
    # 수확을 기다린 기록이 과거 식물 생애 시각으로 소급되는 일을 막는다.
    user = await rewards.lock_user(db, user_id)
    plant = await rewards.lock_active_plant(db, user_id)
    now = utcnow()
    local_day = local_date_of(now)

    entry = MoodEntry(
        user_id=user_id,
        local_date=local_day,
        recorded_at_utc=now,
        # 기존 스키마/클라이언트 호환용 중립값이다. 식물 분기는 이 값을 읽지 않는다.
        mood_level=mood_level if mood_level is not None else 3,
        mood_level_explicit=mood_level is not None,
        emotion_tags=emotion_tags,
        content=content,
        content_length=diary_content_marker(content),
        analysis_status=AnalysisStatus.NOT_REQUESTED,
    )
    db.add(entry)
    await db.flush()

    safety_action = None
    if safety_result.flagged:
        # 기록은 저장하되 분석 job은 만들지 않는다 (design.md 6.3)
        record_safety_event(db, user_id, "mood", "mood_entry", entry.id, safety_result)
        safety_action = safety.safety_action_payload(
            safety_result.route, safety_result.reason_codes
        )
    else:
        await enqueue_analysis(db, entry)

    # 보상: 하루 첫 기록·첫 일기는 안전 분기와 무관하게 동일 지급
    outcome = RewardOutcome(seed_balance=user.seed_balance)

    await rewards.grant(
        db,
        user,
        plant,
        RewardEventType.MOOD_FIRST_DAILY,
        rewards.dedupe_key(
            RewardEventType.MOOD_FIRST_DAILY, user_id=user_id, local_date=local_day
        ),
        "mood_entry",
        entry.id,
        local_day,
        outcome,
    )
    if content and len(content.strip()) >= 50:
        await rewards.grant(
            db,
            user,
            plant,
            RewardEventType.DIARY_FIRST_DAILY,
            rewards.dedupe_key(
                RewardEventType.DIARY_FIRST_DAILY, user_id=user_id, local_date=local_day
            ),
            "mood_entry",
            entry.id,
            local_day,
            outcome,
        )
    if rewards.update_streak(user, local_day):
        recorded_days = int(
            await db.scalar(
                sa.select(sa.func.count(sa.distinct(MoodEntry.local_date))).where(
                    MoodEntry.user_id == user_id
                )
            )
            or 0
        )
        if recorded_days > 0 and recorded_days % 7 == 0:
            await rewards.grant(
                db,
                user,
                plant,
                RewardEventType.STREAK_WEEK,
                rewards.dedupe_key(
                    RewardEventType.STREAK_WEEK,
                    user_id=user_id,
                    recorded_days=recorded_days,
                ),
                "record_milestone",
                None,
                local_day,
                outcome,
            )
    # 분석 전에도 pending_count가 즉시 보이도록 활성 식물 프로필을 동기화한다.
    await plant_service.refresh_active_plant_growth(
        db, user_id, plant=plant, observed_at=now, lock_entries=True
    )
    return entry, outcome, safety_action


async def patch_mood(
    db: AsyncSession, entry: MoodEntry, fields: dict
) -> tuple[MoodEntry, RewardOutcome, dict | None]:
    """기록 입력 변경을 반영하되 본문이 바뀔 때만 다시 분류한다."""
    legacy_fields_changed = any(
        key in fields and fields[key] is not None and getattr(entry, key) != fields[key]
        for key in ("mood_level", "emotion_tags")
    )
    explicit_mood_changed = (
        fields.get("mood_level") is not None and not entry.mood_level_explicit
    )
    content_changed = "content" in fields and entry.content != fields["content"]
    record_changed = legacy_fields_changed or explicit_mood_changed or content_changed
    for key in ("mood_level", "emotion_tags"):
        if key in fields and fields[key] is not None:
            setattr(entry, key, fields[key])
    if fields.get("mood_level") is not None:
        entry.mood_level_explicit = True
    if "content" in fields:
        # PATCH의 explicit null은 일기 본문을 비우는 의미다.
        entry.content = fields["content"]
        entry.content_length = diary_content_marker(entry.content)
    if "ai_emotion_override" in fields:
        entry.ai_emotion_override = fields["ai_emotion_override"]
    if fields.get("ai_label_hidden") is not None:
        entry.ai_label_hidden = fields["ai_label_hidden"]

    safety_action = None
    outcome = RewardOutcome()
    if record_changed:
        entry.input_version += 1
    if content_changed:
        entry.analysis_version += 1
        # 이전 버전의 분석 결과는 더 이상 유효하지 않다
        entry.ai_emotion = None
        entry.ai_scores = None
        entry.analyzed_at = None
        entry.analysis_model_version = None
        safety_result = (
            safety.check_text(entry.content)
            if entry.content
            else safety.SafetyResult("normal")
        )
        if safety_result.flagged:
            entry.analysis_status = AnalysisStatus.NOT_REQUESTED
            record_safety_event(
                db, entry.user_id, "mood", "mood_entry", entry.id, safety_result
            )
            safety_action = safety.safety_action_payload(
                safety_result.route, safety_result.reason_codes
            )
        else:
            await enqueue_analysis(db, entry)

        # 수정으로 일기 50자 조건을 처음 충족해도 그날 1회만 지급 (design.md 7.1)
        if entry.content and len(entry.content.strip()) >= 50:
            user = await rewards.lock_user(db, entry.user_id)
            plant = await rewards.lock_active_plant(db, entry.user_id)
            outcome = RewardOutcome(seed_balance=user.seed_balance)
            await rewards.grant(
                db,
                user,
                plant,
                RewardEventType.DIARY_FIRST_DAILY,
                rewards.dedupe_key(
                    RewardEventType.DIARY_FIRST_DAILY,
                    user_id=entry.user_id,
                    local_date=entry.local_date,
                ),
                "mood_entry",
                entry.id,
                entry.local_date,
                outcome,
            )
    return entry, outcome, safety_action


async def calendar_summary(
    db: AsyncSession, user_id: int, year: int, month: int
) -> list[dict]:
    rows = await db.execute(
        sa.select(MoodEntry)
        .where(
            MoodEntry.user_id == user_id,
            sa.extract("year", MoodEntry.local_date) == year,
            sa.extract("month", MoodEntry.local_date) == month,
        )
        .order_by(MoodEntry.local_date, MoodEntry.recorded_at_utc)
    )
    days: dict[str, dict] = {}
    for entry in rows.scalars():
        key = entry.local_date.isoformat()
        info = days.setdefault(
            key,
            {
                "date": key,
                "entry_count": 0,
                "last_mood_level": None,
                "last_mood_level_explicit": False,
                "last_ai_emotion": None,
                "last_analysis_status": AnalysisStatus.NOT_REQUESTED,
                "pending_count": 0,
            },
        )
        info["entry_count"] += 1
        info["last_mood_level_explicit"] = bool(entry.mood_level_explicit)
        info["last_mood_level"] = (
            entry.mood_level if entry.mood_level_explicit else None
        )
        info["last_analysis_status"] = entry.analysis_status
        info["last_ai_emotion"] = (
            (entry.ai_emotion_override or entry.ai_emotion)
            if entry.analysis_status == AnalysisStatus.SUCCEEDED
            and not entry.ai_label_hidden
            else None
        )
        if entry.analysis_status in (AnalysisStatus.PENDING, AnalysisStatus.RUNNING):
            info["pending_count"] += 1
    return list(days.values())
