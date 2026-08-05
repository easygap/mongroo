import asyncio
import threading
import weakref
from dataclasses import dataclass
from datetime import date, timedelta

import sqlalchemy as sa
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.errors import AppError
from app.core.timeutil import local_date_of, local_day_bounds_utc, to_utc_iso, utcnow
from app.models.enums import AnalysisStatus, PlantStatus, RewardEventType
from app.models.game import (
    FarmLayout,
    Item,
    Quest,
    UserItem,
    UserQuest,
    UserSpeciesUnlock,
)
from app.models.mood import MoodEntry
from app.models.plant import Plant, PlantSpecies
from app.models.reward import RewardEvent
from app.models.safety import SafetyEvent
from app.models.user import User
from app.services.quest_rotation import QuestHistory, choose_daily_quest
from app.services.rewards import RewardOutcome, grant, lock_active_plant, lock_user


_inventory_locks_guard = threading.Lock()
_inventory_locks: weakref.WeakValueDictionary[int, asyncio.Lock] = (
    weakref.WeakValueDictionary()
)
_ACQUISITION_TYPES = frozenset(
    {
        "purchase",
        "quest_count",
        "streak",
        "record_count",
        "own_item",
        "collection_count",
        "harvest_form",
    }
)
_HARVEST_FORMS = frozenset(
    {"sunny", "rainy", "ember", "moonlit", "sparkling", "mosaic"}
)

_EMOTION_QUEST_CATEGORIES = {
    "기쁨": ("creativity", "expression", "connection", "senses"),
    "평온": ("rest", "senses", "reflection"),
    "슬픔": ("self_kindness", "rest", "reflection"),
    "상처": ("self_kindness", "rest", "reflection"),
    "분노": ("movement", "body", "space", "environment"),
    "불안": ("grounding", "senses", "planning"),
    "당황": ("grounding", "reflection", "planning"),
    "놀람": ("grounding", "creativity", "reflection"),
    "혼합": ("reflection", "senses", "self_kindness"),
    "joy": ("creativity", "expression", "connection", "senses"),
    "sadness": ("self_kindness", "rest", "reflection"),
    "anger": ("movement", "body", "space", "environment"),
    "anxiety": ("grounding", "senses", "planning"),
    "surprise": ("grounding", "creativity", "reflection"),
    "mixed": ("reflection", "senses", "self_kindness"),
}


async def _today_quest_context(
    db: AsyncSession,
    user_id: int,
    today: date,
) -> tuple[str, str | None, tuple[str, ...]]:
    latest = await db.scalar(
        sa.select(MoodEntry)
        .where(
            MoodEntry.user_id == user_id,
            MoodEntry.local_date == today,
            MoodEntry.content_length > 0,
        )
        .order_by(MoodEntry.recorded_at_utc.desc(), MoodEntry.id.desc())
        .limit(1)
    )
    if latest is None:
        return "record_optional", None, ()
    if latest.analysis_status in (AnalysisStatus.PENDING, AnalysisStatus.RUNNING):
        return "analyzing", None, ()
    emotion = (
        latest.ai_emotion
        if latest.analysis_status == AnalysisStatus.SUCCEEDED
        else None
    )
    categories = _EMOTION_QUEST_CATEGORIES.get(emotion or "", ())
    if emotion and categories:
        return "diary_matched", emotion, categories
    return "neutral", None, ()


def inventory_lock(user_id: int) -> asyncio.Lock:
    """SQLite/local concurrency mirrors the production user-row inventory lock."""
    with _inventory_locks_guard:
        lock = _inventory_locks.get(user_id)
        if lock is None:
            lock = asyncio.Lock()
            _inventory_locks[user_id] = lock
        return lock


async def lock_inventory_user(db: AsyncSession, user_id: int) -> User:
    """Acquire the DB user lock before idempotency rows take a user FK lock."""
    return await lock_user(db, user_id)


@dataclass(frozen=True)
class AcquisitionContext:
    seed_balance: int
    completed_quest_count: int
    streak_days: int
    recorded_day_count: int
    owned_item_codes: frozenset[str]
    catalog_item_codes: frozenset[str]
    harvested_form_counts: dict[str, int]


def _catalog_error() -> AppError:
    return AppError(503, "SHOP_CATALOG_INVALID", "상점 획득 조건을 확인할 수 없습니다.")


