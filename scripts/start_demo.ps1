# 로컬 데모 실행: MySQL + API + AI worker를 각각 띄운다 (design.md 5.4)
# 사용법: scripts\start_demo.ps1 [-AiMode local|fake|disabled]
param(
    [ValidateSet("local", "fake", "disabled")]
    [string]$AiMode = "fake"
)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

docker compose up -d mysql | Out-Null

if ($AiMode -eq "local") {
    # Ollama 확인 (Windows native)
    try {
        Invoke-RestMethod "http://127.0.0.1:11434/api/tags" -TimeoutSec 3 | Out-Null
    } catch {
        Write-Warning "Ollama가 응답하지 않습니다. scripts\setup_models.ps1 실행 여부를 확인하세요."
    }
}

$env:AI_MODE = $AiMode
Push-Location server
& .venv\Scripts\python.exe -m alembic upgrade head

Write-Host "API 서버 시작 (127.0.0.1:8000), AI worker 시작 - AI_MODE=$AiMode"
Start-Process -FilePath ".venv\Scripts\python.exe" `
    -ArgumentList "-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "8000" `
    -WindowStyle Minimized
Start-Process -FilePath ".venv\Scripts\python.exe" `
    -ArgumentList "-m", "app.workers.ai_worker" `
    -WindowStyle Minimized
Pop-Location

Start-Sleep -Seconds 3
try {
    $ready = Invoke-RestMethod "http://127.0.0.1:8000/api/v1/health/ready"
    Write-Host "health/ready: $($ready.status)"
} catch {
    Write-Warning "서버 상태 확인 실패. 잠시 후 http://127.0.0.1:8000/api/v1/health/ready 를 확인하세요."
}
Write-Host "API 문서: http://127.0.0.1:8000/docs"
Write-Host "에뮬레이터에서 앱 base URL: http://10.0.2.2:8000/api/v1"
Write-Host "종료: scripts\stop_demo.ps1"
