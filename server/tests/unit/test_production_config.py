import pytest
from pydantic import ValidationError
from starlette.responses import Response

from app.api.routers.health import ready
from app.core.config import Settings, get_settings
from app.main import create_app


def _production_settings(**overrides):
    values = {
        "app_env": "production",
        "data_profile": "real-data",
        "database_url": "mysql+aiomysql://mongroo:secret@mysql/mongroo",
        "jwt_secret": "production-secret-0123456789abcdef0123456789",
        "field_encryption_keys": {
            "v1": "MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA="
        },
        "active_field_encryption_key_id": "v1",
        "ai_mode": "disabled",
        "cors_origins": ["https://app.mongroo.example"],
        "cors_origin_regex": None,
        "allowed_hosts": ["api.mongroo.example"],
    }
    values.update(overrides)
    return Settings(_env_file=None, **values)


def test_production_settings_accept_only_explicit_secure_values():
    settings = _production_settings()

    assert settings.app_env == "production"


def test_production_settings_validates_every_decryption_key():
    with pytest.raises(ValidationError):
        _production_settings(
            field_encryption_keys={
                "v1": "MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA=",
                "retired": "not-base64",
            }
        )


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("jwt_secret", "dev-only-secret-change-me"),
        ("data_profile", "demo"),
        ("field_encryption_keys", {}),
        ("database_url", "sqlite+aiosqlite:///./prod.db"),
        (
            "database_url",
            "mysql+aiomysql://mongroo:replace-with-password@mysql/mongroo",
        ),
        ("ai_mode", "fake"),
        ("cors_origins", ["http://app.mongroo.example"]),
        ("cors_origin_regex", ".*"),
        ("allowed_hosts", ["*"]),
    ],
)
def test_production_settings_reject_unsafe_defaults(field, value):
    with pytest.raises(ValidationError):
        _production_settings(**{field: value})


def test_production_app_does_not_publish_api_schema(monkeypatch):
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("DATA_PROFILE", "real-data")
    monkeypatch.setenv("DATABASE_URL", "mysql+aiomysql://mongroo:secret@mysql/mongroo")
    monkeypatch.setenv("JWT_SECRET", "production-secret-0123456789abcdef0123456789")
    monkeypatch.setenv(
        "FIELD_ENCRYPTION_KEYS",
        '{"v1":"MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA="}',
    )
    monkeypatch.setenv("ACTIVE_FIELD_ENCRYPTION_KEY_ID", "v1")
    monkeypatch.setenv("AI_MODE", "disabled")
    monkeypatch.setenv("CORS_ORIGINS", '["https://app.mongroo.example"]')
    monkeypatch.setenv("CORS_ORIGIN_REGEX", "")
    monkeypatch.setenv("ALLOWED_HOSTS", '["api.mongroo.example"]')
    get_settings.cache_clear()
    try:
        app = create_app()
        assert app.docs_url is None
        assert app.redoc_url is None
        assert app.openapi_url is None
    finally:
        get_settings.cache_clear()


class _UnavailableDatabase:
    async def execute(self, _statement):
        raise RuntimeError("database unavailable")


async def test_readiness_returns_503_when_database_is_down():
    response = Response()

    payload = await ready(response, _UnavailableDatabase())

    assert response.status_code == 503
    assert payload["status"] == "down"
