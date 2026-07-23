# 로컬 모델 벤치마크

로컬 LLM 후보를 같은 조건에서 실행한 결과를 모은다. RTX 4060 Ti 8GB에서
VRAM, 첫 응답 시간, 생성 속도와 전체 지연을 측정해 기본 모델과 `num_ctx`,
timeout을 정한다.

## 기록하는 측정 항목

| 항목 | 수집 방법 |
|------|-----------|
| VRAM 사용량 | `nvidia-smi --query-gpu` 파싱. 실행 전 / 워밍업(모델 로드) 직후 / 실행 중 최대 |
| TTFT | 스트리밍 첫 청크 수신까지의 시간 |
| tokens/sec | Ollama 응답의 `eval_count / eval_duration` |
| 전체 지연 | 요청 전송부터 마지막 청크까지 |
| timeout 발생 | 프롬프트당 timeout(기본 120초) 초과 건수 |
| 응답 길이 | 문자 수 (num_predict=384 기준) |
| 한국어 품질 메모 | 자동 수집 불가. 응답 미리보기를 보고 Markdown에 기록 |
| 안전 회귀 결과 | `ai/chatbot_experiments/prompt_probe_set.md` 수동 실행 결과를 수기 기록 |

CPU/RAM offload 여부는 워밍업 직후 VRAM과 모델 크기를 비교해 판단하고 메모에
남긴다.

## 실행 방법

```powershell
ollama pull qwen3:8b-q4_K_M
cd ai\chatbot_experiments
python bench_ollama.py --model qwen3:8b-q4_K_M
python bench_ollama.py --model qwen3:8b-q4_K_M --temperature 0.2
```

- 고정 한국어 자기성찰 프롬프트 8개를 순차(동시성 1)로 실행한다. 프롬프트
  세트는 `bench_ollama.py`의 상수라서 실행 간 비교가 가능하다.
- 기본 옵션은 제품 초기값과 같다: `num_ctx=4096`, `num_predict=384`.
- temperature는 0.2~0.4 범위를 나눠 실행해 비교한다(설계서 6.2).
- 측정 중에는 다른 GPU 작업(분류기 학습 등)을 중단한다.

## 결과 파일 명명 규칙

```
docs/benchmarks/{UTC시각 YYYYMMDD_HHMMSS}_{모델태그의 ':'과 '/'를 '_'로 치환}.json
docs/benchmarks/{동일 이름}.md
```

예: `20260712_143001_qwen3_8b-q4_K_M.json` / `...md`

- JSON: 원시 측정값 (옵션, VRAM 스냅샷, 프롬프트별 결과, 요약 통계)
- Markdown: 사람이 읽는 리포트. "한국어 품질·안전 메모" 절에 품질 소견과
  prompt_probe_set 회귀 결과를 채워 넣어야 리포트가 완성된 것으로 본다.
- 파일은 삭제하지 않고 누적한다. 같은 모델의 재측정은 새 타임스탬프로 남겨
  변경 이력을 추적한다.

## 판정 절차

1. 후보 모델별로 벤치마크를 실행하고 리포트를 완성한다.
2. 비교 기준: VRAM이 8GB 안에서 안정적인가(offload 없이), TTFT와 전체 지연이
   60초 timeout 계약(설계서 12.3) 안에서 여유가 있는가, 한국어 자기성찰 대화
   품질, 안전 회귀(B~D군) 통과 여부, 라이선스 조건(models/manifest.yaml).
3. 확정한 모델·컨텍스트·timeout을 `models/manifest.yaml`의 eval_report 경로와
   함께 갱신하고, 요약 수치를 루트 README에 기록한다.
4. 감정 분류기 평가 리포트(eval_report.md)는 모델 산출물 디렉터리
   (`MONGROO_MODEL_ROOT`)에 남고, 여기에는 회귀·비교 요약만 옮겨 적는다.
