# 몽그루 데이터 사전

설계서 4장의 ERD를 테이블·컬럼 단위로 풀어 쓴 문서다. 스키마 변경은 Alembic
마이그레이션으로만 하며, 이 문서는 마이그레이션과 같은 PR에서 함께 갱신한다.

표기 규칙:

- (확정) 값 세트는 설계서에 고정된 enum이다. (제안) 값 세트는 이 문서에서
  정의하고 구현 시 서버 enum과 함께 확정한다.
- enum은 Python enum과 DB `CHECK` 제약을 같은 값으로 이중 유지한다.

## 0. 공통 규칙 (설계서 4.1)

- 모든 `datetime`은 UTC로 저장한다. `local_date` 계열은 인증 사용자의
  timezone(데모 기본 `Asia/Seoul`) 기준으로 서버가 계산한다. 주 시작은
  월요일, 기간은 `[start, end)`.
- 변경 가능한 테이블은 `created_at`, `updated_at`(UTC)을 갖는다. 아래 표에서는
  이 두 컬럼의 설명을 생략한다.
- 사용자 소유 데이터 API는 항상 `row.user_id == token.sub`를 검사한다.
- 사용자 삭제 시 소유 데이터는 cascade 삭제, 카탈로그성 테이블
  (plant_species, quests, items)은 restrict.
- 주요 조회 인덱스: `mood_entries(user_id, local_date, recorded_at_utc)`,
  `plants(user_id, museum_featured, harvested_at)`,
  `chat_messages(session_id, created_at)`, `ai_jobs(status, available_at)`.

---

## 1. P0 테이블

### 1.1 users — 계정과 게임 재화 원본

| 컬럼 | 타입 | 의미·제약 |
|------|------|-----------|
| id | bigint PK | |
| email | varchar UK | 로그인 ID. UNIQUE |
| password_hash | varchar | Argon2id 해시. 원문 비저장 |
| nickname | varchar | 최대 30자 |
| timezone | varchar | IANA 이름. 데모 기본 `Asia/Seoul` |
| seed_balance | int | 씨앗 포인트 잔액. 음수 불가(트랜잭션에서 보장) |
| streak_days | int | 연속 기록 일수 (KST 기준) |
| last_recorded_local_date | date | 마지막 기록의 local_date. 스트릭 계산용 |

### 1.2 auth_sessions — 로그인 세션 패밀리

refresh token rotation의 단위. 재사용 감지 시 family 전체를 폐기한다.

| 컬럼 | 타입 | 의미·제약 |
|------|------|-----------|
| id | bigint PK | |
| user_id | bigint FK(users) | |
| session_family | varchar UK | rotation 계보 식별자 |
| expires_at | datetime | 세션 만료 (refresh 30일) |
| revoked_at | datetime NULL | 로그아웃/재사용 감지로 폐기된 시각 |

### 1.3 refresh_tokens — 회전형 refresh token

| 컬럼 | 타입 | 의미·제약 |
|------|------|-----------|
| id | bigint PK | |
| session_id | bigint FK(auth_sessions) | |
| jti_hash | varchar UK | 토큰 jti의 해시. **원문 미저장** |
| expires_at | datetime | |
| used_at | datetime NULL | 사용(rotation) 시각. 값이 있는 토큰이 다시 오면 재사용 공격으로 보고 family 폐기 |
| revoked_at | datetime NULL | |
| replaced_by_id | bigint NULL | rotation으로 발급된 다음 토큰 id |

### 1.4 mood_entries — 감정 기록

신규 기록의 원본은 일기 본문이다. 기분·태그는 구 클라이언트 호환용 선택 필드이고
AI 결과는 본문에서 만든 보조 라벨이다. 원본과 분석 결과를 덮어쓰지 않는다.

