"""0035 마이그레이션이 소유·장착 테이블을 실제로 만드는지 확인한다.

단위·API 테스트는 모델에서 스키마를 만들기 때문에 마이그레이션이 깨져도
통과한다. 배포에 실제로 실리는 것은 마이그레이션이므로 여기서 따로 올려 본다.
"""

import sqlite3
from pathlib import Path

import sqlalchemy as sa

from alembic import command
from alembic.config import Config

from app.core.config import get_settings


def _alembic_config(tmp_path, monkeypatch) -> tuple[Config, Path]:
    database_path = tmp_path / "skill-book-ownership.db"
    monkeypatch.setenv(
        "DATABASE_URL", f"sqlite+aiosqlite:///{database_path.as_posix()}"
    )
    get_settings.cache_clear()
    server_dir = Path(__file__).resolve().parents[2]
    config = Config(str(server_dir / "alembic.ini"))
    config.set_main_option("script_location", str(server_dir / "alembic"))
    return config, database_path


def test_migration_creates_ownership_and_loadout_tables(tmp_path, monkeypatch):
    config, database_path = _alembic_config(tmp_path, monkeypatch)
    try:
        command.upgrade(config, "0035_skill_book_ownership")
        with sqlite3.connect(database_path) as connection:
            tables = {
                row[0]
                for row in connection.execute(
                    "SELECT name FROM sqlite_master WHERE type='table'"
                )
            }
            assert "user_skill_books" in tables
            assert "plant_skill_loadouts" in tables

            owned = {
                row[1] for row in connection.execute("PRAGMA table_info(user_skill_books)")
            }
            assert {
                "user_id",
                "skill_book_code",
                "acquired_at",
                "acquire_source",
                "source_ref",
            } <= owned

            loadout = {
                row[1]
                for row in connection.execute("PRAGMA table_info(plant_skill_loadouts)")
            }
            assert {
                "plant_id",
                "preset_code",
                "user_id",
                "slot_b1_code",
                "slot_b2_code",
                "revision",
            } <= loadout

            # 프리셋별로 따로 저장되므로 (plant_id, preset_code)가 복합 키다.
            primary = [
                row[1]
                for row in connection.execute("PRAGMA table_info(plant_skill_loadouts)")
                if row[5]
            ]
            assert set(primary) == {"plant_id", "preset_code"}
    finally:
        get_settings.cache_clear()


def test_same_book_cannot_be_owned_twice(tmp_path, monkeypatch):
    """계정에 한 장뿐이라는 계약을 스키마가 먼저 지킨다."""

    config, database_path = _alembic_config(tmp_path, monkeypatch)
    try:
        command.upgrade(config, "0035_skill_book_ownership")
        with sqlite3.connect(database_path) as connection:
            connection.execute(
                """
                INSERT INTO users (
                    email, password_hash, nickname, timezone, seed_balance,
                    streak_days, created_at, updated_at
                ) VALUES (?, ?, ?, ?, 0, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """,
                ("book-owner@example.com", "not-used", "서고 주인", "Asia/Seoul"),
            )
            user_id = connection.execute(
                "SELECT id FROM users WHERE email = ?", ("book-owner@example.com",)
            ).fetchone()[0]
            connection.execute(
                """
                INSERT INTO user_skill_books
                    (user_id, skill_book_code, acquired_at, acquire_source)
                VALUES (?, 'clear_aim', CURRENT_TIMESTAMP, 'shop')
                """,
                (user_id,),
            )
            try:
                connection.execute(
                    """
                    INSERT INTO user_skill_books
                        (user_id, skill_book_code, acquired_at, acquire_source)
                    VALUES (?, 'clear_aim', CURRENT_TIMESTAMP, 'shop')
                    """,
                    (user_id,),
                )
            except sqlite3.IntegrityError:
                pass
            else:  # pragma: no cover - 제약이 없으면 계약 위반이다
                raise AssertionError("같은 기록서가 두 번 저장됐습니다")
    finally:
        get_settings.cache_clear()


def test_migration_downgrades_cleanly(tmp_path, monkeypatch):
    config, database_path = _alembic_config(tmp_path, monkeypatch)
    try:
        command.upgrade(config, "0035_skill_book_ownership")
        command.downgrade(config, "0034_character_expansion_v7")
        with sqlite3.connect(database_path) as connection:
            tables = {
                row[0]
                for row in connection.execute(
                    "SELECT name FROM sqlite_master WHERE type='table'"
                )
            }
            assert "user_skill_books" not in tables
            assert "plant_skill_loadouts" not in tables
    finally:
        get_settings.cache_clear()


