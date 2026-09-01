import hashlib
from datetime import datetime, timedelta

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.errors import AppError
from app.core.timeutil import local_date_of, to_utc_iso, utcnow
from app.models.adventure import (
    AdventurePatrol,
    DungeonRun,
    UserAdventureItem,
    UserAdventureResearch,
    UserDungeon,
)
from app.models.enums import PlantStatus, RewardEventType
from app.models.game import FarmLayout, Item, UserItem
from app.models.mood import MoodEntry
from app.models.plant import Plant, PlantSpecies
from app.models.reward import RewardEvent
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
    "glass_rooftop": {
        "name": "유리온실 옥상",
        "description": "새벽 별빛이 머무는 옥상에서 오래된 발아 장치의 흔적을 찾아요.",
        "duration_minutes": 30,
        "required_stage": 4,
        "stats": ("courage", "insight"),
        "discovery_code": "starlight_seed_vault",
        "item_code": "glass_leaf_vein",
    },
    "dawn_canopy_walk": {
        "name": "새벽 수관 회랑",
        "description": "만개한 온실 위 나무길을 따라 가장 오래된 성장 관측실을 찾아요.",
        "duration_minutes": 40,
        "required_stage": 5,
        "stats": ("care", "courage"),
        "discovery_code": "heartwood_observatory",
        "item_code": "dawn_bark_rubbing",
    },
}

PATROL_ENCOUNTERS = {
    "greenhouse_edge": (
        {
            "code": "moss_label",
            "title": "이끼 아래의 이름표",
            "text": "젖은 이끼를 살짝 걷어 오래된 화분 이름표를 발견했어요.",
        },
        {
            "code": "snail_path",
            "title": "달팽이가 그린 길",
            "text": "유리벽 아래 은빛 자국을 따라가 숨은 배수구를 찾았어요.",
        },
        {
            "code": "forgotten_watering_can",
            "title": "잊힌 물뿌리개",
            "text": "덩굴 뒤 작은 물뿌리개에 새싹 하나가 기대 자라고 있었어요.",
        },
    ),
    "moonlit_lane": (
        {
            "code": "silver_footsteps",
            "title": "달빛 발자국",
            "text": "희미한 발자국이 밤꽃 사이 안전한 길을 알려 주었어요.",
        },
        {
            "code": "echo_chime",
            "title": "바람 없는 풍경",
            "text": "바람이 없는데도 작은 풍경이 울려 오래된 샛길을 찾았어요.",
        },
        {
            "code": "sleeping_blossom",
            "title": "잠든 밤꽃",
            "text": "접힌 꽃잎 사이 맺힌 이슬이 달빛을 조용히 모으고 있었어요.",
        },
    ),
    "glass_rooftop": (
        {
            "code": "star_reflection",
            "title": "유리 위 작은 별",
            "text": "금이 간 유리 조각에서 새벽별 하나가 오래 머무는 걸 보았어요.",
        },
        {
            "code": "old_seed_tag",
            "title": "빛바랜 씨앗표",
            "text": "난간 아래서 발아 날짜가 적힌 오래된 씨앗표를 발견했어요.",
        },
        {
            "code": "warm_glass",
            "title": "아직 따뜻한 유리",
            "text": "밤이 끝났는데도 온기가 남은 유리 아래 작은 잎맥이 빛났어요.",
        },
    ),
    "dawn_canopy_walk": (
        {
            "code": "feather_marker",
            "title": "깃털로 남긴 표지",
            "text": "나뭇가지에 끼운 작은 깃털이 관측실 방향을 가리켰어요.",
        },
        {
            "code": "heartwood_ring",
            "title": "새벽의 나이테",
            "text": "빛이 스친 나이테에서 어제보다 선명한 한 줄을 발견했어요.",
        },
        {
            "code": "first_birdsong",
            "title": "첫 새소리의 자리",
            "text": "가장 먼저 울린 새소리를 따라 수관 사이 쉼터를 찾았어요.",
        },
    ),
}

PATROL_REACTIONS = {
    "sunny": (
        "따뜻한 길이었어. 네가 기다리고 있어서 더 빨리 돌아오고 싶었어.",
        "오늘 찾은 반짝임, 네 기록 옆에 두면 잘 어울릴 것 같아.",
    ),
    "rainy": (
        "천천히 걸으니 작은 소리까지 들렸어. 네게도 들려주고 싶었어.",
        "조용한 길도 외롭진 않았어. 돌아와서 네게 말할 걸 알고 있었거든.",
    ),
    "ember": (
        "막힌 길은 내가 열었어. 다음엔 더 먼 곳까지 같이 가자.",
        "꽤 근사한 흔적이지? 놓치지 않고 가져왔어.",
    ),
    "moonlit": (
        "눈에 잘 띄지 않는 길일수록 단서가 많아. 하나씩 기억해 뒀어.",
        "서두르지 않고 살펴봤어. 네 기록처럼 작은 차이가 중요하니까.",
    ),
    "sparkling": (
        "예상 못 한 곳에서 재미있는 걸 찾았어! 다음 길도 벌써 궁금해.",
        "봐, 평범한 길도 자세히 보면 비밀이 이렇게 많아.",
    ),
    "mosaic": (
        "서로 다른 흔적을 모으니 한 장면이 됐어. 네 마음 기록처럼.",
        "한 가지 길만 보지 않으니까 이걸 찾을 수 있었어. 같이 기억하자.",
    ),
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
    "starlight_seed_vault": {
        "name": "별빛 씨앗 보관고",
        "description": "옥상 발아실의 오래된 씨앗함을 살펴 잠든 성장 기록을 정리해요.",
        "required_stage": 4,
        "stats": ("care", "focus"),
        "item_code": "starlight_pollen",
        "asset_path": "assets/adventure/dungeon-starlight-seed-vault.webp",
    },
    "heartwood_observatory": {
        "name": "마음나무 관측실",
        "description": "오래된 나무의 성장 고리를 살펴 지금까지의 탐험 기록을 한 장으로 묶어요.",
        "required_stage": 5,
        "stats": ("focus", "insight"),
        "item_code": "heartwood_seed_sample",
        "asset_path": "assets/adventure/dungeon-heartwood-observatory.webp",
    },
}

