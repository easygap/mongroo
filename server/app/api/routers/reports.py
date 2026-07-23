from datetime import date

import sqlalchemy as sa
from fastapi import APIRouter, Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.api import idempotency
from app.api.deps import decode_cursor, get_current_user, get_owned
from app.api.errors import AppError
from app.core.db import get_db
from app.core.timeutil import to_utc_iso
from app.models.report import Report
from app.models.user import User
from app.schemas.requests import ReportCreateRequest
from app.services import reports as report_service

router = APIRouter(tags=["reports"])

PAGE_SIZE = 20


@router.post("/reports")
async def create_report(
    body: ReportCreateRequest,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    key = idempotency.require_key(request)
    try:
        period_start = date.fromisoformat(body.period_start)
    except ValueError:
        raise AppError(400, "REPORT_PERIOD_INVALID", "period_start는 YYYY-MM-DD 형식이어야 합니다.")

    async def handler():
        report, created = await report_service.get_or_create(
            db, user.id, body.period_type, period_start
        )
        await db.flush()
        return (202 if created else 200), {"report": report_service.report_payload(report)}

    return await idempotency.run_idempotent(
        db, user.id, "report_create", key, body.model_dump(), handler
    )


@router.get("/reports")
async def list_reports(
    period_type: str | None = None,
    cursor: str | None = None,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    query = (
        sa.select(Report)
        .where(Report.user_id == user.id)
        .order_by(Report.id.desc())
        .limit(PAGE_SIZE + 1)
    )
    if period_type is not None:
        query = query.where(Report.period_type == period_type)
    cursor_id = decode_cursor(cursor)
    if cursor_id is not None:
        query = query.where(Report.id < cursor_id)
    rows = list((await db.execute(query)).scalars())
    next_cursor = str(rows[PAGE_SIZE - 1].id) if len(rows) > PAGE_SIZE else None
    return {
        "items": [
            {
                "id": r.id,
                "period_type": r.period_type,
                "period_start": r.period_start.isoformat(),
                "period_end": r.period_end.isoformat(),
                "status": r.status,
                "created_at": to_utc_iso(r.created_at),
            }
            for r in rows[:PAGE_SIZE]
        ],
        "next_cursor": next_cursor,
    }


@router.get("/reports/{report_id}")
async def get_report(
    report_id: int,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    report = await get_owned(db, Report, report_id, user.id, "REPORT_NOT_FOUND")
    stale = await report_service.is_stale(db, report)
    return report_service.report_payload(report, stale=stale)
