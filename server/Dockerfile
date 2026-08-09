FROM python:3.14.0-slim-bookworm AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/app/.venv/bin:$PATH"

RUN groupadd --system mongroo && useradd --system --gid mongroo --home /app mongroo

WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN python -m pip install --no-cache-dir uv==0.11.13 \
    && uv sync --frozen --no-dev --no-install-project \
    && rm -rf /root/.cache

COPY alembic.ini ./
COPY alembic ./alembic
COPY app ./app

USER mongroo
EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips=*"]
