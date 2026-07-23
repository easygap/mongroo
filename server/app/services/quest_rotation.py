"""보상 차등 없이 일기 맥락과 반복 방지를 함께 다루는 퀘스트 순환 규칙."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
import hashlib
from typing import Protocol, Sequence, TypeVar


class QuestCandidate(Protocol):
    id: int
    code: str
    category: str
    burden_level: int


@dataclass(frozen=True)
class QuestHistory:
    quest_id: int
    category: str
    burden_level: int
    quest_date: date


QuestT = TypeVar("QuestT", bound=QuestCandidate)


def choose_daily_quest(
    quests: Sequence[QuestT],
    recent: Sequence[QuestHistory],
    *,
    user_id: int,
    today: date,
    preferred_categories: Sequence[str] = (),
) -> QuestT:
    """카탈로그 순서에 영향받지 않는 결정적 선택을 반환한다.

    최근 14회가 아니라 최근 14일의 이력은 호출자가 전달한다. 같은 퀘스트와
    직전 두 번의 category는 대안이 있을 때만 피하므로 작은 카탈로그에서도
    빈 배정을 만들지 않는다. 부담도 2는 날짜 해시의 약 20%만 선택한다.
    """

    eligible = sorted(
        (quest for quest in quests if quest.burden_level in (1, 2)),
        key=lambda quest: (quest.code, quest.id),
    )
    if not eligible:
        raise ValueError("no eligible daily quests")

    recent_ordered = sorted(
        recent,
        key=lambda entry: (entry.quest_date, entry.quest_id),
        reverse=True,
    )
    recent_ids = {entry.quest_id for entry in recent_ordered}
    fresh_pool = [quest for quest in eligible if quest.id not in recent_ids]
    if fresh_pool:
        eligible = fresh_pool

    last_categories = {entry.category for entry in recent_ordered[:2]}
    category_fresh_pool = [
        quest for quest in eligible if quest.category not in last_categories
    ]
    if category_fresh_pool:
        eligible = category_fresh_pool

    # 감정은 성공/실패나 난이도를 결정하지 않는다. 반복 방지 후보 안에서
    # 일기 맥락과 어울리는 행동 카테고리가 있을 때만 후보를 좁힌다.
    preferred = set(preferred_categories)
    contextual = [quest for quest in eligible if quest.category in preferred]
    if contextual:
        eligible = contextual

    digest = hashlib.sha256(
        f"mongroo:quest-rotation:v2:{user_id}:{today.isoformat()}".encode()
    ).digest()
    target_burden = 2 if digest[0] % 5 == 0 else 1
    pool = [quest for quest in eligible if quest.burden_level == target_burden]
    if not pool:
        pool = eligible

    index = int.from_bytes(digest[1:9], "big") % len(pool)
    return pool[index]
