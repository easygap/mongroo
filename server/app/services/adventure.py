from datetime import timedelta

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.errors import AppError
from app.core.timeutil import local_date_of, to_utc_iso, utcnow
from app.models.adventure import (
    AdventurePatrol,
    DungeonRun,
    UserAdventureItem,
    UserDungeon,
)
from app.models.enums import PlantStatus, RewardEventType
from app.models.game import FarmLayout, Item, UserItem
from app.models.mood import MoodEntry
from app.models.plant import Plant, PlantSpecies
from app.services import game as game_service
from app.services.plants import growth_state_payload, stage_from_exp
from app.services.rewards import RewardOutcome, grant, lock_active_plant, lock_user


ROUTES = {
    "greenhouse_edge": {
        "name": "온실 가장자리",
        "description": "온실 바깥의 이끼 낀 표지와 오래된 문을 살펴봐요.",
        "duration_minutes": 10,
        "required_stage": 2,
        "stats": ("care", "insight"),
        "discovery_code": "moss_archive",
        "item_code": "pressed_leaf_map",
    },
    "moonlit_lane": {
        "name": "달빛 샛길",
        "description": "조용한 밤길의 작은 메아리를 따라가 봐요.",
        "duration_minutes": 20,
        "required_stage": 3,
        "stats": ("focus", "courage"),
        "discovery_code": "echo_well",
        "item_code": "moon_dew",
    },
}

DUNGEONS = {
    "moss_archive": {
        "name": "이끼 낀 기억서고",
        "description": "눅눅한 표본 서랍을 정리하며 잊힌 씨앗 기록을 찾아요.",
        "required_stage": 2,
        "stats": ("focus", "insight"),
        "item_code": "moss_key",
        "asset_path": "assets/adventure/dungeon-moss-archive.webp",
    },
    "echo_well": {
        "name": "메아리 우물정원",
        "description": "되돌아오는 소리를 구분해 잠든 화단의 길을 열어요.",
        "required_stage": 3,
        "stats": ("care", "courage"),
        "item_code": "echo_seed",
        "asset_path": "assets/adventure/dungeon-echo-well.webp",
    },
}

ITEMS = {
    "pressed_leaf_map": ("눌러 말린 잎 지도", "다음 길을 찾을 때 쓰는 얇은 지도 조각"),
    "moon_dew": ("달빛 이슬", "밤의 식물에서만 맺히는 맑은 이슬"),
    "moss_key": ("이끼 열쇠", "기억서고의 잠긴 표본함을 여는 작은 열쇠"),
    "echo_seed": ("메아리 씨앗", "흔들면 아주 작은 울림이 돌아오는 씨앗"),
}

STAT_LABELS = {
    "care": "돌봄",
    "focus": "집중",
    "courage": "용기",
    "insight": "관찰",
}

# 감정별 방향은 다르지만 추가 합계는 항상 4다. 특정 감정을 쓰는 것이
# 탐험 성장에 유리해지지 않도록 이 불변식을 테스트로 고정한다.
FORM_STAT_MODIFIERS = {
    "sunny": {"care": 2, "focus": 1, "courage": 1, "insight": 0},
    "rainy": {"care": 0, "focus": 2, "courage": 0, "insight": 2},
    "ember": {"care": 0, "focus": 1, "courage": 2, "insight": 1},
    "moonlit": {"care": 1, "focus": 1, "courage": 0, "insight": 2},
    "sparkling": {"care": 0, "focus": 1, "courage": 1, "insight": 2},
    "mosaic": {"care": 1, "focus": 1, "courage": 1, "insight": 1},
}


def character_stats(stage: int, form: str | None) -> dict[str, int]:
    base = 3 + stage
    modifiers = FORM_STAT_MODIFIERS.get(form or "mosaic", FORM_STAT_MODIFIERS["mosaic"])
    return {stat: base + modifiers[stat] for stat in STAT_LABELS}