DUNGEON_SCENES = {
    "moss_archive": (
        {
            "code": "overturned_drawer",
            "title": "뒤집힌 표본 서랍",
            "text": "젖은 라벨 사이에서 서로 다른 씨앗 기록이 한데 섞여 있었어요.",
        },
        {
            "code": "root_locked_door",
            "title": "뿌리로 잠긴 문",
            "text": "오래 자란 뿌리가 작은 문고리를 감싸 안쪽 기록을 지키고 있었어요.",
        },
        {
            "code": "breathing_ledger",
            "title": "숨을 쉬는 장부",
            "text": "페이지 사이 이끼가 오르내리며 잊힌 발아 순서를 가리켰어요.",
        },
    ),
    "echo_well": (
        {
            "code": "returning_whisper",
            "title": "돌아온 작은 속삭임",
            "text": "우물에 건넨 한마디가 다른 음으로 돌아와 잠든 화단을 깨웠어요.",
        },
        {
            "code": "submerged_bell",
            "title": "물 아래의 종",
            "text": "맑은 물 아래 잠긴 작은 종이 발걸음에 맞춰 낮게 울렸어요.",
        },
        {
            "code": "echo_stair",
            "title": "소리로 놓인 계단",
            "text": "서로 다른 메아리를 차례로 맞추자 보이지 않던 돌계단이 드러났어요.",
        },
    ),
    "starlight_seed_vault": (
        {
            "code": "inverted_seed_drawer",
            "title": "거꾸로 선 씨앗함",
            "text": "천장 쪽으로 열린 씨앗함 안에서 별빛 꽃가루가 천천히 흘렀어요.",
        },
        {
            "code": "stopped_germination_clock",
            "title": "멈춘 발아 시계",
            "text": "멈춘 바늘 아래 아직 따뜻한 씨앗 하나가 다음 새벽을 기다렸어요.",
        },
        {
            "code": "constellation_sprouts",
            "title": "별자리를 닮은 새싹",
            "text": "유리관 속 새싹들이 잎끝을 이어 작은 별자리를 만들고 있었어요.",
        },
    ),
    "heartwood_observatory": (
        {
            "code": "blank_growth_ring",
            "title": "비어 있는 나이테",
            "text": "오래된 나이테 한 칸이 비어 있어 지금의 기록을 기다리고 있었어요.",
        },
        {
            "code": "root_archive",
            "title": "뿌리 아래 보관함",
            "text": "굵은 뿌리가 들어 올린 보관함에서 지난 계절의 관측지가 나왔어요.",
        },
        {
            "code": "first_map_beyond",
            "title": "온실 밖 첫 지도",
            "text": "서로 다른 표본의 흔적을 이으니 온실 밖으로 향하는 첫 선이 나타났어요.",
        },
    ),
}

DUNGEON_APPROACHES = {
    "care": {
        "name": "흔적을 돌보며 걷기",
        "description": "상처 난 잎과 흐트러진 자리를 정돈하며 안전한 길을 만들어요.",
        "stat": "care",
    },
    "focus": {
        "name": "호흡을 고르고 집중하기",
        "description": "주변 소음을 가라앉히고 한 갈래의 기척을 끝까지 따라가요.",
        "stat": "focus",
    },
    "courage": {
        "name": "먼저 길을 열기",
        "description": "망설이기보다 앞으로 나아가 막힌 통로를 직접 확인해요.",
        "stat": "courage",
    },
    "insight": {
        "name": "작은 단서 관찰하기",
        "description": "빛과 소리의 미세한 차이를 살펴 숨은 흔적을 이어 봐요.",
        "stat": "insight",
    },
}

#: `오늘의 성장 효율` 패널이 읽는 하루 경제표(설계서 9.1).
#:
#: 이 값이 지키는 것은 **순서**다 — 마음 일기 한 편이 어떤 탐험보다 크다.
#: 지역 보상을 올릴 때 이 순서가 뒤집히지 않는지 검사가 함께 센다. 상수로
#: 꺼내 둔 이유가 그것이다.
DAILY_ECONOMY = (
    {"code": "diary", "label": "마음 일기", "exp": 40, "seeds": 15},
    {"code": "quest", "label": "작은 행동", "exp": 20, "seeds": 5},
    {"code": "dungeon", "label": "던전", "exp": 10, "seeds": 4},
    {"code": "patrol", "label": "순찰", "exp": 0, "seeds": 3},
)

ITEMS = {
    "pressed_leaf_map": ("눌러 말린 잎 지도", "다음 길을 찾을 때 쓰는 얇은 지도 조각"),
    "moon_dew": ("달빛 이슬", "밤의 식물에서만 맺히는 맑은 이슬"),
    "moss_key": ("이끼 열쇠", "기억서고의 잠긴 표본함을 여는 작은 열쇠"),
    # 나머지 세 지역의 목표 재료도 여기 있어야 한다. 콘텐츠 팩은 처음부터
    # 이 코드들을 목표로 주고 있었는데 이름표가 없어서, 귀환 화면과 인벤토리에
    # 사람이 읽는 이름 대신 `echo_key` 같은 코드가 그대로 떴다.
    "echo_key": ("메아리 열쇠", "우물정원의 잠긴 물목을 여는 젖은 열쇠"),
    "vault_key": ("보관고 열쇠", "별빛 씨앗 서랍을 여는 서늘한 열쇠"),
    "heartwood_key": ("심재 열쇠", "관측실 나이테 문을 여는 나무 열쇠"),
    "echo_seed": ("메아리 씨앗", "흔들면 아주 작은 울림이 돌아오는 씨앗"),
    "glass_leaf_vein": ("유리빛 잎맥", "옥상 식물에서 떨어진 반투명한 잎맥 조각"),
    "starlight_pollen": (
        "별빛 꽃가루",
        "새벽빛을 머금어 은은한 크림색으로 빛나는 꽃가루",
    ),
    "dawn_bark_rubbing": (
        "새벽 나무결 탁본",
        "수관 회랑의 오래된 나무결을 종이에 옮긴 기록",
    ),
    "heartwood_seed_sample": (
        "심재 씨앗 표본",
        "마음나무 곁에서 단단히 여문 씨앗의 작은 표본",
    ),
}

WEEKLY_GOALS = {
    "diary_3": {
        "name": "마음 일기 3일",
        "description": "서로 다른 3일에 마음을 50자 이상 기록해요.",
        "metric": "diary_days",
        "target": 3,
        "reward_seeds": 20,
    },
    "patrol_3": {
        "name": "순찰 귀환 3회",
        "description": "캐릭터가 돌아온 순찰 보상을 3번 받아요.",
        "metric": "claimed_patrols",
        "target": 3,
        "reward_seeds": 8,
    },
    "dungeon_2": {
        "name": "던전 탐험 2회",
        "description": "발견한 던전을 이번 주에 2번 탐험해요.",
        "metric": "dungeon_runs",
        "target": 2,
        "reward_seeds": 6,
    },
}

