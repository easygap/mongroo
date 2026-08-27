"""해금 조건 문구의 `일일 퀘스트`를 `작은 행동`으로 맞춘다

Revision ID: 0039_small_action_wording
Revises: 0038_retire_first_signal
Create Date: 2026-08-27

앱은 이 기능을 `작은 행동`이라고 부른다 - 홈 카드, 오늘의 여정, 화면 제목이
전부 그렇다. `퀘스트`는 만들 때 쓰던 말이 화면까지 나온 것이고, 하고 싶은
날만 하면 되는 활동에 `퀘스트`는 의무처럼 읽힌다.

상점·도감의 해금 조건 문구만 DB에 들어 있어서 코드에서 못 고친다. 라벨은
표시 전용이고 판정은 `acquisition.type`·`target`이 하므로 이 값을 바꿔도
해금 계산은 그대로다.
"""

from __future__ import annotations

import json

import sqlalchemy as sa
from alembic import op


revision = "0039_small_action_wording"
down_revision = "0038_retire_first_signal"
branch_labels = None
depends_on = None


def _items() -> sa.Table:
    return sa.table(
        "items",
        sa.column("code", sa.String),
        sa.column("asset_manifest", sa.JSON),
    )


def _relabel(before: str, after: str) -> None:
    """`acquisition.label` 안의 표기만 바꾼다. 다른 키는 건드리지 않는다."""
    items = _items()
    bind = op.get_bind()
    rows = bind.execute(sa.select(items.c.code, items.c.asset_manifest)).all()
    for code, manifest in rows:
        if isinstance(manifest, str):
            manifest = json.loads(manifest)
        if not isinstance(manifest, dict):
            continue
        acquisition = manifest.get("acquisition")
        if not isinstance(acquisition, dict):
            continue
        label = acquisition.get("label")
        if not isinstance(label, str) or before not in label:
            continue
        acquisition = {**acquisition, "label": label.replace(before, after)}
        bind.execute(
            items.update()
            .where(items.c.code == code)
            .values(asset_manifest={**manifest, "acquisition": acquisition})
        )


def upgrade() -> None:
    _relabel("일일 퀘스트", "작은 행동")


def downgrade() -> None:
    _relabel("작은 행동", "일일 퀘스트")