async def _diary_ready(db: AsyncSession, user_id: int, today) -> bool:
    contents = list(
        (
            await db.execute(
                sa.select(MoodEntry.content).where(
                    MoodEntry.user_id == user_id,
                    MoodEntry.local_date == today,
                    MoodEntry.content.is_not(None),
                )
            )
        ).scalars()
    )
    return any(len((content or "").strip()) >= 50 for content in contents)


async def _active_character(db: AsyncSession, user_id: int):
    row = (
        await db.execute(
            sa.select(Plant, PlantSpecies)
            .join(PlantSpecies, PlantSpecies.id == Plant.species_id)
            .where(Plant.user_id == user_id, Plant.status == PlantStatus.ACTIVE)
        )
    ).first()
    if row is None:
        return None
    plant, species = row
    growth = growth_state_payload(plant)
    cue = growth.get("growth_cue")
    cue_form = cue.get("form") if isinstance(cue, dict) else None
    form = growth.get("growth_form") or cue_form or "mosaic"
    stage = stage_from_exp(plant.exp)
    outfit = await _equipped_outfit(db, user_id)
    return {
        "plant": plant,
        "species": species,
        "stage": stage,
        "form": form,
        "growth": growth,
        "stats": character_stats(stage, form),
        "outfit": outfit,
    }


async def _equipped_outfit(db: AsyncSession, user_id: int) -> dict | None:
    layout_row = await db.get(FarmLayout, user_id)
    wardrobe_id = (
        (layout_row.layout or {}).get("wardrobe_user_item_id") if layout_row else None
    )
    if wardrobe_id is None:
        return None
    row = (
        await db.execute(
            sa.select(Item)
            .join(UserItem, UserItem.item_id == Item.id)
            .where(
                UserItem.id == wardrobe_id,
                UserItem.user_id == user_id,
                Item.type == "wardrobe",
            )
        )
    ).scalar_one_or_none()
    if row is None:
        return None
    manifest = row.asset_manifest if isinstance(row.asset_manifest, dict) else {}
    raw_bonus = manifest.get("adventure_bonus")
    bonus = raw_bonus if isinstance(raw_bonus, dict) else {}
    return {
        "name": row.name,
        "layer_key": manifest.get("wardrobe_layer_key"),
        "bonus": {
            "context": bonus.get("context"),
            "stat": bonus.get("stat"),
            "amount": int(bonus.get("amount") or 0),
            "label": bonus.get("label"),
        },
    }


def _performance(
    character: dict, stats: tuple[str, str], context: str
) -> tuple[int, int]:
    score = sum(character["stats"][stat] for stat in stats)
    outfit = character.get("outfit") or {}
    bonus = outfit.get("bonus") or {}
    if bonus.get("context") == context and bonus.get("stat") in stats:
        score += int(bonus.get("amount") or 0)
    # 성장과 의상은 수집량에만 반영한다. 핵심 XP/씨앗은 고정해 일기보다
    # 효율이 커지는 조합을 만들지 않는다.
    quantity = 2 if score >= 17 else 1
    return score, quantity


def _character_payload(character: dict | None) -> dict | None:
    if character is None:
        return None
    plant = character["plant"]
    species = character["species"]
    return {
        "plant_id": plant.id,
        "name": plant.name,
        "stage": character["stage"],
        "form": character["form"],
        "species_code": species.code,
        "species_name": species.name,
        "stats": [
            {"code": code, "label": STAT_LABELS[code], "value": value}
            for code, value in character["stats"].items()
        ],
        "outfit": character["outfit"],
    }


def _route_payload(code: str, route: dict, stage: int) -> dict:
    return {
        "code": code,
        "name": route["name"],
        "description": route["description"],
        "duration_minutes": route["duration_minutes"],
        "required_stage": route["required_stage"],
        "available": stage >= route["required_stage"],
        "recommended_stats": [STAT_LABELS[stat] for stat in route["stats"]],
        "reward": {"exp": 0, "seeds": 3, "item_code": route["item_code"]},
    }