def _acquisition_rule(item: Item) -> dict:
    if not isinstance(item.asset_manifest, dict):
        raise _catalog_error()
    manifest = item.asset_manifest
    raw = manifest.get("acquisition")
    if raw is None:
        # 0006 이전 카탈로그는 모두 기존 씨앗 구매 규칙을 유지한다.
        return {
            "type": "purchase",
            "label": f"씨앗 {item.price_seeds}개로 구매",
        }
    if not isinstance(raw, dict):
        raise _catalog_error()

    acquisition_type = raw.get("type")
    label = raw.get("label")
    if (
        acquisition_type not in _ACQUISITION_TYPES
        or not isinstance(label, str)
        or not label.strip()
    ):
        raise _catalog_error()

    rule = {"type": acquisition_type, "label": label.strip()}
    if acquisition_type in {
        "quest_count",
        "streak",
        "record_count",
        "collection_count",
        "harvest_form",
    }:
        target = raw.get("target")
        if type(target) is not int or target <= 0:
            raise _catalog_error()
        rule["target"] = target
    if acquisition_type == "harvest_form":
        form = raw.get("form")
        if not isinstance(form, str) or form not in _HARVEST_FORMS:
            raise _catalog_error()
        rule["form"] = form
    elif acquisition_type == "own_item":
        item_code = raw.get("item_code")
        if not isinstance(item_code, str) or not item_code.strip():
            raise _catalog_error()
        rule["item_code"] = item_code.strip()
    return rule


async def _acquisition_context(
    db: AsyncSession,
    user: User,
    *,
    for_update: bool = False,
) -> AcquisitionContext:
    owned_query = (
        sa.select(UserItem.item_id, Item.code)
        .join(Item, Item.id == UserItem.item_id)
        .where(UserItem.user_id == user.id)
    )
    if for_update:
        owned_query = owned_query.with_for_update()
    owned_rows = (await db.execute(owned_query)).all()
    owned_codes = {code for _item_id, code in owned_rows}

    # 비활성화된 아이템도 과거에 정상 획득했다면 collection_count와
    # own_item 진행도가 줄어들지 않도록 전체 카탈로그를 기준으로 한다.
    catalog = list((await db.execute(sa.select(Item))).scalars())
    catalog_codes = {item.code for item in catalog}

    # 품종 상점에서 직접 해금한 경우 UserItem이 없어도 도감은
    # species_unlock 아이템을 보유로 표시하므로 획득 조건도 같은 논리 집합을 쓴다.
    unlock_query = sa.select(UserSpeciesUnlock.species_id).where(
        UserSpeciesUnlock.user_id == user.id
    )
    if for_update:
        unlock_query = unlock_query.with_for_update()
    unlocked_species_ids = set((await db.execute(unlock_query)).scalars())
    species_rows = (
        await db.execute(
            sa.select(PlantSpecies.id, PlantSpecies.code, PlantSpecies.unlock_price)
        )
    ).all()
    unlocked_species_codes = {
        code
        for species_id, code, unlock_price in species_rows
        if unlock_price == 0 or species_id in unlocked_species_ids
    }
    for item in catalog:
        manifest = item.asset_manifest if isinstance(item.asset_manifest, dict) else {}
        if (
            item.type == "species_unlock"
            and manifest.get("species_code") in unlocked_species_codes
        ):
            owned_codes.add(item.code)

    completed_query = sa.select(UserQuest.id).where(
        UserQuest.user_id == user.id,
        UserQuest.status == "completed",
    )
    if for_update:
        completed_query = completed_query.with_for_update()
    completed_quest_count = len(list((await db.execute(completed_query)).scalars()))
    recorded_day_count = (
        await db.scalar(
            sa.select(sa.func.count(sa.distinct(MoodEntry.local_date))).where(
                MoodEntry.user_id == user.id
            )
        )
        or 0
    )
    harvested_query = sa.select(Plant.id, Plant.final_form).where(
        Plant.user_id == user.id,
        Plant.status == PlantStatus.HARVESTED,
        Plant.final_form.is_not(None),
    )
    if for_update:
        harvested_query = harvested_query.with_for_update()
    harvested_form_counts: dict[str, int] = {}
    for _plant_id, final_form in (await db.execute(harvested_query)).all():
        if final_form not in _HARVEST_FORMS:
            continue
        harvested_form_counts[final_form] = harvested_form_counts.get(final_form, 0) + 1
    return AcquisitionContext(
        seed_balance=user.seed_balance,
        completed_quest_count=completed_quest_count,
        streak_days=user.streak_days,
        recorded_day_count=recorded_day_count,
        owned_item_codes=frozenset(owned_codes),
        catalog_item_codes=frozenset(catalog_codes),
        harvested_form_counts=harvested_form_counts,
    )


