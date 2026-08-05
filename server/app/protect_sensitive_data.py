"""민감 컬럼의 평문 backfill·키 회전·검증 CLI.

Alembic은 스키마만 바꾸고 이 명령이 실제 값을 암호화한다. 운영 compose는 API보다
먼저 이 명령을 실행하므로 평문이 남은 상태로 트래픽을 받지 않는다.
"""

from __future__ import annotations

import argparse
import asyncio
import json
from dataclasses import dataclass
from typing import Any

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncConnection, create_async_engine

from app.core.config import get_settings
from app.core.field_encryption import FieldEncryptionError, get_field_cipher, is_encrypted
from app.core.text_metadata import diary_content_marker
from app.core.timeutil import utcnow

PROTECTION_STATE_KEY = "sensitive-fields-v1"
PROTECTION_SCHEMA_REVISION = "0029_real_data_protection"


@dataclass(frozen=True)
class ProtectedColumn:
    table: str
    column: str
    purpose: str
    json_value: bool = False


PROTECTED_COLUMNS = (
    ProtectedColumn("mood_entries", "content", "mood_entries.content"),
    ProtectedColumn(
        "mood_entries", "emotion_tags", "mood_entries.emotion_tags", True
    ),
    ProtectedColumn("mood_entries", "ai_emotion", "mood_entries.ai_emotion"),
    ProtectedColumn("mood_entries", "ai_scores", "mood_entries.ai_scores", True),
    ProtectedColumn(
        "mood_entries",
        "ai_emotion_override",
        "mood_entries.ai_emotion_override",
    ),
    ProtectedColumn("chat_messages", "content", "chat_messages.content"),
    ProtectedColumn("reports", "stats", "reports.stats", True),
    ProtectedColumn("reports", "summary", "reports.summary", True),
    ProtectedColumn(
        "idempotency_keys",
        "response_body",
        "idempotency_keys.response_body",
        True,
    ),
    ProtectedColumn("plants", "name", "plants.name"),
    ProtectedColumn("plants", "final_form", "plants.final_form"),
    ProtectedColumn(
        "plants", "emotion_profile", "plants.emotion_profile", True
    ),
    ProtectedColumn("plants", "growth_branch", "plants.growth_branch"),
    ProtectedColumn(
        "adventure_patrols",
        "reaction_speaker",
        "adventure_patrols.reaction_speaker",
    ),
    ProtectedColumn(
        "expedition_runs",
        "summary_snapshot",
        "expedition_runs.summary_snapshot",
        True,
    ),
    ProtectedColumn(
        "expedition_party_members",
        "snapshot",
        "expedition_party_members.snapshot",
        True,
    ),
    ProtectedColumn(
        "expedition_actions",
        "result_payload",
        "expedition_actions.result_payload",
        True,
    ),
)


def _plaintext(value: Any, column: ProtectedColumn) -> str:
    if isinstance(value, bytes):
        value = value.decode("utf-8")
    if column.json_value and not isinstance(value, str):
        return json.dumps(
            value, ensure_ascii=False, separators=(",", ":"), sort_keys=True
        )
    return str(value)


async def count_unprotected(connection: AsyncConnection) -> int:
    """평문을 세면서 모든 ciphertext의 키·인증 태그·JSON 형식도 검증한다."""

    total = 0
    cipher = get_field_cipher()
    for field in PROTECTED_COLUMNS:
        last_id = 0
        while True:
            rows = (
                await connection.execute(
                    sa.text(
                        f"SELECT id, {field.column} FROM {field.table} "
                        f"WHERE id > :last_id AND {field.column} IS NOT NULL "
                        "ORDER BY id LIMIT 500"
                    ),
                    {"last_id": last_id},
                )
            ).all()
            if not rows:
                break
            for row_id, value in rows:
                last_id = int(row_id)
                raw = _plaintext(value, field)
                if not is_encrypted(raw):
                    total += 1
                    continue
                decrypted = cipher.decrypt(raw, purpose=field.purpose)
                if field.json_value:
                    try:
                        json.loads(decrypted)
                    except json.JSONDecodeError as exc:
                        raise FieldEncryptionError(
                            f"invalid protected JSON in {field.table}.{field.column} "
                            f"at id={row_id}"
                        ) from exc
    return total