def _patrol_payload(patrol: AdventurePatrol, now=None) -> dict:
    now = now or utcnow()
    route = ROUTES[patrol.route_code]
    return {
        "id": patrol.id,
        "route_code": patrol.route_code,
        "route_name": route["name"],
        "status": patrol.status,
        "started_at": to_utc_iso(patrol.started_at),
        "returns_at": to_utc_iso(patrol.returns_at),
        "ready_to_claim": patrol.status == "active" and patrol.returns_at <= now,
        "performance_score": patrol.performance_score,
        "found_item_code": patrol.found_item_code,
        "found_quantity": patrol.found_quantity,
    }


async def state_payload(db: AsyncSession, user_id: int) -> dict:
    now = utcnow()
    today = local_date_of(now)
    suspended = await game_service.safety_active_today(db, user_id, today)
    diary_ready = await _diary_ready(db, user_id, today)
    character = await _active_character(db, user_id)
    stage = character["stage"] if character else 0
    patrol = await db.scalar(
        sa.select(AdventurePatrol).where(
            AdventurePatrol.user_id == user_id,
            AdventurePatrol.local_date == today,
        )
    )
    discovered = {
        row.dungeon_code: row
        for row in (
            await db.execute(
                sa.select(UserDungeon).where(UserDungeon.user_id == user_id)
            )
        ).scalars()
    }
    ran_today = (
        await db.scalar(
            sa.select(DungeonRun.id).where(
                DungeonRun.user_id == user_id, DungeonRun.local_date == today
            )
        )
        is not None
    )
    inventory_rows = list(
        (
            await db.execute(
                sa.select(UserAdventureItem)
                .where(
                    UserAdventureItem.user_id == user_id, UserAdventureItem.quantity > 0
                )
                .order_by(UserAdventureItem.updated_at.desc())
            )
        ).scalars()
    )
    return {
        "date": today.isoformat(),
        "suspended": suspended,
        "diary_ready": diary_ready,
        "diary_requirement": {
            "minimum_characters": 50,
            "reward_exp": 40,
            "reward_seeds": 15,
            "message": "오늘 마음을 50자 이상 기록하면 탐험이 열려요.",
        },
        "economy": [
            {"code": "diary", "label": "마음 일기", "exp": 40, "seeds": 15},
            {"code": "quest", "label": "일일 미션", "exp": 20, "seeds": 5},
            {"code": "dungeon", "label": "던전", "exp": 10, "seeds": 4},
            {"code": "patrol", "label": "순찰", "exp": 0, "seeds": 3},
        ],
        "character": _character_payload(character),
        "routes": [
            _route_payload(code, route, stage) for code, route in ROUTES.items()
        ],
        "patrol": _patrol_payload(patrol, now) if patrol else None,
        "dungeon_run_available": not ran_today,
        "dungeons": [
            {
                "code": code,
                "name": dungeon["name"],
                "description": dungeon["description"],
                "required_stage": dungeon["required_stage"],
                "discovered": code in discovered,
                "available": code in discovered
                and stage >= dungeon["required_stage"]
                and not ran_today,
                "clear_count": discovered[code].clear_count
                if code in discovered
                else 0,
                "recommended_stats": [STAT_LABELS[stat] for stat in dungeon["stats"]],
                "asset_path": dungeon["asset_path"],
                "reward": {"exp": 10, "seeds": 4, "item_code": dungeon["item_code"]},
            }
            for code, dungeon in DUNGEONS.items()
        ],
        "inventory": [
            {
                "code": row.item_code,
                "name": ITEMS.get(row.item_code, (row.item_code, ""))[0],
                "description": ITEMS.get(row.item_code, (row.item_code, ""))[1],
                "quantity": row.quantity,
            }
            for row in inventory_rows
        ],
    }


