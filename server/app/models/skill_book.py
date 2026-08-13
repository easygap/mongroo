from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.core.timeutil import utcnow
from app.models.base import Base, BigIntPK, PreciseDateTime


class UserSkillBook(Base):
    """계정이 보유한 마음결 기록서.

    기록서는 계정 귀속 영구 라이선스다. 소모되지 않고 파괴되지 않으므로 수량
    컬럼이 없다. 같은 코드는 계정에 한 장뿐이라 `(user_id, skill_book_code)`가
    곧 신원이고, 중복 획득은 행을 늘리지 않고 409로 막는다.

    카탈로그는 `app/content/expeditions/skill_books.py`에 있고 이 테이블은
    소유 사실만 남긴다. 밸런스 패치로 책 내용이 바뀌어도 보유는 그대로다.
    """

    __tablename__ = "user_skill_books"
    __table_args__ = (
        sa.UniqueConstraint(
            "user_id", "skill_book_code", name="uq_user_skill_book"
        ),
        sa.Index("ix_user_skill_books_user", "user_id", "acquired_at"),
    )

    id: Mapped[int] = mapped_column(BigIntPK, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    # 카탈로그는 코드로만 참조한다. 콘텐츠 테이블을 만들지 않아 FK를 걸지 않는다.
    skill_book_code: Mapped[str] = mapped_column(sa.String(48), nullable=False)
    acquired_at: Mapped[datetime] = mapped_column(
        PreciseDateTime, default=utcnow, nullable=False
    )
    # shop|unlock|challenge|starter_choice|balance_replacement|refund_restore
    acquire_source: Mapped[str] = mapped_column(sa.String(24), nullable=False)
    # 구매는 씨앗 원장 entry, 해금·도전은 근거 run/목표 code를 가리킨다.
    source_ref: Mapped[str | None] = mapped_column(sa.String(64), nullable=True)


class PlantSkillLoadout(Base):
    """캐릭터별 선택 슬롯 프리셋.

    소유와 장착을 분리하는 축의 절반이다. 보유했다고 자동으로 장착되지 않고,
    같은 책을 여러 캐릭터의 여러 프리셋에 저장하는 것도 허용한다 — 계정
    라이선스이기 때문이다. 실제로 함께 출발하는 파티 안에서만 중복을 막는다.

    슬롯에는 기록서 코드 또는 감정 포인터(`emotion.primary|secondary`)가 들어간다.
    `NULL`은 `아직 고르지 않음`이고, 그 경우 안전 기본값으로 해석된다.
    """

    __tablename__ = "plant_skill_loadouts"
    __table_args__ = (
        sa.Index("ix_plant_skill_loadouts_user", "user_id"),
    )

    plant_id: Mapped[int] = mapped_column(
        sa.ForeignKey("plants.id", ondelete="CASCADE"),
        primary_key=True,
        nullable=False,
    )
    # explore|guard|personal. 수확한 식물의 프리셋도 박물관에서 함께 남는다.
    preset_code: Mapped[str] = mapped_column(
        sa.String(16), primary_key=True, nullable=False
    )
    user_id: Mapped[int] = mapped_column(
        sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    slot_b1_code: Mapped[str | None] = mapped_column(sa.String(48), nullable=True)
    slot_b2_code: Mapped[str | None] = mapped_column(sa.String(48), nullable=True)
    # 낙관적 동시성. 저장 요청이 읽은 값과 다르면 409로 되돌린다.
    revision: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=1)
    updated_at: Mapped[datetime] = mapped_column(
        PreciseDateTime, default=utcnow, onupdate=utcnow, nullable=False
    )


class PlantSkillMastery(Base):
    """캐릭터가 어떤 스킬을 몇 번 썼는지.

    **숙련은 성능을 1도 바꾸지 않는다.** 설계서 11.6이 못 박은 계약이다.
    5단계마다 캐릭터 상세의 회상 문장 한 줄이 열릴 뿐이고, 위력·비용·쿨타임에는
    절대 들어가지 않는다. 오래 쓴 스킬에 애착을 남기는 장치이지 성장 축이 아니다.

    이 기록은 `마음 지키기 누적 30회` 같은 기록서 해금 조건의 근거로도 쓰인다.
    조건을 세려고 별도 카운터를 만들지 않고 이미 남기는 숙련을 읽는다.
    """

    __tablename__ = "plant_skill_mastery"

    plant_id: Mapped[int] = mapped_column(
        sa.ForeignKey("plants.id", ondelete="CASCADE"),
        primary_key=True,
        nullable=False,
    )
    # 고유·감정·기록서·기본 공격·지키기가 같은 이름 공간을 쓴다.
    skill_code: Mapped[str] = mapped_column(
        sa.String(48), primary_key=True, nullable=False
    )
    use_count: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=0)
    mastery_level: Mapped[int] = mapped_column(
        sa.SmallInteger, nullable=False, default=0
    )
    updated_at: Mapped[datetime] = mapped_column(
        PreciseDateTime, default=utcnow, onupdate=utcnow, nullable=False
    )
