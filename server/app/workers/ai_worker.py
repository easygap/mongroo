"""영속 AI job worker (design.md 5.4).

별도 프로세스로 실행한다: python -m app.workers.ai_worker
PyTorch CPU 추론과 Ollama 호출을 API 이벤트 루프에서 격리하기 위한 구조이며,
동시 job 1개(bounded)만 처리한다. 실패는 지수 backoff로 최대 3회 재시도한다.
"""

import asyncio
import json
import logging
from datetime import timedelta

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.core.config import get_settings
from app.core.db import get_session_factory
from app.core.logging import setup_logging
from app.core.timeutil import local_date_of, utcnow
from app.ai import safety
from app.ai.chat_flow import stage_for_reply
from app.ai.classifier import ClassifierError, get_classifier
from app.ai.llm import LlmError, get_llm
from app.ai.prompts import build_chat_messages, build_summary_messages
from app.models.chat import ChatMessage, ChatRun, ChatSession
from app.models.enums import (
    AnalysisStatus,
    ChatSessionStatus,
    JobStatus,
    JobType,
    PlantStatus,
    ReflectionStage,
    ReportStatus,
    RunStatus,
)
from app.models.mood import MoodEntry
from app.models.ops import AiJob, WorkerHeartbeat
from app.models.plant import Plant, PlantSpecies
from app.models.report import Report
from app.services import plants as plant_service

logger = logging.getLogger("mongroo.worker")

WORKER_NAME = "ai-worker"
_BACKOFF_SECONDS = [30, 120, 600]


async def recover_stale_jobs(db: AsyncSession) -> int:
    """재시작 시 오래된 running job을 pending으로 되돌린다."""
    settings = get_settings()
    threshold = utcnow() - timedelta(seconds=settings.job_stale_running_seconds)
    result = await db.execute(
        sa.update(AiJob)
        .where(AiJob.status == JobStatus.RUNNING, AiJob.locked_at < threshold)
        .values(status=JobStatus.PENDING, locked_at=None)
    )
    await db.commit()
    return result.rowcount or 0


async def claim_next_job(db: AsyncSession) -> AiJob | None:
    job_id = await db.scalar(
        sa.select(AiJob.id)
        .where(AiJob.status == JobStatus.PENDING, AiJob.available_at <= utcnow())
        .order_by(AiJob.id)
        .limit(1)
    )
    if job_id is None:
        return None
    result = await db.execute(
        sa.update(AiJob)
        .where(AiJob.id == job_id, AiJob.status == JobStatus.PENDING)
        .values(
            status=JobStatus.RUNNING, locked_at=utcnow(), attempts=AiJob.attempts + 1
        )
    )
    await db.commit()
    if (result.rowcount or 0) == 0:
        return None
    return await db.get(AiJob, job_id)


async def _mark_terminal_resource_failed(db: AsyncSession, job: AiJob) -> None:
    """terminal job과 대상 상태를 같은 commit에 넣어 반쪽 실패를 남기지 않는다."""
    if job.job_type == JobType.MOOD_ANALYSIS:
        user_id = await db.scalar(
            sa.select(MoodEntry.user_id).where(MoodEntry.id == job.resource_id)
        )
        plant = None
        if user_id is not None:
            plant = await db.scalar(
                sa.select(Plant)
                .where(Plant.user_id == user_id, Plant.status == PlantStatus.ACTIVE)
                .with_for_update()
            )
        entry = await db.scalar(
            sa.select(MoodEntry)
            .where(MoodEntry.id == job.resource_id)
            .with_for_update()
            .execution_options(populate_existing=True)
        )
        if entry is not None and entry.analysis_version == job.input_version:
            entry.analysis_status = AnalysisStatus.FAILED
            entry.analysis_error_code = job.last_error_code
            if plant is not None:
                await plant_service.refresh_active_plant_growth(
                    db, entry.user_id, plant=plant, lock_entries=True
                )
    elif job.job_type == JobType.CHAT_GENERATION:
        run = await db.get(ChatRun, job.resource_id)
        if run is not None and run.status not in (
            RunStatus.SUCCEEDED,
            RunStatus.FAILED,
        ):
            run.status = RunStatus.FAILED
            run.error_code = job.last_error_code or "LLM_UNAVAILABLE"
            run.finished_at = utcnow()
    elif job.job_type == JobType.REPORT_SUMMARY:
        report = await db.get(Report, job.resource_id)
        if report is not None and report.status == ReportStatus.PENDING:
            report.status = ReportStatus.FAILED
            report.error_code = job.last_error_code