def acquisition_payload(item: Item, context: AcquisitionContext) -> dict:
    rule = _acquisition_rule(item)
    acquisition_type = rule["type"]
    owned = item.code in context.owned_item_codes

    if acquisition_type == "purchase":
        current = context.seed_balance
        target = item.price_seeds
    elif acquisition_type == "quest_count":
        current = context.completed_quest_count
        target = rule["target"]
    elif acquisition_type == "streak":
        current = context.streak_days
        target = rule["target"]
    elif acquisition_type == "record_count":
        current = context.recorded_day_count
        target = rule["target"]
    elif acquisition_type == "collection_count":
        current = len(context.owned_item_codes)
        target = rule["target"]
    elif acquisition_type == "harvest_form":
        current = context.harvested_form_counts.get(rule["form"], 0)
        target = rule["target"]
    else:
        required_code = rule["item_code"]
        if required_code not in context.catalog_item_codes:
            raise _catalog_error()
        current = int(required_code in context.owned_item_codes)
        target = 1

    return {
        "type": acquisition_type,
        "label": rule["label"],
        "current": current,
        "target": target,
        "eligible": not owned and current >= target,
    }


async def _journey_progress_payload(
    db: AsyncSession,
    user_id: int,
    today: date,
) -> dict:
    """오늘 행동이 성장과 수집으로 이어지는 진행 요약."""

    user = await db.get(User, user_id)
    if user is None:  # 인증 단계에서 걸러지지만 단독 호출도 안전하게 처리한다.
        raise AppError(404, "USER_NOT_FOUND", "사용자를 찾을 수 없습니다.")

    context = await _acquisition_context(db, user)
    week_start = today - timedelta(days=today.weekday())
    weekly_recorded_days = int(
        await db.scalar(
            sa.select(sa.func.count(sa.distinct(MoodEntry.local_date))).where(
                MoodEntry.user_id == user_id,
                MoodEntry.local_date >= week_start,
                MoodEntry.local_date <= today,
            )
        )
        or 0
    )
    weekly_completed_quests = int(
        await db.scalar(
            sa.select(sa.func.count(UserQuest.id)).where(
                UserQuest.user_id == user_id,
                UserQuest.status == "completed",
                UserQuest.quest_date >= week_start,
                UserQuest.quest_date <= today,
            )
        )
        or 0
    )

    items = list(
        (
            await db.execute(
                sa.select(Item).where(Item.is_active.is_(True)).order_by(Item.id)
            )
        ).scalars()
    )
    candidates: list[tuple[tuple, Item, dict]] = []
    for item in items:
        if item.code in context.owned_item_codes:
            continue
        acquisition = acquisition_payload(item, context)
        current = int(acquisition["current"])
        target = max(int(acquisition["target"]), 1)
        progress = min(current / target, 1.0)
        acquisition_type = acquisition["type"]
        # 받을 수 있는 보상과 직접 진행 목표를 파생 조건·구매보다 먼저 보여 준다.
        goal_kind_rank = 2 if acquisition_type == "purchase" else 0
        if acquisition_type == "own_item":
            goal_kind_rank = 1
        rank = (
            0 if acquisition["eligible"] else 1,
            goal_kind_rank,
            max(target - current, 0),
            -progress,
            item.rarity,
            item.id,
        )
        candidates.append((rank, item, acquisition))

    next_unlock = None
    if candidates:
        _, item, acquisition = min(candidates, key=lambda entry: entry[0])
        next_unlock = {
            "item_id": item.id,
            "code": item.code,
            "name": item.name,
            "item_type": item.type,
            "acquisition_type": acquisition["type"],
            "label": acquisition["label"],
            "current": acquisition["current"],
            "target": acquisition["target"],
            "eligible": acquisition["eligible"],
        }

    return {
        "recorded_day_count": context.recorded_day_count,
        "completed_quest_count": context.completed_quest_count,
        "weekly_recorded_days": weekly_recorded_days,
        "weekly_completed_quests": weekly_completed_quests,
        "next_unlock": next_unlock,
    }


def quest_payload(user_quest: UserQuest, quest: Quest) -> dict:
    return {
        "id": user_quest.id,
        "quest_date": user_quest.quest_date.isoformat(),
        "status": user_quest.status,
        "completed_at": to_utc_iso(user_quest.completed_at),
        "quest": {
            "id": quest.id,
            "code": quest.code,
            "title": quest.title,
            "description": quest.description,
            "category": quest.category,
            "burden_level": quest.burden_level,
            "estimated_minutes": quest.estimated_minutes,
            "reward_exp": quest.reward_exp,
            "reward_seeds": quest.reward_seeds,
        },
    }


def item_payload(item: Item, *, owned: bool | None = None) -> dict:
    payload = {
        "id": item.id,
        "code": item.code,
        "type": item.type,
        "name": item.name,
        "description": item.description,
        "price_seeds": item.price_seeds,
        "rarity": item.rarity,
        "asset_manifest": item.asset_manifest,
    }
    if owned is not None:
        payload["owned"] = owned
    return payload