ADVENTURE_MILESTONES = (
    {
        "code": "seven_day_diary",
        "name": "일곱 날의 마음",
        "description": "50자 이상 마음 일기를 서로 다른 7일에 남겨요.",
        "metric": "diary_days",
        "target": 7,
        "title": "마음 기록가",
    },
    {
        "code": "five_patrol_returns",
        "name": "익숙해진 산책길",
        "description": "캐릭터의 순찰 귀환을 5번 맞이해요.",
        "metric": "patrol_returns",
        "target": 5,
        "title": "정원 길잡이",
    },
    {
        "code": "five_dungeon_runs",
        "name": "문 너머의 기록",
        "description": "발견한 던전을 5번 차분히 탐험해요.",
        "metric": "dungeon_runs",
        "target": 5,
        "title": "고요한 탐험가",
    },
    {
        "code": "three_research_projects",
        "name": "세 번째 표본함",
        "description": "서로 다른 표본 연구를 3개 완성해요.",
        "metric": "research_projects",
        "target": 3,
        "title": "표본 연구가",
    },
    {
        "code": "outside_greenhouse_atlas",
        "name": "온실 밖 탐험 1장",
        "description": "마음나무 관측실까지의 탐험 지도를 완성해요.",
        "metric": "chapter_completed",
        "target": 1,
        "title": "온실 밖 지도지기",
    },
)

DONATION_REQUIRED_QUANTITY = 3
DONATION_REWARD_SEEDS = 2

RESEARCH_PROJECTS = {
    "pressed_leaf_atlas": {
        "name": "압화 길잡이 도감",
        "description": "잎 지도와 이끼 열쇠를 엮어 순찰 중 놓치던 작은 흔적을 찾아요.",
        "requirements": {"pressed_leaf_map": 2, "moss_key": 1},
        "effect": {
            "context": "patrol",
            "amount": 1,
            "label": "순찰 수집량 영구 +1",
        },
    },
    "echo_listening_kit": {
        "name": "메아리 청음 키트",
        "description": "달빛 이슬로 조율한 씨앗이 던전의 희미한 울림을 구분해 줘요.",
        "requirements": {"moon_dew": 2, "echo_seed": 1},
        "effect": {
            "context": "dungeon",
            "amount": 1,
            "label": "던전 수집량 영구 +1",
        },
    },
    "memory_specimen_case": {
        "name": "기억 씨앗 표본함",
        "description": "서로 다른 네 발견물을 한자리에 정리해 첫 탐험 기록을 완성해요.",
        "requirements": {
            "pressed_leaf_map": 1,
            "moon_dew": 1,
            "moss_key": 1,
            "echo_seed": 1,
        },
        "effect": {
            "context": "archive",
            "amount": 0,
            "label": "첫 탐험 기록 완성",
        },
    },
    "starlight_greenhouse_clock": {
        "name": "별빛 온실 시계",
        "description": "옥상 빛의 각도를 기록해 모든 순찰의 돌아오는 길을 더 짧게 잡아요.",
        "requirements": {
            "glass_leaf_vein": 2,
            "starlight_pollen": 1,
            "moon_dew": 1,
        },
        "effect": {
            "context": "patrol_time",
            "amount": 5,
            "label": "모든 순찰 시간 영구 -5분",
        },
    },
    "outside_greenhouse_atlas": {
        "name": "온실 밖 탐험 지도",
        "description": "다섯 장소에서 모은 표본을 엮어 첫 번째 탐험 기록을 완성해요.",
        "requirements": {
            "dawn_bark_rubbing": 2,
            "heartwood_seed_sample": 2,
            "moss_key": 1,
            "echo_seed": 1,
            "starlight_pollen": 1,
        },
        "effect": {
            "context": "archive",
            "amount": 0,
            "label": "온실 밖 탐험 1장 완성",
        },
    },
}

STAT_LABELS = {
    "care": "돌봄",
    "focus": "집중",
    "courage": "용기",
    "insight": "관찰",
}

RECENT_JOURNAL_LIMIT = 6

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
    return bool(
        await db.scalar(
            sa.select(MoodEntry.id)
            .where(
                MoodEntry.user_id == user_id,
                MoodEntry.local_date == today,
                MoodEntry.content_length >= 50,
            )
            .limit(1)
        )
    )


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
    character: dict,
    stats: tuple[str, str],
    context: str,
    research_bonus: int = 0,
) -> tuple[int, int]:
    score = sum(character["stats"][stat] for stat in stats)
    outfit = character.get("outfit") or {}
    bonus = outfit.get("bonus") or {}
    if bonus.get("context") == context and bonus.get("stat") in stats:
        score += int(bonus.get("amount") or 0)
    # 성장과 의상은 수집량에만 반영한다. 핵심 XP/씨앗은 고정해 일기보다
    # 효율이 커지는 조합을 만들지 않는다.
    quantity = min(3, (2 if score >= 17 else 1) + research_bonus)
    return score, quantity


def _dungeon_approach_performance(
    character: dict,
    dungeon: dict,
    approach: dict,
    research_bonus: int = 0,
) -> tuple[int, int, str]:
    stat = approach["stat"]
    score = character["stats"][stat]
    if stat in dungeon["stats"]:
        score += 2
    outfit = character.get("outfit") or {}
    outfit_bonus = outfit.get("bonus") or {}
    if outfit_bonus.get("context") == "dungeon" and outfit_bonus.get("stat") == stat:
        score += int(outfit_bonus.get("amount") or 0)
    outcome_code = "resonant" if score >= 9 else "steady"
    quantity = min(3, (2 if outcome_code == "resonant" else 1) + research_bonus)
    return score, quantity, outcome_code


def _dungeon_approach_payloads(
    character: dict | None,
    dungeon: dict,
    research_bonus: int,
) -> list[dict]:
    payloads = []
    for code, approach in DUNGEON_APPROACHES.items():
        stat = approach["stat"]
        if character is None:
            score, quantity, outcome_code = 0, 0, "locked"
            stat_value = 0
        else:
            score, quantity, outcome_code = _dungeon_approach_performance(
                character,
                dungeon,
                approach,
                research_bonus,
            )
            stat_value = character["stats"][stat]
        payloads.append(
            {
                "code": code,
                "name": approach["name"],
                "description": approach["description"],
                "stat_code": stat,
                "stat_label": STAT_LABELS[stat],
                "stat_value": stat_value,
                "recommended": stat in dungeon["stats"],
                "performance_score": score,
                "projected_quantity": quantity,
                "projected_outcome": outcome_code,
            }
        )
    return payloads


async def _research_bonus(db: AsyncSession, user_id: int, context: str) -> int:
    completed = set(
        (
            await db.execute(
                sa.select(UserAdventureResearch.project_code).where(
                    UserAdventureResearch.user_id == user_id
                )
            )
        ).scalars()
    )
    return sum(
        int(project["effect"]["amount"])
        for code, project in RESEARCH_PROJECTS.items()
        if code in completed and project["effect"]["context"] == context
    )