| 컬럼 | 타입 | 의미·제약 |
|------|------|-----------|
| id | bigint PK | |
| user_id | bigint FK(users) | |
| local_date | date | 사용자 timezone 기준 기록 날짜. 서버 계산 |
| recorded_at_utc | datetime(6) | 기록 시각(UTC). MySQL에서도 마이크로초 보존 |
| mood_level | tinyint | CHECK 1~5. 구 클라이언트 호환 필드. 신규 content-only 요청은 내부값 3 저장, 식물 분기에는 사용하지 않음 |
| mood_level_explicit | boolean | 사용자가 실제로 1~5를 보냈는지 여부. false인 내부 3은 캘린더·리포트 평균·채팅 기분 문맥에서 제외 |
| emotion_tags | json | 구 클라이언트의 선택적 다중 태그. 최대 10개. 식물 분기에는 사용하지 않음 |
| content | text NULL | 자유 텍스트 일기. 최대 5,000자. 신규 요청에서는 공백이 아닌 본문 필수, legacy mood_level 요청에서는 생략 가능 |
| edit_version | int | 사용자 PATCH 낙관적 잠금 버전. 최초/기존 행 1, 수락된 비어 있지 않은 PATCH마다 +1. AI worker 갱신은 영향 없음 |
| input_version | int | 리포트 입력 버전. 기분·태그·본문 중 하나가 바뀌면 +1, 리포트 input_hash에 포함 |
| analysis_version | int | 본문 분류 버전. 본문 변경 때만 +1. mood_analysis job의 버전과 달라진 구결과는 적용하지 않음 |
| analysis_status | varchar | (확정) `not_requested\|pending\|running\|succeeded\|failed`. 텍스트 없음·안전 경로 전환 시 `not_requested` |
| ai_emotion | varchar NULL | 모델의 단일 보조 라벨 (기쁨/슬픔/분노/불안/상처/당황/uncertain) |
| ai_scores | json NULL | 클래스별 확률 |
| ai_emotion_override | varchar NULL | 사용자가 수정한 라벨. 원 모델 출력은 ai_emotion에 보존 |
| ai_label_hidden | tinyint | 1이면 UI·리포트 집계에서 AI 라벨 제외 |
| analysis_model_version | varchar NULL | 분석에 쓴 분류기 버전 |
| analyzed_at | datetime NULL | |
| analysis_error_code | varchar NULL | 실패 시 안정된 오류 코드만 저장 |

`edit_version`은 사용자 편집 충돌, `input_version`은 리포트 stale 판정,
`analysis_version`은 본문 분석 stale 판정을 각각 담당한다. 리포트 입력 해시는
`input_version`과 분석 모델 버전을 사용한다. 인덱스는
`(user_id, local_date, recorded_at_utc)`와 식물 생애 집계용
`(user_id, recorded_at_utc, id)`다. 생애 집계 쿼리는 본문 원문과 JSON 필드를
읽지 않고 본문 존재 여부·분석 상태·원 분류 라벨에 필요한 열만 조회한다.

### 1.5 plants — 키우는 식물

| 컬럼 | 타입 | 의미·제약 |
|------|------|-----------|
| id | bigint PK | |
| user_id | bigint FK(users) | |
| species_id | bigint FK(plant_species) | restrict 삭제 |
| name | varchar | 사용자가 붙인 이름 |
| exp | int | 돌봄 행동 누적 경험치. `stage`는 저장하지 않고 `stage_from_exp()`로 계산하며 감정 종류와 무관 |
| status | varchar | (확정) `active\|harvested` |
| planted_at | datetime(6) | 식물 생애 시작 시각. 기록과 같은 초여도 순서를 보존 |
| harvested_at | datetime(6) NULL | 수확 시각. exp·분석 준비 조건을 충족한 active 식물에서 1회 |
| final_form | varchar NULL | 수확 시 고정한 최종 표현형. `sunny\|rainy\|ember\|moonlit\|sparkling\|mosaic`; active 식물은 NULL |
| emotion_profile | json NULL | active에서는 현재 본문 분석 growth_profile v3 캐시, harvested에서는 수확 시 생애 스냅샷. `growth_profile` API 필드의 하위 호환 저장 원본 |
| growth_branch | varchar NULL | active의 안정화된 분기 또는 harvested의 최종 분기. `joy\|sadness\|anger\|anxiety\|surprise\|mixed` |
| branch_decided_at | datetime(6) NULL | 현재 growth_branch가 처음 정해지거나 강한 근거로 바뀐 시각. 수확 때 최종 분기가 달라지면 수확 시각 |
| museum_featured | boolean | 사용자가 대표 전시에 고른 수확 식물인지 여부. 기본 false |

