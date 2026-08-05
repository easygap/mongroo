"""리포트 생성 (design.md 6.4).

통계는 결정적으로 동기 계산하고, 자연어 요약만 AI job으로 미룬다.
각 통계 bucket에 entry_ids를 붙여 원 기록으로 내려갈 수 있게 한다.
"""

import hashlib
import json
from collections import defaultdict
from datetime import date, timedelta

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.errors import AppError
from app.core.config import get_settings
from app.core.timeutil import (
    time_of_day_bucket,
    to_utc_iso,
    utcnow,
    week_period,
    month_period,
)
from app.models.enums import AnalysisStatus, JobStatus, JobType, ReportStatus
from app.models.mood import MoodEntry
from app.models.ops import AiJob
from app.models.report import Report

STATS_VERSION = "report-stats-2"


def resolve_period(period_type: str, period_start: date) -> tuple[date, date]:
    try:
        if period_type == "weekly":
            return week_period(period_start)
        if period_type == "monthly":
            return month_period(period_start)
    except ValueError as exc:
        raise AppError(400, "REPORT_PERIOD_INVALID", str(exc)) from exc
    raise AppError(
        400, "REPORT_PERIOD_INVALID", "period_type은 weekly 또는 monthly만 가능합니다."
    )


async def _entries_in_period(
    db: AsyncSession, user_id: int, start: date, end: date
) -> list[MoodEntry]:
    rows = await db.execute(
        sa.select(MoodEntry)
        .where(
            MoodEntry.user_id == user_id,
            MoodEntry.local_date >= start,
            MoodEntry.local_date < end,
        )
        .order_by(MoodEntry.local_date, MoodEntry.recorded_at_utc)
    )
    return list(rows.scalars())


def compute_input_hash(entries: list[MoodEntry], period_type: str, start: date) -> str:
    parts: list[str] = []
    for entry in entries:
        part = f"{entry.id}:{entry.input_version}:{entry.analysis_model_version or ''}"
        if entry.ai_emotion_override is not None or entry.ai_label_hidden:
            # 기본 라벨 상태에서는 이전 해시 형식을 유지해 배포만으로 모든 기존
            # 리포트가 stale 되는 일을 피한다. 사용자 라벨 설정이 실제로 있을 때만
            # 통계 입력을 결정하는 두 값을 해시에 포함한다.
            label_settings = json.dumps(
                [entry.ai_emotion_override, bool(entry.ai_label_hidden)],
                ensure_ascii=False,
                separators=(",", ":"),
            )
            part = f"{part}:{label_settings}"
        parts.append(part)
    raw = json.dumps(
        {
            "v": STATS_VERSION,
            "period": f"{period_type}:{start.isoformat()}",
            "entries": parts,
        },
        sort_keys=True,
    )
    return hashlib.sha256(raw.encode()).hexdigest()


def compute_stats(
    entries: list[MoodEntry],
    start: date,
    end: date,
    excluded_text_entry_ids: frozenset[int] = frozenset(),
) -> tuple[dict, float]:
    """excluded_text_entry_ids: 안전 신호가 있었던 기록. 기분·태그 집계에는
    포함하되 자유본문은 키워드 추출과 LLM 입력에서 제외한다 (docs/safety.md 6절)."""
    from app.services.keywords import extract_keywords

    mood_daily: dict[str, dict] = defaultdict(
        lambda: {"sum": 0, "count": 0, "entry_ids": []}
    )
    tag_dist: dict[str, dict] = defaultdict(lambda: {"count": 0, "entry_ids": []})
    ai_dist: dict[str, dict] = defaultdict(lambda: {"count": 0, "entry_ids": []})
    tod: dict[str, dict] = defaultdict(lambda: {"count": 0, "entry_ids": []})
    text_docs: list[tuple[int, str]] = []
    analyzed = 0
    with_text = 0

    for e in entries:
        day = e.local_date.isoformat()
        if e.mood_level_explicit:
            mood_daily[day]["sum"] += e.mood_level
            mood_daily[day]["count"] += 1
            mood_daily[day]["entry_ids"].append(e.id)
        for tag in e.emotion_tags or []:
            tag_dist[tag]["count"] += 1
            tag_dist[tag]["entry_ids"].append(e.id)
        bucket = time_of_day_bucket(e.recorded_at_utc)
        tod[bucket]["count"] += 1
        tod[bucket]["entry_ids"].append(e.id)
        if e.content and e.content.strip() and e.id not in excluded_text_entry_ids:
            with_text += 1
            text_docs.append((e.id, e.content))
        if e.analysis_status == AnalysisStatus.SUCCEEDED:
            analyzed += 1
            # 사용자가 숨긴 AI 라벨은 집계에서 제외 (design.md 4.2)
            if e.ai_emotion and not e.ai_label_hidden:
                label = e.ai_emotion_override or e.ai_emotion
                ai_dist[label]["count"] += 1
                ai_dist[label]["entry_ids"].append(e.id)

    # 기간 내 스트릭(연속 기록일) 계산
    recorded_days = sorted({e.local_date for e in entries})
    longest = current = 0
    prev: date | None = None
    for day in recorded_days:
        current = (
            current + 1 if prev is not None and day - prev == timedelta(days=1) else 1
        )
        longest = max(longest, current)
        prev = day
    tail_current = 0
    if recorded_days:
        cursor = recorded_days[-1]
        day_set = set(recorded_days)
        while cursor in day_set:
            tail_current += 1
            cursor -= timedelta(days=1)

    stats = {
        "total_entries": len(entries),
        "explicit_mood_entries": sum(
            1 for entry in entries if entry.mood_level_explicit
        ),
        "entries_with_text": with_text,
        "analyzed_entries": analyzed,
        "mood_daily": [
            {
                "date": day,
                "avg_mood": round(v["sum"] / v["count"], 2),
                "count": v["count"],
                "entry_ids": v["entry_ids"],
            }
            for day, v in sorted(mood_daily.items())
        ],
        "tag_distribution": [
            {"tag": tag, **v}
            for tag, v in sorted(
                tag_dist.items(), key=lambda kv: kv[1]["count"], reverse=True
            )
        ],
        "ai_emotion_distribution": [
            {"emotion": emotion, **v}
            for emotion, v in sorted(
                ai_dist.items(), key=lambda kv: kv[1]["count"], reverse=True
            )
        ],
        "time_of_day": [{"bucket": bucket, **v} for bucket, v in tod.items()],
        "streak": {"current": tail_current, "longest_in_period": longest},
        "keywords": extract_keywords(text_docs),
    }
    coverage = round(analyzed / with_text, 2) if with_text else 0.0
    return stats, coverage


