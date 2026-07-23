import json
import re
import runpy
import sqlite3
from pathlib import Path

from alembic import command
from alembic.config import Config

from app.core.config import get_settings


def test_content_docs_match_catalog_copy():
    server_dir = Path(__file__).resolve().parents[2]
    repository_dir = server_dir.parent
    migration = runpy.run_path(
        str(
            server_dir
            / "alembic"
            / "versions"
            / "20260714_0009_content_copy_refresh.py"
        )
    )
    content_doc = (repository_dir / "docs" / "content_strategy.md").read_text(
        encoding="utf-8"
    )

    for title, description in migration["QUEST_COPY"].values():
        assert title in content_doc
        assert description in content_doc
    for lore_hook, collection_quote in migration["CHARACTER_STORY_COPY"].values():
        assert lore_hook in content_doc
        assert collection_quote in content_doc

    plant_source = (
        repository_dir
        / "app"
        / "lib"
        / "features"
        / "gallery"
        / "domain"
        / "harvested_plant.dart"
    ).read_text(encoding="utf-8")
    plant_descriptions = re.findall(r"description: '([^']+)'", plant_source)[:6]
    assert len(plant_descriptions) == 6
    for description in plant_descriptions:
        assert description in content_doc


def test_content_copy_refresh_updates_existing_catalog_without_metadata_drift(
    tmp_path, monkeypatch
):
    database_path = tmp_path / "content-copy-refresh.db"
    monkeypatch.setenv(
        "DATABASE_URL", f"sqlite+aiosqlite:///{database_path.as_posix()}"
    )
    get_settings.cache_clear()

    server_dir = Path(__file__).resolve().parents[2]
    config = Config(str(server_dir / "alembic.ini"))
    config.set_main_option("script_location", str(server_dir / "alembic"))

    try:
        command.upgrade(config, "0008_character_voice")
        with sqlite3.connect(database_path) as connection:
            seeded_copy = connection.execute(
                "SELECT code, title, description FROM quests ORDER BY code"
            ).fetchall()
            seeded_manifest = json.loads(
                connection.execute(
                    "SELECT asset_manifest FROM items "
                    "WHERE code = 'character_gumiho_pot'"
                ).fetchone()[0]
            )
            quest_metadata = {
                row[0]: row[1:]
                for row in connection.execute(
                    """
                    SELECT code, trigger_rule, category, burden_level,
                           estimated_minutes, safety_tags, reward_exp,
                           reward_seeds, is_active
                    FROM quests
                    """
                ).fetchall()
            }
            connection.execute(
                "UPDATE quests SET title = 'legacy title', "
                "description = 'legacy description'"
            )
            manifest = json.loads(
                connection.execute(
                    "SELECT asset_manifest FROM items "
                    "WHERE code = 'character_gumiho_pot'"
                ).fetchone()[0]
            )
            manifest.update(
                {
                    "lore_hook": "아홉 꼬리마다 서로 다른 마음의 비밀을 하나씩 숨겨 두었다.",
                    "collection_quote": "숨긴 마음도 꽤 귀엽네?",
                    "migration_sentinel": "keep",
                }
            )
            connection.execute(
                "UPDATE items SET asset_manifest = ? "
                "WHERE code = 'character_gumiho_pot'",
                (json.dumps(manifest, ensure_ascii=False),),
            )

        assert len(seeded_copy) == 36
        assert all(
            not any(
                phrase in f"{title} {description}"
                for phrase in ("작은", "한 칸", "천천히", "마음")
            )
            for _code, title, description in seeded_copy
        )
        assert next(row for row in seeded_copy if row[0] == "QST_NOTICE_THREE") == (
            "QST_NOTICE_THREE",
            "색·모양·글자 찾기",
            "지금 있는 곳에서 색, 모양, 글자를 하나씩 찾아 이름을 적어보세요.",
        )
        assert seeded_manifest["lore_hook"] == (
            "달빛 신사의 봉인이 풀린 밤, 아홉 꼬리불을 훔쳐 달아난 여우 화분."
        )
        assert seeded_manifest["collection_quote"] == (
            "후후, 마지막 꼬리불은 어디 있게?"
        )

        command.upgrade(config, "0009_content_copy")
        with sqlite3.connect(database_path) as connection:
            quest_rows = connection.execute(
                """
                SELECT code, title, description, trigger_rule, category,
                       burden_level, estimated_minutes, safety_tags,
                       reward_exp, reward_seeds, is_active
                FROM quests
                ORDER BY code
                """
            ).fetchall()
            refreshed_manifest = json.loads(
                connection.execute(
                    "SELECT asset_manifest FROM items "
                    "WHERE code = 'character_gumiho_pot'"
                ).fetchone()[0]
            )
            character_manifests = [
                (code, json.loads(manifest_json))
                for code, manifest_json in connection.execute(
                    """
                    SELECT code, asset_manifest
                    FROM items
                    WHERE code LIKE 'character_%_pot'
                    ORDER BY code
                    """
                ).fetchall()
            ]

        assert len(quest_rows) == 36
        assert [(row[0], row[1], row[2]) for row in quest_rows] == seeded_copy
        assert len({row[1] for row in quest_rows}) == 36
        assert len({row[2] for row in quest_rows}) == 36
        assert all(row[1] != "legacy title" for row in quest_rows)
        assert all(row[2] != "legacy description" for row in quest_rows)
        for row in quest_rows:
            assert not any(
                phrase in f"{row[1]} {row[2]}"
                for phrase in ("작은", "한 칸", "천천히", "마음")
            )
            assert row[3:] == quest_metadata[row[0]]

        notice = next(row for row in quest_rows if row[0] == "QST_NOTICE_THREE")
        assert notice[1:3] == (
            "색·모양·글자 찾기",
            "지금 있는 곳에서 색, 모양, 글자를 하나씩 찾아 이름을 적어보세요.",
        )
        assert refreshed_manifest["lore_hook"] == (
            "달빛 신사의 봉인이 풀린 밤, 아홉 꼬리불을 훔쳐 달아난 여우 화분."
        )
        assert refreshed_manifest["collection_quote"] == (
            "후후, 마지막 꼬리불은 어디 있게?"
        )
        assert refreshed_manifest["migration_sentinel"] == "keep"
        assert len(character_manifests) == 10
        for _code, character_manifest in character_manifests:
            story_copy = (
                f"{character_manifest['lore_hook']} "
                f"{character_manifest['collection_quote']}"
            )
            assert not any(
                phrase in story_copy
                for phrase in ("마음", "괜찮", "곁에", "천천히", "한 칸")
            )

        command.downgrade(config, "0008_character_voice")
        with sqlite3.connect(database_path) as connection:
            restored_notice = connection.execute(
                "SELECT title, description FROM quests WHERE code = 'QST_NOTICE_THREE'"
            ).fetchone()
            restored_manifest = json.loads(
                connection.execute(
                    "SELECT asset_manifest FROM items "
                    "WHERE code = 'character_gumiho_pot'"
                ).fetchone()[0]
            )

        assert restored_notice == (
            "지금 보이는 세 가지",
            "주변에서 눈에 들어오는 것 세 가지를 천천히 찾아보세요.",
        )
        assert restored_manifest["lore_hook"] == (
            "아홉 꼬리마다 서로 다른 마음의 비밀을 하나씩 숨겨 두었다."
        )
        assert restored_manifest["collection_quote"] == "숨긴 마음도 꽤 귀엽네?"
        assert restored_manifest["migration_sentinel"] == "keep"
    finally:
        get_settings.cache_clear()