**활성 식물 unique 제약**: generated column
`active_user_id = CASE WHEN status='active' THEN user_id ELSE NULL END`
+ unique index로 사용자당 active 식물 최대 1개를 DB에서 강제한다. 수확은 기존
식물을 `harvested`로 전환한다. 이후 `POST /plants`에서 해금된 품종으로 새 active
식물을 만들며, 그전까지 활성 식물이 없을 수 있다.

**활성 성장 프로필과 수확 스냅샷**: `[planted_at, 관찰/수확 시각]` 안의
`mood_entries` 중 본문이 있고 `analysis_status=succeeded`인 원 분류 결과를 집계한다.
대표 라벨은 기록당 한 표로 유지하고 `ai_scores`는 합이 1인 감정 분포로 정규화해
함께 누적한다. `mood_level`, `emotion_tags`, `ai_emotion_override`,
`ai_label_hidden`은 읽지 않는다. 라벨은 `joy`, `sadness`(상처 포함), `anger`,
`anxiety`, `surprise`, `mixed`로 정규화한다. 명확한 대표 라벨의 `ai_scores`만
다중 감정 분포로 누적하고, 저신뢰·동률의 `uncertain`은 counts와 weights 모두
mixed 한 표로 센다. 슬픔·상처처럼 한 성장 결에 속한 라벨 수가 많다는 이유로
특정 감정이 부풀지 않게 하기 위해서다.
v3 `emotion_profile` 저장 형식은 다음과 같다.

```json
{
  "version": 3,
  "source": "diary_text_analysis_scores",
  "total": 5,
  "pending_count": 0,
  "unavailable_count": 0,
  "empty_count": 0,
  "counts": {
    "joy": 1, "sadness": 3, "anger": 1,
    "anxiety": 0, "surprise": 0, "mixed": 0
  },
  "ratios": {
    "joy": 0.2, "sadness": 0.6, "anger": 0.2,
    "anxiety": 0.0, "surprise": 0.0, "mixed": 0.0
  },
  "weights": {
    "joy": 0.8, "sadness": 2.4, "anger": 0.9,
    "anxiety": 0.4, "surprise": 0.3, "mixed": 0.2
  },
  "weighted_ratios": {
    "joy": 0.16, "sadness": 0.48, "anger": 0.18,
    "anxiety": 0.08, "surprise": 0.06, "mixed": 0.04
  }
}
```

`pending_count`는 pending/running 본문, `unavailable_count`는 안전 경로·AI 비활성·
분석 최종 실패처럼 본문은 있으나 분석할 수 없는 기록, `empty_count`는 본문 없는
구 기록 수다. `counts/ratios`는 대표 라벨 호환 통계이고 실제 분기는
`weights/weighted_ratios`를 사용한다. 첫 active 분기는 stage 3·표본 3건부터
1위 60%/2위와 20%p 차이에서 정하고, 이후에는 표본 5건·새 후보 67%/기존보다
25%p 우세일 때만 바꾼다.

