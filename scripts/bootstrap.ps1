# 개발 환경 초기 구성: venv, 의존성, MySQL, 마이그레이션
# 사용법: powershell -ExecutionPolicy Bypass -File scripts\bootstrap.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

Write-Host "[1/5] Python venv"
if (-not (Test-Path "server\.venv")) {
    $py = Get-Command python -ErrorAction SilentlyContinue
    $py312 = "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
    if (Test-Path $py312) { & $py312 -m venv server\.venv }
    elseif ($py) { & python -m venv server\.venv }
    else { throw "Python 3.12를 먼저 설치하세요" }
}
& server\.venv\Scripts\python.exe -m pip install --quiet --upgrade pip
& server\.venv\Scripts\python.exe -m pip install --quiet -e "server[analysis,dev]" 2>$null
if ($LASTEXITCODE -ne 0) {
    Push-Location server
    & .venv\Scripts\python.exe -m pip install --quiet fastapi "uvicorn[standard]" sqlalchemy alembic aiosqlite aiomysql cryptography "pydantic[email]" pydantic-settings argon2-cffi PyJWT httpx tzdata kiwipiepy pytest pytest-asyncio ruff
    Pop-Location
}

Write-Host "[2/5] .env"
if (-not (Test-Path "server\.env")) {
    Copy-Item ".env.example" "server\.env"
    Write-Host "  server\.env 생성됨 - JWT_SECRET을 교체하세요"
}

Write-Host "[3/5] MySQL (Docker)"
docker compose up -d mysql
if ($LASTEXITCODE -ne 0) { throw "Docker Desktop이 실행 중인지 확인하세요" }

Write-Host "[4/5] MySQL 대기"
$deadline = (Get-Date).AddMinutes(2)
while ($true) {
    $health = docker inspect --format "{{.State.Health.Status}}" mongroo-mysql 2>$null
    if ($health -eq "healthy") { break }
    if ((Get-Date) -gt $deadline) { throw "MySQL이 준비되지 않았습니다" }
    Start-Sleep -Seconds 3
}

Write-Host "[5/5] DB 마이그레이션"
Push-Location server
& .venv\Scripts\python.exe -m alembic upgrade head
Pop-Location

Write-Host ""
Write-Host "완료. 데모 실행: scripts\start_demo.ps1"
Write-Host "Flutter 앱: cd app; flutter pub get; flutter run"