def _research_payloads(completed: set[str], inventory: dict[str, int]) -> list[dict]:
    payloads = []
    for code, project in RESEARCH_PROJECTS.items():
        requirements = [
            {
                "code": item_code,
                "name": ITEMS[item_code][0],
                "current": inventory.get(item_code, 0),
                "required": required,
            }
            for item_code, required in project["requirements"].items()
        ]
        is_completed = code in completed
        payloads.append(
            {
                "code": code,
                "name": project["name"],
                "description": project["description"],
                "completed": is_completed,
                "can_complete": not is_completed
                and all(
                    requirement["current"] >= requirement["required"]
                    for requirement in requirements
                ),
                "requirements": requirements,
                "effect": project["effect"],
            }
        )
    return payloads


def _reserved_research_materials(completed: set[str]) -> dict[str, int]:
    reserved: dict[str, int] = {}
    for code, project in RESEARCH_PROJECTS.items():
        if code in completed:
            continue
        for item_code, required in project["requirements"].items():
            reserved[item_code] = reserved.get(item_code, 0) + required
    return reserved


def _donation_payload(
    inventory: dict[str, int],
    completed_research: set[str],
    *,
    used_today: bool,
    suspended: bool,
) -> dict:
    reserved = _reserved_research_materials(completed_research)
    has_eligible_item = any(
        max(0, quantity - reserved.get(item_code, 0)) >= DONATION_REQUIRED_QUANTITY
        for item_code, quantity in inventory.items()
    )
    available_today = not used_today and not suspended
    if suspended:
        message = "오늘은 기증보다 마음 돌봄을 먼저 확인해 주세요."
    elif used_today:
        message = "오늘 표본 기증은 마쳤어요. 내일 다시 정리할 수 있어요."
    elif has_eligible_item:
        message = "연구에 필요한 수량을 남기고 여분 표본만 기증할 수 있어요."
    else:
        message = "미완성 연구 재료를 제외한 여분 표본 3개가 필요해요."
    return {
        "available_today": available_today,
        "used_today": used_today,
        "has_eligible_item": has_eligible_item,
        "required_quantity": DONATION_REQUIRED_QUANTITY,
        "reward_exp": 0,
        "reward_seeds": DONATION_REWARD_SEEDS,
        "message": message,
        "reserved_by_item": reserved,
    }


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


def _route_payload(
    code: str,
    route: dict,
    character: dict | None,
    collection_bonus: int = 0,
    time_bonus: int = 0,
) -> dict:
    stage = character["stage"] if character else 0
    available = stage >= route["required_stage"]
    if character is None or not available:
        performance_score, projected_quantity = 0, 0
    else:
        performance_score, projected_quantity = _performance(
            character,
            route["stats"],
            "patrol",
            collection_bonus,
        )
    duration_minutes = max(5, route["duration_minutes"] - time_bonus)
    return {
        "code": code,
        "name": route["name"],
        "description": route["description"],
        "duration_minutes": duration_minutes,
        "base_duration_minutes": route["duration_minutes"],
        "time_reduction_minutes": route["duration_minutes"] - duration_minutes,
        "required_stage": route["required_stage"],
        "available": available,
        "recommended_stats": [STAT_LABELS[stat] for stat in route["stats"]],
        "performance_score": performance_score,
        "projected_quantity": projected_quantity,
        "best_match": False,
        "reward": {"exp": 0, "seeds": 3, "item_code": route["item_code"]},
    }


def _route_payloads(
    character: dict | None,
    collection_bonus: int = 0,
    time_bonus: int = 0,
) -> list[dict]:
    payloads = [
        _route_payload(
            code,
            route,
            character,
            collection_bonus,
            time_bonus,
        )
        for code, route in ROUTES.items()
    ]
    available = [route for route in payloads if route["available"]]
    if available:
        # 수집 성능이 같으면 가장 최근에 열린 성장 단계의 경로를 먼저 제안한다.
        best = max(
            available,
            key=lambda route: (route["performance_score"], route["required_stage"]),
        )
        best["best_match"] = True
    return payloads


def _patrol_encounter(user_id: int, local_day, route_code: str) -> dict:
    encounters = PATROL_ENCOUNTERS[route_code]
    source = f"{user_id}:{local_day.isoformat()}:{route_code}".encode()
    index = int.from_bytes(hashlib.sha256(source).digest()[:8], "big") % len(encounters)
    return encounters[index]


def _patrol_reaction(
    user_id: int,
    local_day,
    route_code: str,
    form: str,
) -> str:
    resolved_form = form if form in PATROL_REACTIONS else "mosaic"
    reactions = PATROL_REACTIONS[resolved_form]
    source = (
        f"reaction:{user_id}:{local_day.isoformat()}:{route_code}:{resolved_form}"
    ).encode()
    index = int.from_bytes(hashlib.sha256(source).digest()[:8], "big") % len(reactions)
    return reactions[index]


def _dungeon_scene(
    user_id: int,
    local_day,
    dungeon_code: str,
    approach_code: str,
) -> dict:
    scenes = DUNGEON_SCENES[dungeon_code]
    source = (
        f"dungeon:{user_id}:{local_day.isoformat()}:{dungeon_code}:{approach_code}"
    ).encode()
    index = int.from_bytes(hashlib.sha256(source).digest()[:8], "big") % len(scenes)
    return scenes[index]


def _dungeon_scene_payload(run: DungeonRun) -> dict | None:
    if not run.scene_code or not run.scene_title or not run.scene_text:
        return None
    return {
        "code": run.scene_code,
        "title": run.scene_title,
        "text": run.scene_text,
    }


def _claimed_encounter_payload(patrol: AdventurePatrol) -> dict | None:
    if (
        patrol.status != "claimed"
        or not patrol.encounter_code
        or not patrol.encounter_title
        or not patrol.encounter_text
    ):
        return None
    reaction = None
    if patrol.reaction_form and patrol.reaction_speaker and patrol.reaction_text:
        reaction = {
            "form": patrol.reaction_form,
            "speaker": patrol.reaction_speaker,
            "text": patrol.reaction_text,
        }
    return {
        "code": patrol.encounter_code,
        "title": patrol.encounter_title,
        "text": patrol.encounter_text,
        "reaction": reaction,
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
        "encounter_pending": patrol.status == "active",
        "encounter": _claimed_encounter_payload(patrol),
    }


