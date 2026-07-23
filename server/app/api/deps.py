from fastapi import Depends, Request
from fastapi.security.utils import get_authorization_scheme_param
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.errors import AppError
from app.core.db import get_db
from app.core.security import TokenError, decode_token
from app.core.timeutil import utcnow
from app.models.user import AuthSession, User


async def get_current_user(request: Request, db: AsyncSession = Depends(get_db)) -> User:
    authorization = request.headers.get("Authorization")
    scheme, token = get_authorization_scheme_param(authorization)
    if not token or scheme.lower() != "bearer":
        raise AppError(401, "AUTH_TOKEN_INVALID", "인증이 필요합니다.")
    try:
        claims = decode_token(token, "access")
    except TokenError as exc:
        raise AppError(401, exc.code, "다시 로그인해 주세요.") from exc

    session = await db.get(AuthSession, int(claims["sid"]))
    if (
        session is None
        or session.user_id != int(claims["sub"])
        or session.revoked_at is not None
        or session.expires_at < utcnow()
    ):
        raise AppError(401, "AUTH_TOKEN_INVALID", "다시 로그인해 주세요.")

    user = await db.get(User, int(claims["sub"]))
    if user is None:
        raise AppError(401, "AUTH_TOKEN_INVALID", "다시 로그인해 주세요.")
    request.state.auth_session_id = session.id
    return user


async def get_owned(db: AsyncSession, model, resource_id: int, user_id: int, not_found_code: str):
    """소유권 검사. ID 존재 여부만으로 접근하지 않는다 (design.md 4.1)."""
    row = await db.get(model, resource_id)
    if row is None:
        raise AppError(404, not_found_code, "대상을 찾을 수 없습니다.")
    if row.user_id != user_id:
        raise AppError(403, "FORBIDDEN", "접근 권한이 없습니다.")
    return row


def encode_cursor(value: int | None) -> str | None:
    return str(value) if value is not None else None


def decode_cursor(cursor: str | None) -> int | None:
    if cursor is None:
        return None
    try:
        return int(cursor)
    except ValueError:
        raise AppError(422, "VALIDATION_ERROR", "cursor 값이 올바르지 않습니다.")


async def paginate_ids(query_result: list, limit: int) -> tuple[list, str | None]:
    """id 내림차순 목록에서 limit+1개를 받아 next_cursor를 계산한다."""
    items = list(query_result)
    if len(items) > limit:
        return items[:limit], str(items[limit - 1].id)
    return items, None