수확은 exp≥450, pending_count=0, total≥3에서 가능하다. 단 unavailable_count>0이면
분석 장애나 안전 경로 때문에 사용자가 영구히 막히지 않도록 표본 부족 예외를 허용하며,
empty_count만 있는 경우는 예외가 아니다. 수확 직전 전체 프로필로 active
히스테리시스를 갱신한 뒤 마지막 안정 분기를 그대로 고정한다. 끝까지 안정 분기가
없으면 `mosaic`으로 확정한다. 다른 최종 형태 매핑은 `joy→sunny`,
`sadness→rainy`, `anger→ember`, `anxiety→moonlit`,
`surprise→sparkling`이다. 이 필드는 수확 이후 원본 기록 수정·재분석으로 바뀌지
않으며 어느 형태도 보상·성장·희귀도상 우위를 갖지 않는다.

대표 전시는 서비스 계층에서 사용자 row와 식물 row를 잠근 뒤 최대 10개를
검사한다. DB에는 수확 식물을 모두 보존하고 `ix_plants_museum(user_id,
museum_featured, harvested_at)`으로 최근/대표 전시 조회를 지원한다.

Alembic `0010_diary_growth`는 당시 대표 라벨로 v2 프로필을 만들었다. 이후 활성
식물은 성장 상태를 갱신할 때 저장된 `ai_scores`까지 포함한 v3 프로필로 전환한다.
수확 식물의 `final_form`은 당시 전시 형태를
보존하는 기준값으로 유지하고 여기서 최종 분기를 복원한다. 같은 migration은 구 worker가
남긴 `failed job + pending/running entry` 반쪽 상태를 failed로 맞추고,
`growth_branch`, `branch_decided_at`, mood_entries의 `analysis_version`과
`mood_level_explicit`, 생애 시각의 MySQL 마이크로초 정밀도를 함께 적용한다.

### 1.6 plant_species — 품종 카탈로그

| 컬럼 | 타입 | 의미·제약 |
|------|------|-----------|
| id | bigint PK | |
| code | varchar UK | 품종 코드. 자산 경로에 사용 |
| name | varchar | |
| persona_key | varchar | 대화 페르소나 프롬프트 키 |
| asset_manifest | json | 품종 렌더링 확장 필드. `growth` 아래 `seed_shape`, `vessel_style`, `rarity_effect`, `asset_namespace` |
| rarity | tinyint | 희귀도 (표시용. 성장·보상에 영향 없음) |
| unlock_price | int | 해금 씨앗 포인트. P0 기본 품종은 0 |

### 1.7 reward_events — 보상 원장

경험치·씨앗 변동의 유일한 원장. 잔액·경험치 변경과 원장 insert는 한
트랜잭션에서 수행하고 user/active plant row를 `FOR UPDATE`로 잠근다.

| 컬럼 | 타입 | 의미·제약 |
|------|------|-----------|
| id | bigint PK | |
| user_id | bigint FK(users) | |
| plant_id | bigint FK(plants) NULL | 씨앗 포인트처럼 식물 귀속이 없는 이벤트는 NULL |
| event_type | varchar | (확정) `mood_first_daily\|diary_first_daily\|chat_first_daily\|streak_week\|quest_completed\|shop_purchase`. `streak_week`는 호환용 이름이며 누적 기록 7일 보상을 의미 |
| source_type | varchar | 근거 리소스 타입 (mood_entry, chat_session, user_quest 등) |
| source_id | bigint | 근거 리소스 id |
| dedupe_key | varchar UK | 중복 지급 방지 키. 예: `mood_daily:{user_id}:{local_date}`, `record_week:{user_id}:{recorded_days}`, `harvest:{plant_id}` |
| exp_delta | int | 일일 상한(P0 30, P1 50) 적용 후 실제 반영값 |
| seed_delta | int | |
| seed_balance_after | int | 반영 후 잔액 스냅샷 |

기록 삭제 후 재작성해도 dedupe_key가 남아 같은 보상을 다시 주지 않는다.

### 1.8 chat_sessions — 식물 대화 세션