def user_item_payload(user_item: UserItem, item: Item) -> dict:
    return {
        "id": user_item.id,
        "item": item_payload(item),
        "acquired_at": to_utc_iso(user_item.acquired_at),
    }


async def safety_active_today(db: AsyncSession, user_id: int, today: date) -> bool:
    start, end = local_day_bounds_utc(today)
    event_id = await db.scalar(
        sa.select(SafetyEvent.id)
        .where(
            SafetyEvent.user_id == user_id,
            SafetyEvent.created_at >= start,
            SafetyEvent.created_at < end,
            SafetyEvent.severity.in_(("concern", "imminent")),
        )
        .limit(1)
    )
    return event_id is not None


async def get_or_assign_today(db: AsyncSession, user_id: int) -> dict:
    today = local_date_of(utcnow())
    if await safety_active_today(db, user_id, today):
        return {
            "date": today.isoformat(),
            "suspended": True,
            "suspension_reason": "safety_support_active",
            "items": [],
        }

    context_status, context_emotion, preferred_categories = await _today_quest_context(
        db, user_id, today
    )

    # 같은 사용자의 첫 동시 GET을 직렬화해 하루 배정을 정확히 하나만 만든다.
    await lock_user(db, user_id)
    row = (
        await db.execute(
            sa.select(UserQuest, Quest)
            .join(Quest, Quest.id == UserQuest.quest_id)
            .where(UserQuest.user_id == user_id, UserQuest.quest_date == today)
            .order_by(UserQuest.id)
        )
    ).first()
    should_select = row is None
    if row is not None:
        user_quest, quest = row
        should_select = (
            user_quest.status == "assigned"
            and bool(preferred_categories)
            and quest.category not in preferred_categories
        )

    if should_select:
        quests = list(
            (
                await db.execute(
                    sa.select(Quest)
                    .where(
                        Quest.is_active.is_(True),
                        Quest.burden_level.in_((1, 2)),
                    )
                    .order_by(Quest.id)
                )
            ).scalars()
        )
        if not quests:
            raise AppError(
                503, "QUEST_CATALOG_EMPTY", "오늘의 퀘스트를 준비하지 못했어요."
            )
        recent_rows = (
            await db.execute(
                sa.select(
                    UserQuest.quest_id,
                    Quest.category,
                    Quest.burden_level,
                    UserQuest.quest_date,
                )
                .join(Quest, Quest.id == UserQuest.quest_id)
                .where(
                    UserQuest.user_id == user_id,
                    UserQuest.quest_date >= today - timedelta(days=14),
                    UserQuest.quest_date < today,
                )
                .order_by(UserQuest.quest_date.desc(), UserQuest.id.desc())
            )
        ).all()
        recent = [
            QuestHistory(
                quest_id=quest_id,
                category=category,
                burden_level=burden_level,
                quest_date=quest_date,
            )
            for quest_id, category, burden_level, quest_date in recent_rows
        ]
        quest = choose_daily_quest(
            quests,
            recent,
            user_id=user_id,
            today=today,
            preferred_categories=preferred_categories,
        )
        if row is None:
            user_quest = UserQuest(
                user_id=user_id,
                quest_id=quest.id,
                quest_date=today,
                status="assigned",
            )
            db.add(user_quest)
        else:
            # 사용자가 완료하기 전이라면, 비동기 일기 분석이 끝난 시점에만
            # 중립 배정을 오늘의 마음 맥락과 어울리는 행동으로 연결한다.
            user_quest.quest_id = quest.id
        await db.commit()
        await db.refresh(user_quest)
    else:
        user_quest, quest = row
        await db.commit()
    journey = await _journey_progress_payload(db, user_id, today)
    return {
        "date": today.isoformat(),
        "suspended": False,
        "suspension_reason": None,
        "context_status": context_status,
        "context_emotion": context_emotion,
        "items": [quest_payload(user_quest, quest)],
        "journey": journey,
    }


async def _owned_user_quest_for_update(
    db: AsyncSession, user_id: int, user_quest_id: int
) -> UserQuest:
    user_quest = await db.scalar(
        sa.select(UserQuest).where(UserQuest.id == user_quest_id).with_for_update()
    )
    if user_quest is None:
        raise AppError(404, "USER_QUEST_NOT_FOUND", "퀘스트를 찾을 수 없습니다.")
    if user_quest.user_id != user_id:
        raise AppError(403, "FORBIDDEN", "접근 권한이 없습니다.")
    return user_quest


