import pytest

from app.core.config import get_settings
from app.core.field_encryption import (
    FieldEncryptionError,
    ProtectedJSON,
    ProtectedText,
    get_field_cipher,
)


@pytest.fixture
def real_data_settings(monkeypatch):
    monkeypatch.setenv("DATA_PROFILE", "real-data")
    monkeypatch.setenv(
        "FIELD_ENCRYPTION_KEYS",
        '{"v1":"MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA="}',
    )
    monkeypatch.setenv("ACTIVE_FIELD_ENCRYPTION_KEY_ID", "v1")
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def test_field_cipher_is_authenticated_and_nondeterministic(real_data_settings):
    cipher = get_field_cipher()

    first = cipher.encrypt("아주 사적인 마음 일기", purpose="mood_entries.content")
    second = cipher.encrypt("아주 사적인 마음 일기", purpose="mood_entries.content")

    assert first.startswith("enc:v1:v1:")
    assert first != second
    assert cipher.decrypt(first, purpose="mood_entries.content") == "아주 사적인 마음 일기"
    with pytest.raises(FieldEncryptionError):
        cipher.decrypt(first, purpose="chat_messages.content")


def test_field_cipher_rejects_tampering(real_data_settings):
    cipher = get_field_cipher()
    encrypted = cipher.encrypt("원문", purpose="mood_entries.content")
    marker = len(encrypted) // 2
    replacement = "A" if encrypted[marker] != "A" else "B"
    tampered = encrypted[:marker] + replacement + encrypted[marker + 1 :]

    with pytest.raises(FieldEncryptionError):
        cipher.decrypt(tampered, purpose="mood_entries.content")

    with pytest.raises(FieldEncryptionError):
        cipher.decrypt(
            encrypted.rsplit(":", 1)[0] + ":!" + encrypted.rsplit(":", 1)[1],
            purpose="mood_entries.content",
        )


def test_protected_types_round_trip_text_and_json(real_data_settings):
    text_type = ProtectedText("mood_entries.content")
    json_type = ProtectedJSON("mood_entries.emotion_tags")

    stored_text = text_type.process_bind_param("오늘의 기록", None)
    stored_json = json_type.process_bind_param(["기쁨", "안도"], None)

    assert stored_text != "오늘의 기록"
    assert stored_json != '["기쁨","안도"]'
    assert text_type.process_result_value(stored_text, None) == "오늘의 기록"
    assert json_type.process_result_value(stored_json, None) == ["기쁨", "안도"]


def test_envelope_looking_user_text_is_encrypted_as_plaintext(real_data_settings):
    field = ProtectedText("mood_entries.content")
    user_text = "enc:v1:v1:사용자가 직접 쓴 문자열"

    stored = field.process_bind_param(user_text, None)

    assert stored != user_text
    assert field.process_result_value(stored, None) == user_text


def test_real_data_profile_never_reads_plaintext_protected_fields(real_data_settings):
    with pytest.raises(FieldEncryptionError):
        ProtectedText("mood_entries.content").process_result_value("평문", None)
    with pytest.raises(FieldEncryptionError):
        ProtectedJSON("reports.stats").process_result_value("{}", None)