| 컬럼 | 타입 | 의미·제약 |
|------|------|-----------|
| id | bigint PK | |
| user_id | bigint FK(users) | |
| plant_id | bigint FK(plants) | 화자인 식물 |
| reflection_stage | varchar | (확정) `greeting\|emotion_check\|explore\|reframe_option\|action\|closing` |
| safety_state | varchar | (확정) `normal\|concern\|imminent`. 다중 턴 안전 문맥. 진단 아님 |
| status | varchar | (확정) `active\|closed`. 최대 사용자 10턴 또는 30분 후 종료 |
| started_at | datetime | |
| ended_at | datetime NULL | |
| last_message_at | datetime NULL | |

### 1.9 chat_messages — 대화 메시지

| 컬럼 | 타입 | 의미·제약 |
|------|------|-----------|
| id | bigint PK | |
| session_id | bigint FK(chat_sessions) | |
| role | varchar | (확정) `user\|plant` |
| content | text | 최대 2,000자(user). 출력 가드 통과분만 저장(plant) |
| safety_status | varchar | (확정) `normal\|concern\|imminent`. 해당 메시지 입력 검사 라우팅 (plant 메시지는 normal) |
| ai_emotion | varchar NULL | 보조 감정 라벨 (선택) |
| model_version | varchar NULL | plant 메시지 생성 모델 버전. 인사말은 `template` |

인덱스: `(session_id, created_at)`.

### 1.10 chat_runs — 응답 생성 실행 단위

202 응답 후 SSE/조회의 대상. 본문의 `client_message_id`(클라이언트 생성 UUID)가
재전송 식별자이고, `Idempotency-Key` 헤더는 별도로 idempotency_keys에서 처리한다.

| 컬럼 | 타입 | 의미·제약 |
|------|------|-----------|
| id | bigint PK | |
| session_id | bigint FK(chat_sessions) | |
| user_message_id | bigint FK(chat_messages) | 트리거가 된 사용자 메시지 |
| assistant_message_id | bigint FK(chat_messages) NULL | 최종 plant 메시지 |
| client_message_id | varchar UK | 같은 값 재전송 시 기존 run 반환 |
| status | varchar | (확정) `queued\|generating\|succeeded\|failed` |
| error_code | varchar NULL | 안정된 오류 코드만(`LLM_TIMEOUT\|LLM_UNAVAILABLE\|GUARD_REJECTED`). 모델 원문 오류 비저장 |
| finished_at | datetime NULL | |

세션당 진행 중 run 1개 제한은 메시지 전송 시 서버 검사로 강제한다
(409 CHAT_RUN_ACTIVE_EXISTS). 가드 실패는 `failed` + `GUARD_REJECTED`로 남는다.

UI timeout(60초)과 무관하게 run은 terminal 상태까지 서버에 유지된다.

### 1.11 reports — 감정 회고 리포트

| 컬럼 | 타입 | 의미·제약 |
|------|------|-----------|
| id | bigint PK | |
| user_id | bigint FK(users) | |
| period_type | varchar | (확정) `weekly\|monthly` |
| period_start | date | 기간 시작 (포함) |
| period_end | date | 기간 끝 (미포함, `[start, end)`) |
| input_hash | varchar | 기간 내 정렬된 `(mood_entry_id, input_version, analysis_model_version)` 목록에 기본값이 아닌 `ai_emotion_override`·`ai_label_hidden`, stats_version, 기간을 더한 해시 |
| status | varchar | (확정) `pending\|succeeded\|failed` |
| stats | json | 결정적 통계. bucket마다 근거 mood_entry_id 목록 포함 |
| analysis_coverage | decimal | 분석 성공 건수 / 텍스트 포함 건수 |
| summary | json NULL | LLM 요약 (overview/patterns/reflection_questions). 실패 시 NULL + 고정 안내 |
| summary_model_version | varchar NULL | |
| error_code | varchar NULL | |

**UNIQUE(user_id, period_type, period_start, input_hash)** — 같은 입력의 중복
생성을 막는다. 기록 추가·삭제·수정·AI 결과 반영·표시 라벨 수정이나 숨김으로
input_hash가 바뀌면 이전 리포트를 재사용하지 않는다.