async def _finish(
    db: AsyncSession, job: AiJob, ok: bool, error_code: str | None = None
) -> None:
    settings = get_settings()
    current = await db.scalar(
        sa.select(AiJob)
        .where(AiJob.id == job.id)
        .with_for_update()
        .execution_options(populate_existing=True)
    )
    if current is None:
        await db.rollback()
        return
    if current.status != JobStatus.RUNNING:
        # 설정 전환 정리 작업처럼 다른 worker가 이미 terminal 상태로 만든 job을
        # 늦게 끝난 handler가 다시 pending/succeeded로 되돌리지 않는다.
        await db.commit()
        logger.info(
            "job_finish_skipped",
            extra={
                "job_id": current.id,
                "job_type": current.job_type,
                "status": current.status,
            },
        )
        return
    job = current
    if ok:
        job.status = JobStatus.SUCCEEDED
        job.last_error_code = None
    elif job.attempts >= settings.job_max_attempts:
        job.status = JobStatus.FAILED
        job.last_error_code = error_code
    else:
        job.status = JobStatus.PENDING
        job.available_at = utcnow() + timedelta(
            seconds=_BACKOFF_SECONDS[min(job.attempts - 1, len(_BACKOFF_SECONDS) - 1)]
        )
        job.last_error_code = error_code
    job.locked_at = None
    if job.status == JobStatus.FAILED:
        await _mark_terminal_resource_failed(db, job)
    await db.commit()
    logger.info(
        "job_finished",
        extra={
            "job_id": job.id,
            "job_type": job.job_type,
            "attempts": job.attempts,
            "error_code": error_code,
        },
    )


async def handle_mood_analysis(db: AsyncSession, job: AiJob) -> tuple[bool, str | None]:
    entry = await db.get(MoodEntry, job.resource_id)
    if entry is None:
        return True, None  # 기록이 삭제됨 → 할 일 없음
    if entry.analysis_version != job.input_version:
        return True, None  # 이전 버전 job은 결과를 적용하지 않는다 (design.md 5.4)
    classifier = get_classifier()
    if classifier is None:
        return False, "CLASSIFIER_UNAVAILABLE"
    entry.analysis_status = AnalysisStatus.RUNNING
    await db.commit()
    try:
        label, scores = await asyncio.to_thread(
            classifier.classify, entry.content or ""
        )
    except ClassifierError:
        # 분류 중 본문이 수정되거나 안전 경로로 바뀔 수 있다. 시작할 때 읽은
        # ORM 객체를 쓰지 말고 현재 버전의 running 행만 원자적으로 되돌린다.
        result = await db.execute(
            sa.update(MoodEntry)
            .where(
                MoodEntry.id == job.resource_id,
                MoodEntry.analysis_version == job.input_version,
                MoodEntry.analysis_status == AnalysisStatus.RUNNING,
            )
            .values(analysis_status=AnalysisStatus.PENDING)
        )
        await db.commit()
        if (result.rowcount or 0) == 0:
            return True, None
        return False, "CLASSIFIER_ERROR"
    # 최종 반영은 plant → mood 순서로 잠가 수확과 같은 순서를 지킨다.
    plant = await db.scalar(
        sa.select(Plant)
        .where(Plant.user_id == entry.user_id, Plant.status == PlantStatus.ACTIVE)
        .with_for_update()
    )
    entry = await db.scalar(
        sa.select(MoodEntry)
        .where(MoodEntry.id == entry.id)
        .with_for_update()
        .execution_options(populate_existing=True)
    )
    if entry is None:
        return True, None
    if entry.analysis_version != job.input_version:
        return True, None
    entry.ai_emotion = label
    entry.ai_scores = scores
    entry.analysis_model_version = classifier.model_version
    entry.analyzed_at = utcnow()
    entry.analysis_status = AnalysisStatus.SUCCEEDED
    entry.analysis_error_code = None
    if plant is not None:
        await plant_service.refresh_active_plant_growth(
            db, entry.user_id, plant=plant, lock_entries=True
        )
    await db.commit()
    return True, None


async def _today_mood_summary(db: AsyncSession, user_id: int) -> str | None:
    """오늘의 명시적 기분 또는 표시 가능한 분석 라벨. 본문은 넣지 않는다."""
    today = local_date_of(utcnow())
    rows = await db.execute(
        sa.select(
            MoodEntry.mood_level,
            MoodEntry.mood_level_explicit,
            MoodEntry.emotion_tags,
            MoodEntry.analysis_status,
            MoodEntry.ai_emotion,
            MoodEntry.ai_emotion_override,
            MoodEntry.ai_label_hidden,
        )
        .where(MoodEntry.user_id == user_id, MoodEntry.local_date == today)
        .order_by(MoodEntry.recorded_at_utc.desc())
        .limit(3)
    )
    entries = rows.all()
    if not entries:
        return None
    level_names = {1: "매우 힘듦", 2: "힘듦", 3: "보통", 4: "좋음", 5: "매우 좋음"}
    parts = []
    for level, explicit, tags, status, ai_emotion, override, hidden in entries:
        text = level_names.get(level, str(level)) if explicit else ""
        if tags:
            tag_text = ", ".join(tags[:3])
            text += f"({tag_text})" if text else tag_text
        if not text and status == AnalysisStatus.SUCCEEDED and not hidden:
            text = override or ai_emotion or ""
        if text:
            parts.append(text)
    return " / ".join(parts) or None


