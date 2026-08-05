from collections.abc import AsyncIterator

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import get_settings

_engine = None
_session_factory: async_sessionmaker[AsyncSession] | None = None


def get_engine():
    global _engine, _session_factory
    if _engine is None:
        settings = get_settings()
        kwargs: dict = {
            "pool_pre_ping": True,
            "pool_size": settings.database_pool_size,
            "max_overflow": settings.database_max_overflow,
            "pool_recycle": settings.database_pool_recycle_seconds,
        }
        if settings.database_url.startswith("sqlite"):
            kwargs = {"connect_args": {"timeout": 30}}
        _engine = create_async_engine(settings.database_url, **kwargs)
        if settings.database_url.startswith("sqlite"):
            # SQLite는 기본값으로 외래키를 무시한다. 개발·테스트에서도 운영 MySQL과
            # 같은 CASCADE/RESTRICT 계약을 강제해 계정 삭제 같은 흐름의 거짓 양성을 막는다.
            @sa.event.listens_for(_engine.sync_engine, "connect")
            def _enable_sqlite_foreign_keys(dbapi_connection, _record) -> None:
                cursor = dbapi_connection.cursor()
                cursor.execute("PRAGMA foreign_keys=ON")
                cursor.close()
        _session_factory = async_sessionmaker(_engine, expire_on_commit=False)
    return _engine


def get_session_factory() -> async_sessionmaker[AsyncSession]:
    get_engine()
    assert _session_factory is not None
    return _session_factory


async def get_db() -> AsyncIterator[AsyncSession]:
    factory = get_session_factory()
    async with factory() as session:
        yield session


def reset_engine() -> None:
    """테스트에서 DATABASE_URL 교체 후 재초기화용."""
    global _engine, _session_factory
    _engine = None
    _session_factory = None