### 1.12 safety_events — 안전 이벤트 (원문 미보관)

| 컬럼 | 타입 | 의미·제약 |
|------|------|-----------|
| id | bigint PK | |
| user_id | bigint FK(users) | |
| source | varchar | (확정) `mood\|chat`. P1 자가설문에서 `assessment` 추가 예정 |
| resource_type | varchar | 관련 리소스 타입 |
| resource_id | bigint | 관련 리소스 id |
| severity | varchar | (확정) `concern\|imminent` (normal은 이벤트를 만들지 않음) |
| reason_codes | json | 탐지 이유 코드 목록. **원문·발췌 저장 금지** |
| detector_version | varchar | 탐지 규칙·사전·모델 묶음 버전 |
| action_taken | varchar | 취한 조치. (확정) P0에서는 `show_support_screen` 단일 값 |

상세 원칙은 docs/safety.md 6절 참고.

### 1.13 ai_jobs — 영속 AI 작업 큐

감정 분석, 대화 생성, 리포트 요약의 재시도 가능한 큐. FastAPI
BackgroundTasks를 쓰지 않는 이유는 설계서 5.4 참고.

| 컬럼 | 타입 | 의미·제약 |
|------|------|-----------|
| id | bigint PK | |
| job_type | varchar | (확정) `mood_analysis\|chat_generation\|report_summary` |
| resource_type | varchar | 대상 리소스 타입 |
| resource_id | bigint | 대상 리소스 id |
| input_version | int | job 대상별 처리 버전. `mood_analysis`에서는 `mood_entries.analysis_version` 복사, 다른 job은 해당 리소스 입력 버전. 구버전 결과 폐기용 |
| status | varchar | (확정) `pending\|running\|succeeded\|failed` |
| attempts | int | 실행 시도 횟수. 실패 시 지수 backoff(30s/2m/10m)로 최대 3회 |
| available_at | datetime | 이 시각 이후 실행 가능 (backoff 반영) |
| locked_at | datetime NULL | worker 점유 시각. 재시작 시 오래된 running 회수 |
| last_error_code | varchar NULL | |

**UNIQUE(job_type, resource_type, resource_id, input_version)**.
인덱스: `(status, available_at)`.

### 1.14 idempotency_keys — 쓰기 요청 멱등성

| 컬럼 | 타입 | 의미·제약 |
|------|------|-----------|
| id | bigint PK | |
| user_id | bigint FK(users) | |
| route_scope | varchar | 엔드포인트 범위 |
| idempotency_key | varchar | 클라이언트 헤더 값 |
| request_hash | varchar | 정규화한 요청 본문 SHA-256. 같은 key+다른 hash면 409 `IDEMPOTENCY_KEY_CONFLICT` |
| response_status | int | 최초 완료 응답의 HTTP 상태 코드. 처리 전 선점 row는 트랜잭션 밖에 노출되지 않음 |
| response_body | json | 같은 key 재시도에 그대로 재생할 최초 응답 본문 |
| created_at | datetime | key 생성 시각. 현재 자동 만료·정리 정책은 없음 |

**UNIQUE(user_id, route_scope, idempotency_key)**. key 선점, 도메인 변경,
응답 저장은 같은 트랜잭션에서 commit한다. 같은 프로세스에서는 key별 비동기 lock이
불필요한 DB 경합을 줄이고, 다중 프로세스에서는 이 unique 제약이 최종 직렬화한다.
모든 경로는 부모 user row를 먼저 잠근 뒤 key를 선점해 MySQL FK 잠금 승격 순서를 통일한다.

---

## 2. P1 테이블

아래 테이블은 `0002_p1_gameplay` 마이그레이션에서 추가된다. P0 기능은 이 테이블들 없이도
완결된다(설계서 1.2).