async def handle_chat_generation(
    db: AsyncSession, job: AiJob
) -> tuple[bool, str | None]:
    run = await db.get(ChatRun, job.resource_id)
    if run is None or run.status in (RunStatus.SUCCEEDED, RunStatus.FAILED):
        return True, None
    session = await db.get(ChatSession, run.session_id)
    if session is None:
        return True, None
    llm = get_llm()
    if llm is None:
        run.status = RunStatus.FAILED
        run.error_code = "LLM_UNAVAILABLE"
        run.finished_at = utcnow()
        await db.commit()
        return True, None

    run.status = RunStatus.GENERATING
    await db.commit()

    settings = get_settings()
    rows = await db.execute(
        sa.select(ChatMessage)
        .where(ChatMessage.session_id == session.id)
        .order_by(ChatMessage.id.desc())
        .limit(settings.chat_prompt_message_window)
    )
    recent = [
        {"role": m.role, "content": m.content} for m in reversed(list(rows.scalars()))
    ]
    user_turns = sum(1 for m in recent if m["role"] == "user")
    total_user_turns = await db.scalar(
        sa.select(sa.func.count())
        .select_from(ChatMessage)
        .where(ChatMessage.session_id == session.id, ChatMessage.role == "user")
    )
    latest_user_text = next(
        (m["content"] for m in reversed(recent) if m["role"] == "user"), ""
    )
    stage = stage_for_reply(
        session.reflection_stage,
        user_turns,
        latest_user_text,
        total_user_turns,
        settings.chat_session_max_user_turns,
    )

    plant = await db.get(Plant, session.plant_id)
    species = await db.get(PlantSpecies, plant.species_id)
    growth_state = plant_service.growth_state_payload(plant)
    messages = build_chat_messages(
        species.persona_key,
        plant.name,
        stage,
        recent,
        await _today_mood_summary(db, session.user_id),
        growth_state["growth_persona"],
        growth_state,
    )

    try:
        reply = await llm.chat(messages)
    except LlmError as exc:
        run.status = RunStatus.QUEUED  # 재시도 대상
        await db.commit()
        return False, exc.code

    ok, guard_codes = safety.guard_output(reply)
    if not ok:
        # 가드 실패 시 원문을 전달하지 않는다 (fail-closed, design.md 6.3)
        run.status = RunStatus.FAILED
        run.error_code = "GUARD_REJECTED"
        run.finished_at = utcnow()
        await db.commit()
        logger.info(
            "guard_rejected",
            extra={"run_id": run.id, "error_code": ",".join(guard_codes)},
        )
        return True, None

    message = ChatMessage(
        session_id=session.id,
        role="plant",
        content=reply,
        model_version=llm.model_version,
    )
    db.add(message)
    await db.flush()
    run.assistant_message_id = message.id
    run.status = RunStatus.SUCCEEDED
    run.finished_at = utcnow()
    session.reflection_stage = stage
    session.last_message_at = utcnow()
    if stage == ReflectionStage.CLOSING:
        session.status = ChatSessionStatus.CLOSED
        session.ended_at = utcnow()
    await db.commit()
    return True, None


def _summary_valid(summary: dict, stats: dict) -> bool:
    """스키마와 수치 검증: 입력에 없는 숫자를 만들면 거부한다 (design.md 6.4)."""
    import re

    if not isinstance(summary.get("overview"), str) or not summary["overview"].strip():
        return False
    if not isinstance(summary.get("patterns"), list) or not all(
        isinstance(p, str) for p in summary["patterns"]
    ):
        return False
    if not isinstance(summary.get("reflection_questions"), list) or not all(
        isinstance(q, str) for q in summary["reflection_questions"]
    ):
        return False
    stats_numbers = set(re.findall(r"\d+(?:\.\d+)?", json.dumps(stats)))
    text = (
        summary["overview"]
        + " ".join(summary["patterns"])
        + " ".join(summary["reflection_questions"])
    )
    for number in re.findall(r"\d+(?:\.\d+)?", text):
        if number not in stats_numbers:
            return False
    banned_ok, _ = safety.guard_output(text)
    return banned_ok


