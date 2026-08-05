"""인증. refresh는 매 사용 시 회전하고 재사용을 감지한다 (design.md 9.2)."""
import hashlib
import hmac
import uuid
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
from app.models.user import AuthSession, LoginRateLimit, RefreshToken, User
from app.schemas.requests import (
    AccountDeleteRequest,
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    SignupRequest,
)
from app.services import plants as plant_service
from app.services.account import build_account_export, delete_account_data

router = APIRouter(tags=["auth"])

def _login_rate_key(scope: str, identifier: str) -> str:
    """식별자 원문 대신 서버 secret 기반 HMAC만 DB에 남긴다."""

    secret = get_settings().jwt_secret.encode("utf-8")
    message = f"login|{scope}|{identifier.lower()}".encode("utf-8")
    return hmac.new(secret, message, hashlib.sha256).hexdigest()


async def _check_login_rate(db: AsyncSession, key: str, limit: int) -> None:
    settings = get_settings()
    now = utcnow()
    row = await db.scalar(
        sa.select(LoginRateLimit)
        .where(LoginRateLimit.rate_key == key)
        .with_for_update()
    )
    if row is None:
        return
    if row.window_started_at <= now - timedelta(
        seconds=settings.login_rate_limit_window_seconds
    ):
        await db.delete(row)
        await db.flush()
        return
    if row.failure_count >= limit:
        raise AppError(429, "RATE_LIMITED", "잠시 후 다시 시도해 주세요.")


async def _record_login_failure(db: AsyncSession, key: str) -> None:
    settings = get_settings()
    now = utcnow()
    await db.execute(
        sa.delete(LoginRateLimit).where(
            LoginRateLimit.updated_at
            < now - timedelta(seconds=settings.login_rate_limit_window_seconds * 2)
        )
    )
    row = await db.scalar(
        sa.select(LoginRateLimit)
        .where(LoginRateLimit.rate_key == key)
        .with_for_update()
    )
    if row is None:
        try:
            async with db.begin_nested():
                row = LoginRateLimit(
                    rate_key=key,
                    failure_count=1,
                    window_started_at=now,
                    updated_at=now,
                )
                db.add(row)
                await db.flush([row])
            return
        except IntegrityError:
            # 다른 API 프로세스가 같은 HMAC bucket을 먼저 만들었다. SAVEPOINT만
            # 롤백해 이 요청에서 먼저 기록한 계정/IP bucket을 잃지 않는다.
            row = await db.scalar(
                sa.select(LoginRateLimit)
                .where(LoginRateLimit.rate_key == key)
                .with_for_update()
            )
            if row is None:
                raise
    if row.window_started_at <= now - timedelta(
        seconds=settings.login_rate_limit_window_seconds
    ):
        row.window_started_at = now
        row.failure_count = 1
    else:
        row.failure_count += 1
    row.updated_at = now
    await db.flush()


async def _clear_login_failures(db: AsyncSession, key: str) -> None:
    row = await db.get(LoginRateLimit, key)
    if row is not None:
        await db.delete(row)


def user_payload(user: User) -> dict:
    return {
        "id": user.id,
        "email": user.email,
        "nickname": user.nickname,
        "timezone": user.timezone,
        "seed_balance": user.seed_balance,
        "streak_days": user.streak_days,
        "consent": {
            "terms_version": user.terms_version,
            "privacy_version": user.privacy_version,
            "sensitive_consent_version": user.sensitive_consent_version,
            "age_confirmed": user.age_confirmed_at is not None,
        },
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
    settings = get_settings()
    accepted = all(
        (
            body.terms_accepted,
            body.privacy_accepted,
            body.sensitive_data_consent,
            body.age_over_18,
        )
    )
    if settings.data_profile == "real-data" and not accepted:
        raise AppError(
            422,
            "CONSENT_REQUIRED",
            "만 18세 이상 확인과 필수 약관·개인정보·민감정보 동의가 필요합니다.",
        )
    if settings.data_profile == "real-data" and (
        body.terms_version != settings.terms_version
        or body.privacy_version != settings.privacy_version
        or body.sensitive_consent_version != settings.sensitive_consent_version
    ):
        raise AppError(
            409,
            "CONSENT_VERSION_OUTDATED",
            "약관과 동의 내용이 갱신되었습니다. 앱을 새로고침한 뒤 다시 확인해 주세요.",
        )
    exists = await db.scalar(sa.select(User.id).where(User.email == body.email.lower()))
    if exists is not None:
        raise AppError(409, "EMAIL_ALREADY_EXISTS", "이미 가입된 이메일입니다.")

    consented_at = utcnow() if accepted else None
    user = User(
        email=body.email.lower(),
        password_hash=hash_password(body.password),
        nickname=body.nickname.strip(),
        terms_version=settings.terms_version if accepted else None,
        privacy_version=settings.privacy_version if accepted else None,
        sensitive_consent_version=(
            settings.sensitive_consent_version if accepted else None
        ),
        age_confirmed_at=consented_at,
        consented_at=consented_at,
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
    account_rate_key = _login_rate_key("account", body.email)
    ip_rate_key = _login_rate_key("ip", client_ip)
    settings = get_settings()
    await _check_login_rate(db, account_rate_key, settings.login_rate_limit_count)
    await _check_login_rate(db, ip_rate_key, settings.login_ip_rate_limit_count)

    user = await db.scalar(sa.select(User).where(User.email == body.email.lower()))
    # 계정 존재 여부가 드러나지 않게 오류 문구를 통일한다
    if user is None or not verify_password(user.password_hash, body.password):
        await _record_login_failure(db, account_rate_key)
        await _record_login_failure(db, ip_rate_key)
        await db.commit()
        raise AppError(401, "AUTH_INVALID_CREDENTIALS", "이메일 또는 비밀번호를 확인해 주세요.")
    await _clear_login_failures(db, account_rate_key)
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


@router.get("/users/me/export")
async def export_account(
    response: Response,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    response.headers["Content-Disposition"] = (
        'attachment; filename="mongroo-account-export.json"'
    )
    return await build_account_export(db, user)


@router.delete("/users/me", status_code=204)
async def delete_account(
    body: AccountDeleteRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if body.confirmation != "몽그루 탈퇴" or not verify_password(
        user.password_hash, body.password
    ):
        raise AppError(
            422,
            "ACCOUNT_DELETE_CONFIRMATION_INVALID",
            "확인 문구와 현재 비밀번호를 다시 확인해 주세요.",
        )
    await delete_account_data(db, user)
    await db.commit()
    return Response(status_code=204)
