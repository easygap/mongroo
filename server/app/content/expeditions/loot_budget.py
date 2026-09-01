"""귀환 후보를 가치 예산 안으로 고르는 규칙.

설계서 9.1이 지역마다 `가치 예산`과 `최대 칸`을 정해 뒀다. 예산은 사용자에게
화폐처럼 보여 주지 않는 정수이고, 하는 일은 하나다 — **멀리 갈수록 더 가져오되
얼마나 더 가져올지는 콘텐츠가 아니라 이 표가 정한다.**

세 가지를 여기서 지킨다.

1. `core`는 예산을 쓰지 않는다. 핵심 발견·이야기 표본은 고르든 말든 남는다
   (설계서 9.1의 `안전 귀환·목표 전 귀환 · 핵심 발견만`).
2. 사용자가 고르면 그 조합이 예산과 칸을 넘지 않는지 본다. 넘으면 조용히
   잘라 내지 않고 422로 돌려준다 — 잘라 내면 무엇이 빠졌는지 알 길이 없다.
3. 안 고르면 서버가 채운다. **목표 재료 우선, 그다음 먼저 발견한 순서**다
   (설계서 9.8). 목표를 뒤로 미루면 가장 오래 걸린 것을 못 가져오는 날이 온다.

판정은 하지 않는다. run도 journey도 이 함수 하나를 지나 같은 규칙으로 끝난다.
"""

from dataclasses import dataclass
from typing import Any, Iterable, Protocol


#: 예산을 쓰지 않고 언제나 남는 종류.
CORE_KIND = "core"

#: 목표 재료. 자동으로 채울 때 맨 앞에 선다.
OBJECTIVE_KIND = "objective"


class LootRow(Protocol):
    """이 규칙이 읽는 것만 적는다. ORM 행과 검사용 더미가 같이 통과한다."""

    id: int
    item_code: str
    quantity: int
    value_units: int
    loot_kind: str


class LootBudgetError(Exception):
    """고른 조합이 예산·칸을 넘었거나 이 run의 후보가 아니다."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


@dataclass(frozen=True)
class LootSelection:
    """가져갈 것과 기록으로만 남길 것."""

    granted: tuple[Any, ...]
    recorded: tuple[Any, ...]

    @property
    def spent_units(self) -> int:
        return sum(
            row.value_units for row in self.granted if row.loot_kind != CORE_KIND
        )


def _sort_key(row: Any) -> tuple[int, int]:
    # 목표 재료가 먼저, 그다음은 발견 순서(= 행이 만들어진 순서)다.
    return (0 if row.loot_kind == OBJECTIVE_KIND else 1, int(row.id))


def select_within_budget(
    candidates: Iterable[Any],
    *,
    budget: int,
    slots: int,
    selected_ids: Iterable[int] | None = None,
) -> LootSelection:
    """후보를 예산 안에서 가른다.

    `selected_ids`가 없으면(또는 비어 있으면) 서버가 채운다. 빈 목록과 `None`을
    같게 보는 것은 의도다 — 앱이 `아무것도 안 고름`을 빈 배열로 보내도 설계서의
    자동 채우기 규칙을 그대로 타야 한다.
    """

    rows = list(candidates)
    core = [row for row in rows if row.loot_kind == CORE_KIND]
    priced = sorted(
        (row for row in rows if row.loot_kind != CORE_KIND), key=_sort_key
    )

    if selected_ids:
        wanted = list(dict.fromkeys(int(value) for value in selected_ids))
        by_id = {int(row.id): row for row in priced}
        unknown = [value for value in wanted if value not in by_id]
        if unknown:
            raise LootBudgetError(
                "EXPEDITION_LOOT_INVALID",
                "이번 귀환의 후보가 아닌 재료가 섞여 있어요.",
            )
        chosen = [by_id[value] for value in wanted]
        if len(chosen) > slots:
            raise LootBudgetError(
                "EXPEDITION_LOOT_INVALID",
                f"한 번에 {slots}칸까지 담을 수 있어요.",
            )
        spent = sum(row.value_units for row in chosen)
        if spent > budget:
            raise LootBudgetError(
                "EXPEDITION_LOOT_INVALID",
                "고른 재료가 이번 귀환의 가치 예산을 넘어요.",
            )
    else:
        chosen = []
        spent = 0
        for row in priced:
            if len(chosen) >= slots or spent + row.value_units > budget:
                continue
            chosen.append(row)
            spent += row.value_units

    picked = {id(row) for row in chosen}
    return LootSelection(
        granted=tuple(core + chosen),
        recorded=tuple(row for row in priced if id(row) not in picked),
    )


def budget_of(reward: dict[str, Any]) -> tuple[int, int]:
    """지역 보상에서 (예산, 칸)을 읽는다.

    예전에 시작한 run의 스냅샷에는 이 칸이 없다. 그때는 목표 하나만 가져오던
    시절이므로 `1칸 · 1가치`로 읽는다 — 진행 중인 run이 갑자기 더 받거나 덜
    받게 만들지 않는다.
    """

    return (
        int(reward.get("loot_value_units", 1)),
        int(reward.get("loot_slots", 1)),
    )
