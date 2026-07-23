# 데모 데이터 초기화: MySQL 볼륨을 지우고 스키마를 다시 만든다
# demo 프로파일은 합성 데이터만 담으므로 파기해도 된다 (design.md 9.1)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

& "$PSScriptRoot\stop_demo.ps1"

docker compose down -v
docker compose up -d mysql

$deadline = (Get-Date).AddMinutes(2)
while ($true) {
    $health = docker inspect --format "{{.State.Health.Status}}" mongroo-mysql 2>$null
    if ($health -eq "healthy") { break }
    if ((Get-Date) -gt $deadline) { throw "MySQL이 준비되지 않았습니다" }
    Start-Sleep -Seconds 3
}

Push-Location server
& .venv\Scripts\python.exe -m alembic upgrade head
Pop-Location
Write-Host "초기화 완료"
