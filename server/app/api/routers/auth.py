"""인증. refresh는 매 사용 시 회전하고 재사용을 감지한다 (design.md 9.2)."""
import time
import uuid
from collections import defaultdict, deque
from datetime import timedelta

import sqlalchemy as sa
from fastapi import APIRouter, Depends, Request
from fastapi.responses import Response
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.api.errors import AppError
from app.core.config import get_settings
from app.core.db import get_db
from app.core.security import (TokenError, create_access_token, create_refresh_token,
                               decode_token, hash_password, sha256_hex, verify_password)
from app.core.timeutil import to_utc_iso, utcnow
from app.models.enums import PlantStatus
from app.models.game import Item, UserItem
from app.models.plant import Plant, PlantSpecies
from app.models.user import AuthSession, RefreshToken, User
from app.schemas.requests import LoginRequest, LogoutRequest, RefreshRequest, SignupRequest
from app.services import plants as plant_service

router = APIRouter(tags=["auth"])

# 단일 프로세스 데모 기준의 실패한 로그인 시도 제한
_login_attempts: dict[str, deque] = defaultdict(deque)


def _check_login_rate(key: str) -> None:
    settings = get_settings()
    window = settings.login_rate_limit_window_seconds
    now = time.monotonic()
    attempts = _login_attempts.get(key)
    if not attempts:
        return
    while attempts and now - attempts[0] > window:
        attempts.popleft()
    if not attempts:
        _login_attempts.pop(key, None)
        return
    if len(attempts) >= settings.login_rate_limit_count:
        raise AppError(429, "RATE_LIMITED", "잠시 후 다시 시도해 주세요.")


def _record_login_failure(key: str) -> None:
    _login_attempts[key].append(time.monotonic())


def _clear_login_failures(key: str) -> None:
    _login_attempts.pop(key, None)


def user_payload(user: User) -> dict:
    return {
        "id": user.id,
        "email": user.email,
        "nickname": user.nickname,
        "timezone": user.timezone,
        "seed_balance": user.seed_balance,
        "streak_days": user.streak_days,
        "created_at": to_utc_iso(user.created_at),
    }


async def _issue_tokens(db: AsyncSession, user: User) -> dict:
    settings = get_settings()
    session = AuthSession(
        user_id=user.id,
        session_family=uuid.uuid4().hex,
        expires_at=utcnow() + timedelta(days=settings.refresh_token_ttl_days),
    )
    db.add(session)
    await db.flush()
    refresh, jti = create_refresh_token(user.id, session.id)
    db.add(
        RefreshToken(
            session_id=session.id,
            jti_hash=sha256_hex(jti),
            expires_at=session.expires_at,
        )
    )
    access = create_access_token(user.id, session.id)
    return {
        "user": user_payload(user),
        "access_token": access,
        "refresh_token": refresh,
        "token_type": "bearer",
        "expires_in": settings.access_token_ttl_seconds,
    }


@router.post("/auth/signup", status_code=201)
async def signup(body: SignupRequest, db: AsyncSession = Depends(get_db)):
    exists = await db.scalar(sa.select(User.id).where(User.email == body.email.lower()))
    if exists is not None:
        raise AppError(409, "EMAIL_ALREADY_EXISTS", "이미 가입된 이메일입니다.")

    user = User(
        email=body.email.lower(),
        password_hash=hash_password(body.password),
        nickname=body.nickname.strip(),
    )
    db.add(user)
    try:
        await db.flush()
    except IntegrityError as exc:
        # 동시 가입은 사전 조회를 둘 다 통과할 수 있으므로 DB unique를 마지막 방어선으로 삼는다.
        await db.rollback()
        raise AppError(409, "EMAIL_ALREADY_EXISTS", "이미 가입된 이메일입니다.") from exc

    # 가입과 동시에 기본 품종 식물을 심어준다 (design.md 3.1)
    species = await db.scalar(
        sa.select(PlantSpecies).where(PlantSpecies.unlock_price == 0).order_by(PlantSpecies.id)
    )
    if species is not None:
        db.add(
            Plant(
                user_id=user.id, species_id=species.id, name=species.name,
                status=PlantStatus.ACTIVE, planted_at=utcnow(),
                emotion_profile=plant_service.empty_emotion_profile(),
            )
        )

    # 0003 캐릭터 카탈로그가 설치된 환경에서는 무료 스타터도 함께 지급한다.
    starter_item = await db.scalar(
        sa.select(Item).where(
            Item.code == "character_baby_pot",
            Item.type == "main_character",
            Item.is_active.is_(True),
        )
    )
    if starter_item is not None:
        db.add(UserItem(user_id=user.id, item_id=starter_item.id))
    payload = await _issue_tokens(db, user)
    await db.commit()
    return payload


