from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.dialects import mysql
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

from app.core.timeutil import utcnow

# sqlite 테스트에서도 autoincrement가 동작하도록 variant 지정
BigIntPK = sa.BigInteger().with_variant(sa.Integer(), "sqlite")
# 식물 생애 경계에 쓰는 시각은 MySQL의 기본 초 단위 DATETIME으로 저장하면
# 같은 초에 수확·다시 심기한 기록이 섞일 수 있어 마이크로초를 보존한다.
PreciseDateTime = sa.DateTime().with_variant(mysql.DATETIME(fsp=6), "mysql")


class Base(DeclarativeBase):
    pass


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(
        sa.DateTime(), default=utcnow, nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        sa.DateTime(), default=utcnow, onupdate=utcnow, nullable=False
    )