async def handle_report_summary(
    db: AsyncSession, job: AiJob
) -> tuple[bool, str | None]:
    report = await db.get(Report, job.resource_id)
    if report is None:
        return True, None
    llm = get_llm()
    if llm is None:
        report.status = ReportStatus.FAILED
        report.error_code = "LLM_UNAVAILABLE"
        await db.commit()
        return True, None
    try:
        raw = await llm.chat(
            build_summary_messages(
                json.dumps(_public_stats(report.stats), ensure_ascii=False)
            )
        )
    except LlmError as exc:
        return False, exc.code

    summary = _parse_summary_json(raw)
    if summary is None or not _summary_valid(summary, report.stats):
        if job.attempts >= get_settings().job_max_attempts:
            report.status = ReportStatus.FAILED
            report.error_code = "SUMMARY_INVALID"
            await db.commit()
            return True, None
        return False, "SUMMARY_INVALID"

    report.summary = summary
    report.summary_model_version = llm.model_version
    report.status = ReportStatus.SUCCEEDED
    report.error_code = None
    await db.commit()
    return True, None


def _public_stats(stats: dict) -> dict:
    """LLM 입력에는 entry_ids를 제외한 통계만 넘긴다."""

    def strip(obj):
        if isinstance(obj, dict):
            return {k: strip(v) for k, v in obj.items() if k != "entry_ids"}
        if isinstance(obj, list):
            return [strip(v) for v in obj]
        return obj

    return strip(stats)


def _parse_summary_json(raw: str) -> dict | None:
    text = raw.strip()
    if text.startswith("```"):
        text = text.strip("`")
        if text.startswith("json"):
            text = text[4:]
    start, end = text.find("{"), text.rfind("}")
    if start < 0 or end <= start:
        return None
    try:
        return json.loads(text[start : end + 1])
    except json.JSONDecodeError:
        return None


_HANDLERS = {
    JobType.MOOD_ANALYSIS: handle_mood_analysis,
    JobType.CHAT_GENERATION: handle_chat_generation,
    JobType.REPORT_SUMMARY: handle_report_summary,
}


async def process_one(db: AsyncSession, job: AiJob) -> None:
    handler = _HANDLERS.get(job.job_type)
    if handler is None:
        await _finish(db, job, ok=False, error_code="UNKNOWN_JOB_TYPE")
        return
    try:
        ok, error_code = await handler(db, job)
    except Exception:
        logger.exception(
            "job_error", extra={"job_id": job.id, "job_type": job.job_type}
        )
        await db.rollback()
        ok, error_code = False, "HANDLER_ERROR"
    await _finish(db, job, ok=ok, error_code=error_code)


async def heartbeat(db: AsyncSession) -> None:
    now = utcnow()
    existing = await db.get(WorkerHeartbeat, WORKER_NAME)
    if existing is None:
        db.add(WorkerHeartbeat(worker_name=WORKER_NAME, beat_at=now))
    else:
        existing.beat_at = now
    await db.commit()


def _disabled_error_code(job_type: JobType) -> str:
    if job_type == JobType.MOOD_ANALYSIS:
        return "CLASSIFIER_UNAVAILABLE"
    if job_type in (JobType.CHAT_GENERATION, JobType.REPORT_SUMMARY):
        return "LLM_UNAVAILABLE"
    return "AI_UNAVAILABLE"


async def fail_jobs_for_disabled_mode(db: AsyncSession) -> int:
    """AI 비활성 전환 전에 남은 job과 대상 상태를 terminal로 정리한다."""
    jobs = list(
        (
            await db.execute(
                sa.select(AiJob)
                .where(AiJob.status.in_((JobStatus.PENDING, JobStatus.RUNNING)))
                .order_by(AiJob.id)
                .with_for_update()
                .execution_options(populate_existing=True)
            )
        ).scalars()
    )
    for job in jobs:
        job.status = JobStatus.FAILED
        job.last_error_code = _disabled_error_code(job.job_type)
        job.locked_at = None
        await _mark_terminal_resource_failed(db, job)
    await db.commit()
    return len(jobs)


async def run_pending_once(factory: async_sessionmaker) -> int:
    """대기 job을 한 바퀴 처리한다. 테스트에서도 직접 호출한다."""
    processed = 0
    while True:
        async with factory() as db:
            job = await claim_next_job(db)
            if job is None:
                return processed
            await process_one(db, job)
            processed += 1


async def main() -> None:
    setup_logging()
    settings = get_settings()
    if settings.ai_mode == "disabled":
        factory = get_session_factory()
        async with factory() as db:
            failed = await fail_jobs_for_disabled_mode(db)
        logger.info("worker_exit_ai_disabled", extra={"jobs_failed": failed})
        return
    factory = get_session_factory()
    async with factory() as db:
        recovered = await recover_stale_jobs(db)
        if recovered:
            logger.info("jobs_recovered", extra={"attempts": recovered})
    logger.info("worker_started")
    while True:
        async with factory() as db:
            await heartbeat(db)
        processed = await run_pending_once(factory)
        if processed == 0:
            await asyncio.sleep(settings.worker_poll_interval_seconds)


if __name__ == "__main__":
    asyncio.run(main())