async def _journal_payload(
    db: AsyncSession,
    user_id: int,
    discovered: dict[str, UserDungeon],
) -> dict:
    patrols = list(
        (
            await db.execute(
                sa.select(AdventurePatrol)
                .where(
                    AdventurePatrol.user_id == user_id,
                    AdventurePatrol.status == "claimed",
                    AdventurePatrol.claimed_at.is_not(None),
                )
                .order_by(AdventurePatrol.claimed_at.desc())
                .limit(RECENT_JOURNAL_LIMIT)
            )
        ).scalars()
    )
    dungeon_runs = list(
        (
            await db.execute(
                sa.select(DungeonRun, UserDungeon.dungeon_code)
                .join(UserDungeon, UserDungeon.id == DungeonRun.user_dungeon_id)
                .where(DungeonRun.user_id == user_id)
                .order_by(DungeonRun.created_at.desc())
                .limit(RECENT_JOURNAL_LIMIT)
            )
        ).all()
    )

    timeline: list[tuple[datetime, dict]] = []
    for patrol in patrols:
        if patrol.claimed_at is None:
            continue
        route = ROUTES.get(patrol.route_code, {})
        item_name = ITEMS.get(
            patrol.found_item_code,
            (patrol.found_item_code, ""),
        )[0]
        encounter = _claimed_encounter_payload(patrol)
        title = (
            encounter["title"]
            if encounter
            else f"{route.get('name', patrol.route_code)} 순찰 귀환"
        )
        description = (
            " · ".join(
                [
                    encounter["text"],
                    *(
                        [
                            f"{encounter['reaction']['speaker']} “"
                            f"{encounter['reaction']['text']}”"
                        ]
                        if encounter["reaction"]
                        else []
                    ),
                    f"{item_name} {patrol.found_quantity}개",
                ]
            )
            if encounter
            else f"{item_name} {patrol.found_quantity}개를 수집했어요."
        )
        timeline.append(
            (
                patrol.claimed_at,
                {
                    "kind": "patrol",
                    "title": title,
                    "description": description,
                    "occurred_at": to_utc_iso(patrol.claimed_at),
                    "location_code": patrol.route_code,
                    "item_code": patrol.found_item_code,
                    "item_name": item_name,
                    "quantity": patrol.found_quantity,
                    "outcome_code": None,
                },
            )
        )
    for run, dungeon_code in dungeon_runs:
        dungeon = DUNGEONS.get(dungeon_code, {})
        item_name = ITEMS.get(run.found_item_code, (run.found_item_code, ""))[0]
        scene = _dungeon_scene_payload(run)
        if run.approach_code == "steady":
            approach_name = "차분히 둘러보기"
        else:
            approach_name = DUNGEON_APPROACHES.get(run.approach_code, {}).get(
                "name",
                run.approach_code,
            )
        timeline.append(
            (
                run.created_at,
                {
                    "kind": "dungeon",
                    "title": (
                        scene["title"]
                        if scene
                        else f"{dungeon.get('name', dungeon_code)} 탐험"
                    ),
                    "description": (
                        " · ".join(
                            [
                                *([scene["text"]] if scene else []),
                                approach_name,
                                f"{item_name} {run.found_quantity}개",
                            ]
                        )
                    ),
                    "occurred_at": to_utc_iso(run.created_at),
                    "location_code": dungeon_code,
                    "item_code": run.found_item_code,
                    "item_name": item_name,
                    "quantity": run.found_quantity,
                    "outcome_code": run.outcome_code,
                },
            )
        )

    known_dungeons = [
        dungeon for code, dungeon in discovered.items() if code in DUNGEONS
    ]
    recent_entries = [
        entry
        for _, entry in sorted(
            timeline,
            key=lambda timeline_entry: timeline_entry[0],
            reverse=True,
        )[:RECENT_JOURNAL_LIMIT]
    ]
    return {
        "discovered_count": len(known_dungeons),
        "total_dungeons": len(DUNGEONS),
        "total_clear_count": sum(dungeon.clear_count for dungeon in known_dungeons),
        "recent_entries": recent_entries,
    }


