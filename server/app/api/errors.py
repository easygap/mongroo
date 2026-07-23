import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

logger = logging.getLogger("mongroo.api")


class AppError(Exception):
    def __init__(self, http_status: int, code: str, message: str, details: dict | None = None):
        self.http_status = http_status
        self.code = code
        self.message = message
        self.details = details or {}


def error_body(request: Request, code: str, message: str, details: dict | None = None) -> dict:
    return {
        "code": code,
        "message": message,
        "details": details or {},
        "request_id": getattr(request.state, "request_id", ""),
    }


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def handle_app_error(request: Request, exc: AppError):
        return JSONResponse(
            status_code=exc.http_status,
            content=error_body(request, exc.code, exc.message, exc.details),
        )

    @app.exception_handler(RequestValidationError)
    async def handle_validation_error(request: Request, exc: RequestValidationError):
        errors = [
            {"loc": ".".join(str(p) for p in e["loc"][1:]), "type": e["type"]}
            for e in exc.errors()
        ]
        return JSONResponse(
            status_code=422,
            content=error_body(
                request, "VALIDATION_ERROR", "요청 값이 올바르지 않습니다.", {"errors": errors}
            ),
        )

    @app.exception_handler(Exception)
    async def handle_unexpected(request: Request, exc: Exception):
        # 내부 예외 원문은 응답에 노출하지 않는다
        logger.error(
            "unhandled_error",
            extra={"request_id": getattr(request.state, "request_id", ""),
                   "error_code": type(exc).__name__},
        )
        return JSONResponse(
            status_code=500,
            content=error_body(request, "INTERNAL_ERROR", "일시적인 오류가 발생했습니다."),
        )
