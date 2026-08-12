"""성장 캐릭터 3종과 v8 전투 키트 연결

Revision ID: 0034_character_expansion_v7
Revises: 0033_premium_story_v6
Create Date: 2026-08-12
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op


revision = "0034_character_expansion_v7"
down_revision = "0033_premium_story_v6"
branch_labels = None
depends_on = None


NEW_CHARACTERS = (
    {
        "species_code": "restorer-pot",
        "species_name": "황혼 복원사 에단",
        "persona_key": "patient_restorer",
        "role": "patina_warden",
        "rarity": 5,
        "price": 260,
        "item_code": "character_restorer_pot",
        "description": "흔적을 지우지 않고 금빛 이음새로 다시 잇는 중년 수호·제어 복원사",
        "personality": "서두르지 않고 상처가 버텨 온 모양까지 살피는 노련한 복원사",
        "catchphrase": "흔적은 지우지 않아. 다시 이어 주지.",
        "motion_key": "restorer_settle",
        "palette": ["#F4E6D7", "#718698", "#3E3B39", "#7A5B45"],
        "story_role": "깨진 감정 기록을 금빛 이음새로 되살리는 황혼 공방의 수석 복원사",
        "lore_hook": "완벽하게 감춘 흉터보다 다시 견딜 수 있게 이은 흔적을 더 귀하게 여긴다.",
        "collection_quote": "시간은 상처를 없애지 않아. 견딘 모양을 남겨 주지.",
        "outfit_key": "bluegray-restorer-workwear",
        "outfit_name": "블루그레이 복원 워크웨어",
        "age_progression": ["seed", "boy_8", "teen_boy_15", "man_28", "man_40"],
    },
    {
        "species_code": "marten-pot",
        "species_name": "잎귀 담비 모루",
        "persona_key": "trail_marten",
        "role": "trail_vanguard",
        "rarity": 4,
        "price": 170,
        "item_code": "character_marten_pot",
        "description": "발자국과 체온으로 길을 기억하며 약점 추격과 무리 보호를 오가는 숲담비",
        "personality": "귀엽지만 스스로 길과 동료를 선택하는 호기심 많은 둥지지기",
        "catchphrase": "모루가 먼저 가. 이 냄새, 집으로 이어져!",
        "motion_key": "marten_scout",
        "palette": ["#684837", "#E8D6B6", "#3F7F70", "#D39857"],
        "story_role": "길을 잃은 마음 앞에 먼저 귀가 발자국을 남기는 숲의 둥지지기",
        "lore_hook": "폭풍에 흩어진 가족의 발소리를 기억해 어떤 길에서도 돌아갈 냄새를 찾는다.",
        "collection_quote": "모루가 먼저 가. 이 냄새, 집으로 이어져.",
        "outfit_key": "leaf-trail-harness",
        "outfit_name": "잎길 탐험 하네스",
        "age_progression": ["seed", "cub_3m", "juvenile_9m", "young_2y", "guardian_5y"],
    },
    {
        "species_code": "gal-pot",
        "species_name": "스타일 메이커 리아",
        "persona_key": "patchwork_gal",
        "role": "runway_catalyst",
        "rarity": 5,
        "price": 320,
        "item_code": "character_gal_pot",
        "description": "좋아하는 색과 천 조각을 엮어 약점과 동료의 다음 움직임을 바꾸는 공격 촉매",
        "personality": "유행을 규칙이 아닌 자기표현의 언어로 다루는 자신감 있는 스타일 메이커",
        "catchphrase": "좋아하는 걸 숨기지 마. 그게 오늘 제일 강해.",
        "motion_key": "gal_style_step",
        "palette": ["#F8EDE3", "#E68273", "#454143", "#ECE5D8"],
        "story_role": "탐험대의 감정색을 즉석에서 전투복으로 엮는 패치워크 스타일 메이커",
        "lore_hook": "남들이 버린 색과 천을 모아 친구가 가장 자신 있게 움직일 한 벌을 만든다.",
        "collection_quote": "좋아하는 걸 숨기지 마. 그게 오늘 제일 강한 컬러야.",
        "outfit_key": "coral-lingerie-work",
        "outfit_name": "코랄 란제리 워크 스트리트",
        "age_progression": ["seed", "girl_8", "teen_girl_14", "woman_20", "woman_23"],
    },
)


def _species_table() -> sa.TableClause:
    return sa.table(
        "plant_species",
        sa.column("id", sa.BigInteger),
        sa.column("code", sa.String),
        sa.column("name", sa.String),
        sa.column("persona_key", sa.String),
        sa.column("asset_manifest", sa.JSON),
        sa.column("rarity", sa.SmallInteger),
        sa.column("unlock_price", sa.Integer),
    )


def _items_table() -> sa.TableClause:
    return sa.table(
        "items",
        sa.column("id", sa.BigInteger),
        sa.column("code", sa.String),
        sa.column("type", sa.String),
        sa.column("name", sa.String),
        sa.column("description", sa.String),
        sa.column("price_seeds", sa.Integer),
        sa.column("rarity", sa.SmallInteger),
        sa.column("asset_manifest", sa.JSON),
        sa.column("is_active", sa.Boolean),
    )


def _species_manifest(character: dict) -> dict:
    code = character["species_code"]
    return {
        "growth": {
            "seed_shape": f"{code}-signature-seed",
            "vessel_style": "premium_glass_vessel"
            if character["rarity"] >= 5
            else "character_vessel",
            "rarity_effect": "restrained_edge_light",
            "asset_namespace": f"plants/{code}",
            "character_art_version": 7,
            "age_progression": character["age_progression"],
        },
        "combat": {"role": character["role"], "kit_version": 8},
    }


def _item_manifest(character: dict) -> dict:
    code = character["species_code"]
    return {
        "asset_key": f"characters/{code}",
        "asset_version": 7,
        "species_code": code,
        "growth_asset_namespace": f"plants/{code}",
        "personality": character["personality"],
        "catchphrase": character["catchphrase"],
        "motion_key": character["motion_key"],
        "palette": character["palette"],
        "accent": character["palette"][2],
        "combat_role": character["role"],
        "story_role": character["story_role"],
        "lore_hook": character["lore_hook"],
        "collection_quote": character["collection_quote"],
        "base_outfit": {
            "key": character["outfit_key"],
            "name": character["outfit_name"],
            "rarity": character["rarity"],
            "included_with_character": True,
        },
    }


def upgrade() -> None:
    bind = op.get_bind()
    species = _species_table()
    items = _items_table()

    for character in NEW_CHARACTERS:
        code = character["species_code"]
        existing_species = (
            bind.execute(
                sa.select(species.c.id, species.c.asset_manifest).where(
                    species.c.code == code
                )
            )
            .mappings()
            .first()
        )
        species_manifest = (
            dict(existing_species["asset_manifest"] or {}) if existing_species else {}
        )
        species_manifest.update(_species_manifest(character))
        species_values = {
            "code": code,
            "name": character["species_name"],
            "persona_key": character["persona_key"],
            "asset_manifest": species_manifest,
            "rarity": character["rarity"],
            "unlock_price": character["price"],
        }
        if existing_species:
            bind.execute(
                sa.update(species)
                .where(species.c.id == existing_species["id"])
                .values(**species_values)
            )
        else:
            bind.execute(sa.insert(species).values(**species_values))

        existing_item = bind.execute(
            sa.select(items.c.id).where(items.c.code == character["item_code"])
        ).scalar_one_or_none()
        item_values = {
            "code": character["item_code"],
            "type": "main_character",
            "name": character["species_name"],
            "description": character["description"],
            "price_seeds": character["price"],
            "rarity": character["rarity"],
            "asset_manifest": _item_manifest(character),
            "is_active": True,
        }
        if existing_item is None:
            bind.execute(sa.insert(items).values(**item_values))
        else:
            bind.execute(
                sa.update(items)
                .where(items.c.id == existing_item)
                .values(**item_values)
            )

    # 전투 응답 자체가 v8이므로 기존 12종의 저장 메타도 같은 버전으로 맞춘다.
    rows = bind.execute(
        sa.select(species.c.id, species.c.asset_manifest).where(
            species.c.code.like("%-pot")
        )
    ).mappings()
    for row in rows:
        manifest = dict(row["asset_manifest"] or {})
        combat = dict(manifest.get("combat") or {})
        combat["kit_version"] = 8
        manifest["combat"] = combat
        bind.execute(
            sa.update(species)
            .where(species.c.id == row["id"])
            .values(asset_manifest=manifest)
        )

    user_items = sa.table(
        "user_items",
        sa.column("user_id", sa.BigInteger),
        sa.column("item_id", sa.BigInteger),
    )
    unlocks = sa.table(
        "user_species_unlocks",
        sa.column("user_id", sa.BigInteger),
        sa.column("species_id", sa.BigInteger),
        sa.column("unlocked_at", sa.DateTime),
    )
    for character in NEW_CHARACTERS:
        item_id = bind.execute(
            sa.select(items.c.id).where(items.c.code == character["item_code"])
        ).scalar_one()
        species_id = bind.execute(
            sa.select(species.c.id).where(species.c.code == character["species_code"])
        ).scalar_one()
        already_unlocked = sa.exists(
            sa.select(1)
            .select_from(unlocks)
            .where(
                unlocks.c.user_id == user_items.c.user_id,
                unlocks.c.species_id == species_id,
            )
        )
        bind.execute(
            sa.insert(unlocks).from_select(
                ["user_id", "species_id", "unlocked_at"],
                sa.select(
                    user_items.c.user_id,
                    sa.literal(species_id),
                    sa.func.current_timestamp(),
                ).where(user_items.c.item_id == item_id, ~already_unlocked),
            )
        )


def downgrade() -> None:
    bind = op.get_bind()
    species = _species_table()
    items = _items_table()
    new_item_codes = tuple(item["item_code"] for item in NEW_CHARACTERS)
    new_species_codes = tuple(item["species_code"] for item in NEW_CHARACTERS)

    item_ids = tuple(
        bind.execute(
            sa.select(items.c.id).where(items.c.code.in_(new_item_codes))
        ).scalars()
    )
    if item_ids:
        user_items = sa.table(
            "user_items",
            sa.column("id", sa.BigInteger),
            sa.column("item_id", sa.BigInteger),
        )
        bind.execute(sa.delete(user_items).where(user_items.c.item_id.in_(item_ids)))
        bind.execute(sa.delete(items).where(items.c.id.in_(item_ids)))

    species_rows = bind.execute(
        sa.select(species.c.id, species.c.code).where(
            species.c.code.in_(new_species_codes)
        )
    ).mappings()
    species_ids = {row["code"]: row["id"] for row in species_rows}
    if species_ids:
        plants = sa.table("plants", sa.column("species_id", sa.BigInteger))
        used_ids = set(
            bind.execute(
                sa.select(plants.c.species_id)
                .where(plants.c.species_id.in_(tuple(species_ids.values())))
                .distinct()
            ).scalars()
        )
        removable_ids = tuple(
            species_id
            for species_id in species_ids.values()
            if species_id not in used_ids
        )
        if removable_ids:
            unlocks = sa.table(
                "user_species_unlocks", sa.column("species_id", sa.BigInteger)
            )
            bind.execute(
                sa.delete(unlocks).where(unlocks.c.species_id.in_(removable_ids))
            )
            bind.execute(sa.delete(species).where(species.c.id.in_(removable_ids)))

    # 남은 기존 계보는 이전 전투 키트 버전으로 되돌린다.
    rows = bind.execute(
        sa.select(species.c.id, species.c.asset_manifest).where(
            species.c.code.like("%-pot")
        )
    ).mappings()
    for row in rows:
        manifest = dict(row["asset_manifest"] or {})
        combat = dict(manifest.get("combat") or {})
        combat["kit_version"] = 7
        manifest["combat"] = combat
        bind.execute(
            sa.update(species)
            .where(species.c.id == row["id"])
            .values(asset_manifest=manifest)
        )