async def _protect_column(engine, field: ProtectedColumn, rotate: bool) -> int:
    changed = 0
    last_id = 0
    cipher = get_field_cipher()
    while True:
        async with engine.begin() as connection:
            rows = (
                await connection.execute(
                    sa.text(
                        f"SELECT id, {field.column} FROM {field.table} "
                        f"WHERE id > :last_id AND {field.column} IS NOT NULL "
                        "ORDER BY id LIMIT 500"
                    ),
                    {"last_id": last_id},
                )
            ).all()
            if not rows:
                break
            for row_id, value in rows:
                last_id = int(row_id)
                raw = _plaintext(value, field)
                if is_encrypted(raw):
                    if not rotate:
                        continue
                    raw = cipher.decrypt(raw, purpose=field.purpose)
                encrypted = cipher.encrypt(raw, purpose=field.purpose)
                assignments = f"{field.column} = :encrypted"
                params: dict[str, Any] = {
                    "encrypted": encrypted,
                    "previous": value,
                    "row_id": row_id,
                }
                if field.table == "mood_entries" and field.column == "content":
                    assignments += ", content_length = :content_length"
                    params["content_length"] = diary_content_marker(raw)
                result = await connection.execute(
                    sa.text(
                        f"UPDATE {field.table} SET {assignments} "
                        f"WHERE id = :row_id AND {field.column} = :previous"
                    ),
                    params,
                )
                changed += int(result.rowcount or 0)
    return changed


async def _mark_protection_state(engine, remaining: int) -> None:
    settings = get_settings()
    async with engine.begin() as connection:
        result = await connection.execute(
            sa.text(
                "UPDATE data_protection_states SET "
                "schema_revision = :schema_revision, active_key_id = :active_key_id, "
                "remaining_plaintext = :remaining, verified_at = :verified_at "
                "WHERE protection_key = :protection_key"
            ),
            {
                "protection_key": PROTECTION_STATE_KEY,
                "schema_revision": PROTECTION_SCHEMA_REVISION,
                "active_key_id": settings.active_field_encryption_key_id,
                "remaining": remaining,
                "verified_at": utcnow(),
            },
        )
        if (result.rowcount or 0) == 0:
            await connection.execute(
                sa.text(
                    "INSERT INTO data_protection_states "
                    "(protection_key, schema_revision, active_key_id, "
                    "remaining_plaintext, verified_at) VALUES "
                    "(:protection_key, :schema_revision, :active_key_id, "
                    ":remaining, :verified_at)"
                ),
                {
                    "protection_key": PROTECTION_STATE_KEY,
                    "schema_revision": PROTECTION_SCHEMA_REVISION,
                    "active_key_id": settings.active_field_encryption_key_id,
                    "remaining": remaining,
                    "verified_at": utcnow(),
                },
            )


async def run(*, verify_only: bool, rotate: bool) -> tuple[int, int]:
    settings = get_settings()
    if settings.data_profile != "real-data":
        return 0, 0
    engine = create_async_engine(settings.database_url, pool_pre_ping=True)
    try:
        # 검사 중에는 readiness를 닫아 새 트래픽과 backfill/회전이 겹치지 않게 한다.
        await _mark_protection_state(engine, -1)
        changed = 0
        if not verify_only:
            for field in PROTECTED_COLUMNS:
                changed += await _protect_column(engine, field, rotate)
        async with engine.connect() as connection:
            remaining = await count_unprotected(connection)
        await _mark_protection_state(engine, remaining)
        return changed, remaining
    finally:
        await engine.dispose()


def main() -> None:
    parser = argparse.ArgumentParser(description="몽그루 민감 필드 암호화")
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument(
        "--rotate",
        action="store_true",
        help="이전 키 ciphertext도 active key로 다시 암호화",
    )
    args = parser.parse_args()
    changed, remaining = asyncio.run(
        run(verify_only=args.verify_only, rotate=args.rotate)
    )
    print(f"protected={changed} remaining_plaintext={remaining}")
    if remaining:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