async def _require_available_day(db: AsyncSession, user_id: int, today) -> None:
    if await game_service.safety_active_today(db, user_id, today):
        raise AppError(
            409,
            "ADVENTURE_SUSPENDED",
            "오늘은 탐험보다 마음 돌봄을 먼저 확인해 주세요.",
        )
    if not await _diary_ready(db, user_id, today):
        raise AppError(
            409,
            "DIARY_REQUIRED",
            "오늘 마음 일기를 50자 이상 쓰면 탐험을 시작할 수 있어요.",
        )


async def start_patrol(db: AsyncSession, user_id: int, route_code: str) -> dict:
    now = utcnow()
    today = local_date_of(now)
    await _require_available_day(db, user_id, today)
    route = ROUTES.get(route_code)
    if route is None:
        raise AppError(404, "PATROL_ROUTE_NOT_FOUND", "순찰 경로를 찾을 수 없습니다.")
    character = await _active_character(db, user_id)
    if character is None:
        raise AppError(
            409, "ACTIVE_PLANT_REQUIRED", "순찰을 맡길 활성 캐릭터가 필요해요."
        )
    if character["stage"] < route["required_stage"]:
        raise AppError(
            409,
            "PATROL_STAGE_REQUIRED",
            f"{route['required_stage']}단계부터 갈 수 있는 경로예요.",
        )
    exists = await db.scalar(
        sa.select(AdventurePatrol.id).where(
            AdventurePatrol.user_id == user_id, AdventurePatrol.local_date == today
        )
    )
    if exists is not None:
        raise AppError(409, "PATROL_ALREADY_STARTED", "오늘 순찰은 이미 보냈어요.")
    score, quantity = _performance(character, route["stats"], "patrol")
    patrol = AdventurePatrol(
        user_id=user_id,
        plant_id=character["plant"].id,
        route_code=route_code,
        local_date=today,
        status="active",
        started_at=now,
        returns_at=now + timedelta(minutes=route["duration_minutes"]),
        reward_exp=0,
        reward_seeds=3,
        discovery_code=route["discovery_code"],
        found_item_code=route["item_code"],
        found_quantity=quantity,
        performance_score=score,
    )
    db.add(patrol)
    await db.flush()
    return {
        "patrol": _patrol_payload(patrol),
        "state": await state_payload(db, user_id),
    }


async def _add_inventory(
    db: AsyncSession, user_id: int, item_code: str, quantity: int
) -> None:
    row = await db.scalar(
        sa.select(UserAdventureItem)
        .where(
            UserAdventureItem.user_id == user_id,
            UserAdventureItem.item_code == item_code,
        )
        .with_for_update()
    )
    if row is None:
        db.add(
            UserAdventureItem(user_id=user_id, item_code=item_code, quantity=quantity)
        )
    else:
        row.quantity += quantity
        row.updated_at = utcnow()


async def claim_patrol(db: AsyncSession, user_id: int, patrol_id: int) -> dict:
    now = utcnow()
    today = local_date_of(now)
    await _require_available_day(db, user_id, today)
    user = await lock_user(db, user_id)
    patrol = await db.scalar(
        sa.select(AdventurePatrol)
        .where(AdventurePatrol.id == patrol_id)
        .with_for_update()
    )
    if patrol is None:
        raise AppError(404, "PATROL_NOT_FOUND", "순찰 기록을 찾을 수 없습니다.")
    if patrol.user_id != user_id:
        raise AppError(403, "FORBIDDEN", "접근 권한이 없습니다.")
    if patrol.status != "active":
        raise AppError(409, "PATROL_ALREADY_CLAIMED", "이미 돌아온 순찰이에요.")
    if patrol.returns_at > now:
        raise AppError(
            409,
            "PATROL_NOT_READY",
            "아직 순찰 중이에요.",
            {"returns_at": to_utc_iso(patrol.returns_at)},
        )
    plant = await lock_active_plant(db, user_id)
    outcome = RewardOutcome(seed_balance=user.seed_balance)
    await grant(
        db,
        user,
        plant,
        RewardEventType.PATROL_CLAIMED,
        f"patrol_claim:{patrol.id}",
        "adventure_patrol",
        patrol.id,
        today,
        outcome,
        reward_amounts=(patrol.reward_exp, patrol.reward_seeds),
    )
    await _add_inventory(db, user_id, patrol.found_item_code, patrol.found_quantity)
    discovery_new = False
    if patrol.discovery_code:
        dungeon = await db.scalar(
            sa.select(UserDungeon).where(
                UserDungeon.user_id == user_id,
                UserDungeon.dungeon_code == patrol.discovery_code,
            )
        )
        if dungeon is None:
            db.add(
                UserDungeon(
                    user_id=user_id,
                    dungeon_code=patrol.discovery_code,
                    discovered_at=now,
                )
            )
            discovery_new = True
    patrol.status = "claimed"
    patrol.claimed_at = now
    await db.flush()
    return {
        "patrol": _patrol_payload(patrol, now),
        "reward": outcome.payload(),
        "discovery": {"code": patrol.discovery_code, "is_new": discovery_new},
        "state": await state_payload(db, user_id),
    }


