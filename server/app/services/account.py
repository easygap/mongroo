"""사용자 권리 행사용 계정 데이터 내보내기."""

from __future__ import annotations

from datetime import date, datetime
from typing import Any

import sqlalchemy as sa
from sqlalchemy import inspect
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.timeutil import to_utc_iso, utcnow
from app.models.adventure import (
    AdventurePatrol,
    DungeonRun,
    UserAdventureItem,
    UserAdventureResearch,
    UserDungeon,
)
from app.models.chat import ChatMessage, ChatRun, ChatSession
from app.models.expedition import (
    ExpeditionAction,
    ExpeditionContentExposure,
    ExpeditionLoot,
    ExpeditionNodeState,
    ExpeditionPartyMember,
    ExpeditionRun,
    PlantAdventureBond,
    PlantRegionFamiliarity,
    UserActiveExpedition,
    UserRegionProgress,
)
from app.models.game import FarmLayout, UserItem, UserQuest, UserSpeciesUnlock
from app.models.mood import MoodEntry
from app.models.plant import Plant
from app.models.report import Report
from app.models.reward import RewardEvent
from app.models.safety import SafetyEvent
from app.models.user import User


def _json_value(value: Any) -> Any:
    if isinstance(value, datetime):
        return to_utc_iso(value)
    if isinstance(value, date):
        return value.isoformat()
    return value


def _row_payload(row: Any, *, exclude: frozenset[str] = frozenset()) -> dict:
    return {
        attribute.key: _json_value(getattr(row, attribute.key))
        for attribute in inspect(type(row)).column_attrs
        if attribute.key not in exclude
    }


async def _owned_rows(
    db: AsyncSession, model: type, user_id: int
) -> list[Any]:
    return list(
        (
            await db.execute(
                sa.select(model)
                .where(getattr(model, "user_id") == user_id)
                .order_by(getattr(model, "id", getattr(model, "user_id")))
            )
        ).scalars()
    )


async def build_account_export(db: AsyncSession, user: User) -> dict:
    """비밀번호·토큰·rate-limit 키를 제외한 사용자 소유 데이터를 반환한다."""

    direct_models = {
        "mood_entries": MoodEntry,
        "plants": Plant,
        "reward_events": RewardEvent,
        "chat_sessions": ChatSession,
        "reports": Report,
        "safety_events": SafetyEvent,
        "user_quests": UserQuest,
        "user_items": UserItem,
        "farm_layouts": FarmLayout,
        "species_unlocks": UserSpeciesUnlock,
        "adventure_patrols": AdventurePatrol,
        "user_dungeons": UserDungeon,
        "dungeon_runs": DungeonRun,
        "adventure_items": UserAdventureItem,
        "adventure_research": UserAdventureResearch,
        "expedition_runs": ExpeditionRun,
        "active_expeditions": UserActiveExpedition,
        "plant_bonds": PlantAdventureBond,
        "region_progress": UserRegionProgress,
        "plant_region_familiarity": PlantRegionFamiliarity,
    }
    owned: dict[str, list[Any]] = {}
    for name, model in direct_models.items():
        owned[name] = await _owned_rows(db, model, user.id)

    session_ids = [row.id for row in owned["chat_sessions"]]
    if session_ids:
        chat_messages = list(
            (
                await db.execute(
                    sa.select(ChatMessage)
                    .where(ChatMessage.session_id.in_(session_ids))
                    .order_by(ChatMessage.id)
                )
            ).scalars()
        )
        chat_runs = list(
            (
                await db.execute(
                    sa.select(ChatRun)
                    .where(ChatRun.session_id.in_(session_ids))
                    .order_by(ChatRun.id)
                )
            ).scalars()
        )
    else:
        chat_messages = []
        chat_runs = []

    run_ids = [row.id for row in owned["expedition_runs"]]
    expedition_children: dict[str, list[Any]] = {}
    for name, model in {
        "expedition_party_members": ExpeditionPartyMember,
        "expedition_node_states": ExpeditionNodeState,
        "expedition_actions": ExpeditionAction,
        "expedition_loot": ExpeditionLoot,
        "expedition_content_exposures": ExpeditionContentExposure,
    }.items():
        if not run_ids:
            expedition_children[name] = []
            continue
        expedition_children[name] = list(
            (
                await db.execute(
                    sa.select(model)
                    .where(model.run_id.in_(run_ids))
                    .order_by(model.id)
                )
            ).scalars()
        )

    data = {
        name: [_row_payload(row) for row in rows] for name, rows in owned.items()
    }
    data["chat_messages"] = [_row_payload(row) for row in chat_messages]
    data["chat_runs"] = [_row_payload(row) for row in chat_runs]
    data.update(
        {
            name: [_row_payload(row) for row in rows]
            for name, rows in expedition_children.items()
        }
    )
    return {
        "format_version": 1,
        "exported_at": to_utc_iso(utcnow()),
        "profile": _row_payload(user, exclude=frozenset({"password_hash"})),
        "data": data,
    }


async def delete_account_data(db: AsyncSession, user: User) -> None:
    """식물 참조가 RESTRICT인 이력부터 지운 뒤 계정 cascade를 실행한다.

    식물을 개별 삭제할 때 탐험 이력을 실수로 잃지 않도록 RESTRICT를 유지하되,
    사용자가 계정 전체 삭제를 명시한 경우에는 같은 트랜잭션에서 의존 이력을 먼저
    지운다. 이 순서는 MySQL의 cascade 처리 순서에 의존하지 않는다.
    """

    await db.execute(
        sa.delete(AdventurePatrol).where(AdventurePatrol.user_id == user.id)
    )
    await db.execute(sa.delete(DungeonRun).where(DungeonRun.user_id == user.id))
    await db.execute(
        sa.delete(ExpeditionRun).where(ExpeditionRun.user_id == user.id)
    )
    await db.delete(user)