### 2.1 quests — 실생활 행동 카탈로그

| 컬럼 | 타입 | 의미·제약 |
|------|------|-----------|
| id | bigint PK | |
| code | varchar UK | |
| title / description | varchar | 검수된 실생활 행동 (산책, 물 마시기 등) |
| trigger_rule | varchar | 룰 기반 배정 조건 |
| category | varchar | 행동 분류 |
| burden_level | tinyint | 부담도. 감정 신호 불확실 시 low-burden만 제안 |
| estimated_minutes | int | 예상 소요 시간 |
| safety_tags | json | 제외 조건 태그. concern/imminent에서는 추천 자체를 중단 |
| reward_exp / reward_seeds | int | 완료 보상 (+20 exp, +5 seeds) |
| is_active | tinyint | 카탈로그 노출 여부 |

`0009_content_copy` 기준 카탈로그는 36개, 10개 category이며 부담도 1은
28개, 부담도 2는 8개다. 최근 14일 동일 퀘스트와 직전 2회 동일 category는
대안이 있으면 피한다. 부담도 2는 결정적 해시 기준 약 20%만 배정하고 모든
퀘스트의 보상은 동일하다. 상세 편집·운영 규칙은 `docs/content_strategy.md`를
따른다.

`0009_content_copy`는 기존 행의 `title`과 `description`만 갱신한다.
`trigger_rule`, category, 부담도, 시간, 안전 태그, 보상과 이미 배정된
`user_quests`는 변경하지 않는다.

### 2.2 user_quests — 사용자별 퀘스트 배정

| 컬럼 | 타입 | 의미·제약 |
|------|------|-----------|
| id | bigint PK | |
| user_id | bigint FK(users) | |
| quest_id | bigint FK(quests) | restrict 삭제 |
| quest_date | date | 배정 날짜 (local_date) |
| status | varchar | (확정) `assigned\|completed\|skipped`. 건너뛰기에 이유를 묻지 않음 |
| completed_at | datetime NULL | 자기보고 완료. 위치·사진 검증 없음 |

**UNIQUE(user_id, quest_date)**. 하루 배정은 정확히 하나이며, 보상은
`reward_events.dedupe_key = quest_daily:{user_id}:{quest_date}`로 하루 1회만 지급한다.

### 2.3 items — 상점 카탈로그

| 컬럼 | 타입 | 의미·제약 |
|------|------|-----------|
| id | bigint PK | |
| code | varchar UK | |
| type | varchar | 신규 쓰기: `deco\|room_theme\|companion\|species_unlock`. `main_character`는 사람형 성장 계보를 담은 호환값 |
| name | varchar | |
| description | varchar | 사용자에게 표시할 짧은 설명 |
| price_seeds | int | 씨앗 포인트 가격 |
| rarity | tinyint | UI 희귀도 |
| asset_manifest | json | 번들 `asset_key`; 성장 씨앗이면 `species_code`; 동행 소품이면 `personality`, `catchphrase`, `motion_key`; 조건형 아이템이면 `acquisition` |
| is_active | tinyint | 카탈로그 노출 여부 |

`0003_character_catalog`이 `main_character`로 등록한 사람형 캐릭터 10종은
폐기하지 않는다. 앱은 이를 완제품 장착 아이템이 아니라 씨앗에서 도달하는
사람형 완전체 계보로 해석하고, 상점·도감에서 씨앗과 완전체 미리보기를 함께
보여 준다. 신규 성장 계보의 원본은 `plant_species`와 `species_unlock`에 두며,
기존 보유 행은 대응 품종 해금으로 매핑한다.

`asset_manifest.acquisition`은 스키마 컬럼을 늘리지 않고 콘텐츠별 획득 규칙을
버전 관리한다. `type`은 `purchase|quest_count|streak|record_count|own_item|collection_count`,
조건형 규칙은 `target` 또는 `item_code`, 모든 규칙은 사용자 안내용 `label`을 가진다.
API가 반환하는 `current`, `target`, `eligible`은 저장값이 아니라 요청 시점에 계산한
파생값이다. 규칙이 없는 기존 item은 `purchase`로 해석해 이전 카탈로그와 호환한다.

