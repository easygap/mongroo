from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.errors import register_error_handlers
from app.api.routers import auth, chat, game, health, moods, plants, reports
from app.core.config import get_settings
from app.core.logging import RequestLogMiddleware, setup_logging


def create_app() -> FastAPI:
    setup_logging()
    app = FastAPI(
        title="몽그루 API",
        version="0.1.0",
        docs_url="/docs",
        openapi_url="/openapi.json",
    )
    app.add_middleware(RequestLogMiddleware)
    settings = get_settings()
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_origin_regex=settings.cors_origin_regex,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "Idempotency-Key", "X-Request-ID"],
    )
    register_error_handlers(app)

    prefix = "/api/v1"
    app.include_router(auth.router, prefix=prefix)
    app.include_router(moods.router, prefix=prefix)
    app.include_router(plants.router, prefix=prefix)
    app.include_router(chat.router, prefix=prefix)
    app.include_router(reports.router, prefix=prefix)
    app.include_router(game.router, prefix=prefix)
    app.include_router(health.router, prefix=prefix)
    return app


app = create_app()
