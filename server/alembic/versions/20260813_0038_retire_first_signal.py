"""선제 신호를 상점에서 내린다

Revision ID: 0038_retire_first_signal
Revises: 0037_plant_skill_mastery
Create Date: 2026-08-13

`first_signal`(선제 신호)의 효과 문장은 `적 의도 공개 후 1라운드 명령 순서
재배치`인데, 순차 명령 독(stage-battle-v2.0)에서는 **모든 플레이어가 이미 매
라운드 공짜로 하는 일**이다. 적 의도는 명령 전에 늘 공개되고, 대기 중인 대원은
아무나 골라 아무 순서로 행동시킬 수 있다. 이 책은 순서를 미리 제출하고 잠그던
예약형 지휘 패널 시절에 설계됐고, 그 패널이 교체되면서 팔 것이 사라졌다.

씨앗 120을 받으면서 아무 일도 하지 않는 항목이라 상점에서 내린다.

**행을 지우지 않고 `is_active=False`로 둔다.** 이미 산 사람의 `user_items`가
이 행을 참조하고 있고, 구매 이력은 환불·문의의 근거다. `is_active`는 상점
목록과 구매 처리 양쪽의 관문이라(`app/services/game.py`) 이 한 줄로 노출과
구매가 함께 막힌다.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op


revision = "0038_retire_first_signal"
down_revision = "0037_plant_skill_mastery"
branch_labels = None
depends_on = None


RETIRED_ITEM_CODE = "skill_book_first_signal"


def _items() -> sa.Table:
    return sa.table(
        "items",
        sa.column("code", sa.String),
        sa.column("is_active", sa.Boolean),
    )


def upgrade() -> None:
    items = _items()
    op.execute(
        items.update()
        .where(items.c.code == RETIRED_ITEM_CODE)
        .values(is_active=False)
    )


def downgrade() -> None:
    items = _items()
    op.execute(
        items.update()
        .where(items.c.code == RETIRED_ITEM_CODE)
        .values(is_active=True)
    )