### 2.4 user_items — 보유 아이템과 마이팜 배치

| 컬럼 | 타입 | 의미·제약 |
|------|------|-----------|
| id | bigint PK | |
| user_id | bigint FK(users) | |
| item_id | bigint FK(items) | restrict 삭제 |
| acquired_at | datetime | 구매 또는 조건 해금 완료 시각(UTC) |

구매는 잔액 확인·차감·인벤토리 추가를 한 트랜잭션으로 처리하고 잔액 음수를
금지한다. 조건 해금은 서버가 같은 트랜잭션 안에서 사용자 진행도를 다시 확인한 뒤
인벤토리를 추가하며 seed 원장 이벤트를 만들지 않는다. 신규 가입은 무료 기본
`plant_species`를 해금하고 같은 품종의 활성 `plants` 인스턴스를 만든다.
과거 `character_baby_pot` 지급 행은 별도 캐릭터 장착값으로 쓰지 않지만 사람형
성장 계보의 보유 여부와 완전체 미리보기에는 사용한다. 성장·대화·정원 중앙
캐릭터의 현재 상태는 계속 활성 `plants` 인스턴스가 원본이다.

**UNIQUE(user_id, item_id)**. 현재 MVP 아이템은 카탈로그 항목당 한 번만 해금한다.

### 2.5 farm_layouts — 방과 소품 배치

| 컬럼 | 타입 | 의미·제약 |
|------|------|-----------|
| user_id | bigint PK/FK(users) | 사용자당 하나의 배치 문서 |
| version | int | PUT 낙관적 잠금 버전. 최초 저장은 expected_version=0 |
| layout | json | 보유 `user_item_id` 기반 room/companion/decorations 배치. 중앙 성장 캐릭터는 활성 `plants.id`로 자동 결정. decoration rotation은 라디안 `-pi~pi` |
| updated_at | datetime | 마지막 저장 시각(UTC) |

서버는 소유권, 아이템 type, 중복 배치, 좌표·크기·라디안 회전 범위를 검증한다.
과거 `main_character_user_item_id`는 구버전 클라이언트 응답을 위한 nullable
호환 필드이며 신규 PUT은 항상 `null`을 보낸다.

### 2.6 user_species_unlocks — 유료 품종 해금

| 컬럼 | 타입 | 의미·제약 |
|------|------|-----------|
| id | bigint PK | |
| user_id | bigint FK(users) | |
| species_id | bigint FK(plant_species) | restrict 삭제 |
| unlocked_at | datetime | 해금 시각(UTC) |

**UNIQUE(user_id, species_id)**. `unlock_price=0` 품종은 행 없이도 항상 해금 상태다.

### 2.7 assessments — PHQ-9 자가설문

정확한 한국어 판본과 사용 근거 확인 전에는 feature flag로 비활성(설계서 3.2).
결과는 선별용 자가설문으로만 표시하고 감정 추세와 합쳐 위험 점수를 만들지
않는다.

| 컬럼 | 타입 | 의미·제약 |
|------|------|-----------|
| id | bigint PK | |
| user_id | bigint FK(users) | |
| instrument_code | varchar | 예: `PHQ-9` |
| instrument_version | varchar | 판본 식별 |
| locale | varchar | 판본 언어 |
| question_set_version | varchar | 문항 세트 버전 (임의 수정 금지) |
| scoring_version | varchar | 결정적 채점 로직 버전 |
| answers | json | 문항별 응답. 민감정보 취급 |
| score | int | 총점. 9번 문항이 0보다 크면 총점과 별개로 안전 리소스 화면 표시 |
| consent_version | varchar | 응답 시점 동의 문서 버전 |
| completed_at | datetime | |
