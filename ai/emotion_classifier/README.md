# 감정 분류기 학습 파이프라인

AI Hub 감성 대화 말뭉치로 KcELECTRA 기반 감정 6대분류(기쁨/슬픔/분노/불안/상처/당황)
분류기를 학습·평가한다. 결과는 몽그루 서버의 감정 보조 태깅(설계서 6.1)에 쓰인다.

분류기 출력은 사용자가 직접 고른 감정 태그를 덮어쓰지 않는 보조 라벨이며,
자살·자해 위험 탐지기로 사용하지 않는다. 평가에서 베이스라인을 이기지 못하면
앱 UI에 노출하지 않는다.

## 구성

| 파일 | 역할 |
|------|------|
| `label_mapping.py` | 세부 감정 60종(E10~E69) -> 6대분류 매핑, 매핑 버전 관리 |
| `prepare_data.py` | 원본 JSON/xlsx -> 화자 단위 group split -> parquet + meta.json |
| `baseline_tfidf.py` | TF-IDF + Logistic Regression 베이스라인 |
| `train.py` | KcELECTRA 파인튜닝 (클래스 가중 손실, HF Trainer) |
| `evaluate.py` | test 평가, calibration, abstain 스윕, UI 노출 판정 |
| `common.py` | 경로/환경변수/전처리 SHA 헬퍼 |
| `DATA_CARD.md` | 데이터 출처·라이선스·한계 |

## 환경변수

데이터와 모델 가중치는 저장소에 커밋하지 않고 아래 경로에 둔다.

| 변수 | 용도 | 예시 |
|------|------|------|
| `AIHUB_DATA_ROOT` | AI Hub 원본(감성 대화 말뭉치) 루트 | `D:\mongroo\aihub_data` |
| `MONGROO_MODEL_ROOT` | 학습 산출물(가중치·리포트) 루트 | `D:\mongroo\models` |

미설정 시 각 스크립트가 한국어 안내와 함께 종료한다. 전처리 중간 산출물은
`ai/data/processed/`에 저장되며 `.gitignore`로 커밋이 차단되어 있다.

## 실행 순서

```powershell
$env:AIHUB_DATA_ROOT = "D:\mongroo\aihub_data"
$env:MONGROO_MODEL_ROOT = "D:\mongroo\models"

pip install -r requirements.txt

# 1) 전처리: 화자 단위 group split, seed 고정
python prepare_data.py --data-version aihub-v1.2 --seed 42

# 2) 베이스라인: 판정 기준선을 먼저 만든다
python baseline_tfidf.py --data-version aihub-v1.2 --seed 42

# 3) 파인튜닝: base revision은 HF 모델 페이지에서 커밋 해시를 확인해 고정
python train.py --base-revision <commit-hash> --data-version aihub-v1.2 --fp16

# 4) 평가와 UI 노출 판정
python evaluate.py --run-id <run_id> --data-version aihub-v1.2
```

학습은 GPU(RTX 4060 Ti 8GB) 기준이며, 학습 중에는 Ollama 모델을 내려 VRAM을
비운다(설계서 1.3). 서빙은 CPU 추론이 기본이다.

## 라벨 매핑 검증 절차 (필수)

`label_mapping.py`의 코드 프리픽스 -> 대분류 대응(E1x=분노, E2x=슬픔, E3x=불안,
E4x=상처, E5x=당황, E6x=기쁨)은 말뭉치 소개 자료에서 통용되는 배치를 따른
**잠정값**이다. 원본을 내려받은 뒤 반드시 아래를 거쳐 확정한다.

1. AI Hub 배포본에 포함된 감정 분류 체계표(라벨 정의 문서 또는 xlsx의
   감정_대분류/감정_소분류 컬럼)를 연다.
2. `python -c "import label_mapping, json; print(json.dumps(label_mapping.full_code_table(), ensure_ascii=False, indent=2))"`
   출력과 원본 표를 60개 코드 전부 대조한다.
3. 불일치가 있으면 `CODE_PREFIX_TO_MAJOR`를 고치고, 프리픽스 규칙으로 표현되지
   않는 예외가 있으면 코드 단위 예외 dict를 추가한다.
4. 대조가 끝나면 `PREFIX_MAPPING_VERIFIED = True`로 바꾸고 `MAPPING_VERSION`을
   올린 뒤 전처리부터 다시 실행한다.

검증 전에는 `prepare_data.py`가 경고를 출력하고, `evaluate.py`는
`ui_exposure_allowed=false`로 판정한다.

## 재현 방법

- 같은 `--seed`, `--data-version`, `--base-revision`이면 split과 학습이 재현된다.
- 전처리 코드가 바뀌면 `meta.json`과 `model_card.json`의
  `preprocess_code_sha256`이 달라지므로 결과 비교 시 먼저 확인한다.
- run 디렉터리 구조: `MONGROO_MODEL_ROOT/emotion_classifier/{run_id}/`
  - `model/` 가중치와 tokenizer
  - `model_card.json` split/seed/전처리 SHA/데이터 버전/base revision
  - `eval_report.json`, `eval_report.md`, `confusion_matrix.csv`
- 모델을 교체하면 서버의 `analysis_model_version`도 함께 올린다. 기존 분석
  결과를 조용히 덮어쓰지 않는다(설계서 6.5).