async def complete_quest(db: AsyncSession, user_id: int, user_quest_id: int) -> dict:
    user = await lock_user(db, user_id)
    user_quest = await _owned_user_quest_for_update(db, user_id, user_quest_id)
    today = local_date_of(utcnow())
    if await safety_active_today(db, user_id, today):
        raise AppError(
            409,
            "QUESTS_SUSPENDED",
            "지금은 퀘스트 대신 안전 지원을 먼저 확인해 주세요.",
        )
    if user_quest.quest_date != today:
        raise AppError(409, "QUEST_EXPIRED", "오늘 배정된 퀘스트만 완료할 수 있습니다.")
    if user_quest.status != "assigned":
        raise AppError(
            409, "QUEST_ALREADY_RESOLVED", "이미 완료하거나 건너뛴 퀘스트입니다."
        )

    quest = await db.get(Quest, user_quest.quest_id)
    plant = await lock_active_plant(db, user_id)
    outcome = RewardOutcome(seed_balance=user.seed_balance)
    granted = await grant(
        db,
        user,
        plant,
        RewardEventType.QUEST_COMPLETED,
        f"quest_daily:{user.id}:{today.isoformat()}",
        "user_quest",
        user_quest.id,
        today,
        outcome,
        reward_amounts=(quest.reward_exp, quest.reward_seeds),
    )
    if not granted:
        raise AppError(409, "QUEST_ALREADY_RESOLVED", "이미 보상받은 퀘스트입니다.")
    user_quest.status = "completed"
    user_quest.completed_at = utcnow()
    await db.flush()
    journey = await _journey_progress_payload(db, user_id, today)
    return {
        "user_quest": quest_payload(user_quest, quest),
        "reward": outcome.payload(),
        "journey": journey,
    }


async def skip_quest(db: AsyncSession, user_id: int, user_quest_id: int) -> dict:
    user_quest = await _owned_user_quest_for_update(db, user_id, user_quest_id)
    if user_quest.quest_date != local_date_of(utcnow()):
        raise AppError(409, "QUEST_EXPIRED", "오늘 배정된 퀘스트만 건너뛸 수 있습니다.")
    if user_quest.status != "assigned":
        raise AppError(
            409, "QUEST_ALREADY_RESOLVED", "이미 완료하거나 건너뛴 퀘스트입니다."
        )
    user_quest.status = "skipped"
    quest = await db.get(Quest, user_quest.quest_id)
    await db.commit()
    return {"user_quest": quest_payload(user_quest, quest)}


async def shop_items(db: AsyncSession, user: User) -> dict:
    items = list(
        (
            await db.execute(
                sa.select(Item).where(Item.is_active.is_(True)).order_by(Item.id)
            )
        ).scalars()
    )
    context = await _acquisition_context(db, user)
    return {
        "items": [
            {
                **item_payload(item, owned=item.code in context.owned_item_codes),
                "acquisition": acquisition_payload(item, context),
            }
            for item in items
        ],
        "seed_balance": user.seed_balance,
    }


async def purchase_item(db: AsyncSession, user_id: int, item_id: int) -> dict:
    item = await db.get(Item, item_id)
    if item is None or not item.is_active:
        raise AppError(404, "ITEM_NOT_FOUND", "아이템을 찾을 수 없습니다.")
    if _acquisition_rule(item)["type"] != "purchase":
        raise AppError(
            409,
            "ITEM_NOT_PURCHASABLE",
            "조건을 달성해 획득하는 아이템은 씨앗으로 구매할 수 없어요.",
        )
    user = await lock_user(db, user_id)
    owned = await db.scalar(
        sa.select(UserItem.id)
        .where(UserItem.user_id == user_id, UserItem.item_id == item_id)
        .with_for_update()
    )
    if owned is not None:
        raise AppError(409, "ITEM_ALREADY_OWNED", "이미 보유한 아이템입니다.")
    if user.seed_balance < item.price_seeds:
        raise AppError(
            409,
            "INSUFFICIENT_SEEDS",
            "씨앗 포인트가 부족합니다.",
            {"required": item.price_seeds, "balance": user.seed_balance},
        )

    species_unlock = None
    if item.type == "species_unlock":
        species_code = item.asset_manifest.get("species_code")
        species = await db.scalar(
            sa.select(PlantSpecies).where(PlantSpecies.code == species_code)
        )
        if species is None:
            raise AppError(
                503, "SHOP_CATALOG_INVALID", "상점 품종 정보를 확인할 수 없습니다."
            )
        already_unlocked = await db.scalar(
            sa.select(UserSpeciesUnlock.id)
            .where(
                UserSpeciesUnlock.user_id == user_id,
                UserSpeciesUnlock.species_id == species.id,
            )
            .with_for_update()
        )
        if already_unlocked is not None:
            raise AppError(409, "SPECIES_ALREADY_UNLOCKED", "이미 해금한 품종입니다.")
        species_unlock = UserSpeciesUnlock(user_id=user.id, species_id=species.id)

    user.seed_balance -= item.price_seeds
    db.add(
        RewardEvent(
            user_id=user.id,
            plant_id=None,
            event_type=RewardEventType.SHOP_PURCHASE,
            source_type="item",
            source_id=item.id,
            dedupe_key=f"purchase:item:{user.id}:{item.id}",
            exp_delta=0,
            seed_delta=-item.price_seeds,
            seed_balance_after=user.seed_balance,
        )
    )
    user_item = UserItem(user_id=user.id, item_id=item.id)
    db.add(user_item)
    if species_unlock is not None:
        db.add(species_unlock)
    await db.flush()
    return {
        "user_item": user_item_payload(user_item, item),
        "seed_balance": user.seed_balance,
    }


