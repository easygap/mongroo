from datetime import timedelta

import sqlalchemy as sa
from fastapi import APIRouter, Depends, Response
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.db import get_db
from app.core.timeutil import utcnow
from app.models.ops import WorkerHeartbeat
from app.protect_sensitive_data import (
    PROTECTION_SCHEMA_REVISION,
    PROTECTION_STATE_KEY,
)

router = APIRouter(tags=["health"])
EXPECTED_SCHEMA_REVISION = "0034_character_expansion_v7"


@router.get("/health/live")
async def live():
    return {"status": "ok"}


@router.get("/health/ready")
async def ready(response: Response, db: AsyncSession = Depends(get_db)):
    settings = get_settings()
    checks: dict[str, dict] = {}

    try:
        await db.execute(sa.text("SELECT 1"))
        checks["database"] = {"status": "ok"}
    except Exception:
        checks["database"] = {"status": "down"}

    if settings.data_profile == "real-data" and checks["database"]["status"] == "ok":
        try:
            revision = await db.scalar(
                sa.text("SELECT version_num FROM alembic_version")
            )
            checks["schema"] = {
                "status": "ok" if revision == EXPECTED_SCHEMA_REVISION else "down"
            }
            protection_state = (
                await db.execute(
                    sa.text(
                        "SELECT schema_revision, active_key_id, remaining_plaintext "
                        "FROM data_protection_states WHERE protection_key = :key"
                    ),
                    {"key": PROTECTION_STATE_KEY},
                )
            ).one_or_none()
            protection_valid = (
                protection_state is not None
                and protection_state.schema_revision == PROTECTION_SCHEMA_REVISION
                and protection_state.active_key_id
                == settings.active_field_encryption_key_id
                and protection_state.remaining_plaintext == 0
            )
            checks["sensitive_storage"] = {
                "status": "ok" if protection_valid else "down"
            }
            stale_consents = int(
                await db.scalar(
                    sa.text(
                        "SELECT COUNT(*) FROM users WHERE "
                        "terms_version IS NULL OR terms_version != :terms OR "
                        "privacy_version IS NULL OR privacy_version != :privacy OR "
                        "sensitive_consent_version IS NULL OR "
                        "sensitive_consent_version != :sensitive OR "
                        "age_confirmed_at IS NULL"
                    ),
                    {
                        "terms": settings.terms_version,
                        "privacy": settings.privacy_version,
                        "sensitive": settings.sensitive_consent_version,
                    },
                )
                or 0
            )
            checks["consent_contract"] = {
                "status": "ok" if stale_consents == 0 else "down"
            }
        except Exception:
            checks["schema"] = {"status": "down"}
            checks["sensitive_storage"] = {"status": "down"}
            checks["consent_contract"] = {"status": "down"}
    else:
        checks["schema"] = {"status": "disabled"}
        checks["sensitive_storage"] = {"status": "disabled"}
        checks["consent_contract"] = {"status": "disabled"}

    if settings.ai_mode == "disabled":
        checks["ai_worker"] = {"status": "disabled", "last_heartbeat": None}
        checks["classifier"] = {"status": "disabled", "mode": settings.ai_mode}
        checks["ollama"] = {"status": "disabled", "mode": settings.ai_mode}
    else:
        beat = None
        if checks["database"]["status"] == "ok":
            beat = await db.scalar(
                sa.select(WorkerHeartbeat.beat_at).where(
                    WorkerHeartbeat.worker_name == "ai-worker"
                )
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
            checks["ollama"] = {
                "status": "ok" if ok else "down",
                "mode": settings.ai_mode,
            }
        elif settings.ai_mode == "rules":
            checks["ollama"] = {"status": "disabled", "mode": settings.ai_mode}
        else:
            checks["ollama"] = {"status": "ok", "mode": settings.ai_mode}

    # DB·스키마·암호화·동의는 트래픽 수신 전 필수, AI는 degraded 허용이다.
    critical_checks = (
        "database",
        "schema",
        "sensitive_storage",
        "consent_contract",
    )
    if any(checks[name]["status"] == "down" for name in critical_checks):
        status = "down"
        response.status_code = 503
    elif any(c["status"] == "down" for c in checks.values()):
        status = "degraded"
    else:
        status = "ok"
    return {"status": status, "checks": checks}
