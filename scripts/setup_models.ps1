# 로컬 LLM 준비: Ollama 설치 확인 + 후보 모델 다운로드 (design.md 6.2, 6.5)
# 사용법: scripts\setup_models.ps1 [-WithExaone]
param(
    [switch]$WithExaone
)
$ErrorActionPreference = "Stop"

$ollama = Get-Command ollama -ErrorAction SilentlyContinue
if (-not $ollama) {
    Write-Host "Ollama가 없습니다. 설치: winget install -e --id Ollama.Ollama"
    Write-Host "설치 후 이 스크립트를 다시 실행하세요."
    exit 1
}

Write-Host "[1/2] 기본 모델: qwen3:8b-q4_K_M (Apache-2.0)"
ollama pull qwen3:8b-q4_K_M

if ($WithExaone) {
    # EXAONE 1.1-NC 라이선스: 상업 이용 금지. models/manifest.yaml의 조건 확인 후 사용
    Write-Host "[2/2] 비교 모델: exaone3.5:7.8b (EXAONE 1.1-NC, 비상업)"
    ollama pull exaone3.5:7.8b
} else {
    Write-Host "[2/2] 비교 모델 생략 (-WithExaone로 추가 가능)"
}

Write-Host ""
Write-Host "모델 목록:"
ollama list
Write-Host ""
Write-Host "벤치마크: server\.venv\Scripts\python.exe ai\chatbot_experiments\bench_ollama.py --model qwen3:8b-q4_K_M"
Write-Host "결과를 docs\benchmarks\ 에 기록하고 models\manifest.yaml 을 갱신하세요."
