import hashlib
import uuid
from datetime import datetime, timedelta, timezone

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError

from app.core.config import get_settings

# argon2id 기본 파라미터 사용. 변경 시 버전을 남길 것
PASSWORD_HASHER_VERSION = "argon2id-v1"
_hasher = PasswordHasher()


def hash_password(raw: str) -> str:
    return _hasher.hash(raw)


def verify_password(hashed: str, raw: str) -> bool:
    try:
        return _hasher.verify(hashed, raw)
    except VerifyMismatchError:
        return False
    except Exception:
        return False


def sha256_hex(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


class TokenError(Exception):
    def __init__(self, code: str) -> None:
        self.code = code  # AUTH_TOKEN_EXPIRED | AUTH_TOKEN_INVALID


def _base_claims(user_id: int, session_id: int, ttl: timedelta, token_type: str) -> dict:
    settings = get_settings()
    # naive datetime의 timestamp()는 로컬 시간대로 해석되므로 aware UTC를 사용한다
    now = datetime.now(timezone.utc)
    return {
        "iss": settings.jwt_issuer,
        "aud": settings.jwt_audience,
        "sub": str(user_id),
        "sid": session_id,
        "jti": uuid.uuid4().hex,
        "typ": token_type,
        "iat": int(now.timestamp()),
        "exp": int((now + ttl).timestamp()),
    }


def create_access_token(user_id: int, session_id: int) -> str:
    settings = get_settings()
    claims = _base_claims(
        user_id, session_id, timedelta(seconds=settings.access_token_ttl_seconds), "access"
    )
    return jwt.encode(claims, settings.jwt_secret, algorithm="HS256")


def create_refresh_token(user_id: int, session_id: int) -> tuple[str, str]:
    """(token, jti) 반환. DB에는 jti의 sha256만 저장한다 (design.md 9.2)."""
    settings = get_settings()
    claims = _base_claims(
        user_id, session_id, timedelta(days=settings.refresh_token_ttl_days), "refresh"
    )
    token = jwt.encode(claims, settings.jwt_secret, algorithm="HS256")
    return token, claims["jti"]


def decode_token(token: str, expected_type: str) -> dict:
    settings = get_settings()
    try:
        claims = jwt.decode(
            token,
            settings.jwt_secret,
            algorithms=["HS256"],
            issuer=settings.jwt_issuer,
            audience=settings.jwt_audience,
            options={"require": ["exp", "iat", "sub", "sid", "jti", "typ"]},
        )
    except jwt.ExpiredSignatureError as exc:
        raise TokenError("AUTH_TOKEN_EXPIRED") from exc
    except jwt.PyJWTError as exc:
        raise TokenError("AUTH_TOKEN_INVALID") from exc
    if claims.get("typ") != expected_type:
        raise TokenError("AUTH_TOKEN_INVALID")
    return claims