async def claim_item(db: AsyncSession, user_id: int, item_id: int) -> dict:
    item = await db.get(Item, item_id)
    if item is None or not item.is_active:
        raise AppError(404, "ITEM_NOT_FOUND", "아이템을 찾을 수 없습니다.")
    if _acquisition_rule(item)["type"] == "purchase":
        raise AppError(
            409,
            "ITEM_NOT_CLAIMABLE",
            "씨앗으로 구매하는 아이템은 조건 해금할 수 없어요.",
        )

    user = await lock_user(db, user_id)
    owned = await db.scalar(
        sa.select(UserItem)
        .where(
            UserItem.user_id == user_id,
            UserItem.item_id == item_id,
        )
        .with_for_update()
    )
    if owned is not None:
        raise AppError(409, "ITEM_ALREADY_OWNED", "이미 보유한 아이템입니다.")

    context = await _acquisition_context(db, user, for_update=True)
    acquisition = acquisition_payload(item, context)
    if not acquisition["eligible"]:
        raise AppError(
            409,
            "ITEM_ACQUISITION_NOT_MET",
            "아직 아이템 획득 조건을 달성하지 못했어요.",
            {"item_id": item.id, "acquisition": acquisition},
        )

    user_item = UserItem(user_id=user.id, item_id=item.id)
    try:
        async with db.begin_nested():
            db.add(user_item)
            await db.flush([user_item])
    except IntegrityError as exc:
        # 다중 API 프로세스에서 서로 다른 멱등 키가 경합해도
        # unique 제약을 500으로 노출하지 않는다.
        raise AppError(409, "ITEM_ALREADY_OWNED", "이미 보유한 아이템입니다.") from exc
    return {
        "user_item": user_item_payload(user_item, item),
        "acquisition": {**acquisition, "eligible": False},
        "seed_balance": user.seed_balance,
    }


async def shop_species(db: AsyncSession, user_id: int) -> dict:
    unlocked_ids = set(
        (
            await db.execute(
                sa.select(UserSpeciesUnlock.species_id).where(
                    UserSpeciesUnlock.user_id == user_id
                )
            )
        ).scalars()
    )
    species = list(
        (await db.execute(sa.select(PlantSpecies).order_by(PlantSpecies.id))).scalars()
    )
    user = await db.get(User, user_id)
    return {
        "items": [
            species_payload(s, s.unlock_price == 0 or s.id in unlocked_ids)
            for s in species
        ],
        "seed_balance": user.seed_balance,
    }


def species_payload(species: PlantSpecies, unlocked: bool) -> dict:
    return {
        "id": species.id,
        "code": species.code,
        "name": species.name,
        "rarity": species.rarity,
        "unlock_price": species.unlock_price,
        "asset_manifest": species.asset_manifest,
        "is_unlocked": unlocked,
    }