async def _story_collection_payload(db: AsyncSession, user_id: int) -> dict:
    patrols = list(
        (
            await db.execute(
                sa.select(AdventurePatrol)
                .where(
                    AdventurePatrol.user_id == user_id,
                    AdventurePatrol.status == "claimed",
                    AdventurePatrol.claimed_at.is_not(None),
                    AdventurePatrol.encounter_code.is_not(None),
                )
                .order_by(AdventurePatrol.claimed_at.asc())
            )
        ).scalars()
    )
    dungeon_runs = list(
        (
            await db.execute(
                sa.select(DungeonRun, UserDungeon.dungeon_code)
                .join(UserDungeon, UserDungeon.id == DungeonRun.user_dungeon_id)
                .where(
                    DungeonRun.user_id == user_id,
                    DungeonRun.scene_code.is_not(None),
                )
                .order_by(DungeonRun.created_at.asc())
            )
        ).all()
    )

    collected_patrols: dict[str, AdventurePatrol] = {}
    for patrol in patrols:
        if patrol.encounter_code:
            collected_patrols.setdefault(patrol.encounter_code, patrol)

    patrol_items = []
    for route_code, encounters in PATROL_ENCOUNTERS.items():
        route = ROUTES[route_code]
        for encounter in encounters:
            patrol = collected_patrols.get(encounter["code"])
            discovered = patrol is not None
            detail = None
            if discovered and patrol.reaction_speaker and patrol.reaction_text:
                detail = f"{patrol.reaction_speaker} “{patrol.reaction_text}”"
            patrol_items.append(
                {
                    "kind": "patrol",
                    "code": encounter["code"],
                    "location_code": route_code,
                    "location_name": route["name"],
                    "discovered": discovered,
                    "title": patrol.encounter_title if discovered else None,
                    "text": patrol.encounter_text if discovered else None,
                    "detail": detail,
                    "discovered_at": (
                        to_utc_iso(patrol.claimed_at) if discovered else None
                    ),
                }
            )

    dungeon_items = []
    run_by_scene: dict[str, tuple[DungeonRun, str]] = {}
    for run, dungeon_code in dungeon_runs:
        if run.scene_code:
            run_by_scene.setdefault(run.scene_code, (run, dungeon_code))
    for dungeon_code, scenes in DUNGEON_SCENES.items():
        dungeon = DUNGEONS[dungeon_code]
        for scene in scenes:
            snapshot = run_by_scene.get(scene["code"])
            discovered = snapshot is not None
            run = snapshot[0] if snapshot else None
            detail = None
            if run is not None:
                approach_name = (
                    "차분히 둘러보기"
                    if run.approach_code == "steady"
                    else DUNGEON_APPROACHES.get(run.approach_code, {}).get(
                        "name", run.approach_code
                    )
                )
                outcome_name = (
                    "성장 공명" if run.outcome_code == "resonant" else "차분한 발견"
                )
                detail = f"{approach_name} · {outcome_name}"
            dungeon_items.append(
                {
                    "kind": "dungeon",
                    "code": scene["code"],
                    "location_code": dungeon_code,
                    "location_name": dungeon["name"],
                    "discovered": discovered,
                    "title": run.scene_title if run is not None else None,
                    "text": run.scene_text if run is not None else None,
                    "detail": detail,
                    "discovered_at": (
                        to_utc_iso(run.created_at) if run is not None else None
                    ),
                }
            )

    chapters = [
        {
            "code": "patrol_memories",
            "name": "순찰에서 주운 장면",
            "description": "온실 밖 네 길에서 캐릭터와 함께 발견한 작은 이야기",
            "collected_count": sum(item["discovered"] for item in patrol_items),
            "total_count": len(patrol_items),
            "items": patrol_items,
        },
        {
            "code": "dungeon_memories",
            "name": "문 너머에서 만난 장면",
            "description": "네 던전 안쪽에서 접근 방식을 골라 마주친 기록",
            "collected_count": sum(item["discovered"] for item in dungeon_items),
            "total_count": len(dungeon_items),
            "items": dungeon_items,
        },
    ]
    collected_count = sum(chapter["collected_count"] for chapter in chapters)
    total_count = sum(chapter["total_count"] for chapter in chapters)
    return {
        "collected_count": collected_count,
        "total_count": total_count,
        "completed": collected_count == total_count,
        "chapters": chapters,
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
    inventory = {row.item_code: row.quantity for row in inventory_rows}
    completed_research = set(
        (
            await db.execute(
                sa.select(UserAdventureResearch.project_code).where(
                    UserAdventureResearch.user_id == user_id
                )
            )
        ).scalars()
    )
    donation_key = _donation_reward_key(user_id, today)
    donation_used_today = (
        await db.scalar(
            sa.select(RewardEvent.id).where(
                RewardEvent.user_id == user_id,
                RewardEvent.dedupe_key == donation_key,
            )
        )
        is not None
    )
    donation = _donation_payload(
        inventory,
        completed_research,
        used_today=donation_used_today,
        suspended=suspended,
    )
    dungeon_research_bonus = sum(
        int(project["effect"]["amount"])
        for code, project in RESEARCH_PROJECTS.items()
        if code in completed_research and project["effect"]["context"] == "dungeon"
    )
    patrol_research_bonus = sum(
        int(project["effect"]["amount"])
        for code, project in RESEARCH_PROJECTS.items()
        if code in completed_research and project["effect"]["context"] == "patrol"
    )
    patrol_time_bonus = sum(
        int(project["effect"]["amount"])
        for code, project in RESEARCH_PROJECTS.items()
        if code in completed_research and project["effect"]["context"] == "patrol_time"
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
        "economy": [dict(row) for row in DAILY_ECONOMY],
        "weekly_board": await _weekly_board_payload(
            db,
            user_id,
            today,
            suspended=suspended,
        ),
        "milestones": await _milestone_progress_payload(
            db,
            user_id,
            completed_research,
        ),
        "donation": {
            key: value for key, value in donation.items() if key != "reserved_by_item"
        },
        "character": _character_payload(character),
        "routes": _route_payloads(
            character,
            patrol_research_bonus,
            patrol_time_bonus,
        ),
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
                "approaches": _dungeon_approach_payloads(
                    character,
                    dungeon,
                    dungeon_research_bonus,
                ),
            }
            for code, dungeon in DUNGEONS.items()
        ],
        "inventory": [
            {
                "code": row.item_code,
                "name": ITEMS.get(row.item_code, (row.item_code, ""))[0],
                "description": ITEMS.get(row.item_code, (row.item_code, ""))[1],
                "quantity": row.quantity,
                "reserved_quantity": min(
                    row.quantity,
                    donation["reserved_by_item"].get(row.item_code, 0),
                ),
                "donatable_quantity": max(
                    0,
                    row.quantity - donation["reserved_by_item"].get(row.item_code, 0),
                ),
                "can_donate": donation["available_today"]
                and row.quantity - donation["reserved_by_item"].get(row.item_code, 0)
                >= DONATION_REQUIRED_QUANTITY,
            }
            for row in inventory_rows
        ],
        "research_projects": _research_payloads(completed_research, inventory),
        "research_summary": {
            "completed_count": len(completed_research),
            "total_count": len(RESEARCH_PROJECTS),
            "chapter_completed": "outside_greenhouse_atlas" in completed_research,
            "chapter_name": "온실 밖 탐험 1장",
        },
        "journal": await _journal_payload(db, user_id, discovered),
        "story_collection": await _story_collection_payload(db, user_id),
    }


def _milestone_payload(progress_by_metric: dict[str, int]) -> dict:
    items = []
    for milestone in ADVENTURE_MILESTONES:
        progress = min(
            int(progress_by_metric.get(milestone["metric"], 0)),
            milestone["target"],
        )
        items.append(
            {
                "code": milestone["code"],
                "name": milestone["name"],
                "description": milestone["description"],
                "progress": progress,
                "target": milestone["target"],
                "unlocked": progress >= milestone["target"],
                "title": milestone["title"],
            }
        )
    unlocked = [item for item in items if item["unlocked"]]
    return {
        "current_title": unlocked[-1]["title"] if unlocked else "첫 발자국",
        "unlocked_count": len(unlocked),
        "total_count": len(items),
        "items": items,
    }


async def _milestone_progress_payload(
    db: AsyncSession,
    user_id: int,
    completed_research: set[str],
) -> dict:
    counts = (
        await db.execute(
            sa.select(
                sa.func.coalesce(
                    sa.func.sum(
                        sa.case(
                            (
                                RewardEvent.event_type
                                == RewardEventType.DIARY_FIRST_DAILY,
                                1,
                            ),
                            else_=0,
                        )
                    ),
                    0,
                ),
                sa.func.coalesce(
                    sa.func.sum(
                        sa.case(
                            (
                                RewardEvent.event_type
                                == RewardEventType.PATROL_CLAIMED,
                                1,
                            ),
                            else_=0,
                        )
                    ),
                    0,
                ),
                sa.func.coalesce(
                    sa.func.sum(
                        sa.case(
                            (
                                RewardEvent.event_type
                                == RewardEventType.DUNGEON_CLEARED,
                                1,
                            ),
                            else_=0,
                        )
                    ),
                    0,
                ),
            ).where(RewardEvent.user_id == user_id)
        )
    ).one()
    return _milestone_payload(
        {
            "diary_days": int(counts[0]),
            "patrol_returns": int(counts[1]),
            "dungeon_runs": int(counts[2]),
            "research_projects": len(completed_research),
            "chapter_completed": int("outside_greenhouse_atlas" in completed_research),
        }
    )


def _weekly_reward_key(user_id: int, week_start, goal_code: str) -> str:
    return f"adventure_weekly:{user_id}:{week_start.isoformat()}:{goal_code}"


