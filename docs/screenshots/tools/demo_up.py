"""도트 개편 실기 검증용 데모 스택.

도커 없이 SQLite로 API(18800)와 AI worker(fake)를 띄우고 QA 계정을 준비한다.
메모리 `mood-pot-capture-pipeline`의 절차를 스크립트로 옮긴 것이다.

    server/.venv/Scripts/python.exe docs/screenshots/tools/demo_up.py
    server/.venv/Scripts/python.exe docs/screenshots/tools/demo_up.py --down
"""

from __future__ import annotations

import datetime as dt
import os
import pathlib
import sqlite3
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[3]
SERVER = ROOT / "server"
#: DB·로그·PID는 저장소의 tmp/ 아래(gitignore)에 둔다.
SCRATCH = ROOT / "tmp" / "demo"
SCRATCH.mkdir(parents=True, exist_ok=True)
DB = SCRATCH / "demo.sqlite"
PY = SERVER / ".venv" / "Scripts" / "python.exe"
PIDS = SCRATCH / "demo.pids"
BASE = "http://127.0.0.1:18800/api/v1"
EMAIL = "qa-pixel@example.com"
PASSWORD = "pixel-demo-2026!"

ENV = dict(
    os.environ,
    DATABASE_URL=f"sqlite+aiosqlite:///{DB.as_posix()}",
    AI_MODE="fake",
    APP_ENV="development",
    JWT_SECRET="pixel-overhaul-demo-secret-0123456789abcdef-xyz",
    CORS_ORIGINS='["http://127.0.0.1:8080","http://localhost:8080"]',
)


def down() -> None:
    if PIDS.exists():
        for pid in PIDS.read_text().split():
            subprocess.run(["taskkill", "/PID", pid, "/T", "/F"], capture_output=True)
        PIDS.unlink()
    print("stopped")


def up() -> None:
    import httpx

    if DB.exists():
        DB.unlink()
    subprocess.run(
        [str(PY), "-m", "alembic", "upgrade", "head"], cwd=SERVER, env=ENV, check=True
    )
    flags = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS
    api = subprocess.Popen(
        [str(PY), "-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "18800"],
        cwd=SERVER,
        env=ENV,
        stdout=open(SCRATCH / "api.log", "w"),
        stderr=subprocess.STDOUT,
        creationflags=flags,
    )
    worker = subprocess.Popen(
        [str(PY), "-m", "app.workers.ai_worker"],
        cwd=SERVER,
        env=ENV,
        stdout=open(SCRATCH / "worker.log", "w"),
        stderr=subprocess.STDOUT,
        creationflags=flags,
    )
    PIDS.write_text(f"{api.pid}\n{worker.pid}\n")
    for _ in range(90):
        try:
            if httpx.get(BASE + "/health/ready", timeout=2).status_code == 200:
                break
        except Exception:
            pass
        time.sleep(1)
    else:
        raise SystemExit("API가 준비되지 않았습니다 — api.log 확인")

    response = httpx.post(
        BASE + "/auth/signup",
        json={
            "email": EMAIL,
            "password": PASSWORD,
            "nickname": "도트검수",
            "terms_accepted": True,
            "privacy_accepted": True,
            "sensitive_data_consent": True,
            "age_over_18": True,
            "terms_version": "2026-08-05",
            "privacy_version": "2026-08-05",
            "sensitive_consent_version": "2026-08-05",
        },
        timeout=30,
    )
    print("signup", response.status_code, response.text[:160])
    response = httpx.post(
        BASE + "/auth/login", json={"email": EMAIL, "password": PASSWORD}, timeout=30
    )
    data = response.json()
    token = data.get("access_token") or data.get("tokens", {}).get("access_token")
    headers = {"Authorization": f"Bearer {token}"}

    con = sqlite3.connect(DB)
    row = con.execute("select id from plant_species where code='baby-pot'").fetchone()
    species_id = row[0] if row else None
    response = httpx.post(
        BASE + "/plants",
        json={"species_id": species_id, "name": "뽀또"},
        headers=headers,
        timeout=30,
    )
    print("plant", response.status_code, response.text[:160])
    if response.status_code >= 400 and response.status_code != 409:
        response = httpx.post(
            BASE + "/plants", json={"name": "뽀또"}, headers=headers, timeout=30
        )
        print("plant(default)", response.status_code, response.text[:160])

    response = httpx.post(
        BASE + "/moods",
        json={"content": "오늘은 도트로 다시 그린 서고를 걸어 볼 거야. 두근거린다."},
        headers={**headers, "Idempotency-Key": "pixel-demo-mood-1"},
        timeout=30,
    )
    print("mood", response.status_code, response.text[:120])

    user_id = con.execute("select id from users where email=?", (EMAIL,)).fetchone()[0]
    con.execute("update plants set exp=120 where user_id=?", (user_id,))
    now = dt.datetime.utcnow().replace(microsecond=0).isoformat(sep=" ")
    for region in (
        "moss_archive",
        "echo_well",
        "starlight_seed_vault",
        "heartwood_observatory",
    ):
        for stage in range(1, 9):
            con.execute(
                "insert or ignore into user_stage_progress"
                "(user_id, region_code, stage_no, cleared_at, clear_count, story_seen, updated_at)"
                " values (?,?,?,?,?,?,?)",
                (user_id, region, stage, now, 1, 1, now),
            )
    con.execute("update users set seed_balance=500 where id=?", (user_id,))
    con.commit()
    print("READY", EMAIL, PASSWORD, "user", user_id)


if __name__ == "__main__":
    if "--down" in sys.argv:
        down()
    else:
        up()
