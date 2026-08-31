"""탐험 run 하나를 안전하게 다루는 공통 규칙 — 잠금·멱등·revision.

`expeditions.py`가 오래 들고 있던 세 함수다. 합동 수호전도 같은 `ExpeditionRun`
행을 쓰므로 같은 규칙이 필요해졌고, 사본을 하나 더 만들면 두 곳의 충돌 처리가
조용히 갈라진다. 그래서 옮겨 두고 양쪽이 함께 쓴다.

세 가지가 함께 있어야 한 판이 안전하다.

- **잠금**: 같은 run을 동시에 두 요청이 건드리지 못하게 행을 잠근다.
- **멱등**: 같은 `client_action_id`가 다시 오면 저장해 둔 결과를 그대로
  돌려준다. 네트워크가 끊겨 앱이 재시도해도 판이 두 번 진행되지 않는다.
- **revision**: 앱이 본 상태와 서버 상태가 같은지 본다. 다르면 거절하고
  최신 상태를 다시 읽게 한다.
"""

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.errors import AppError
from app.models.expedition import ExpeditionAction, ExpeditionRun


async def lock_run(db: AsyncSession, user_id: int, run_id: int) -> ExpeditionRun:
    run = await db.scalar(
        sa.select(ExpeditionRun)
        .where(ExpeditionRun.id == run_id, ExpeditionRun.user_id == user_id)
        .with_for_update()
    )
    if run is None:
        raise AppError(404, "EXPEDITION_NOT_FOUND", "탐험 기록을 찾을 수 없습니다.")
    return run


async def existing_action(
    db: AsyncSession,
    run: ExpeditionRun,
    client_action_id: str,
    action_type: str,
    request_payload: dict,
) -> dict | None:
    action = await db.scalar(
        sa.select(ExpeditionAction).where(
            ExpeditionAction.run_id == run.id,
            ExpeditionAction.client_action_id == client_action_id,
        )
    )
    if action is None:
        return None
    if action.action_type != action_type or action.request_payload != request_payload:
        raise AppError(
            409,
            "EXPEDITION_ACTION_ID_CONFLICT",
            "같은 행동 키로 다른 요청을 보냈습니다.",
        )
    return action.result_payload


def check_revision(run: ExpeditionRun, expected_revision: int) -> None:
    if run.status != "active":
        raise AppError(409, "EXPEDITION_FINISHED", "이미 끝난 탐험입니다.")
    if run.revision != expected_revision:
        raise AppError(
            409,
            "EXPEDITION_REVISION_CONFLICT",
            "탐험 상태가 바뀌었습니다. 최신 지도를 불러와 주세요.",
            {"expected_revision": expected_revision, "current_revision": run.revision},
        )