async def _weekly_board_payload(
    db: AsyncSession,
    user_id: int,
    today,
    *,
    suspended: bool = False,
) -> dict:
    week_start = today - timedelta(days=today.weekday())
    next_week = week_start + timedelta(days=7)
    progress = {
        "diary_days": int(
            await db.scalar(
                sa.select(sa.func.count(sa.func.distinct(MoodEntry.local_date))).where(
                    MoodEntry.user_id == user_id,
                    MoodEntry.local_date >= week_start,
                    MoodEntry.local_date < next_week,
                    MoodEntry.content_length >= 50,
                )
            )
            or 0
        ),
        "claimed_patrols": int(
            await db.scalar(
                sa.select(sa.func.count(AdventurePatrol.id)).where(
                    AdventurePatrol.user_id == user_id,
                    AdventurePatrol.local_date >= week_start,
                    AdventurePatrol.local_date < next_week,
                    AdventurePatrol.status == "claimed",
                )
            )
            or 0
        ),
        "dungeon_runs": int(
            await db.scalar(
                sa.select(sa.func.count(DungeonRun.id)).where(
                    DungeonRun.user_id == user_id,
                    DungeonRun.local_date >= week_start,
                    DungeonRun.local_date < next_week,
                )
            )
            or 0
        ),
    }
    reward_keys = {
        code: _weekly_reward_key(user_id, week_start, code) for code in WEEKLY_GOALS
    }
    claimed_keys = set(
        (
            await db.execute(
                sa.select(RewardEvent.dedupe_key).where(
                    RewardEvent.user_id == user_id,
                    RewardEvent.dedupe_key.in_(tuple(reward_keys.values())),
                )
            )
        ).scalars()
    )
    goals = []
    for code, goal in WEEKLY_GOALS.items():
        current = progress[goal["metric"]]
        completed = current >= goal["target"]
        claimed = reward_keys[code] in claimed_keys
        goals.append(
            {
                "code": code,
                "name": goal["name"],
                "description": goal["description"],
                "progress": current,
                "target": goal["target"],
                "reward_exp": 0,
                "reward_seeds": goal["reward_seeds"],
                "completed": completed,
                "claimed": claimed,
                "can_claim": completed and not claimed and not suspended,
            }
        )
    return {
        "week_start": week_start.isoformat(),
        "week_end": (next_week - timedelta(days=1)).isoformat(),
        "goals": goals,
    }


async def claim_weekly_goal(
    db: AsyncSession,
    user_id: int,
    goal_code: str,
) -> dict:
    goal = WEEKLY_GOALS.get(goal_code)
    if goal is None:
        raise AppError(404, "WEEKLY_GOAL_NOT_FOUND", "주간 목표를 찾을 수 없습니다.")

    now = utcnow()
    today = local_date_of(now)
    if await game_service.safety_active_today(db, user_id, today):
        raise AppError(
            409,
            "ADVENTURE_SUSPENDED",
            "오늘은 탐험보다 마음 돌봄을 먼저 확인해 주세요.",
        )
    board = await _weekly_board_payload(db, user_id, today)
    goal_payload = next(item for item in board["goals"] if item["code"] == goal_code)
    if goal_payload["claimed"]:
        raise AppError(
            409,
            "WEEKLY_GOAL_ALREADY_CLAIMED",
            "이미 받은 주간 목표 보상이에요.",
        )
    if not goal_payload["completed"]:
        raise AppError(
            409,
            "WEEKLY_GOAL_INCOMPLETE",
            "주간 목표를 채운 뒤 보상을 받을 수 있어요.",
            {
                "progress": goal_payload["progress"],
                "target": goal_payload["target"],
            },
        )

    user = await lock_user(db, user_id)
    outcome = RewardOutcome(seed_balance=user.seed_balance)
    week_start = today - timedelta(days=today.weekday())
    granted = await grant(
        db,
        user,
        None,
        RewardEventType.ADVENTURE_WEEKLY,
        _weekly_reward_key(user_id, week_start, goal_code),
        "adventure_weekly",
        None,
        today,
        outcome,
        reward_amounts=(0, goal["reward_seeds"]),
    )
    if not granted:
        raise AppError(
            409,
            "WEEKLY_GOAL_ALREADY_CLAIMED",
            "이미 받은 주간 목표 보상이에요.",
        )
    await db.flush()
    return {
        "goal": {**goal_payload, "claimed": True, "can_claim": False},
        "reward": outcome.payload(),
        "state": await state_payload(db, user_id),
    }


def _donation_reward_key(user_id: int, today) -> str:
    return f"adventure_donation:{user_id}:{today.isoformat()}"