async def purchase_species(db: AsyncSession, user_id: int, species_id: int) -> dict:
    species = await db.get(PlantSpecies, species_id)
    if species is None:
        raise AppError(404, "SPECIES_NOT_FOUND", "품종을 찾을 수 없습니다.")
    if species.unlock_price == 0:
        raise AppError(
            409, "SPECIES_ALREADY_UNLOCKED", "이미 사용할 수 있는 품종입니다."
        )
    user = await lock_user(db, user_id)
    unlocked = await db.scalar(
        sa.select(UserSpeciesUnlock.id)
        .where(
            UserSpeciesUnlock.user_id == user_id,
            UserSpeciesUnlock.species_id == species_id,
        )
        .with_for_update()
    )
    if unlocked is not None:
        raise AppError(409, "SPECIES_ALREADY_UNLOCKED", "이미 해금한 품종입니다.")
    if user.seed_balance < species.unlock_price:
        raise AppError(
            409,
            "INSUFFICIENT_SEEDS",
            "씨앗 포인트가 부족합니다.",
            {"required": species.unlock_price, "balance": user.seed_balance},
        )
    user.seed_balance -= species.unlock_price
    db.add(
        RewardEvent(
            user_id=user.id,
            plant_id=None,
            event_type=RewardEventType.SHOP_PURCHASE,
            source_type="plant_species",
            source_id=species.id,
            dedupe_key=f"purchase:species:{user.id}:{species.id}",
            exp_delta=0,
            seed_delta=-species.unlock_price,
            seed_balance_after=user.seed_balance,
        )
    )
    unlock = UserSpeciesUnlock(user_id=user.id, species_id=species.id)
    db.add(unlock)
    await db.flush()
    return {
        "species": species_payload(species, True),
        "seed_balance": user.seed_balance,
    }


async def _owned_items(db: AsyncSession, user_id: int) -> list[tuple[UserItem, Item]]:
    return list(
        (
            await db.execute(
                sa.select(UserItem, Item)
                .join(Item, Item.id == UserItem.item_id)
                .where(UserItem.user_id == user_id)
                .order_by(UserItem.id)
            )
        ).all()
    )


async def collection_payload(db: AsyncSession, user: User) -> dict:
    owned = await _owned_items(db, user.id)
    owned_by_item_id = {item.id: user_item for user_item, item in owned}
    catalog = list(
        (
            await db.execute(
                sa.select(Item).where(Item.is_active.is_(True)).order_by(Item.id)
            )
        ).scalars()
    )
    context = await _acquisition_context(db, user)
    unlocked_ids = set(
        (
            await db.execute(
                sa.select(UserSpeciesUnlock.species_id).where(
                    UserSpeciesUnlock.user_id == user.id
                )
            )
        ).scalars()
    )
    species = list(
        (await db.execute(sa.select(PlantSpecies).order_by(PlantSpecies.id))).scalars()
    )

    def catalog_item_owned(item: Item) -> bool:
        return item.code in context.owned_item_codes

    return {
        "items": [user_item_payload(ui, item) for ui, item in owned],
        "catalog_items": [
            {
                **item_payload(item, owned=catalog_item_owned(item)),
                "acquisition": acquisition_payload(item, context),
                "locked": not catalog_item_owned(item),
                "user_item_id": (
                    owned_by_item_id[item.id].id
                    if item.id in owned_by_item_id
                    else None
                ),
                "acquired_at": (
                    to_utc_iso(owned_by_item_id[item.id].acquired_at)
                    if item.id in owned_by_item_id
                    else None
                ),
            }
            for item in catalog
        ],
        "species": [
            species_payload(s, s.unlock_price == 0 or s.id in unlocked_ids)
            for s in species
        ],
        "seed_balance": user.seed_balance,
    }


def default_layout(
    version: int = 0, main_character_user_item_id: int | None = None
) -> dict:
    return {
        "version": version,
        "room_theme_user_item_id": None,
        "main_character_user_item_id": main_character_user_item_id,
        "wardrobe_user_item_id": None,
        "companion_user_item_ids": [],
        "decorations": [],
    }


def _wardrobe_supports_species(asset_manifest: object, species_code: str) -> bool:
    if not isinstance(asset_manifest, dict):
        return False
    compatible_species = asset_manifest.get("compatible_species")
    if not isinstance(compatible_species, list):
        return False
    return species_code in {
        code.strip()
        for code in compatible_species
        if isinstance(code, str) and code.strip()
    }


async def unequip_incompatible_wardrobe(
    db: AsyncSession, user_id: int, species_code: str
) -> bool:
    """새 활성 품종과 맞지 않는 의상을 같은 트랜잭션에서 해제한다."""
    row = await db.scalar(
        sa.select(FarmLayout).where(FarmLayout.user_id == user_id).with_for_update()
    )
    if row is None:
        return False

    layout = {**default_layout(version=row.version), **(row.layout or {})}
    wardrobe_user_item_id = layout.get("wardrobe_user_item_id")
    if wardrobe_user_item_id is None:
        return False

    asset_manifest = await db.scalar(
        sa.select(Item.asset_manifest)
        .join(UserItem, UserItem.item_id == Item.id)
        .where(
            UserItem.id == wardrobe_user_item_id,
            UserItem.user_id == user_id,
            Item.type == "wardrobe",
        )
    )
    if _wardrobe_supports_species(asset_manifest, species_code):
        return False

    layout["wardrobe_user_item_id"] = None
    layout.pop("version", None)
    row.layout = layout
    row.version += 1
    row.updated_at = utcnow()
    return True


