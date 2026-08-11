"""성장 캐릭터 12종과 프리미엄 지원가 카탈로그 연결

Revision ID: 0032_combat_roster
Revises: 0031_stage_progress
Create Date: 2026-08-11
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op


revision = "0032_combat_roster"
down_revision = "0031_stage_progress"
branch_labels = None
depends_on = None


ROSTER = (
    ("baby-pot", "아기 화분 뽀또", "pure_sprout", 1, 0, "guardian_support"),
    ("handsome-pot", "냉미남 화분 로제온", "quiet_commander", 2, 50, "tempo_striker"),
    ("pretty-pot", "센터 아이돌 블루미", "stage_idol", 2, 50, "stage_healer"),
    ("tsundere-pot", "선인장 츤데레 가시로", "prickly_partner", 3, 80, "counter_tank"),
    ("zombie-pot", "좀비 화분 시들잎", "undying_sprout", 3, 90, "last_stand"),
    ("gumiho-pot", "구미호 여우비", "fox_trickster", 4, 120, "charm_controller"),
    ("ninja-pot", "닌자 그림싹", "shadow_scout", 4, 120, "weakness_assassin"),
    ("student-pot", "학생회장 하루", "student_leader", 4, 130, "focus_engine"),
    ("magical-pot", "마법사 별솔", "arcane_prodigy", 5, 150, "prism_burst"),
    ("aloof-pot", "서리동백 설화", "frost_rival", 5, 180, "steady_controller"),
    (
        "maestro-pot",
        "공명 지휘자 세렌",
        "resonance_maestro",
        5,
        240,
        "resonance_director",
    ),
    ("nurse-pot", "백의 수호사 백화", "white_guardian", 5, 280, "premium_healer"),
)

CHARACTER_SPECIES = {
    "character_baby_pot": "baby-pot",
    "character_handsome_pot": "handsome-pot",
    "character_pretty_pot": "pretty-pot",
    "character_tsundere_pot": "tsundere-pot",
    "character_zombie_pot": "zombie-pot",
    "character_gumiho_pot": "gumiho-pot",
    "character_ninja_pot": "ninja-pot",
    "character_student_pot": "student-pot",
    "character_magical_pot": "magical-pot",
    "character_aloof_pot": "aloof-pot",
    "character_maestro_pot": "maestro-pot",
    "character_nurse_pot": "nurse-pot",
}

NEW_CHARACTER_ROWS = (
    {
        "code": "character_maestro_pot",
        "type": "main_character",
        "name": "공명 지휘자 세렌",
        "description": "한 번의 첫박으로 아군을 끌어올리고 마지막 박자로 적의 흐름을 끊는 최상급 지휘자",
        "price_seeds": 240,
        "rarity": 5,
        "asset_manifest": {
            "asset_key": "characters/maestro-pot",
            "asset_version": 4,
            "species_code": "maestro-pot",
            "personality": "차분한 눈빛으로 전장의 박자를 지배하는 공명 지휘자",
            "catchphrase": "서두르지 마. 승리할 박자는 내가 정할게.",
            "motion_key": "maestro_cue",
            "palette": ["#F5ECEA", "#17131F", "#35203F", "#9A6C86"],
            "accent": "#7D4D75",
            "combat_role": "resonance_director",
            "story_role": "잊힌 감정의 파장을 악보로 되살리는 밤의 지휘자",
            "lore_hook": "감정이 소음으로 뒤엉킨 날에도 단 하나의 진짜 박자를 찾아낸다.",
            "collection_quote": "침묵도 음악이야. 네 마음이 다시 시작할 자리를 남겨 주니까.",
            "base_outfit": {
                "key": "midnight-resonance",
                "name": "미드나잇 레조넌스",
                "rarity": 5,
                "included_with_character": True,
            },
        },
        "is_active": True,
    },
    {
        "code": "character_nurse_pot",
        "type": "main_character",
        "name": "백의 수호사 백화",
        "description": "위기의 생명선을 다시 잇고 성장하면 쓰러진 동료까지 깨우는 최고 등급의 전담 힐러",
        "price_seeds": 280,
        "rarity": 5,
        "asset_manifest": {
            "asset_key": "characters/nurse-pot",
            "asset_version": 4,
            "species_code": "nurse-pot",
            "personality": "부드럽지만 단호하게 모두의 생명선을 지키는 성숙한 수호사",
            "catchphrase": "괜찮아. 내가 있는 동안 누구도 혼자 쓰러지게 두지 않아.",
            "motion_key": "nurse_breathe",
            "palette": ["#FAF4F0", "#2A151D", "#F2D5D1", "#B97570"],
            "accent": "#C77872",
            "combat_role": "premium_healer",
            "story_role": "상처 난 기억을 백색 정원에서 돌보는 최상위 수호사",
            "lore_hook": "고장 난 감정의 생명선을 앰플 하나로 다시 피워 낸다는 소문이 있다.",
            "collection_quote": "아픈 마음은 약한 마음이 아니야. 오래 버텨 온 마음이지.",
            "base_outfit": {
                "key": "white-triage",
                "name": "순백 트리아주",
                "rarity": 5,
                "included_with_character": True,
            },
        },
        "is_active": True,
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


def _growth_manifest(code: str, role: str, rarity: int) -> dict:
    return {
        "growth": {
            "seed_shape": f"{code}-signature-seed",
            "vessel_style": "premium_glass_vessel"
            if rarity >= 5
            else "character_vessel",
            "rarity_effect": "restrained_edge_light"
            if rarity >= 4
            else "soft_growth_motes",
            "asset_namespace": f"plants/{code}",
        },
        "combat": {"role": role, "kit_version": 7},
    }


def upgrade() -> None:
    bind = op.get_bind()
    species = _species_table()
    items = _items_table()

    for code, name, persona, rarity, price, role in ROSTER:
        existing = (
            bind.execute(
                sa.select(species.c.id, species.c.asset_manifest).where(
                    species.c.code == code
                )
            )
            .mappings()
            .first()
        )
        manifest = dict(existing["asset_manifest"] or {}) if existing else {}
        manifest.update(_growth_manifest(code, role, rarity))
        values = {
            "code": code,
            "name": name,
            "persona_key": persona,
            "asset_manifest": manifest,
            "rarity": rarity,
            "unlock_price": price,
        }
        if existing:
            bind.execute(
                sa.update(species)
                .where(species.c.id == existing["id"])
                .values(**values)
            )
        else:
            bind.execute(sa.insert(species).values(**values))

    existing_item_codes = set(
        bind.execute(
            sa.select(items.c.code).where(items.c.code.in_(CHARACTER_SPECIES))
        ).scalars()
    )
    for row in NEW_CHARACTER_ROWS:
        if row["code"] not in existing_item_codes:
            bind.execute(sa.insert(items).values(**row))

    item_rows = bind.execute(
        sa.select(items.c.id, items.c.code, items.c.asset_manifest).where(
            items.c.code.in_(CHARACTER_SPECIES)
        )
    ).mappings()
    for row in item_rows:
        manifest = dict(row["asset_manifest"] or {})
        species_code = CHARACTER_SPECIES[row["code"]]
        manifest["species_code"] = species_code
        manifest["growth_asset_namespace"] = f"plants/{species_code}"
        bind.execute(
            sa.update(items)
            .where(items.c.id == row["id"])
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
    for item_code, species_code in CHARACTER_SPECIES.items():
        item_id = bind.execute(
            sa.select(items.c.id).where(items.c.code == item_code)
        ).scalar_one_or_none()
        species_id = bind.execute(
            sa.select(species.c.id).where(species.c.code == species_code)
        ).scalar_one_or_none()
        if item_id is None or species_id is None:
            continue
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
    new_codes = tuple(row["code"] for row in NEW_CHARACTER_ROWS)
    new_item_ids = tuple(
        bind.execute(sa.select(items.c.id).where(items.c.code.in_(new_codes))).scalars()
    )
    if new_item_ids:
        user_items = sa.table(
            "user_items",
            sa.column("id", sa.BigInteger),
            sa.column("item_id", sa.BigInteger),
        )
        bind.execute(
            sa.delete(user_items).where(user_items.c.item_id.in_(new_item_ids))
        )
        bind.execute(sa.delete(items).where(items.c.id.in_(new_item_ids)))

    rows = bind.execute(
        sa.select(items.c.id, items.c.asset_manifest).where(
            items.c.code.in_(
                tuple(code for code in CHARACTER_SPECIES if code not in new_codes)
            )
        )
    ).mappings()
    for row in rows:
        manifest = dict(row["asset_manifest"] or {})
        manifest.pop("species_code", None)
        manifest.pop("growth_asset_namespace", None)
        bind.execute(
            sa.update(items)
            .where(items.c.id == row["id"])
            .values(asset_manifest=manifest)
        )

    roster_codes = tuple(row[0] for row in ROSTER)
    species_ids = tuple(
        bind.execute(
            sa.select(species.c.id).where(species.c.code.in_(roster_codes))
        ).scalars()
    )
    if species_ids:
        plants = sa.table("plants", sa.column("species_id", sa.BigInteger))
        used_species_ids = set(
            bind.execute(
                sa.select(plants.c.species_id)
                .where(plants.c.species_id.in_(species_ids))
                .distinct()
            ).scalars()
        )
        removable_species_ids = tuple(
            species_id
            for species_id in species_ids
            if species_id not in used_species_ids
        )
        unlocks = sa.table(
            "user_species_unlocks", sa.column("species_id", sa.BigInteger)
        )
        if removable_species_ids:
            bind.execute(
                sa.delete(unlocks).where(
                    unlocks.c.species_id.in_(removable_species_ids)
                )
            )
            bind.execute(
                sa.delete(species).where(species.c.id.in_(removable_species_ids))
            )