async def donate_adventure_item(
    db: AsyncSession,
    user_id: int,
    item_code: str,
) -> dict:
    if item_code not in ITEMS:
        raise AppError(
            404, "ADVENTURE_ITEM_NOT_FOUND", "기증할 표본을 찾을 수 없습니다."
        )

    now = utcnow()
    today = local_date_of(now)
    if await game_service.safety_active_today(db, user_id, today):
        raise AppError(
            409,
            "ADVENTURE_SUSPENDED",
            "오늘은 기증보다 마음 돌봄을 먼저 확인해 주세요.",
        )
    reward_key = _donation_reward_key(user_id, today)
    if await db.scalar(
        sa.select(RewardEvent.id).where(
            RewardEvent.user_id == user_id,
            RewardEvent.dedupe_key == reward_key,
        )
    ):
        raise AppError(
            409,
            "ADVENTURE_DONATION_DAILY_LIMIT",
            "오늘 표본 기증은 이미 마쳤어요.",
        )

    user = await lock_user(db, user_id)
    completed_research = set(
        (
            await db.execute(
                sa.select(UserAdventureResearch.project_code).where(
                    UserAdventureResearch.user_id == user_id
                )
            )
        ).scalars()
    )
    reserved_quantity = _reserved_research_materials(completed_research).get(
        item_code,
        0,
    )
    item = await db.scalar(
        sa.select(UserAdventureItem)
        .where(
            UserAdventureItem.user_id == user_id,
            UserAdventureItem.item_code == item_code,
        )
        .with_for_update()
    )
    current_quantity = item.quantity if item is not None else 0
    donatable_quantity = max(0, current_quantity - reserved_quantity)
    if item is None or donatable_quantity < DONATION_REQUIRED_QUANTITY:
        raise AppError(
            409,
            "ADVENTURE_DONATION_EXCESS_REQUIRED",
            "미완성 연구에 필요한 수량을 제외한 여분 표본이 부족해요.",
            {
                "item_code": item_code,
                "current_quantity": current_quantity,
                "reserved_quantity": min(current_quantity, reserved_quantity),
                "donatable_quantity": donatable_quantity,
                "required_quantity": DONATION_REQUIRED_QUANTITY,
            },
        )

    item.quantity -= DONATION_REQUIRED_QUANTITY
    item.updated_at = now
    outcome = RewardOutcome(seed_balance=user.seed_balance)
    granted = await grant(
        db,
        user,
        None,
        RewardEventType.ADVENTURE_DONATED,
        reward_key,
        "adventure_donation",
        item.id,
        today,
        outcome,
        reward_amounts=(0, DONATION_REWARD_SEEDS),
    )
    if not granted:
        raise AppError(
            409,
            "ADVENTURE_DONATION_DAILY_LIMIT",
            "오늘 표본 기증은 이미 마쳤어요.",
        )
    await db.flush()
    return {
        "donation": {
            "item_code": item_code,
            "item_name": ITEMS[item_code][0],
            "quantity": DONATION_REQUIRED_QUANTITY,
        },
        "reward": outcome.payload(),
        "state": await state_payload(db, user_id),
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
    research_bonus = await _research_bonus(db, user_id, "patrol")
    score, quantity = _performance(character, route["stats"], "patrol", research_bonus)
    time_bonus = await _research_bonus(db, user_id, "patrol_time")
    duration_minutes = max(5, route["duration_minutes"] - time_bonus)
    encounter = _patrol_encounter(user_id, today, route_code)
    reaction_form = character["form"]
    reaction_text = _patrol_reaction(user_id, today, route_code, reaction_form)
    patrol = AdventurePatrol(
        user_id=user_id,
        plant_id=character["plant"].id,
        route_code=route_code,
        local_date=today,
        status="active",
        started_at=now,
        returns_at=now + timedelta(minutes=duration_minutes),
        reward_exp=0,
        reward_seeds=3,
        discovery_code=route["discovery_code"],
        encounter_code=encounter["code"],
        encounter_title=encounter["title"],
        encounter_text=encounter["text"],
        reaction_form=reaction_form,
        reaction_speaker=character["plant"].name,
        reaction_text=reaction_text,
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
    encounter = _claimed_encounter_payload(patrol)
    reaction = encounter.get("reaction") if encounter else None
    return {
        "patrol": _patrol_payload(patrol, now),
        "reward": outcome.payload(),
        "discovery": {"code": patrol.discovery_code, "is_new": discovery_new},
        "encounter": encounter,
        "outcome_message": (
            (
                f"{encounter['title']}: {encounter['text']}\n"
                f"{reaction['speaker']}: “{reaction['text']}”"
                if reaction
                else f"{encounter['title']}: {encounter['text']}"
            )
            if encounter
            else None
        ),
        "state": await state_payload(db, user_id),
    }


async def run_dungeon(
    db: AsyncSession,
    user_id: int,
    dungeon_code: str,
    approach_code: str | None = None,
) -> dict:
    now = utcnow()
    today = local_date_of(now)
    await _require_available_day(db, user_id, today)
    dungeon = DUNGEONS.get(dungeon_code)
    if dungeon is None:
        raise AppError(404, "DUNGEON_NOT_FOUND", "던전을 찾을 수 없습니다.")
    approach = DUNGEON_APPROACHES.get(approach_code) if approach_code else None
    if approach_code is not None and approach is None:
        raise AppError(
            404,
            "DUNGEON_APPROACH_NOT_FOUND",
            "선택한 탐험 방식을 찾을 수 없습니다.",
        )
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
    research_bonus = await _research_bonus(db, user_id, "dungeon")
    if approach is None:
        score, quantity = _performance(
            character, dungeon["stats"], "dungeon", research_bonus
        )
        resolved_approach_code = "steady"
        approach_stat = None
        outcome_code = "steady"
        result_message = (
            f"차분히 길을 살펴 {ITEMS[dungeon['item_code']][0]} "
            f"{quantity}개를 찾았어요."
        )
    else:
        score, quantity, outcome_code = _dungeon_approach_performance(
            character,
            dungeon,
            approach,
            research_bonus,
        )
        resolved_approach_code = approach_code
        approach_stat = approach["stat"]
        if outcome_code == "resonant":
            result_message = (
                f"{STAT_LABELS[approach_stat]} 성장이 이 길과 맞아 "
                f"{ITEMS[dungeon['item_code']][0]} {quantity}개를 꼼꼼히 찾았어요."
            )
        else:
            result_message = (
                f"{approach['name']} 방식으로 길을 살펴 "
                f"{ITEMS[dungeon['item_code']][0]} {quantity}개를 찾았어요."
            )
    scene = _dungeon_scene(
        user_id,
        today,
        dungeon_code,
        resolved_approach_code,
    )
    outcome_message = f"{scene['title']}: {scene['text']}\n{result_message}"
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
        approach_code=resolved_approach_code,
        approach_stat=approach_stat,
        outcome_code=outcome_code,
        scene_code=scene["code"],
        scene_title=scene["title"],
        scene_text=scene["text"],
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
            "approach_code": run.approach_code,
            "approach_stat": run.approach_stat,
            "outcome_code": run.outcome_code,
            "scene": _dungeon_scene_payload(run),
            "outcome_message": outcome_message,
        },
        "reward": outcome.payload(),
        "state": await state_payload(db, user_id),
    }


async def complete_research(db: AsyncSession, user_id: int, project_code: str) -> dict:
    project = RESEARCH_PROJECTS.get(project_code)
    if project is None:
        raise AppError(
            404,
            "RESEARCH_PROJECT_NOT_FOUND",
            "표본 연구 항목을 찾을 수 없습니다.",
        )
    completed = await db.scalar(
        sa.select(UserAdventureResearch)
        .where(
            UserAdventureResearch.user_id == user_id,
            UserAdventureResearch.project_code == project_code,
        )
        .with_for_update()
    )
    if completed is not None:
        raise AppError(409, "RESEARCH_ALREADY_COMPLETED", "이미 완성한 연구예요.")

    required_codes = tuple(project["requirements"])
    rows = list(
        (
            await db.execute(
                sa.select(UserAdventureItem)
                .where(
                    UserAdventureItem.user_id == user_id,
                    UserAdventureItem.item_code.in_(required_codes),
                )
                .with_for_update()
            )
        ).scalars()
    )
    inventory = {row.item_code: row for row in rows}
    missing = [
        {
            "code": item_code,
            "name": ITEMS[item_code][0],
            "current": inventory[item_code].quantity if item_code in inventory else 0,
            "required": required,
        }
        for item_code, required in project["requirements"].items()
        if item_code not in inventory or inventory[item_code].quantity < required
    ]
    if missing:
        raise AppError(
            409,
            "RESEARCH_MATERIALS_REQUIRED",
            "연구를 완성하려면 탐험 재료가 더 필요해요.",
            {"missing": missing},
        )

    now = utcnow()
    for item_code, required in project["requirements"].items():
        inventory[item_code].quantity -= required
        inventory[item_code].updated_at = now
    db.add(
        UserAdventureResearch(
            user_id=user_id,
            project_code=project_code,
            completed_at=now,
        )
    )
    await db.flush()
    return {
        "research": {
            "code": project_code,
            "name": project["name"],
            "effect": project["effect"],
        },
        "state": await state_payload(db, user_id),
    }
