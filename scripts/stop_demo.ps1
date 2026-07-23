# 데모 프로세스 종료
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
    Where-Object { $_.CommandLine -match "uvicorn app.main:app|app.workers.ai_worker" } |
    ForEach-Object {
        Write-Host "종료: PID $($_.ProcessId)"
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }

docker compose stop mysql
Write-Host "완료"