def report_payload(report: Report, stale: bool | None = None) -> dict:
    body = {
        "id": report.id,
        "period_type": report.period_type,
        "period_start": report.period_start.isoformat(),
        "period_end": report.period_end.isoformat(),
        "status": report.status,
        "stats": report.stats,
        "analysis_coverage": report.analysis_coverage,
        "summary": report.summary,
        "summary_model_version": report.summary_model_version,
        "error_code": report.error_code,
        "created_at": to_utc_iso(report.created_at),
        "updated_at": to_utc_iso(report.updated_at),
    }
    if stale is not None:
        body["stale"] = stale
    return body


async def _safety_flagged_entry_ids(
    db: AsyncSession, user_id: int, entry_ids: list[int]
) -> frozenset[int]:
    if not entry_ids:
        return frozenset()
    from app.models.safety import SafetyEvent

    rows = await db.execute(
        sa.select(SafetyEvent.resource_id).where(
            SafetyEvent.user_id == user_id,
            SafetyEvent.resource_type == "mood_entry",
            SafetyEvent.resource_id.in_(entry_ids),
        )
    )
    return frozenset(r[0] for r in rows)


async def get_or_create(
    db: AsyncSession, user_id: int, period_type: str, period_start: date
) -> tuple[Report, bool]:
    """같은 입력이면 기존 리포트, 아니면 새로 생성. (report, created) 반환."""
    start, end = resolve_period(period_type, period_start)
    entries = await _entries_in_period(db, user_id, start, end)
    input_hash = compute_input_hash(entries, period_type, start)

    existing = await db.scalar(
        sa.select(Report).where(
            Report.user_id == user_id,
            Report.period_type == period_type,
            Report.period_start == start,
            Report.input_hash == input_hash,
        )
    )
    if existing is not None:
        return existing, False

    excluded = await _safety_flagged_entry_ids(db, user_id, [e.id for e in entries])
    stats, coverage = compute_stats(entries, start, end, excluded)
    ai_on = get_settings().ai_mode != "disabled" and stats["total_entries"] > 0
    report = Report(
        user_id=user_id,
        period_type=period_type,
        period_start=start,
        period_end=end,
        input_hash=input_hash,
        stats=stats,
        analysis_coverage=coverage,
        status=ReportStatus.PENDING if ai_on else ReportStatus.SUCCEEDED,
    )
    db.add(report)
    await db.flush()
    if ai_on:
        db.add(
            AiJob(
                user_id=user_id,
                job_type=JobType.REPORT_SUMMARY,
                resource_type="report",
                resource_id=report.id,
                input_version=1,
                status=JobStatus.PENDING,
                available_at=utcnow(),
            )
        )
    return report, True


async def is_stale(db: AsyncSession, report: Report) -> bool:
    """기록 변경·삭제로 입력이 달라졌으면 stale (design.md 5.4)."""
    entries = await _entries_in_period(
        db, report.user_id, report.period_start, report.period_end
    )
    return (
        compute_input_hash(entries, report.period_type, report.period_start)
        != report.input_hash
    )
