from datetime import timedelta

import sqlalchemy as sa
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.db import get_db
from app.core.timeutil import utcnow
from app.models.ops import WorkerHeartbeat

router = APIRouter(tags=["health"])


@router.get("/health/live")
async def live():
    return {"status": "ok"}


@router.get("/health/ready")
async def ready(db: AsyncSession = Depends(get_db)):
    settings = get_settings()
    checks: dict[str, dict] = {}

    try:
        await db.execute(sa.text("SELECT 1"))
        checks["database"] = {"status": "ok"}
    except Exception:
        checks["database"] = {"status": "down"}

    if settings.ai_mode == "disabled":
        checks["ai_worker"] = {"status": "disabled", "last_heartbeat": None}
        checks["classifier"] = {"status": "disabled", "mode": settings.ai_mode}
        checks["ollama"] = {"status": "disabled", "mode": settings.ai_mode}
    else:
        beat = None
        if checks["database"]["status"] == "ok":
            beat = await db.scalar(
                sa.select(WorkerHeartbeat.beat_at).where(WorkerHeartbeat.worker_name == "ai-worker")
            )
        alive = beat is not None and beat > utcnow() - timedelta(
            seconds=settings.worker_heartbeat_stale_seconds
        )
        checks["ai_worker"] = {
            "status": "ok" if alive else "down",
            "last_heartbeat": beat.isoformat() + "Z" if beat else None,
        }
        checks["classifier"] = {"status": "ok", "mode": settings.ai_mode}
        if settings.ai_mode == "local":
            from app.ai.llm import OllamaClient

            ok = await OllamaClient().ping()
            checks["ollama"] = {"status": "ok" if ok else "down", "mode": settings.ai_mode}
        else:
            checks["ollama"] = {"status": "ok", "mode": settings.ai_mode}

    # DB 불능만 down, AI 의존성 불능은 degraded (design.md 12.2)
    if checks["database"]["status"] != "ok":
        status = "down"
    elif any(c["status"] == "down" for c in checks.values()):
        status = "degraded"
    else:
        status = "ok"
    return {"status": status, "checks": checks}
