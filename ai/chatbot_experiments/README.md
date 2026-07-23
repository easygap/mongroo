# 챗봇 후보 모델 측정

식물 대화에 쓸 로컬 LLM 후보를 RTX 4060 Ti 8GB에서 같은 조건으로 비교한다.
VRAM, TTFT, tokens/sec, 전체 지연, timeout과 한국어 품질을 기록한다.

P0에서는 챗봇 파인튜닝을 하지 않는다. 이 디렉터리는 측정과 프롬프트 실험만
다루고, 실제 대화 파이프라인(상태머신·안전 레이어)은 서버 쪽 구현이다.

## 구성

| 파일 | 역할 |
|------|------|
| `bench_ollama.py` | Ollama API로 고정 프롬프트 세트 실행, 성능·VRAM 측정 |
| `prompt_probe_set.md` | 한국어 품질·안전 회귀 프로브 목록과 기대 동작 |

후보 모델과 라이선스 조건은 `models/manifest.yaml`에 정리되어 있다.

## 실행 방법

```powershell
pip install httpx

# Ollama 실행 후 후보 모델 설치
ollama pull qwen3:8b-q4_K_M

# 기본 옵션: num_ctx=4096, num_predict=384, temperature=0.3, 순차 실행
python bench_ollama.py --model qwen3:8b-q4_K_M

# temperature 비교 (설계서 6.2: 0.2~0.4 실측 비교)
python bench_ollama.py --model qwen3:8b-q4_K_M --temperature 0.2
python bench_ollama.py --model qwen3:8b-q4_K_M --temperature 0.4

# 비교 후보 (라이선스 조건 확인 후)
python bench_ollama.py --model exaone3.5:7.8b
```

- Ollama는 `127.0.0.1:11434` 기본 주소를 그대로 쓴다. `--host`로 바꿀 수 있지만
  외부 공개 바인딩은 하지 않는다.
- VRAM은 `nvidia-smi` 파싱으로 실행 전/워밍업 직후/실행 중 최대를 기록한다.
- 결과는 `docs/benchmarks/{UTC시각}_{모델명}.json`과 같은 이름의 `.md`로
  저장된다. 명명 규칙과 판정 절차는 `docs/benchmarks/README.md` 참고.

## 측정 후 할 일

1. 벤치마크 Markdown의 "한국어 품질·안전 메모"에 응답 품질 소견을 적는다.
2. `prompt_probe_set.md`의 B~D군을 수동으로 돌려 안전 회귀 결과를 기록한다.
3. 결과를 근거로 기본 모델·num_ctx·timeout을 확정하고 `models/manifest.yaml`의
   평가 리포트 경로를 갱신한다.
