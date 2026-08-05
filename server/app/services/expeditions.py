"""직접 조작형 탐험 런 서비스.

지도, 판정, 자원, 보상은 서버가 확정한다. 클라이언트는 매 행동마다 자신이 본
revision과 고유 client_action_id를 보내고, 서버는 재전송을 같은 결과로 재생한다.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
from pathlib import Path
from typing import Any

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.errors import AppError
from app.content.expeditions.skills import skill_definition
from app.content.expeditions.validator import expand_map_templates, validate_content
from app.core.config import get_settings
from app.core.timeutil import local_date_of, to_utc_iso, utcnow
from app.models.adventure import UserAdventureItem
from app.models.enums import PlantStatus, RewardEventType
from app.models.expedition import (
    ExpeditionAction,
    ExpeditionContentExposure,
    ExpeditionLoot,
    ExpeditionNodeState,
    ExpeditionPartyMember,
    ExpeditionRun,
    PlantAdventureBond,
    PlantRegionFamiliarity,
    UserRegionProgress,
    UserActiveExpedition,
)
from app.models.mood import MoodEntry
from app.models.plant import Plant, PlantSpecies
from app.models.reward import RewardEvent
from app.services import game as game_service
from app.services import rewards
from app.services.adventure import ITEMS, character_stats
from app.services.plants import growth_state_payload, stage_from_exp


_CONTENT_PATH = (
    Path(__file__).resolve().parents[1]
    / "content"
    / "expeditions"
    / "v1"
    / "moss_archive.json"
)
_STAT_LABELS = {"care": "돌봄", "focus": "집중", "courage": "용기", "insight": "관찰"}
_OUTCOME_LABELS = {
    "flourish": "멋지게 풀어냈어요",
    "clear": "차분히 길을 열었어요",
    "detour": "뜻밖의 우회로가 생겼어요",
    "safe": "안전한 선택으로 물러났어요",
}


def _content() -> dict[str, Any]:
    with _CONTENT_PATH.open(encoding="utf-8") as file:
        content = json.load(file)
    validate_content(content)
    return content


def select_map_template(
    content: dict[str, Any], map_seed: str, mode: str
) -> dict[str, Any]:
    templates = expand_map_templates(content)
    if not templates:
        raise RuntimeError("검증된 탐험 지도 템플릿이 없습니다")
    if mode == "tutorial":
        return templates[0]
    return templates[int(map_seed[:8], 16) % len(templates)]


def _node_defs(run: ExpeditionRun) -> dict[str, dict]:
    return {node["code"]: node for node in run.map_snapshot["nodes"]}


def _neighbors(run: ExpeditionRun, node_code: str) -> list[str]:
    result: list[str] = []
    for left, right in run.map_snapshot["edges"]:
        if left == node_code:
            result.append(right)
        elif right == node_code:
            result.append(left)
    return result


def _event(run: ExpeditionRun, event_code: str | None) -> dict | None:
    if event_code is None:
        return None
    return run.map_snapshot.get("events", {}).get(event_code)


def _growth_form(plant: Plant) -> str:
    growth = growth_state_payload(plant)
    cue = growth.get("growth_cue")
    cue_form = cue.get("form") if isinstance(cue, dict) else None
    return str(growth.get("growth_form") or cue_form or plant.final_form or "mosaic")


def _bounded_stats(raw_stats: dict[str, int], stat_cap: int | None) -> dict[str, int]:
    if stat_cap is None:
        return dict(raw_stats)
    return {stat: min(value, stat_cap) for stat, value in raw_stats.items()}


def _plant_snapshot(
    plant: Plant, species: PlantSpecies, *, stat_cap: int | None = None
) -> dict:
    stage = stage_from_exp(plant.exp)
    form = _growth_form(plant)
    raw_stats = character_stats(stage, form)
    effective_stats = _bounded_stats(raw_stats, stat_cap)
    return {
        "plant_id": plant.id,
        "name": plant.name,
        "status": plant.status,
        "species": {"code": species.code, "name": species.name},
        "stage": stage,
        "form": form,
        "stats": effective_stats,
        "raw_stats": raw_stats,
        "effective_stats": effective_stats,
        "stat_cap": stat_cap,
        "asset_manifest": species.asset_manifest or {},
    }


def _guide_snapshot(position: int, *, stat_cap: int | None = None) -> dict:
    raw_stats = {"care": 6, "focus": 6, "courage": 5, "insight": 7}
    effective_stats = _bounded_stats(raw_stats, stat_cap)
    return {
        "plant_id": None,
        "name": "기록 안내자" if position == 0 else f"기록 안내자 {position + 1}",
        "species": {"code": "archive_guide", "name": "서고 안내자"},
        "stage": 2,
        "form": "mosaic",
        "stats": effective_stats,
        "raw_stats": raw_stats,
        "effective_stats": effective_stats,
        "stat_cap": stat_cap,
        "asset_manifest": {},
    }


async def _diary_ready(db: AsyncSession, user_id: int, local_date) -> bool:
    contents = (
        await db.execute(
            sa.select(MoodEntry.content).where(
                MoodEntry.user_id == user_id,
                MoodEntry.local_date == local_date,
                MoodEntry.content.is_not(None),
            )
        )
    ).scalars()
    return any(len((content or "").strip()) >= 50 for content in contents)


async def _reward_used(db: AsyncSession, user_id: int, local_date) -> bool:
    key = f"active_expedition_daily:{user_id}:{local_date.isoformat()}"
    return (
        await db.scalar(
            sa.select(RewardEvent.id).where(RewardEvent.dedupe_key == key).limit(1)
        )
        is not None
    )


async def _active_run(db: AsyncSession, user_id: int) -> ExpeditionRun | None:
    return await db.scalar(
        sa.select(ExpeditionRun)
        .join(UserActiveExpedition, UserActiveExpedition.run_id == ExpeditionRun.id)
        .where(UserActiveExpedition.user_id == user_id)
    )


async def catalog_payload(db: AsyncSession, user_id: int) -> dict:
    today = local_date_of(utcnow())
    active = await _active_run(db, user_id)
    diary_ready = await _diary_ready(db, user_id, today)
    reward_used = await _reward_used(db, user_id, today)
    safety_active = await game_service.safety_active_today(db, user_id, today)
    tutorial_completed = bool(
        await db.scalar(
            sa.select(sa.func.count(ExpeditionRun.id)).where(
                ExpeditionRun.user_id == user_id,
                ExpeditionRun.mode == "tutorial",
                ExpeditionRun.status == "completed",
            )
        )
    )
    content = _content()
    return {
        "content_version": content["content_version"],
        "active_run_id": active.id if active else None,
        "entry": {
            "diary_ready": diary_ready,
            "heart_resonance_available": diary_ready
            and not reward_used
            and not safety_active,
            "free_explore_available": not safety_active,
            "suspended": safety_active,
            "tutorial_completed": tutorial_completed,
            "reason": "safety_support_active" if safety_active else None,
        },
        "regions": [
            {
                **content["region"],
                "modes": ["tutorial", "heart_resonance", "free_explore"],
            }
        ],
        "rules": {
            "party_min": 1,
            "party_max": 3,
            "daily_reward_mode": "heart_resonance",
            "free_explore_reward": False,
        },
    }


def _cursor_signature(raw: bytes) -> str:
    return hmac.new(
        get_settings().jwt_secret.encode(), raw, hashlib.sha256
    ).hexdigest()[:24]


def _encode_cursor(after_id: int) -> str:
    raw = json.dumps({"after_id": after_id}, separators=(",", ":")).encode()
    token = base64.urlsafe_b64encode(raw).decode().rstrip("=")
    return f"{token}.{_cursor_signature(raw)}"


def _decode_cursor(cursor: str | None) -> int:
    if not cursor:
        return 0
    try:
        token, signature = cursor.split(".", 1)
        raw = base64.urlsafe_b64decode(token + "=" * (-len(token) % 4))
        if not hmac.compare_digest(signature, _cursor_signature(raw)):
            raise ValueError
        return max(0, int(json.loads(raw)["after_id"]))
    except (ValueError, KeyError, TypeError, json.JSONDecodeError):
        raise AppError(422, "INVALID_CURSOR", "탐험대 목록 커서가 올바르지 않습니다.")


async def roster_payload(
    db: AsyncSession, user_id: int, cursor: str | None = None, limit: int = 30
) -> dict:
    after_id = _decode_cursor(cursor)
    limit = max(1, min(limit, 50))
    rows = (
        await db.execute(
            sa.select(Plant, PlantSpecies)
            .join(PlantSpecies, PlantSpecies.id == Plant.species_id)
            .where(
                Plant.user_id == user_id,
                Plant.id > after_id,
                Plant.status.in_((PlantStatus.ACTIVE, PlantStatus.HARVESTED)),
            )
            .order_by(Plant.id)
            .limit(limit + 1)
        )
    ).all()
    page = rows[:limit]
    items = []
    for plant, species in page:
        snapshot = _plant_snapshot(plant, species)
        snapshot["eligible"] = snapshot["stage"] >= 2
        snapshot["ineligible_reason"] = (
            None if snapshot["eligible"] else "새싹 단계부터 탐험할 수 있어요."
        )
        items.append(snapshot)
    return {
        "items": items,
        "next_cursor": _encode_cursor(page[-1][0].id) if len(rows) > limit else None,
    }


async def _party_rows(db: AsyncSession, run_id: int) -> list[ExpeditionPartyMember]:
    return list(
        (
            await db.execute(
                sa.select(ExpeditionPartyMember)
                .where(ExpeditionPartyMember.run_id == run_id)
                .order_by(ExpeditionPartyMember.position)
            )
        ).scalars()
    )


async def _node_rows(db: AsyncSession, run_id: int) -> list[ExpeditionNodeState]:
    return list(
        (
            await db.execute(
                sa.select(ExpeditionNodeState).where(
                    ExpeditionNodeState.run_id == run_id
                )
            )
        ).scalars()
    )


def _member_payload(member: ExpeditionPartyMember, phase: str) -> dict:
    if member.is_guide:
        skills = {
            "signature": {"used": True, "available": False},
            "form": {"used": True, "available": False},
        }
    else:
        species_code = member.snapshot["species"]["code"]
        form = member.snapshot.get("form", "mosaic")
        signature = skill_definition(species_code, form, "signature")
        form_skill = skill_definition(species_code, form, "form")
        skills = {
            "signature": {
                **signature,
                "used": member.signature_used,
                "available": phase in signature["phases"] and not member.signature_used,
            },
            "form": {
                **form_skill,
                "used": member.form_used,
                "available": phase in form_skill["phases"] and not member.form_used,
            },
        }
    return {
        "id": member.id,
        "position": member.position,
        "is_guide": member.is_guide,
        **member.snapshot,
        "skills": skills,
    }


def _choice_preview(choice: dict, member: ExpeditionPartyMember, effects: dict) -> dict:
    stat = choice.get("stat")
    if stat is None:
        return {
            "member_id": member.id,
            "safe": True,
            "label": "판정 없이 안전하게 진행",
        }
    pending = effects.get("pending_skill") or {}
    applies = pending.get("member_id") == member.id
    effective_stat = pending.get("stat_override", stat) if applies else stat
    allowed_stats = pending.get("allowed_stats") if applies else None
    bonus = (
        int(pending.get("bonus", 0))
        if applies and (not allowed_stats or effective_stat in allowed_stats)
        else 0
    )
    effective_value = int(member.snapshot["stats"].get(effective_stat, 0))
    raw_value = int(
        member.snapshot.get("raw_stats", member.snapshot["stats"]).get(
            effective_stat, effective_value
        )
    )
    value = effective_value + bonus
    difficulty = max(
        0,
        int(choice["difficulty"])
        + (int(pending.get("difficulty_delta", 0)) if applies else 0),
    )
    return {
        "member_id": member.id,
        "stat": effective_stat,
        "stat_label": _STAT_LABELS[effective_stat],
        "value": value,
        "raw_value": raw_value,
        "effective_value": effective_value,
        "skill_bonus": bonus,
        "difficulty": difficulty,
        "forecast": "유리" if value >= difficulty else "도전",
        "label": (
            f"{_STAT_LABELS[effective_stat]} {value} · 기준 {difficulty}"
            + (
                f" · 원래 {raw_value} → 탐험 {effective_value}"
                if raw_value != effective_value
                else ""
            )
        ),
    }


async def run_payload(db: AsyncSession, run: ExpeditionRun) -> dict:
    members = await _party_rows(db, run.id)
    node_states = await _node_rows(db, run.id)
    states = {state.node_code: state for state in node_states}
    defs = _node_defs(run)
    nodes: list[dict] = []
    for code, definition in defs.items():
        state = states[code]
        if state.status == "hidden":
            nodes.append({"code": code, "status": "hidden", "type": "unknown"})
            continue
        nodes.append(
            {
                **{
                    key: value
                    for key, value in definition.items()
                    if key != "event_code"
                },
                "status": state.status,
                "outcome": state.outcome_code,
            }
        )

    current_state = states[run.current_node_code]
    current_event = None
    event = _event(run, current_state.event_code)
    if run.status == "active" and run.phase == "awaiting_event" and event:
        pending_skill = (run.runtime_effects_snapshot or {}).get("pending_skill") or {}
        current_event = {
            "code": current_state.event_code,
            "node_code": current_state.node_code,
            "title": event["title"],
            "text": event["text"],
            "skill_hint": pending_skill.get("story_hint"),
            "spotlight_member_id": next(
                (
                    item["member_id"]
                    for item in run.spotlight_snapshot
                    if item["event_code"] == current_state.event_code
                ),
                None,
            ),
            "choices": [
                {
                    **choice,
                    "previews": [
                        _choice_preview(choice, member, run.runtime_effects_snapshot)
                        for member in members
                    ],
                }
                for choice in event["choices"]
            ],
        }

    available: list[dict] = []
    if run.status == "active" and run.phase == "exploring":
        for code in _neighbors(run, run.current_node_code):
            state = states[code]
            if state.status != "hidden":
                available.append(
                    {
                        "type": "move",
                        "node_code": code,
                        "cost": int(defs[code].get("cost", 0)),
                    }
                )
        if run.objective_secured and defs[run.current_node_code]["type"] in (
            "exit",
            "camp",
            "entrance",
        ):
            available.append({"type": "extract"})
        if any(
            not member.is_guide
            and (
                (
                    not member.signature_used
                    and run.phase
                    in skill_definition(
                        member.snapshot["species"]["code"],
                        member.snapshot.get("form", "mosaic"),
                        "signature",
                    )["phases"]
                )
                or (
                    not member.form_used
                    and run.phase
                    in skill_definition(
                        member.snapshot["species"]["code"],
                        member.snapshot.get("form", "mosaic"),
                        "form",
                    )["phases"]
                )
            )
            for member in members
        ):
            available.append({"type": "skill"})
        available.append({"type": "retreat"})
    elif run.status == "active" and run.phase == "awaiting_event":
        available.extend(({"type": "choice"}, {"type": "skill"}))

    loots = list(
        (
            await db.execute(
                sa.select(ExpeditionLoot).where(ExpeditionLoot.run_id == run.id)
            )
        ).scalars()
    )
    return {
        "run": {
            "id": run.id,
            "region_code": run.region_code,
            "mode": run.mode,
            "status": run.status,
            "phase": run.phase,
            "revision": run.revision,
            "current_node_code": run.current_node_code,
            "trail_light": run.trail_light,
            "resolve": run.resolve,
            "objective_secured": run.objective_secured,
            "reward_eligible": run.reward_eligible,
            "started_at": to_utc_iso(run.started_at),
            "completed_at": to_utc_iso(run.completed_at),
        },
        "region": run.map_snapshot["region"],
        "party": [_member_payload(member, run.phase) for member in members],
        "map": {
            "code": run.map_snapshot["code"],
            "name": run.map_snapshot["name"],
            "nodes": nodes,
            "edges": run.map_snapshot["edges"],
        },
        "current_event": current_event,
        "available_actions": available,
        "run_thread": run.run_thread_snapshot,
        "memory": run.run_memory_snapshot,
        "loot": [
            {
                "item_code": loot.item_code,
                "name": ITEMS.get(loot.item_code, (loot.item_code, ""))[0],
                "quantity": loot.quantity,
                "disposition": loot.disposition,
            }
            for loot in loots
        ],
        "summary": run.summary_snapshot,
    }


async def active_payload(db: AsyncSession, user_id: int) -> dict | None:
    run = await _active_run(db, user_id)
    return await run_payload(db, run) if run else None


async def get_run_payload(db: AsyncSession, user_id: int, run_id: int) -> dict:
    run = await db.scalar(
        sa.select(ExpeditionRun).where(
            ExpeditionRun.id == run_id, ExpeditionRun.user_id == user_id
        )
    )
    if run is None:
        raise AppError(404, "EXPEDITION_NOT_FOUND", "탐험 기록을 찾을 수 없습니다.")
    return await run_payload(db, run)


async def start_run(
    db: AsyncSession,
    user_id: int,
    *,
    region_code: str,
    mode: str,
    plant_ids: list[int],
    guide_count: int,
) -> dict:
    content = _content()
    if (
        not plant_ids
        or len(plant_ids) != len(set(plant_ids))
        or not 1 <= len(plant_ids) + guide_count <= 3
    ):
        raise AppError(
            422,
            "INVALID_EXPEDITION_PARTY",
            "서로 다른 보유 캐릭터를 한 명 이상, 전체 세 명 이하로 편성해 주세요.",
        )
    if region_code != content["region"]["code"]:
        raise AppError(
            404, "EXPEDITION_REGION_NOT_FOUND", "탐험 지역을 찾을 수 없습니다."
        )
    today = local_date_of(utcnow())
    if await game_service.safety_active_today(db, user_id, today):
        raise AppError(
            409,
            "EXPEDITION_SUSPENDED",
            "지금은 탐험보다 안전 지원을 먼저 이용해 주세요.",
        )
    if await _active_run(db, user_id):
        raise AppError(409, "EXPEDITION_ALREADY_ACTIVE", "진행 중인 탐험이 있습니다.")
    if mode == "heart_resonance":
        if not await _diary_ready(db, user_id, today):
            raise AppError(
                409,
                "DIARY_REQUIRED",
                "오늘 마음 일기를 50자 이상 기록하면 마음 공명 탐험을 시작할 수 있어요.",
            )
        if await _reward_used(db, user_id, today):
            raise AppError(
                409,
                "EXPEDITION_REWARD_USED",
                "오늘의 마음 공명 탐험 보상은 이미 받았습니다.",
            )

    rows = (
        await db.execute(
            sa.select(Plant, PlantSpecies)
            .join(PlantSpecies, PlantSpecies.id == Plant.species_id)
            .where(Plant.user_id == user_id, Plant.id.in_(plant_ids))
            .order_by(Plant.id)
        )
    ).all()
    by_id = {plant.id: (plant, species) for plant, species in rows}
    if set(by_id) != set(plant_ids):
        raise AppError(
            422, "INVALID_EXPEDITION_PARTY", "보유한 캐릭터만 편성할 수 있습니다."
        )
    if any(stage_from_exp(plant.exp) < 2 for plant, _ in rows):
        raise AppError(
            422, "EXPEDITION_STAGE_REQUIRED", "새싹 단계부터 탐험할 수 있습니다."
        )
    if mode == "tutorial" and (
        len(plant_ids) != 1
        or by_id[plant_ids[0]][0].status != PlantStatus.ACTIVE
        or guide_count != 1
    ):
        raise AppError(
            422,
            "TUTORIAL_PARTY_FIXED",
            "조작 연습은 현재 자라는 캐릭터와 기록 안내자 한 명이 함께 떠나요.",
        )

    seed_source = f"{user_id}:{today}:{mode}:{','.join(map(str, plant_ids))}"
    map_seed = hmac.new(
        get_settings().jwt_secret.encode(), seed_source.encode(), hashlib.sha256
    ).hexdigest()
    map_data = select_map_template(content, map_seed, mode)
    map_snapshot = {
        "code": map_data["code"],
        "name": map_data["name"],
        "entrance": map_data["entrance"],
        "nodes": map_data["nodes"],
        "edges": map_data["edges"],
        "events": content["events"],
        "discoveries": content["discoveries"],
        "region": content["region"],
    }
    thread = content["run_threads"][int(map_seed[:2], 16) % len(content["run_threads"])]
    run = ExpeditionRun(
        user_id=user_id,
        region_code=region_code,
        mode=mode,
        local_date=today,
        content_version=content["content_version"],
        map_seed=map_seed,
        map_snapshot=map_snapshot,
        run_thread_snapshot={**thread, "stage": "seed", "current_text": thread["seed"]},
        run_memory_snapshot={"discoveries": [], "outcomes": []},
        spotlight_snapshot=[],
        runtime_effects_snapshot={},
        current_node_code=map_data["entrance"],
        trail_light=10,
        resolve=6,
        reward_eligible=mode == "heart_resonance",
    )
    db.add(run)
    await db.flush()
    db.add(UserActiveExpedition(user_id=user_id, run_id=run.id))

    members: list[ExpeditionPartyMember] = []
    position = 0
    for plant_id in plant_ids:
        plant, species = by_id[plant_id]
        member = ExpeditionPartyMember(
            run_id=run.id,
            position=position,
            plant_id=plant.id,
            is_guide=False,
            snapshot=_plant_snapshot(
                plant,
                species,
                stat_cap=int(content["region"].get("stat_cap", 7)),
            ),
        )
        db.add(member)
        members.append(member)
        position += 1
    for guide_index in range(guide_count):
        member = ExpeditionPartyMember(
            run_id=run.id,
            position=position,
            plant_id=None,
            is_guide=True,
            snapshot=_guide_snapshot(
                guide_index,
                stat_cap=int(content["region"].get("stat_cap", 7)),
            ),
        )
        db.add(member)
        members.append(member)
        position += 1
    await db.flush()

    real_members = [member for member in members if not member.is_guide] or members
    run.spotlight_snapshot = [
        {
            "event_code": "wet_label_order",
            "member_id": real_members[0].id,
            "consumed": False,
        },
        {
            "event_code": "ledger_keeper",
            "member_id": real_members[-1].id,
            "consumed": False,
        },
    ]
    for node in map_data["nodes"]:
        status = (
            "revealed"
            if mode == "tutorial" or node["code"] in map_data["initial_revealed"]
            else "hidden"
        )
        if node["code"] == map_data["entrance"]:
            status = "visited"
        db.add(
            ExpeditionNodeState(
                run_id=run.id,
                node_code=node["code"],
                status=status,
                event_code=node.get("event_code"),
                entered_at=utcnow() if node["code"] == map_data["entrance"] else None,
            )
        )
    db.add(
        ExpeditionContentExposure(
            user_id=user_id,
            run_id=run.id,
            content_kind="map_template",
            content_code=map_data["code"],
            context_code=region_code,
            exposure_index=0,
        )
    )
    db.add(
        ExpeditionContentExposure(
            user_id=user_id,
            run_id=run.id,
            content_kind="run_thread",
            content_code=thread["code"],
            context_code=region_code,
            exposure_index=0,
        )
    )
    await db.flush()
    return await run_payload(db, run)


async def _lock_run(db: AsyncSession, user_id: int, run_id: int) -> ExpeditionRun:
    run = await db.scalar(
        sa.select(ExpeditionRun)
        .where(ExpeditionRun.id == run_id, ExpeditionRun.user_id == user_id)
        .with_for_update()
    )
    if run is None:
        raise AppError(404, "EXPEDITION_NOT_FOUND", "탐험 기록을 찾을 수 없습니다.")
    return run


async def _existing_action(
    db: AsyncSession,
    run: ExpeditionRun,
    client_action_id: str,
    action_type: str,
    request_payload: dict,
) -> dict | None:
    action = await db.scalar(
        sa.select(ExpeditionAction).where(
            ExpeditionAction.run_id == run.id,
            ExpeditionAction.client_action_id == client_action_id,
        )
    )
    if action is None:
        return None
    if action.action_type != action_type or action.request_payload != request_payload:
        raise AppError(
            409,
            "EXPEDITION_ACTION_ID_CONFLICT",
            "같은 행동 키로 다른 요청을 보냈습니다.",
        )
    return action.result_payload


def _check_revision(run: ExpeditionRun, expected_revision: int) -> None:
    if run.status != "active":
        raise AppError(409, "EXPEDITION_FINISHED", "이미 끝난 탐험입니다.")
    if run.revision != expected_revision:
        raise AppError(
            409,
            "EXPEDITION_REVISION_CONFLICT",
            "탐험 상태가 바뀌었습니다. 최신 지도를 불러와 주세요.",
            {"expected_revision": expected_revision, "current_revision": run.revision},
        )


async def _finish_action(
    db: AsyncSession,
    run: ExpeditionRun,
    *,
    action_type: str,
    client_action_id: str,
    expected_revision: int,
    request_payload: dict,
) -> dict:
    run.revision += 1
    await db.flush()
    result = await run_payload(db, run)
    db.add(
        ExpeditionAction(
            run_id=run.id,
            action_index=run.revision,
            client_action_id=client_action_id,
            expected_revision=expected_revision,
            action_type=action_type,
            request_payload=request_payload,
            result_payload=result,
        )
    )
    await db.flush()
    return result


async def move(
    db: AsyncSession,
    user_id: int,
    run_id: int,
    *,
    node_code: str,
    expected_revision: int,
    client_action_id: str,
) -> dict:
    run = await _lock_run(db, user_id, run_id)
    request_payload = {"node_code": node_code, "expected_revision": expected_revision}
    replay = await _existing_action(db, run, client_action_id, "move", request_payload)
    if replay is not None:
        return replay
    _check_revision(run, expected_revision)
    if run.phase != "exploring":
        raise AppError(
            409, "EXPEDITION_EVENT_PENDING", "현재 사건의 선택을 먼저 마쳐 주세요."
        )
    if node_code not in _neighbors(run, run.current_node_code):
        raise AppError(
            422, "EXPEDITION_NODE_NOT_ADJACENT", "연결된 장소로만 이동할 수 있습니다."
        )
    state = await db.scalar(
        sa.select(ExpeditionNodeState).where(
            ExpeditionNodeState.run_id == run.id,
            ExpeditionNodeState.node_code == node_code,
        )
    )
    if state is None or state.status == "hidden":
        raise AppError(422, "EXPEDITION_NODE_HIDDEN", "아직 발견하지 못한 장소입니다.")
    definition = _node_defs(run)[node_code]
    cost = int(definition.get("cost", 0))
    effects = dict(run.runtime_effects_snapshot)
    if effects.get("next_move_free") and state.status == "revealed":
        cost = 0
        effects.pop("next_move_free", None)
        run.runtime_effects_snapshot = effects
    if run.trail_light < cost:
        raise AppError(409, "EXPEDITION_LIGHT_SHORTAGE", "길을 밝힐 빛이 부족합니다.")
    run.trail_light -= cost
    run.current_node_code = node_code
    state.entered_at = state.entered_at or utcnow()
    if state.status != "resolved":
        state.status = "visited"
    for neighbor in _neighbors(run, node_code):
        neighbor_state = await db.scalar(
            sa.select(ExpeditionNodeState).where(
                ExpeditionNodeState.run_id == run.id,
                ExpeditionNodeState.node_code == neighbor,
            )
        )
        if neighbor_state and neighbor_state.status == "hidden":
            neighbor_state.status = "revealed"

    node_type = definition["type"]
    if definition.get("event_code") and state.resolved_at is None:
        run.phase = "awaiting_event"
    elif node_type == "camp" and state.resolved_at is None:
        run.trail_light = min(12, run.trail_light + 2)
        run.resolve = min(6, run.resolve + 1)
        state.status = "resolved"
        state.resolved_at = utcnow()
        state.outcome_code = "rested"
    elif node_type == "discovery" and state.resolved_at is None:
        discovery = run.map_snapshot["discoveries"][node_code]
        state.status = "resolved"
        state.resolved_at = utcnow()
        state.outcome_code = "discovered"
        state.story_snapshot = discovery
        memory = dict(run.run_memory_snapshot)
        memory["discoveries"] = [
            *memory.get("discoveries", []),
            {"code": node_code, **discovery},
        ]
        run.run_memory_snapshot = memory
    elif node_type == "objective" and not run.objective_secured:
        run.objective_secured = True
        state.status = "resolved"
        state.resolved_at = utcnow()
        state.outcome_code = "secured"
        thread = dict(run.run_thread_snapshot)
        thread.update({"stage": "payoff", "current_text": thread["payoff"]})
        run.run_thread_snapshot = thread
        reward = run.map_snapshot["region"]["reward"]
        db.add(
            ExpeditionLoot(
                run_id=run.id,
                node_code=node_code,
                item_code=reward["item_code"],
                quantity=1,
                value_units=1,
                loot_kind="objective",
                disposition="candidate" if run.reward_eligible else "recorded",
            )
        )
    return await _finish_action(
        db,
        run,
        action_type="move",
        client_action_id=client_action_id,
        expected_revision=expected_revision,
        request_payload=request_payload,
    )


def _deterministic_roll(
    run: ExpeditionRun, event_code: str, choice_code: str, member_id: int
) -> int:
    raw = f"{run.map_seed}:{event_code}:{choice_code}:{member_id}".encode()
    return int(hashlib.sha256(raw).hexdigest()[:8], 16) % 4 + 1


async def choose(
    db: AsyncSession,
    user_id: int,
    run_id: int,
    *,
    choice_code: str,
    acting_member_id: int,
    expected_revision: int,
    client_action_id: str,
) -> dict:
    run = await _lock_run(db, user_id, run_id)
    request_payload = {
        "choice_code": choice_code,
        "acting_member_id": acting_member_id,
        "expected_revision": expected_revision,
    }
    replay = await _existing_action(
        db, run, client_action_id, "choice", request_payload
    )
    if replay is not None:
        return replay
    _check_revision(run, expected_revision)
    if run.phase != "awaiting_event":
        raise AppError(409, "EXPEDITION_EVENT_MISSING", "선택할 사건이 없습니다.")
    state = await db.scalar(
        sa.select(ExpeditionNodeState).where(
            ExpeditionNodeState.run_id == run.id,
            ExpeditionNodeState.node_code == run.current_node_code,
        )
    )
    event = _event(run, state.event_code if state else None)
    choice = next(
        (
            item
            for item in (event or {}).get("choices", [])
            if item["code"] == choice_code
        ),
        None,
    )
    if state is None or event is None or choice is None:
        raise AppError(422, "EXPEDITION_CHOICE_INVALID", "선택지를 찾을 수 없습니다.")
    member = await db.scalar(
        sa.select(ExpeditionPartyMember).where(
            ExpeditionPartyMember.id == acting_member_id,
            ExpeditionPartyMember.run_id == run.id,
        )
    )
    if member is None:
        raise AppError(422, "EXPEDITION_MEMBER_INVALID", "탐험대원을 찾을 수 없습니다.")

    effects = dict(run.runtime_effects_snapshot)
    pending = effects.get("pending_skill") or {}
    applies = pending.get("member_id") == member.id
    effective_stat = (
        pending.get("stat_override", choice.get("stat"))
        if applies
        else choice.get("stat")
    )
    allowed_stats = pending.get("allowed_stats") if applies else None
    bonus = (
        int(pending.get("bonus", 0))
        if applies and (not allowed_stats or effective_stat in allowed_stats)
        else 0
    )
    if choice.get("safe"):
        outcome = "safe"
        score = 0
    else:
        stat_value = int(member.snapshot["stats"].get(effective_stat, 0))
        score = (
            stat_value
            + bonus
            + _deterministic_roll(run, state.event_code, choice_code, member.id)
        )
        difficulty = max(
            0,
            int(choice["difficulty"])
            + (int(pending.get("difficulty_delta", 0)) if applies else 0),
        )
        margin = score - difficulty
        outcome = (
            "clear"
            if applies and pending.get("force_clear")
            else "flourish"
            if margin >= 3
            else "clear"
            if margin >= 0
            else "detour"
        )
        if outcome == "detour":
            resolve_loss = max(
                0,
                int(choice.get("resolve_cost", 1))
                + (int(pending.get("resolve_cost_delta", 0)) if applies else 0),
            )
            if applies and pending.get("resolve_guard"):
                resolve_loss = 0
            run.resolve = max(0, run.resolve - resolve_loss)
    effects.pop("pending_skill", None)
    run.runtime_effects_snapshot = effects
    run.phase = "exploring"
    state.status = "resolved"
    state.resolved_at = utcnow()
    state.outcome_code = outcome
    state.acting_member_id = member.id
    state.story_snapshot = {
        "title": event["title"],
        "choice": choice["label"],
        "outcome": _OUTCOME_LABELS[outcome],
        "score": score,
        "stat": effective_stat,
        "skill_code": pending.get("skill_code") if applies else None,
    }
    memory = dict(run.run_memory_snapshot)
    memory["outcomes"] = [
        *memory.get("outcomes", []),
        {
            "event_code": state.event_code,
            "member_id": member.id,
            **state.story_snapshot,
        },
    ]
    run.run_memory_snapshot = memory
    spotlights = [dict(item) for item in run.spotlight_snapshot]
    for item in spotlights:
        if item["event_code"] == state.event_code and item["member_id"] == member.id:
            item["consumed"] = True
    run.spotlight_snapshot = spotlights
    if len(memory["outcomes"]) == 1:
        thread = dict(run.run_thread_snapshot)
        thread.update({"stage": "echo", "current_text": thread["echo"]})
        run.run_thread_snapshot = thread
    if run.resolve == 0:
        await _safe_return(db, run, reason="resolve_depleted")
    return await _finish_action(
        db,
        run,
        action_type="choice",
        client_action_id=client_action_id,
        expected_revision=expected_revision,
        request_payload=request_payload,
    )


async def _reveal_nearby_nodes(
    db: AsyncSession,
    run: ExpeditionRun,
    *,
    max_distance: int,
    limit: int,
) -> list[str]:
    rows = await _node_rows(db, run.id)
    states = {row.node_code: row for row in rows}
    distances = {run.current_node_code: 0}
    queue = [run.current_node_code]
    candidates: list[str] = []
    while queue:
        current = queue.pop(0)
        distance = distances[current]
        if distance >= max_distance:
            continue
        for neighbor in sorted(_neighbors(run, current)):
            if neighbor in distances:
                continue
            distances[neighbor] = distance + 1
            queue.append(neighbor)
            state = states.get(neighbor)
            if state is not None and state.status == "hidden":
                candidates.append(neighbor)
    revealed = candidates[:limit]
    for code in revealed:
        states[code].status = "revealed"
    return revealed


async def use_skill(
    db: AsyncSession,
    user_id: int,
    run_id: int,
    *,
    member_id: int,
    skill_type: str,
    mode_code: str | None,
    expected_revision: int,
    client_action_id: str,
) -> dict:
    run = await _lock_run(db, user_id, run_id)
    request_payload = {
        "member_id": member_id,
        "skill_type": skill_type,
        "mode_code": mode_code,
        "expected_revision": expected_revision,
    }
    replay = await _existing_action(db, run, client_action_id, "skill", request_payload)
    if replay is not None:
        return replay
    _check_revision(run, expected_revision)
    member = await db.scalar(
        sa.select(ExpeditionPartyMember).where(
            ExpeditionPartyMember.id == member_id,
            ExpeditionPartyMember.run_id == run.id,
        )
    )
    if member is None or member.is_guide:
        raise AppError(422, "EXPEDITION_MEMBER_INVALID", "탐험대원을 찾을 수 없습니다.")
    definition = skill_definition(
        member.snapshot["species"]["code"],
        member.snapshot.get("form", "mosaic"),
        skill_type,
    )
    if run.phase not in definition["phases"]:
        raise AppError(
            409,
            "EXPEDITION_SKILL_TIMING",
            "이 스킬을 쓸 수 있는 장면이 아닙니다.",
        )
    modes = {item["code"] for item in definition["modes"]}
    if mode_code is None and len(modes) == 1:
        mode_code = next(iter(modes))
    if mode_code not in modes:
        raise AppError(
            422,
            "EXPEDITION_SKILL_MODE_INVALID",
            "스킬의 사용 방식을 골라 주세요.",
            {"allowed_modes": sorted(modes)},
        )
    used_field = "signature_used" if skill_type == "signature" else "form_used"
    if getattr(member, used_field):
        raise AppError(
            409, "EXPEDITION_SKILL_USED", "이번 탐험에서 이미 사용한 스킬입니다."
        )
    if (run.runtime_effects_snapshot or {}).get("pending_skill"):
        raise AppError(
            409, "EXPEDITION_SKILL_PENDING", "먼저 사용한 스킬로 선택을 마쳐 주세요."
        )
    effects = dict(run.runtime_effects_snapshot)
    pending: dict[str, Any] = {
        "member_id": member.id,
        "skill_type": skill_type,
        "skill_code": definition["code"],
    }
    species_code = member.snapshot["species"]["code"]
    form = member.snapshot.get("form", "mosaic")
    needs_choice = True

    if skill_type == "signature":
        if species_code in {"baby-pot", "tsundere-pot"}:
            pending["resolve_guard"] = True
        elif species_code == "handsome-pot":
            pending["bonus"] = 2
        elif species_code == "pretty-pot":
            current_state = await db.scalar(
                sa.select(ExpeditionNodeState).where(
                    ExpeditionNodeState.run_id == run.id,
                    ExpeditionNodeState.node_code == run.current_node_code,
                )
            )
            event = _event(run, current_state.event_code if current_state else None)
            if not set((event or {}).get("tags", [])) & {"social", "performance"}:
                raise AppError(
                    409,
                    "EXPEDITION_SKILL_CONTEXT_INVALID",
                    "관계나 발표 사건에서 쓸 수 있어요.",
                )
            pending["force_clear"] = True
        elif species_code == "zombie-pot":
            effects["next_move_free"] = member.id
            await _reveal_nearby_nodes(db, run, max_distance=2, limit=1)
            needs_choice = False
        elif species_code == "gumiho-pot":
            if mode_code == "hidden_path":
                if run.phase != "exploring":
                    raise AppError(
                        409,
                        "EXPEDITION_SKILL_CONTEXT_INVALID",
                        "지도를 살펴보는 중에 쓸 수 있어요.",
                    )
                revealed = await _reveal_nearby_nodes(db, run, max_distance=2, limit=1)
                if not revealed:
                    raise AppError(
                        409,
                        "EXPEDITION_SKILL_CONTEXT_INVALID",
                        "지금 열 수 있는 숨은 길이 없어요.",
                    )
                needs_choice = False
            else:
                current_type = _node_defs(run)[run.current_node_code]["type"]
                if run.phase != "awaiting_event" or current_type != "guardian":
                    raise AppError(
                        409,
                        "EXPEDITION_SKILL_CONTEXT_INVALID",
                        "수호자를 마주했을 때 쓸 수 있어요.",
                    )
                pending["resolve_cost_delta"] = -1
        elif species_code == "ninja-pot":
            revealed = await _reveal_nearby_nodes(db, run, max_distance=2, limit=2)
            if not revealed:
                raise AppError(
                    409,
                    "EXPEDITION_SKILL_CONTEXT_INVALID",
                    "지금 더 살펴볼 길이 없어요.",
                )
            needs_choice = False
        elif species_code == "magical-pot":
            pending["stat_override"] = mode_code
        elif species_code == "aloof-pot":
            pending["difficulty_delta"] = -2
            pending["story_hint"] = "이 선택이 남길 기록 종류를 결과 전에 확인했어요."
        elif species_code == "student-pot":
            if mode_code == "restore_form":
                if not member.form_used:
                    raise AppError(
                        409,
                        "EXPEDITION_SKILL_CONTEXT_INVALID",
                        "먼저 성장형 스킬을 사용해야 회복할 수 있어요.",
                    )
                member.form_used = False
            else:
                if run.trail_light >= 12:
                    raise AppError(
                        409,
                        "EXPEDITION_SKILL_CONTEXT_INVALID",
                        "길빛이 이미 가득 찼어요.",
                    )
                run.trail_light = min(12, run.trail_light + 2)
            needs_choice = False
        else:
            pending["bonus"] = 2
    else:
        if form == "sunny" and mode_code == "restore_resolve":
            if run.resolve >= 6:
                raise AppError(
                    409,
                    "EXPEDITION_SKILL_CONTEXT_INVALID",
                    "결의가 이미 가득 찼어요.",
                )
            run.resolve = min(6, run.resolve + 1)
            needs_choice = False
        elif form == "sunny":
            pending.update({"bonus": 3, "allowed_stats": ["care"]})
        elif form == "rainy":
            pending.update({"bonus": 3, "allowed_stats": ["focus", "insight"]})
            await _reveal_nearby_nodes(db, run, max_distance=2, limit=1)
        elif form == "ember":
            pending.update(
                {"bonus": 3, "allowed_stats": ["courage"], "resolve_guard": True}
            )
        elif form == "moonlit":
            pending.update({"bonus": 3, "allowed_stats": ["insight"]})
            await _reveal_nearby_nodes(db, run, max_distance=2, limit=2)
        elif form == "sparkling":
            pending.update({"bonus": 3, "allowed_stats": ["focus", "courage"]})
            await _reveal_nearby_nodes(db, run, max_distance=2, limit=1)
        elif form == "mosaic":
            pending.update({"stat_override": mode_code, "bonus": 1})
        else:
            pending["bonus"] = 2

    setattr(member, used_field, True)
    if needs_choice:
        effects["pending_skill"] = pending
    run.runtime_effects_snapshot = effects
    return await _finish_action(
        db,
        run,
        action_type="skill",
        client_action_id=client_action_id,
        expected_revision=expected_revision,
        request_payload=request_payload,
    )


async def _return_scene(db: AsyncSession, run: ExpeditionRun) -> dict[str, Any]:
    members = await _party_rows(db, run.id)
    outcome_counts: dict[int, int] = {}
    for outcome in run.run_memory_snapshot.get("outcomes", []):
        if isinstance(outcome, dict) and isinstance(outcome.get("member_id"), int):
            member_id = int(outcome["member_id"])
            outcome_counts[member_id] = outcome_counts.get(member_id, 0) + 1
    payload_members = []
    for member in members:
        outcome_count = outcome_counts.get(member.id, 0)
        if outcome_count:
            contribution = f"사건 {outcome_count}건을 직접 풀었어요."
        elif member.signature_used or member.form_used:
            contribution = "스킬로 탐험대의 길을 바꿔 줬어요."
        elif member.is_guide:
            contribution = "돌아오는 길까지 기록을 잘 챙겼어요."
        else:
            contribution = "탐험대 곁을 지키며 함께 돌아왔어요."
        payload_members.append(
            {
                "plant_id": member.plant_id,
                "name": member.snapshot["name"],
                "species_code": member.snapshot["species"]["code"],
                "form": member.snapshot.get("form", "mosaic"),
                "is_guide": member.is_guide,
                "contribution": contribution,
            }
        )
    names = [member["name"] for member in payload_members if not member["is_guide"]]
    return {
        "code": f"{run.region_code}.homeward.{min(len(names), 3)}",
        "title": "함께 돌아온 탐험대",
        "caption": (
            f"{', '.join(names)}이(가) 고른 길과 기록을 안고 집으로 돌아왔어요."
            if names
            else "기록 안내자가 탐험의 흔적을 안고 돌아왔어요."
        ),
        "members": payload_members,
    }


async def _safe_return(db: AsyncSession, run: ExpeditionRun, reason: str) -> None:
    run.status = "safe_returned"
    run.completed_at = utcnow()
    run.summary_snapshot = {
        "title": "안전하게 돌아왔어요",
        "reason": reason,
        "reward": None,
        "memory_count": len(run.run_memory_snapshot.get("outcomes", [])),
        "return_scene": await _return_scene(db, run),
    }
    await db.execute(
        sa.delete(UserActiveExpedition).where(UserActiveExpedition.run_id == run.id)
    )
    await db.execute(
        sa.update(ExpeditionLoot)
        .where(
            ExpeditionLoot.run_id == run.id,
            ExpeditionLoot.disposition == "candidate",
        )
        .values(disposition="recorded")
    )


async def _record_completion_progress(
    db: AsyncSession, run: ExpeditionRun
) -> dict[str, Any]:
    now = utcnow()
    event_codes = sorted(
        set(
            (
                await db.execute(
                    sa.select(ExpeditionNodeState.event_code).where(
                        ExpeditionNodeState.run_id == run.id,
                        ExpeditionNodeState.resolved_at.is_not(None),
                        ExpeditionNodeState.event_code.is_not(None),
                    )
                )
            ).scalars()
        )
    )
    progress = await db.scalar(
        sa.select(UserRegionProgress)
        .where(
            UserRegionProgress.user_id == run.user_id,
            UserRegionProgress.region_code == run.region_code,
        )
        .with_for_update()
    )
    first_clear = progress is None
    if progress is None:
        progress = UserRegionProgress(
            user_id=run.user_id,
            region_code=run.region_code,
            first_cleared_at=now,
            clear_count=1,
            templates_seen=[run.map_snapshot["code"]],
            events_seen=event_codes,
            knowledge_code=f"{run.region_code}.first_path",
            updated_at=now,
        )
        db.add(progress)
    else:
        progress.clear_count += 1
        progress.templates_seen = sorted(
            {*progress.templates_seen, run.map_snapshot["code"]}
        )
        progress.events_seen = sorted({*progress.events_seen, *event_codes})
        progress.updated_at = now

    scene_codes = sorted(
        {
            item["code"]
            for item in run.run_memory_snapshot.get("discoveries", [])
            if isinstance(item, dict) and item.get("code")
        }
    )
    bond_results: list[dict[str, Any]] = []
    for member in await _party_rows(db, run.id):
        if member.plant_id is None:
            continue
        bond = await db.scalar(
            sa.select(PlantAdventureBond)
            .where(PlantAdventureBond.plant_id == member.plant_id)
            .with_for_update()
        )
        bond_gained = bond is None or bond.last_bond_local_date != run.local_date
        if bond is None:
            bond = PlantAdventureBond(
                plant_id=member.plant_id,
                user_id=run.user_id,
                bond_points=1,
                last_bond_local_date=run.local_date,
                updated_at=now,
            )
            db.add(bond)
        elif bond_gained:
            bond.bond_points += 1
            bond.last_bond_local_date = run.local_date
            bond.updated_at = now

        familiarity = await db.scalar(
            sa.select(PlantRegionFamiliarity)
            .where(
                PlantRegionFamiliarity.plant_id == member.plant_id,
                PlantRegionFamiliarity.region_code == run.region_code,
            )
            .with_for_update()
        )
        familiarity_gained = (
            familiarity is None or familiarity.last_point_local_date != run.local_date
        )
        if familiarity is None:
            familiarity = PlantRegionFamiliarity(
                plant_id=member.plant_id,
                region_code=run.region_code,
                user_id=run.user_id,
                points=1,
                participation_count=1,
                last_point_local_date=run.local_date,
                unlocked_scene_codes=scene_codes,
                updated_at=now,
            )
            db.add(familiarity)
        else:
            familiarity.participation_count += 1
            if familiarity_gained:
                familiarity.points = min(6, familiarity.points + 1)
                familiarity.last_point_local_date = run.local_date
            familiarity.unlocked_scene_codes = sorted(
                {*familiarity.unlocked_scene_codes, *scene_codes}
            )
            familiarity.updated_at = now
        bond_results.append(
            {
                "plant_id": member.plant_id,
                "bond_gained": bond_gained,
                "bond_points": bond.bond_points,
                "familiarity_gained": familiarity_gained,
                "familiarity_points": familiarity.points,
            }
        )

    return {
        "first_clear": first_clear,
        "clear_count": progress.clear_count,
        "knowledge_code": progress.knowledge_code,
        "bonds": bond_results,
    }


async def extract(
    db: AsyncSession,
    user_id: int,
    run_id: int,
    *,
    expected_revision: int,
    client_action_id: str,
) -> dict:
    run = await _lock_run(db, user_id, run_id)
    request_payload = {"expected_revision": expected_revision}
    replay = await _existing_action(
        db, run, client_action_id, "extract", request_payload
    )
    if replay is not None:
        return replay
    _check_revision(run, expected_revision)
    if run.phase != "exploring" or not run.objective_secured:
        raise AppError(
            409,
            "EXPEDITION_OBJECTIVE_REQUIRED",
            "탐험 목표를 확보한 뒤 귀환할 수 있습니다.",
        )
    if _node_defs(run)[run.current_node_code]["type"] not in (
        "exit",
        "camp",
        "entrance",
    ):
        raise AppError(
            409, "EXPEDITION_EXIT_REQUIRED", "안전한 귀환 지점으로 이동해 주세요."
        )

    outcome = rewards.RewardOutcome()
    reward_payload = None
    if run.reward_eligible:
        user = await rewards.lock_user(db, user_id)
        # 박물관에 보관한 캐릭터도 탐험대에 편성할 수 있다. 탐험 성장 XP는
        # 편성 여부와 무관하게 오늘 일기로 자라고 있는 활성 캐릭터에 붙인다.
        lead = await rewards.lock_active_plant(db, user_id)
        await rewards.grant(
            db,
            user,
            lead,
            RewardEventType.EXPEDITION_COMPLETED,
            f"active_expedition_daily:{user_id}:{run.local_date.isoformat()}",
            "expedition_run",
            run.id,
            run.local_date,
            outcome,
            reward_amounts=(
                int(run.map_snapshot["region"]["reward"]["exp"]),
                int(run.map_snapshot["region"]["reward"]["seeds"]),
            ),
        )
        reward_payload = outcome.payload()

    loots = list(
        (
            await db.execute(
                sa.select(ExpeditionLoot).where(ExpeditionLoot.run_id == run.id)
            )
        ).scalars()
    )
    if run.reward_eligible:
        for loot in loots:
            existing = await db.scalar(
                sa.select(UserAdventureItem)
                .where(
                    UserAdventureItem.user_id == user_id,
                    UserAdventureItem.item_code == loot.item_code,
                )
                .with_for_update()
            )
            if existing:
                existing.quantity += loot.quantity
            else:
                db.add(
                    UserAdventureItem(
                        user_id=user_id,
                        item_code=loot.item_code,
                        quantity=loot.quantity,
                    )
                )
            loot.disposition = "granted"
            loot.granted_at = utcnow()
    completion_progress = await _record_completion_progress(db, run)
    run.status = "completed"
    run.completed_at = utcnow()
    run.summary_snapshot = {
        "title": "마음의 기록을 안고 돌아왔어요",
        "reward": reward_payload,
        "memory_count": len(run.run_memory_snapshot.get("outcomes", [])),
        "objective_secured": True,
        "progress": completion_progress,
        "return_scene": await _return_scene(db, run),
    }
    await db.execute(
        sa.delete(UserActiveExpedition).where(UserActiveExpedition.run_id == run.id)
    )
    return await _finish_action(
        db,
        run,
        action_type="extract",
        client_action_id=client_action_id,
        expected_revision=expected_revision,
        request_payload=request_payload,
    )


async def retreat(
    db: AsyncSession,
    user_id: int,
    run_id: int,
    *,
    expected_revision: int,
    client_action_id: str,
) -> dict:
    run = await _lock_run(db, user_id, run_id)
    request_payload = {"expected_revision": expected_revision}
    replay = await _existing_action(
        db, run, client_action_id, "retreat", request_payload
    )
    if replay is not None:
        return replay
    _check_revision(run, expected_revision)
    run.status = "retreated"
    run.completed_at = utcnow()
    run.summary_snapshot = {
        "title": "무리하지 않고 돌아왔어요",
        "reward": None,
        "memory_count": len(run.run_memory_snapshot.get("outcomes", [])),
        "return_scene": await _return_scene(db, run),
    }
    await db.execute(
        sa.delete(UserActiveExpedition).where(UserActiveExpedition.run_id == run.id)
    )
    await db.execute(
        sa.update(ExpeditionLoot)
        .where(
            ExpeditionLoot.run_id == run.id, ExpeditionLoot.disposition == "candidate"
        )
        .values(disposition="recorded")
    )
    return await _finish_action(
        db,
        run,
        action_type="retreat",
        client_action_id=client_action_id,
        expected_revision=expected_revision,
        request_payload=request_payload,
    )
