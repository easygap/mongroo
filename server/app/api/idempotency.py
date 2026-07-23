"""Idempotency-Key 처리 (design.md 5.3).

같은 사용자·route scope·key의 재시도는 저장된 첫 응답을 그대로 반환한다.
같은 키에 다른 본문이면 409.
"""
import asyncio
import hashlib
import json
import threading
import weakref
from collections.abc import Awaitable, Callable

import sqlalchemy as sa
from fastapi import Request
from fastapi.responses import JSONResponse
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.errors import AppError
from app.models.ops import IdempotencyKey
from app.models.user import User


# 같은 프로세스의 동일 키 재시도는 DB까지 경합시키지 않는다. weak registry라
# 요청이 끝난 키는 자동으로 제거되며, 다중 프로세스의 최종 직렬화는 아래의
# unique key 선점이 담당한다.
_local_locks: weakref.WeakValueDictionary[
    tuple[int, str, str], asyncio.Lock
] = weakref.WeakValueDictionary()
_local_locks_guard = threading.Lock()


def _local_lock(user_id: int, route_scope: str, key: str) -> asyncio.Lock:
    lock_key = (user_id, route_scope, key)
    with _local_locks_guard:
        lock = _local_locks.get(lock_key)
        if lock is None:
            lock = asyncio.Lock()
            _local_locks[lock_key] = lock
        return lock


def _request_hash(body: dict) -> str:
    raw = json.dumps(body, sort_keys=True, ensure_ascii=False, default=str)
    return hashlib.sha256(raw.encode()).hexdigest()


def require_key(request: Request) -> str:
    key = request.headers.get("Idempotency-Key")
    if not key or len(key) > 64:
        raise AppError(400, "IDEMPOTENCY_KEY_REQUIRED", "Idempotency-Key 헤더가 필요합니다.")
    return key


async def _lock_user_before_claim(db: AsyncSession, user_id: int) -> None:
    """InnoDB FK 잠금 승격 교착을 막기 위해 부모 user row를 먼저 잠근다."""
    result = await db.execute(
        sa.select(User.id).where(User.id == user_id).with_for_update()
    )
    result.scalar_one()


async def run_idempotent(
    db: AsyncSession,
    user_id: int,
    route_scope: str,
    key: str,
    body: dict,
    handler: Callable[[], Awaitable[tuple[int, dict]]],
) -> JSONResponse:
    """동일 key의 첫 응답을 재생한다.

    handler는 ``(status_code, body_dict)``를 반환하고 commit하지 않아야 한다.
    key 선점, 도메인 변경, 응답 저장을 한 트랜잭션으로 확정하기 위해서다.
    """
    request_hash = _request_hash(body)
    lookup = sa.select(IdempotencyKey).where(
        IdempotencyKey.user_id == user_id,
        IdempotencyKey.route_scope == route_scope,
        IdempotencyKey.idempotency_key == key,
    )

    async with _local_lock(user_id, route_scope, key):
        # 같은 사용자의 서로 다른 key도 user → idempotency 순서로 직렬화한다.
        await _lock_user_before_claim(db, user_id)
        existing = await db.scalar(lookup)
        if existing is not None:
            if existing.request_hash != request_hash:
                raise AppError(
                    409,
                    "IDEMPOTENCY_KEY_CONFLICT",
                    "같은 키로 다른 요청을 보냈습니다.",
                )
            return JSONResponse(
                status_code=existing.response_status,
                content=existing.response_body,
            )

        # handler보다 먼저 key를 같은 트랜잭션에서 선점한다. 여러 서버 프로세스가
        # 동시에 사전 조회를 통과해도 unique constraint에서 패자는 첫 응답을 재생한다.
        claim = IdempotencyKey(
            user_id=user_id,
            route_scope=route_scope,
            idempotency_key=key,
            request_hash=request_hash,
            response_status=0,
            response_body={},
        )
        db.add(claim)
        try:
            await db.flush()
        except IntegrityError:
            # 다른 프로세스가 같은 key를 먼저 선점했다. unique insert는 선행
            # 트랜잭션이 끝난 뒤 실패하므로 rollback 후 완성된 응답을 읽을 수 있다.
            await db.rollback()
            stored = await db.scalar(lookup)
            if stored is None:
                raise
            if stored.request_hash != request_hash:
                raise AppError(
                    409,
                    "IDEMPOTENCY_KEY_CONFLICT",
                    "같은 키로 다른 요청을 보냈습니다.",
                )
            return JSONResponse(
                status_code=stored.response_status,
                content=stored.response_body,
            )

        status_code, response_body = await handler()
        claim.response_status = status_code
        claim.response_body = response_body
        await db.commit()
        return JSONResponse(status_code=status_code, content=response_body)
