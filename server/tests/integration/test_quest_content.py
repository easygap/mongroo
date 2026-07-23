import json
import sqlite3
from datetime import timedelta
from pathlib import Path

from alembic import command
from alembic.config import Config
import sqlalchemy as sa

from app.core.config import get_settings
from app.core.timeutil import local_date_of, utcnow
from app.models.game import Quest, UserQuest
from tests.conftest import auth_headers, signup


async def test_assignment_avoids_recent_quest_and_reuses_today(client, session_factory):
    tokens = await signup(client)
    user_id = tokens["user"]["id"]
    today = local_date_of(utcnow())

    async with session_factory() as db:
        recent_quest = await db.scalar(
            sa.select(Quest).where(Quest.code == "QST_NOTICE_THREE")
        )
        db.add(
            UserQuest(
                user_id=user_id,
                quest_id=recent_quest.id,
                quest_date=today - timedelta(days=1),
                status="skipped",
            )
        )
        await db.commit()

    first = await client.get("/quests/today", headers=auth_headers(tokens))
    second = await client.get("/quests/today", headers=auth_headers(tokens))

    assert first.status_code == 200
    assert first.json()["items"][0]["quest"]["code"] == "QST_SIP_COMMA"
    assert second.json()["items"][0]["id"] == first.json()["items"][0]["id"]


def test_content_depth_migration_expands_catalog_and_story_meta(tmp_path, monkeypatch):
    database_path = tmp_path / "content-depth.db"
    monkeypatch.setenv(
        "DATABASE_URL", f"sqlite+aiosqlite:///{database_path.as_posix()}"
    )
    get_settings.cache_clear()

    server_dir = Path(__file__).resolve().parents[2]
    config = Config(str(server_dir / "alembic.ini"))
    config.set_main_option("script_location", str(server_dir / "alembic"))

    try:
        command.upgrade(config, "0004_content_depth")
        with sqlite3.connect(database_path) as connection:
            quest_count = connection.execute("SELECT COUNT(*) FROM quests").fetchone()[
                0
            ]
            category_count = connection.execute(
                "SELECT COUNT(DISTINCT category) FROM quests"
            ).fetchone()[0]
            reward_variants = connection.execute(
                "SELECT COUNT(DISTINCT reward_exp || ':' || reward_seeds) FROM quests"
            ).fetchone()[0]
            medium_count = connection.execute(
                "SELECT COUNT(*) FROM quests WHERE burden_level = 2"
            ).fetchone()[0]
            manifest_json = connection.execute(
                "SELECT asset_manifest FROM items WHERE code = 'character_gumiho_pot'"
            ).fetchone()[0]

        manifest = json.loads(manifest_json)
        assert quest_count == 36
        assert category_count >= 10
        assert medium_count == 8
        assert reward_variants == 1
        assert manifest["story_role"] == "달빛 온실의 장난꾼"
        assert manifest["quest_affinities"] == ["reflection", "creativity"]
        assert manifest["lore_hook"] == (
            "달빛 신사의 봉인이 풀린 밤, 아홉 꼬리불을 훔쳐 달아난 여우 화분."
        )
        assert manifest["collection_quote"] == "후후, 마지막 꼬리불은 어디 있게?"

        command.downgrade(config, "0003_character_catalog")
        with sqlite3.connect(database_path) as connection:
            quest_count_after = connection.execute(
                "SELECT COUNT(*) FROM quests"
            ).fetchone()[0]
            manifest_after = json.loads(
                connection.execute(
                    "SELECT asset_manifest FROM items WHERE code = 'character_gumiho_pot'"
                ).fetchone()[0]
            )
        assert quest_count_after == 12
        assert "story_role" not in manifest_after
    finally:
        get_settings.cache_clear()