def test_shop_migration_lists_only_the_purchasable_books(tmp_path, monkeypatch):
    """상점에는 구매 경로 11종만 올라간다. 해금·도전 책은 나타나지 않는다."""

    config, database_path = _alembic_config(tmp_path, monkeypatch)
    try:
        command.upgrade(config, "0036_skill_book_shop")
        with sqlite3.connect(database_path) as connection:
            rows = connection.execute(
                "SELECT code, price_seeds, rarity, asset_manifest FROM items "
                "WHERE type = 'skill_book' ORDER BY rarity, code"
            ).fetchall()
        assert len(rows) == 11
        # 1등급 7종 씨앗 40, 2등급 상점 4종 씨앗 120.
        assert [row[1] for row in rows if row[2] == 1] == [40] * 7
        assert [row[1] for row in rows if row[2] == 2] == [120] * 4

        codes = {row[0] for row in rows}
        # 도전으로만 얻는 3등급은 상점에 없다.
        assert "skill_book_shadow_oath" not in codes
        assert "skill_book_heart_encyclopedia" not in codes
        # 해금 조건이 있는 2등급도 없다.
        assert "skill_book_reviving_root" not in codes

        # asset_manifest가 카탈로그 코드를 가리켜야 구매 처리기가 찾을 수 있다.
        import json as _json

        from app.content.expeditions.skill_books import SKILL_BOOK_CATALOG

        for _, _, _, manifest in rows:
            book_code = _json.loads(manifest)["skill_book_code"]
            assert book_code in SKILL_BOOK_CATALOG
            assert SKILL_BOOK_CATALOG[book_code]["acquire_kind"] == "shop"
    finally:
        get_settings.cache_clear()


def test_shop_migration_downgrades_cleanly(tmp_path, monkeypatch):
    config, database_path = _alembic_config(tmp_path, monkeypatch)
    try:
        command.upgrade(config, "0036_skill_book_shop")
        command.downgrade(config, "0035_skill_book_ownership")
        with sqlite3.connect(database_path) as connection:
            remaining = connection.execute(
                "SELECT COUNT(*) FROM items WHERE type = 'skill_book'"
            ).fetchone()[0]
        assert remaining == 0
    finally:
        get_settings.cache_clear()


def test_mastery_migration_creates_the_record_table(tmp_path, monkeypatch):
    config, database_path = _alembic_config(tmp_path, monkeypatch)
    try:
        command.upgrade(config, "0037_plant_skill_mastery")
        with sqlite3.connect(database_path) as connection:
            columns = {
                row[1]
                for row in connection.execute("PRAGMA table_info(plant_skill_mastery)")
            }
            assert {
                "plant_id",
                "skill_code",
                "use_count",
                "mastery_level",
                "updated_at",
            } <= columns
            primary = [
                row[1]
                for row in connection.execute("PRAGMA table_info(plant_skill_mastery)")
                if row[5]
            ]
            assert set(primary) == {"plant_id", "skill_code"}

        command.downgrade(config, "0036_skill_book_shop")
        with sqlite3.connect(database_path) as connection:
            tables = {
                row[0]
                for row in connection.execute(
                    "SELECT name FROM sqlite_master WHERE type='table'"
                )
            }
            assert "plant_skill_mastery" not in tables
    finally:
        get_settings.cache_clear()


def test_retiring_first_signal_pulls_it_from_the_shop(tmp_path, monkeypatch):
    """0038 — 선제 신호는 더 이상 팔리지 않고, 산 기록은 남는다.

    `is_active`가 상점 목록과 구매 처리 양쪽의 관문이라 이 한 줄로 둘 다 막힌다.
    행을 지우지 않는 이유는 이미 산 사람의 `user_items`가 참조하고 있어서다.
    """

    config, database_path = _alembic_config(tmp_path, monkeypatch)
    command.upgrade(config, "0038_retire_first_signal")

    engine = sa.create_engine(f"sqlite:///{database_path}")
    with engine.connect() as connection:
        rows = dict(
            connection.execute(
                sa.text(
                    "SELECT code, is_active FROM items WHERE type = 'skill_book'"
                )
            ).all()
        )

    assert rows["skill_book_first_signal"] == 0
    # 한 권만 내렸다. 나머지 열 권은 그대로 팔린다.
    assert sum(1 for active in rows.values() if active) == len(rows) - 1
    assert rows["skill_book_clear_aim"] == 1

    # 되돌리면 다시 팔린다.
    command.downgrade(config, "0037_plant_skill_mastery")
    with engine.connect() as connection:
        restored = connection.execute(
            sa.text(
                "SELECT is_active FROM items WHERE code = 'skill_book_first_signal'"
            )
        ).scalar_one()
    assert restored == 1
    engine.dispose()
