"""프리미엄 지원가의 서사와 v6 캐릭터 원화 계약

Revision ID: 0033_premium_story_v6
Revises: 0032_combat_roster
Create Date: 2026-08-12
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op


revision = "0033_premium_story_v6"
down_revision = "0032_combat_roster"
branch_labels = None
depends_on = None


V6_STORIES = {
    "character_nurse_pot": {
        "description": (
            "백색 정원의 붕괴에서 한 사람을 잃은 뒤 누구도 아픈 동안 혼자 두지 "
            "않겠다고 선서한 최고 등급의 전담 수호사"
        ),
        "asset_version": 6,
        "personality": "포근하게 다가오되 위기 앞에서는 누구보다 단호한 백색 정원의 야간 수호사",
        "story_role": "끊어진 감정의 생명선을 다시 잇는 백색 정원의 마지막 수호사",
        "lore_hook": (
            "감정을 지우는 대신 버틸 힘이 남은 기억을 봉합해 다시 일어설 한 번의 "
            "호흡을 만든다."
        ),
        "collection_quote": "아픈 마음은 약한 마음이 아니야. 오래 버텨 온 마음이지.",
        "visual_story": {
            "shape_language": "soft_curves",
            "hair": "pearl_champagne_long_wave",
            "silhouette": "asymmetric_white_field_coat",
            "prop": "ampoule_suture_injector",
        },
    },
    "character_maestro_pot": {
        "description": (
            "완벽한 합주를 무너뜨린 뒤 침묵의 가치를 배워 아군의 다음 박자를 "
            "설계하는 최상급 공명 지휘자"
        ),
        "asset_version": 6,
        "personality": "말수는 적지만 동료의 호흡이 돌아올 때까지 자기 박자를 늦추는 공명 지휘자",
        "story_role": "위험한 감정 소음을 끊고 다시 시작할 쉼표를 만드는 야상 공명홀의 지휘자",
        "lore_hook": (
            "가장 위험한 소음만 한 박자 끊어 모두가 자기 리듬으로 움직일 틈을 "
            "만든다."
        ),
        "collection_quote": "침묵도 음악이야. 다시 시작할 자리를 남겨 주니까.",
        "visual_story": {
            "shape_language": "sharp_angles",
            "hair": "ink_violet_blunt_bob",
            "silhouette": "sleeveless_tailored_long_tail",
            "prop": "ebony_baton",
        },
    },
}


PREVIOUS_STORIES = {
    "character_nurse_pot": {
        "description": "위기의 생명선을 다시 잇고 성장하면 쓰러진 동료까지 깨우는 최고 등급의 전담 힐러",
        "asset_version": 4,
        "personality": "부드럽지만 단호하게 모두의 생명선을 지키는 성숙한 수호사",
        "story_role": "상처 난 기억을 백색 정원에서 돌보는 최상위 수호사",
        "lore_hook": "고장 난 감정의 생명선을 앰플 하나로 다시 피워 낸다는 소문이 있다.",
        "collection_quote": "아픈 마음은 약한 마음이 아니야. 오래 버텨 온 마음이지.",
    },
    "character_maestro_pot": {
        "description": "한 번의 첫박으로 아군을 끌어올리고 마지막 박자로 적의 흐름을 끊는 최상급 지휘자",
        "asset_version": 4,
        "personality": "차분한 눈빛으로 전장의 박자를 지배하는 공명 지휘자",
        "story_role": "잊힌 감정의 파장을 악보로 되살리는 밤의 지휘자",
        "lore_hook": "감정이 소음으로 뒤엉킨 날에도 단 하나의 진짜 박자를 찾아낸다.",
        "collection_quote": "침묵도 음악이야. 네 마음이 다시 시작할 자리를 남겨 주니까.",
    },
}


def _items_table() -> sa.TableClause:
    return sa.table(
        "items",
        sa.column("id", sa.BigInteger),
        sa.column("code", sa.String),
        sa.column("description", sa.String),
        sa.column("asset_manifest", sa.JSON),
    )


def _species_table() -> sa.TableClause:
    return sa.table(
        "plant_species",
        sa.column("id", sa.BigInteger),
        sa.column("code", sa.String),
        sa.column("asset_manifest", sa.JSON),
    )


def _apply(stories: dict[str, dict], *, remove_visual_story: bool) -> None:
    bind = op.get_bind()
    items = _items_table()
    species = _species_table()
    species_by_item = {
        "character_nurse_pot": "nurse-pot",
        "character_maestro_pot": "maestro-pot",
    }

    rows = bind.execute(
        sa.select(items.c.id, items.c.code, items.c.asset_manifest).where(
            items.c.code.in_(tuple(stories))
        )
    ).mappings()
    for row in rows:
        story = stories[row["code"]]
        manifest = dict(row["asset_manifest"] or {})
        for key in (
            "asset_version",
            "personality",
            "story_role",
            "lore_hook",
            "collection_quote",
        ):
            manifest[key] = story[key]
        if remove_visual_story:
            manifest.pop("visual_story", None)
        else:
            manifest["visual_story"] = story["visual_story"]
        bind.execute(
            sa.update(items)
            .where(items.c.id == row["id"])
            .values(description=story["description"], asset_manifest=manifest)
        )

        species_code = species_by_item[row["code"]]
        species_row = bind.execute(
            sa.select(species.c.id, species.c.asset_manifest).where(
                species.c.code == species_code
            )
        ).mappings().first()
        if species_row is None:
            continue
        species_manifest = dict(species_row["asset_manifest"] or {})
        growth = dict(species_manifest.get("growth") or {})
        if remove_visual_story:
            growth.pop("character_art_version", None)
        else:
            growth["character_art_version"] = 6
        species_manifest["growth"] = growth
        bind.execute(
            sa.update(species)
            .where(species.c.id == species_row["id"])
            .values(asset_manifest=species_manifest)
        )


def upgrade() -> None:
    _apply(V6_STORIES, remove_visual_story=False)


def downgrade() -> None:
    _apply(PREVIOUS_STORIES, remove_visual_story=True)
