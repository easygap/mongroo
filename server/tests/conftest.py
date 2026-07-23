import os
import uuid

import pytest
import sqlalchemy as sa
from httpx import ASGITransport, AsyncClient

os.environ.setdefault("AI_MODE", "fake")
os.environ.setdefault("JWT_SECRET", "test-secret-0123456789abcdef0123456789abcdef")

from app.core import db as db_module  # noqa: E402
from app.core.config import get_settings  # noqa: E402


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.fixture
async def engine(tmp_path, monkeypatch):
    url = f"sqlite+aiosqlite:///{tmp_path / 'test.db'}"
    monkeypatch.setenv("DATABASE_URL", url)
    get_settings.cache_clear()
    db_module.reset_engine()

    from app.models import Base

    engine = db_module.get_engine()
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        # 활성 식물 1개 제약 (마이그레이션의 sqlite 경로와 동일)
        await conn.execute(sa.text(
            "CREATE UNIQUE INDEX uq_plants_active_user ON plants (user_id) "
            "WHERE status = 'active'"
        ))
        await conn.execute(sa.text(
            "INSERT INTO plant_species (code, name, persona_key, asset_manifest, rarity, unlock_price) "
            "VALUES ('basic_sprout', '새싹몬', 'sprout', '{}', 1, 0), "
            "('cactus', '가시니', 'cactus', '{}', 2, 100), "
            "('sunflower', '해바라기', 'sunflower', '{}', 2, 100)"
        ))
        await conn.execute(sa.text(
            "INSERT INTO quests "
            "(code, title, description, trigger_rule, category, burden_level, estimated_minutes, "
            "safety_tags, reward_exp, reward_seeds, is_active) VALUES "
            "('QST_NOTICE_THREE', '색·모양·글자 찾기', '지금 있는 곳에서 색, 모양, 글자를 하나씩 찾아 이름을 적어보세요.', "
            "'daily_neutral', 'senses', 1, 3, '[]', 20, 5, 1), "
            "('QST_SIP_COMMA', '음료 세 모금', '물이나 평소 마시는 음료를 준비해 세 모금 마신 뒤 컵을 내려놓으세요.', "
            "'daily_neutral', 'rest', 1, 2, '[]', 20, 5, 1)"
        ))
        await conn.execute(sa.text(
            "INSERT INTO items "
            "(code, type, name, description, price_seeds, rarity, asset_manifest, is_active) VALUES "
            "('deco_cushion_leaf', 'deco', '잎사귀 쿠션', '폭신한 쿠션', 25, 1, "
            "'{\"emoji\": \"leaf\", \"asset_key\": \"deco/cushion_leaf\"}', 1), "
            "('companion_dewdrop', 'companion', '이슬이', '이슬 요정', 75, 2, "
            "'{\"emoji\": \"drop\", \"asset_key\": \"companion/dewdrop\"}', 1), "
            "('species_cactus', 'species_unlock', '가시니 씨앗', '가시니 품종 해금', 100, 2, "
            "'{\"emoji\": \"cactus\", \"asset_key\": \"species/cactus\", "
            "\"species_code\": \"cactus\"}', 1), "
            "('character_baby_pot', 'main_character', '아기 화분', '호기심 많은 막내 화분', "
            "0, 1, '{\"asset_key\": \"characters/baby-pot\", "
            "\"personality\": \"호기심 많은 말랑한 막내\", "
            "\"catchphrase\": \"쪼꼬만 용기, 같이 심을래?\", "
            "\"motion_key\": \"baby_bounce\"}', 1)"
        ))
    yield engine
    await engine.dispose()
    db_module.reset_engine()
    get_settings.cache_clear()


@pytest.fixture
async def client(engine):
    from app.main import create_app

    app = create_app()
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test/api/v1") as client:
        yield client


@pytest.fixture
def session_factory(engine):
    return db_module.get_session_factory()


async def signup(client: AsyncClient, email: str | None = None) -> dict:
    email = email or f"user-{uuid.uuid4().hex[:8]}@example.com"
    res = await client.post(
        "/auth/signup",
        json={"email": email, "password": "password123", "nickname": "테스트"},
    )
    assert res.status_code == 201, res.text
    return res.json()


def auth_headers(tokens: dict, idem: bool = False) -> dict:
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}
    if idem:
        headers["Idempotency-Key"] = uuid.uuid4().hex
    return headers


@pytest.fixture
async def user_tokens(client):
    return await signup(client)