async def run_dungeon(db: AsyncSession, user_id: int, dungeon_code: str) -> dict:
    now = utcnow()
    today = local_date_of(now)
    await _require_available_day(db, user_id, today)
    dungeon = DUNGEONS.get(dungeon_code)
    if dungeon is None:
        raise AppError(404, "DUNGEON_NOT_FOUND", "던전을 찾을 수 없습니다.")
    user = await lock_user(db, user_id)
    unlocked = await db.scalar(
        sa.select(UserDungeon)
        .where(UserDungeon.user_id == user_id, UserDungeon.dungeon_code == dungeon_code)
        .with_for_update()
    )
    if unlocked is None:
        raise AppError(
            409, "DUNGEON_NOT_DISCOVERED", "순찰에서 먼저 이 장소를 발견해야 해요."
        )
    if (
        await db.scalar(
            sa.select(DungeonRun.id).where(
                DungeonRun.user_id == user_id, DungeonRun.local_date == today
            )
        )
        is not None
    ):
        raise AppError(
            409, "DUNGEON_DAILY_LIMIT", "던전 탐험은 하루에 한 번만 할 수 있어요."
        )
    character = await _active_character(db, user_id)
    if character is None:
        raise AppError(
            409, "ACTIVE_PLANT_REQUIRED", "던전에 들어갈 활성 캐릭터가 필요해요."
        )
    if character["stage"] < dungeon["required_stage"]:
        raise AppError(
            409,
            "DUNGEON_STAGE_REQUIRED",
            f"{dungeon['required_stage']}단계부터 들어갈 수 있어요.",
        )
    score, quantity = _performance(character, dungeon["stats"], "dungeon")
    run = DungeonRun(
        user_id=user_id,
        plant_id=character["plant"].id,
        user_dungeon_id=unlocked.id,
        local_date=today,
        reward_exp=10,
        reward_seeds=4,
        found_item_code=dungeon["item_code"],
        found_quantity=quantity,
        performance_score=score,
    )
    db.add(run)
    await db.flush()
    outcome = RewardOutcome(seed_balance=user.seed_balance)
    await grant(
        db,
        user,
        character["plant"],
        RewardEventType.DUNGEON_CLEARED,
        f"dungeon_run:{run.id}",
        "dungeon_run",
        run.id,
        today,
        outcome,
        reward_amounts=(run.reward_exp, run.reward_seeds),
    )
    await _add_inventory(db, user_id, run.found_item_code, run.found_quantity)
    unlocked.clear_count += 1
    unlocked.last_cleared_at = now
    await db.flush()
    return {
        "run": {
            "id": run.id,
            "dungeon_code": dungeon_code,
            "dungeon_name": dungeon["name"],
            "performance_score": score,
            "found_item_code": run.found_item_code,
            "found_quantity": run.found_quantity,
        },
        "reward": outcome.payload(),
        "state": await state_payload(db, user_id),
    }