@router.post("/auth/login")
async def login(body: LoginRequest, request: Request, db: AsyncSession = Depends(get_db)):
    client_ip = request.client.host if request.client else "unknown"
    rate_key = f"{body.email.lower()}|{client_ip}"
    _check_login_rate(rate_key)

    user = await db.scalar(sa.select(User).where(User.email == body.email.lower()))
    # 계정 존재 여부가 드러나지 않게 오류 문구를 통일한다
    if user is None or not verify_password(user.password_hash, body.password):
        _record_login_failure(rate_key)
        raise AppError(401, "AUTH_INVALID_CREDENTIALS", "이메일 또는 비밀번호를 확인해 주세요.")
    _clear_login_failures(rate_key)
    payload = await _issue_tokens(db, user)
    await db.commit()
    return payload


@router.post("/auth/refresh")
async def refresh(body: RefreshRequest, db: AsyncSession = Depends(get_db)):
    try:
        claims = decode_token(body.refresh_token, "refresh")
    except TokenError as exc:
        raise AppError(401, exc.code, "다시 로그인해 주세요.") from exc

    token_row = await db.scalar(
        sa.select(RefreshToken)
        .where(RefreshToken.jti_hash == sha256_hex(claims["jti"]))
        .with_for_update()
    )
    session = await db.get(AuthSession, int(claims["sid"]))
    if (
        token_row is None
        or session is None
        or token_row.session_id != session.id
        or session.user_id != int(claims["sub"])
        or session.revoked_at is not None
    ):
        raise AppError(401, "AUTH_TOKEN_INVALID", "다시 로그인해 주세요.")

    now = utcnow()
    if token_row.revoked_at is not None or token_row.expires_at < now:
        raise AppError(401, "AUTH_TOKEN_INVALID", "다시 로그인해 주세요.")

    if token_row.used_at is not None:
        # 이미 사용한 refresh의 재사용 → 같은 세션 패밀리 전체 폐기 (design.md 9.2)
        session.revoked_at = now
        await db.execute(
            sa.update(RefreshToken)
            .where(RefreshToken.session_id == session.id, RefreshToken.revoked_at.is_(None))
            .values(revoked_at=now)
        )
        await db.commit()
        raise AppError(401, "AUTH_REFRESH_REUSED", "보안을 위해 다시 로그인해 주세요.")

    user = await db.get(User, int(claims["sub"]))
    if user is None:
        raise AppError(401, "AUTH_TOKEN_INVALID", "다시 로그인해 주세요.")

    token_row.used_at = now
    new_refresh, new_jti = create_refresh_token(user.id, session.id)
    new_row = RefreshToken(
        session_id=session.id, jti_hash=sha256_hex(new_jti), expires_at=session.expires_at
    )
    db.add(new_row)
    await db.flush()
    token_row.replaced_by_id = new_row.id

    settings = get_settings()
    payload = {
        "user": user_payload(user),
        "access_token": create_access_token(user.id, session.id),
        "refresh_token": new_refresh,
        "token_type": "bearer",
        "expires_in": settings.access_token_ttl_seconds,
    }
    await db.commit()
    return payload


@router.post("/auth/logout", status_code=204)
async def logout(
    body: LogoutRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    try:
        claims = decode_token(body.refresh_token, "refresh")
    except TokenError as exc:
        raise AppError(401, "AUTH_TOKEN_INVALID", "토큰이 올바르지 않습니다.") from exc
    session = await db.get(AuthSession, int(claims["sid"]))
    if session is not None and session.user_id == user.id and session.revoked_at is None:
        now = utcnow()
        session.revoked_at = now
        await db.execute(
            sa.update(RefreshToken)
            .where(RefreshToken.session_id == session.id, RefreshToken.revoked_at.is_(None))
            .values(revoked_at=now)
        )
        await db.commit()
    return Response(status_code=204)


@router.post("/auth/logout-all", status_code=204)
async def logout_all(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    now = utcnow()
    await db.execute(
        sa.update(AuthSession)
        .where(AuthSession.user_id == user.id, AuthSession.revoked_at.is_(None))
        .values(revoked_at=now)
    )
    await db.commit()
    return Response(status_code=204)


@router.get("/users/me")
async def me(user: User = Depends(get_current_user)):
    return user_payload(user)
