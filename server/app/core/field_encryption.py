"""민감 필드용 AES-256-GCM envelope 암호화.

DB에는 키 ID와 nonce가 포함된 ciphertext만 저장한다. 키는 환경의 secret store에서
주입하며, 이전 키를 ``FIELD_ENCRYPTION_KEYS``에 남겨 둔 채 active ID만 바꾸면
무중단으로 읽기 키를 회전할 수 있다.
"""

from __future__ import annotations

import base64
import binascii
import json
import os
from dataclasses import dataclass
from functools import lru_cache
from typing import Any

import sqlalchemy as sa
from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from sqlalchemy.types import TypeDecorator

from app.core.config import get_settings

ENVELOPE_PREFIX = "enc:v1:"
_NONCE_BYTES = 12


class FieldEncryptionError(RuntimeError):
    """키 누락, 변조 또는 운영 DB의 평문 민감 필드를 나타낸다."""


@dataclass(frozen=True)
class FieldCipher:
    keys: dict[str, bytes]
    active_key_id: str

    @classmethod
    def from_settings(cls) -> "FieldCipher":
        settings = get_settings()
        keys: dict[str, bytes] = {}
        for key_id, encoded in settings.field_encryption_keys.items():
            try:
                decoded = base64.b64decode(encoded, validate=True)
            except Exception as exc:  # 설정 validator 밖에서 직접 호출하는 경우의 방어선
                raise FieldEncryptionError(
                    f"field encryption key {key_id!r} is not valid base64"
                ) from exc
            if len(decoded) != 32:
                raise FieldEncryptionError(
                    f"field encryption key {key_id!r} must be exactly 32 bytes"
                )
            keys[key_id] = decoded
        if settings.active_field_encryption_key_id not in keys:
            raise FieldEncryptionError("active field encryption key is unavailable")
        return cls(keys=keys, active_key_id=settings.active_field_encryption_key_id)

    def encrypt(self, plaintext: str, *, purpose: str) -> str:
        nonce = os.urandom(_NONCE_BYTES)
        ciphertext = AESGCM(self.keys[self.active_key_id]).encrypt(
            nonce,
            plaintext.encode("utf-8"),
            purpose.encode("utf-8"),
        )
        payload = base64.urlsafe_b64encode(nonce + ciphertext).decode("ascii")
        return f"{ENVELOPE_PREFIX}{self.active_key_id}:{payload}"

    def decrypt(self, envelope: str, *, purpose: str) -> str:
        try:
            marker, version, key_id, encoded = envelope.split(":", 3)
        except ValueError as exc:
            raise FieldEncryptionError("invalid encrypted field envelope") from exc
        if marker != "enc" or version != "v1" or key_id not in self.keys:
            raise FieldEncryptionError("encrypted field uses an unavailable key")
        try:
            payload = base64.b64decode(
                encoded.encode("ascii"), altchars=b"-_", validate=True
            )
            nonce, ciphertext = payload[:_NONCE_BYTES], payload[_NONCE_BYTES:]
            if len(nonce) != _NONCE_BYTES or not ciphertext:
                raise ValueError("empty ciphertext")
            plaintext = AESGCM(self.keys[key_id]).decrypt(
                nonce,
                ciphertext,
                purpose.encode("utf-8"),
            )
            return plaintext.decode("utf-8")
        except (binascii.Error, InvalidTag, ValueError, UnicodeError) as exc:
            raise FieldEncryptionError("encrypted field authentication failed") from exc


@lru_cache(maxsize=8)
def _cipher_for_configuration(
    keys: tuple[tuple[str, str], ...], active_key_id: str
) -> FieldCipher:
    decoded: dict[str, bytes] = {}
    for key_id, encoded in keys:
        value = base64.b64decode(encoded, validate=True)
        if len(value) != 32:
            raise FieldEncryptionError(
                f"field encryption key {key_id!r} must be exactly 32 bytes"
            )
        decoded[key_id] = value
    if active_key_id not in decoded:
        raise FieldEncryptionError("active field encryption key is unavailable")
    return FieldCipher(keys=decoded, active_key_id=active_key_id)


def get_field_cipher() -> FieldCipher:
    settings = get_settings()
    return _cipher_for_configuration(
        tuple(sorted(settings.field_encryption_keys.items())),
        settings.active_field_encryption_key_id,
    )


def is_encrypted(value: object) -> bool:
    return isinstance(value, str) and value.startswith(ENVELOPE_PREFIX)


class ProtectedText(TypeDecorator[str]):
    """real-data 프로파일에서만 암호화하는 TEXT 컬럼 타입."""

    impl = sa.Text
    cache_ok = True

    def __init__(self, purpose: str) -> None:
        super().__init__()
        self.purpose = purpose

    def process_bind_param(self, value: str | None, dialect) -> str | None:
        if value is None:
            return None
        if get_settings().data_profile != "real-data":
            return value
        return get_field_cipher().encrypt(value, purpose=self.purpose)

    def process_result_value(self, value: str | None, dialect) -> str | None:
        if value is None:
            return None
        if is_encrypted(value):
            return get_field_cipher().decrypt(value, purpose=self.purpose)
        if get_settings().data_profile == "real-data":
            raise FieldEncryptionError(
                f"plaintext value found in protected field {self.purpose}"
            )
        return value


class ProtectedJSON(TypeDecorator[Any]):
    """JSON 값을 canonical JSON으로 직렬화한 뒤 암호화해 TEXT에 저장한다."""

    impl = sa.Text
    cache_ok = True

    def __init__(self, purpose: str) -> None:
        super().__init__()
        self.purpose = purpose

    def process_bind_param(self, value: Any, dialect) -> str | None:
        if value is None:
            return None
        raw = json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
        if get_settings().data_profile != "real-data":
            return raw
        return get_field_cipher().encrypt(raw, purpose=self.purpose)

    def process_result_value(self, value: Any, dialect) -> Any:
        if value is None:
            return None
        if not isinstance(value, str):
            # JSON→TEXT 전환 직후의 드라이버 값이나 demo fixture를 허용한다.
            if get_settings().data_profile == "real-data":
                raise FieldEncryptionError(
                    f"plaintext value found in protected field {self.purpose}"
                )
            return value
        if is_encrypted(value):
            raw = get_field_cipher().decrypt(value, purpose=self.purpose)
        else:
            if get_settings().data_profile == "real-data":
                raise FieldEncryptionError(
                    f"plaintext value found in protected field {self.purpose}"
                )
            raw = value
        try:
            return json.loads(raw)
        except json.JSONDecodeError as exc:
            raise FieldEncryptionError(
                f"protected JSON field {self.purpose} is invalid"
            ) from exc