async def farm_payload(db: AsyncSession, user_id: int) -> dict:
    row = await db.get(FarmLayout, user_id)
    owned = await _owned_items(db, user_id)
    default_character_id = next(
        (ui.id for ui, item in owned if item.code == "character_baby_pot"),
        next((ui.id for ui, item in owned if item.type == "main_character"), None),
    )
    layout = (
        default_layout(main_character_user_item_id=default_character_id)
        if row is None
        else {
            **default_layout(version=row.version),
            **row.layout,
            "version": row.version,
        }
    )
    return {
        "layout": layout,
        "owned_items": [user_item_payload(ui, item) for ui, item in owned],
    }


async def save_farm_layout(db: AsyncSession, user_id: int, body) -> dict:
    # 최초 layout insert 경합도 안전하게 직렬화하기 위해 사용자 row를 먼저 잠근다.
    await lock_user(db, user_id)
    row = await db.scalar(
        sa.select(FarmLayout).where(FarmLayout.user_id == user_id).with_for_update()
    )
    current_version = row.version if row is not None else 0
    if body.expected_version != current_version:
        raise AppError(
            409,
            "FARM_LAYOUT_VERSION_CONFLICT",
            "다른 기기에서 방 배치가 변경되었습니다.",
            {
                "expected_version": body.expected_version,
                "current_version": current_version,
            },
        )

    requested_ids = {
        item_id
        for item_id in (
            body.room_theme_user_item_id,
            body.main_character_user_item_id,
            body.wardrobe_user_item_id,
        )
        if item_id is not None
    }
    requested_ids.update(body.companion_user_item_ids)
    requested_ids.update(d.user_item_id for d in body.decorations)
    owned_items: dict[int, tuple[str, object]] = {}
    if requested_ids:
        rows = await db.execute(
            sa.select(UserItem.id, Item.type, Item.asset_manifest)
            .join(Item, Item.id == UserItem.item_id)
            .where(UserItem.user_id == user_id, UserItem.id.in_(requested_ids))
        )
        owned_items = {
            user_item_id: (item_type, asset_manifest)
            for user_item_id, item_type, asset_manifest in rows.all()
        }
    if set(owned_items) != requested_ids:
        raise AppError(
            422, "FARM_ITEM_NOT_OWNED", "보유하지 않은 아이템은 배치할 수 없습니다."
        )
    owned_types = {
        user_item_id: item_type
        for user_item_id, (item_type, _asset_manifest) in owned_items.items()
    }

    expected_types: list[tuple[int | None, str]] = [
        (body.room_theme_user_item_id, "room_theme"),
        (body.main_character_user_item_id, "main_character"),
        (body.wardrobe_user_item_id, "wardrobe"),
    ]
    expected_types.extend((i, "companion") for i in body.companion_user_item_ids)
    expected_types.extend((d.user_item_id, "deco") for d in body.decorations)
    for item_id, expected_type in expected_types:
        if item_id is not None and owned_types.get(item_id) != expected_type:
            raise AppError(
                422,
                "FARM_ITEM_TYPE_INVALID",
                "아이템을 해당 위치에 배치할 수 없습니다.",
            )

    if body.wardrobe_user_item_id is not None:
        species_code = await db.scalar(
            sa.select(PlantSpecies.code)
            .join(Plant, Plant.species_id == PlantSpecies.id)
            .where(
                Plant.user_id == user_id,
                Plant.status == PlantStatus.ACTIVE,
            )
        )
        wardrobe_manifest = owned_items[body.wardrobe_user_item_id][1]
        if species_code is not None and not _wardrobe_supports_species(
            wardrobe_manifest, species_code
        ):
            raise AppError(
                422,
                "FARM_WARDROBE_SPECIES_INCOMPATIBLE",
                "현재 심어진 캐릭터가 착용할 수 없는 의상입니다.",
                {
                    "species_code": species_code,
                    "wardrobe_user_item_id": body.wardrobe_user_item_id,
                },
            )

    layout = {
        "room_theme_user_item_id": body.room_theme_user_item_id,
        "main_character_user_item_id": body.main_character_user_item_id,
        "wardrobe_user_item_id": body.wardrobe_user_item_id,
        "companion_user_item_ids": body.companion_user_item_ids,
        "decorations": [d.model_dump() for d in body.decorations],
    }
    new_version = current_version + 1
    if row is None:
        row = FarmLayout(user_id=user_id, version=new_version, layout=layout)
        db.add(row)
    else:
        row.version = new_version
        row.layout = layout
        row.updated_at = utcnow()
    await db.commit()
    return {"layout": {"version": new_version, **layout}}
