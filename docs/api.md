# 몽그루 API 계약 (v1)

> 서버(server/)와 앱(app/)이 공유하는 단일 계약 문서. 필드/코드가 바뀌면 이 문서를 먼저 수정한다.
> 설계 근거는 [design.md](design.md) §5 참조. P1 표시가 없는 항목은 P0.

- Base path: `/api/v1`
- 인증: `Authorization: Bearer {access_token}` (표시된 공개 엔드포인트 제외)
- JSON `snake_case`, datetime은 ISO-8601 UTC(`Z`), 사용자 기준 날짜는 `YYYY-MM-DD`(Asia/Seoul)
- 목록 응답: `{"items": [...], "next_cursor": "..." | null}` — `cursor` 쿼리로 다음 페이지
- `X-Request-ID`: 요청에 없으면 서버가 생성해 응답 헤더와 오류 본문에 포함

## 오류 계약

```json
{
  "code": "MOOD_NOT_FOUND",
  "message": "기록을 찾을 수 없습니다.",
  "details": {},
  "request_id": "0f7c…"
}
```

| HTTP | code | 의미 |
|------|------|------|
| 400 | IDEMPOTENCY_KEY_REQUIRED | 멱등성 키 누락 |
| 400 | REPORT_PERIOD_INVALID | 기간 파라미터 오류 (주 시작=월요일, 월 시작=1일) |
| 401 | AUTH_INVALID_CREDENTIALS | 이메일/비밀번호 불일치 (계정 존재 여부 비노출) |
| 401 | AUTH_TOKEN_EXPIRED / AUTH_TOKEN_INVALID | access/refresh 만료·위조 |
| 401 | AUTH_REFRESH_REUSED | refresh 재사용 감지 → 세션 패밀리 전체 폐기됨 |
| 403 | FORBIDDEN | 소유하지 않은 리소스 접근 |
| 404 | *_NOT_FOUND | MOOD / PLANT / SPECIES / CHAT_SESSION / CHAT_RUN / REPORT |
| 409 | PLANT_ACTIVE_EXISTS | 활성 식물이 이미 있음 |
| 409 | PLANT_NOT_HARVESTABLE | exp<450 또는 이미 수확됨 |
| 409 | PLANT_ANALYSIS_PENDING | 수확 범위의 일기 분석이 pending/running. `details.pending_count` 포함 |
| 409 | PLANT_EMOTION_EVIDENCE_REQUIRED | 분석 가능한 일기 표본이 3건 미만. `details.analyzed_count/required_count` 포함 |
| 409 | PLANT_NOT_HARVESTED | 수확하지 않은 식물을 박물관 대표 전시에 선택함 |
| 409 | MUSEUM_FEATURED_LIMIT | 대표 전시 식물 10개 제한 초과 (`details.max_featured=10`) |
| 409 | CHAT_RUN_ACTIVE_EXISTS | 세션에 진행 중 run 존재 |
| 409 | CHAT_RETRY_STALE / CHAT_RETRY_SAFETY_BLOCKED | 이후 user turn 또는 안전 상태 때문에 과거 run 재시도 불가 |
| 409 | CHAT_SESSION_CLOSED | 종료된 세션에 메시지 전송 |
| 409 | MOOD_VERSION_CONFLICT | 감정 기록의 `expected_version`이 현재 편집 버전과 불일치 |
| 409 | IDEMPOTENCY_KEY_CONFLICT | 같은 키로 다른 본문 재시도 |
| 409 | CLIENT_MESSAGE_ID_CONFLICT | 같은 메시지 ID를 다른 세션·본문에 재사용 |
| 409 | EMAIL_ALREADY_EXISTS | 가입 시 이메일 중복 |
| 409 | QUEST_ALREADY_RESOLVED / QUESTS_SUSPENDED | 퀘스트가 이미 처리됐거나 안전 지원 우선 상태 |
| 409 | INSUFFICIENT_SEEDS / ITEM_ALREADY_OWNED | 상점 잔액 부족 또는 중복 구매 |
| 409 | FARM_LAYOUT_VERSION_CONFLICT | 마이팜 낙관적 잠금 버전 충돌 |
| 422 | VALIDATION_ERROR | 필드 검증 실패 (`details.errors`에 필드별 사유) |
| 422 | CONSENT_REQUIRED | real-data 가입의 연령 확인·필수 동의 누락 |
| 409 | CONSENT_VERSION_OUTDATED | 가입 화면의 약관·개인정보·민감정보 문서 버전이 서버 현재 버전과 다름 |
| 422 | ACCOUNT_DELETE_CONFIRMATION_INVALID | 탈퇴 확인 문구 또는 현재 비밀번호 불일치 |
| 429 | RATE_LIMITED | 로그인 시도 제한 |
| 503 | SERVICE_DEGRADED | AI 의존성 불능으로 해당 기능만 불가 |
| 500 | INTERNAL_ERROR | 내부 오류 (원문 비노출) |

## 멱등성

다음 요청은 `Idempotency-Key` 헤더(클라이언트 생성 UUID) 필수. 같은 사용자·같은 route
scope·같은 키의 재시도는 저장된 첫 응답을 그대로 반환한다. 같은 키에 다른 본문이면 409.
서버는 handler 실행 전에 키를 선점하고, 도메인 변경과 응답 저장을 같은 트랜잭션으로
commit한다. 단일 프로세스의 동일 키 요청은 메모리 lock으로 직렬화하며, 여러 프로세스의
경합은 DB unique 제약이 최종 방어한다.

- `POST /moods`, `POST /chat/sessions/{id}/messages`, `POST /plants/{id}/harvest`, `POST /reports`
- `POST /user-quests/{id}/complete`, `POST /shop/items/{id}/purchase`,
  `POST /shop/items/{id}/claim`,
  `POST /shop/plant-species/{id}/purchase`

채팅 전송 응답을 받지 못한 재시도는 `Idempotency-Key`와 본문의
`client_message_id`를 모두 최초 전송과 같은 값으로 유지한다. 서버가 run의 `failed`
상태를 확정한 뒤 사용자가 다시 시도할 때만 같은 `client_message_id`, 새
`Idempotency-Key`, `retry_failed: true`를 보낸다. 이 경우 사용자 메시지는 복제하지
않고 기존 run만 다시 큐에 넣는다. 동시 retry는 같은 run으로 합류한다. 이후 user turn이
있거나 세션 안전 상태가 `concern|imminent`면 각각 409 `CHAT_RETRY_STALE`,
`CHAT_RETRY_SAFETY_BLOCKED`로 거절한다.

## 공통 DTO

### MoodEntry

```json
{
  "id": 1, "local_date": "2026-07-10", "recorded_at": "2026-07-10T03:12:00Z",
  "mood_level": 3, "mood_level_explicit": false,
  "emotion_tags": [], "content": "오늘 있었던 일을 적은 일기 본문",
  "analysis_status": "not_requested | pending | running | succeeded | failed",
  "ai_emotion": "기쁨 | 슬픔 | 분노 | 불안 | 상처 | 당황 | uncertain | null",
  "ai_scores": {"기쁨": 0.72, "…": 0.0} ,
  "ai_emotion_override": "사용자 수정 라벨 또는 null",
  "ai_label_hidden": false,
  "analysis_model_version": "emotion-clf-... | null", "analyzed_at": "… | null",
  "analysis_error_code": null,
  "edit_version": 1,
  "created_at": "…", "updated_at": "…"
}
```

신규 앱은 `mood_level`과 `emotion_tags`를 묻지 않고 일기 본문만 전송한다.
본문만 받은 서버는 현재 NOT NULL 스키마와 구 응답 계약을 위해 `mood_level=3`을
저장하지만 이 값을 식물 외형·성격 분기에 사용하지 않는다. 내부 `input_version`은
기분·태그·본문처럼 리포트 입력이 바뀔 때 증가하고, `analysis_version`은 본문이
바뀔 때만 증가해 늦게 끝난 감정 분석 결과를 폐기한다. 두 내부 버전 중 API 편집
충돌에 사용하는 값은 응답의 `edit_version`이다.
`mood_level_explicit=false`인 내부 3은 캘린더, 리포트 평균, 채팅 문맥에서도
사용자가 직접 고른 “보통”으로 취급하지 않는다.

### RewardResult — 보상이 발생한 쓰기 응답에 포함 (없으면 null)

```json
{
  "events": [
    {"event_type": "mood_first_daily", "exp_delta": 10, "seed_delta": 0},
    {"event_type": "diary_first_daily", "exp_delta": 30, "seed_delta": 15}
  ],
  "plant": {"id": 3, "exp": 40, "stage": 2, "stage_changed": true, "harvestable": false},
  "daily_exp_granted": 40, "daily_exp_cap": 50,
  "seed_balance": 15
}
```

`event_type`: `mood_first_daily`(+10) · `diary_first_daily`(+30, 씨앗 +15, 50자 이상) ·
`chat_first_daily`(+5) · `streak_week`(서로 다른 기록 날 누적 7일마다 씨앗 +30) ·
`quest_completed`(+20, 씨앗 +5) · `patrol_claimed`(씨앗 +3) ·
`dungeon_cleared`(+10, 씨앗 +4). `streak_week`는 기존 원장 코드를 유지한
이름이며 연속 출석을 요구하지 않는다.
일일 경험치 상한은 50이다.

### SafetyAction — 안전 경로 진입 시 포함 (없으면 null)

```json
{
  "action": "show_support_screen",
  "severity": "concern | imminent",
  "message": "지금 마음이 많이 힘드신 것 같아요. 혼자 견디지 않아도 됩니다.",
  "resources": [
    {"label": "자살예방 상담전화", "phone": "109"},
    {"label": "정신건강 위기상담", "phone": "1577-0199"},
    {"label": "긴급 상황", "phone": "112"}
  ]
}
```

`severity=imminent`이면 112/119 항목이 최상단. 이 값은 내부 라우팅이며 진단·위험등급이 아니다.

### ActivePlant

```json
{
  "id": 3, "name": "초록이",
  "species": {
    "id": 1, "code": "basic_sprout", "name": "새싹몬", "rarity": 1,
    "asset_manifest": {"growth": {
      "seed_shape": "heart_speck_seed", "vessel_style": "round_terracotta_pot",
      "rarity_effect": "none", "asset_namespace": "plants/basic_sprout"
    }}
  },
  "exp": 420, "stage": 4, "stage_name": "개화",
  "stage_thresholds": [0, 20, 100, 250, 450],
  "next_stage_exp": 450, "harvestable": false,
  "planted_at": "…",
  "growth_profile": {
    "version": 3, "source": "diary_text_analysis_scores", "total": 3,
    "pending_count": 0, "unavailable_count": 0, "empty_count": 0,
    "counts": {"joy": 2, "sadness": 1, "anger": 0, "anxiety": 0, "surprise": 0, "mixed": 0},
    "ratios": {"joy": 0.6667, "sadness": 0.3333, "anger": 0.0, "anxiety": 0.0, "surprise": 0.0, "mixed": 0.0},
    "weights": {"joy": 1.8, "sadness": 0.8, "anger": 0.2, "anxiety": 0.2, "surprise": 0.0, "mixed": 0.0},
    "weighted_ratios": {"joy": 0.6, "sadness": 0.2667, "anger": 0.0667, "anxiety": 0.0667, "surprise": 0.0, "mixed": 0.0}
  },
  "emotion_profile": {
    "version": 3, "source": "diary_text_analysis_scores", "total": 3,
    "pending_count": 0, "unavailable_count": 0, "empty_count": 0,
    "counts": {"joy": 2, "sadness": 1, "anger": 0, "anxiety": 0, "surprise": 0, "mixed": 0},
    "ratios": {"joy": 0.6667, "sadness": 0.3333, "anger": 0.0, "anxiety": 0.0, "surprise": 0.0, "mixed": 0.0},
    "weights": {"joy": 1.8, "sadness": 0.8, "anger": 0.2, "anxiety": 0.2, "surprise": 0.0, "mixed": 0.0},
    "weighted_ratios": {"joy": 0.6, "sadness": 0.2667, "anger": 0.0667, "anxiety": 0.0667, "surprise": 0.0, "mixed": 0.0}
  },
  "growth_branch": "joy", "growth_form": "sunny",
  "growth_persona": {
    "persona_key": "sunny_optimist", "persona_name": "햇살결",
    "trait": "다정함·나눔",
    "voice_line": "햇빛 자리 찾았어. 오늘 잎을 넓게 펼칠래."
  },
  "dominant_form": "sunny", "secondary_form": "rainy",
  "growth_traits": {
    "version": 1, "source": "diary_text_analysis_scores",
    "fictional_character_profile": true,
    "user_personality_inference": false, "affects_growth_speed": false,
    "stage": 4, "reveal_state": "secondary_revealed",
    "next_reveal": "만개하면 고유한 움직임과 말버릇이 완성돼요.",
    "evidence_count": 3, "title": "빗빛 품은 햇살결",
    "traits": ["온기를 나누는", "여운을 오래 듣는"],
    "temperament": {
      "revealed": true, "fictional_character_axes": true,
      "affects_rewards": false,
      "axes": {"energy": 0.7, "sensitivity": 0.6, "curiosity": 0.5, "deliberation": 0.4},
      "labels": {"energy": "생기 있는", "sensitivity": "깊이 느끼는"},
      "summary": "생기 있는 움직임 · 깊이 느끼는 반응"
    },
    "chat_style": {
      "cadence": "짧고 따뜻하게", "focus": "오늘 남은 작은 온기",
      "question_style": "한 번에 하나씩 구체적으로 묻기",
      "secondary_modifier": "답을 재촉하지 않고 여운을 듣기",
      "stage_expression": "보조결이 말의 리듬에 드러남"
    }
  },
  "temperament": {"summary": "생기 있는 움직임 · 깊이 느끼는 반응"},
  "conversation_profile": {
    "cadence": "짧고 따뜻하게", "focus": "오늘 남은 작은 온기",
    "question_style": "한 번에 하나씩 구체적으로 묻기"
  },
  "branch_phase": "branched", "growth_phase": "bloom",
  "profile_state": "ready", "branch_confidence": 0.6,
  "visual_key": "stage_4_sunny_rainy",
  "growth_visual": {
    "phase": "bloom", "seed_visible": false, "branch_visible": true,
    "seed_shape": "heart_speck_seed", "vessel_style": "round_terracotta_pot",
    "rarity_effect": "none", "secondary_asset_key": "plants/basic_sprout/accents/rainy",
    "render_layers": [
      "plants/basic_sprout/vessels/round_terracotta_pot",
      "plants/basic_sprout/stages/bloom",
      "plants/basic_sprout/branches/sunny/bloom",
      "plants/basic_sprout/accents/rainy"
    ]
  }
}
```

`stage`: 1 씨앗 · 2 새싹 · 3 줄기 · 4 개화 · 5 만개. 서버 계산값만 사용한다.
`growth_profile`과 `emotion_profile`은 같은 v3 객체를 반환하는 정식 이름과 하위 호환
별칭이다. `counts/ratios`는 기록별 대표 라벨의 하위 호환 집계이고,
`weights/weighted_ratios`는 대표 라벨이 명확한 일기 안에서 함께 감지된 감정 점수까지
합친 성장 판정 근거다. 저신뢰·동률로 `uncertain`인 일기는 라벨군 수 차이에 끌리지 않게
mixed 한 표로 누적한다. 구 v1/v2 프로필은 점수 필드가 없을 수 있다. `growth_phase`는
`seed|sprout|branching|bloom|full_bloom`,
`branch_phase`는 `unformed|hinting|branched`, `profile_state`는
`analyzing|limited|ready`다. 1단계에는 분기를 노출하지 않고 2단계에는 프로필의
미세한 시각 단서만 사용한다. `growth_branch/form/persona`는 3단계부터 분석 표본이
충분해 실제 분기가 결정된 경우에 값이 있고, 그 전에는 null이다. 단, 만개했지만
안정 분기가 없는 식물은 분석 대기가 끝나고 표본 또는 분석 불가 기록이 있으면 응답에서만
`mixed/mosaic/모아결` 미리보기를 반환한다. 이 값은 안정 분기로 저장하지 않는다. 구 앱을 위해
`branch_status=observing|emerging|stable`과 `personality={code,name}|null`도 같은
의미의 축약 별칭으로 유지한다. RewardResult의 `plant`는 보상 직후 필요한
stage/form/persona 중심의 축약 성장 상태다. 품종별 `growth_visual`이 필요한 단계 상승
연출은 앱이 최신 ActivePlant를 한 번 갱신해 사용한다.

`growth_traits`는 단계별 공개 계약이다. 3단계는 `dominant`의 외형·페르소나를,
4단계는 전체 가중 분포에서 14% 이상인 `secondary`와 식물 캐릭터 기질을,
5단계는 고유 움직임·말버릇을 공개한다. `temperament`와 `conversation_profile`은
식물의 연출과 대화 질문 방식을 위한 값이며 사용자 성격 추론이 아니다. 서버는
`user_personality_inference=false`, `affects_growth_speed=false`,
`affects_rewards=false`를 함께 반환한다. 구 응답에는 이 객체가 없을 수 있으므로
클라이언트는 기존 `growth_persona`와 주결 기본값으로 안전하게 되돌린다.

`growth_visual`은 구조화된 렌더링 계약이다. 앱의 코드 기반 painter는
`seed_shape/vessel_style/rarity_effect/growth_cue/form`을 소비하고,
`render_layers`와 asset key는 동일 조합의 순서·캐시·향후 자산 치환을 위한 안정 식별자다.
현재 존재하지 않는 파일 경로를 직접 불러오는 계약은 아니다. 1단계는 모든 품종이 `seed_visible=true`,
`branch_visible=false`이고 감정 레이어가 없다. 품종의 `seed_shape`, `vessel_style`,
`rarity_effect`만 달라질 수 있다. 2단계는 `growth_cue`가 있을 때 미세한 cue 레이어를,
3단계부터 안정 분기가 생기면 branch 레이어를, 4단계부터 보조결이 공개되면
`secondary_asset_key` 액센트 레이어를 더한다. 알 수 없는 신규 품종은 서버가
기본 둥근 씨앗과 화분 namespace로 안전하게 되돌린다.

### MuseumPlant

```json
{
  "id": 9,
  "name": "초록이",
  "species": {"id": 1, "code": "basic_sprout", "name": "새싹몬"},
  "exp": 450,
  "planted_at": "2026-06-24T03:00:00Z",
  "harvested_at": "2026-07-14T03:00:00Z",
  "final_form": "rainy",
  "growth_profile": {
    "version": 3, "source": "diary_text_analysis_scores",
    "total": 5,
    "pending_count": 0, "unavailable_count": 0, "empty_count": 0,
    "counts": {
      "joy": 1, "sadness": 3, "anger": 1,
      "anxiety": 0, "surprise": 0, "mixed": 0
    },
    "ratios": {
      "joy": 0.2, "sadness": 0.6, "anger": 0.2,
      "anxiety": 0.0, "surprise": 0.0, "mixed": 0.0
    },
    "weights": {"joy": 0.8, "sadness": 2.4, "anger": 0.9, "anxiety": 0.4, "surprise": 0.3, "mixed": 0.2},
    "weighted_ratios": {"joy": 0.16, "sadness": 0.48, "anger": 0.18, "anxiety": 0.08, "surprise": 0.06, "mixed": 0.04}
  },
  "emotion_profile": {
    "version": 3, "source": "diary_text_analysis_scores", "total": 5,
    "pending_count": 0, "unavailable_count": 0, "empty_count": 0,
    "counts": {"joy": 1, "sadness": 3, "anger": 1, "anxiety": 0, "surprise": 0, "mixed": 0},
    "ratios": {"joy": 0.2, "sadness": 0.6, "anger": 0.2, "anxiety": 0.0, "surprise": 0.0, "mixed": 0.0},
    "weights": {"joy": 0.8, "sadness": 2.4, "anger": 0.9, "anxiety": 0.4, "surprise": 0.3, "mixed": 0.2},
    "weighted_ratios": {"joy": 0.16, "sadness": 0.48, "anger": 0.18, "anxiety": 0.08, "surprise": 0.06, "mixed": 0.04}
  },
  "growth_branch": "sadness", "growth_form": "rainy",
  "growth_persona": {
    "persona_key": "gentle_listener", "persona_name": "빗물결",
    "trait": "섬세함·경청",
    "voice_line": "잎 끝의 물방울, 떨어질 때까지 지켜볼래."
  },
  "branch_phase": "branched", "growth_phase": "full_bloom",
  "profile_state": "ready", "branch_confidence": 0.48,
  "visual_key": "stage_5_rainy",
  "museum_featured": true
}
```

`final_form`은 `sunny|rainy|ember|moonlit|sparkling|mosaic` 중 하나다. 각각
기쁨·슬픔/상처·분노·불안·당황·혼합/불확실한 분포를 표현하며 희귀도, 보상,
성장 속도, 해금 조건에는 영향을 주지 않는다. 프로필의 `counts`와 `ratios`는
여섯 감정 키를 항상 모두 포함한다. `0007_plant_museum`에서 만들어진 과거 수확
표본은 생애 경계를 다시 만들지 않고 v1 프로필을 유지할 수 있다. v1은
`source/pending_count/unavailable_count/empty_count`가 없으므로 클라이언트는 이를
0 또는 알 수 없음으로 읽어야 하며, 저장된 `final_form`을 우선 표시한다.
신규 수확 스냅샷은 ActivePlant와 같은 `dominant_form`, `secondary_form`,
`growth_traits`, `temperament`, `conversation_profile`, `growth_visual`도 고정한다.
박물관은 이 값으로 씨앗부터 만개까지의 계보와 당시의 질문 습관을 재현하며 이후
일기 수정으로 다시 계산하지 않는다.

| growth_branch | growth_form | persona_key | persona_name |
|---|---|---|---|
| `joy` | `sunny` | `sunny_optimist` | 햇살결 |
| `sadness` | `rainy` | `gentle_listener` | 빗물결 |
| `anger` | `ember` | `brave_guardian` | 불씨결 |
| `anxiety` | `moonlit` | `careful_observer` | 달빛결 |
| `surprise` | `sparkling` | `curious_explorer` | 별빛결 |
| `mixed` | `mosaic` | `free_spirit` | 모아결 |

## 인증

| Method/Path | 인증 | 설명 |
|---|---|---|
| POST `/auth/signup` | 공개 | `{email, password(8자 이상), nickname(1~30자), age_over_18, terms_accepted, privacy_accepted, sensitive_data_consent, terms_version, privacy_version, sensitive_consent_version}` → 201 아래 AuthResponse. real-data에서는 네 확인이 모두 필수이고 세 문서 버전이 서버 현재 버전과 일치해야 한다. 기본 품종 활성 식물과 무료 `아기 화분` 캐릭터 자동 생성 |
| POST `/auth/login` | 공개 | `{email, password}` → 200 AuthResponse. 연속 실패 시 429 |
| POST `/auth/refresh` | 공개 | `{refresh_token}` → 200 AuthResponse(회전된 새 refresh). 재사용 감지 시 401 AUTH_REFRESH_REUSED + 패밀리 폐기 |
| POST `/auth/logout` | 필요 | `{refresh_token}` → 204. 해당 세션 패밀리 폐기 |
| POST `/auth/logout-all` | 필요 | 204. 내 모든 세션 폐기 |
| GET `/users/me` | 필요 | `{id, email, nickname, timezone, seed_balance, streak_days, consent, created_at}` |
| GET `/users/me/export` | 필요 | 비밀번호·token·rate-limit key를 제외한 사용자 소유 데이터를 복호화한 JSON. `Content-Disposition` 포함 |
| DELETE `/users/me` | 필요 | `{password, confirmation:"몽그루 탈퇴"}`. 세션·일기·대화·식물·정원·탐험을 FK cascade로 영구 삭제 → 204 |

AuthResponse:

```json
{
  "user": {"id": 1, "email": "a@b.c", "nickname": "준수", "timezone": "Asia/Seoul",
           "seed_balance": 0, "streak_days": 0, "created_at": "…"},
  "access_token": "…", "refresh_token": "…", "token_type": "bearer", "expires_in": 900
}
```

## 감정 기록

| Method/Path | 설명 |
|---|---|
| POST `/moods` (멱등) | 신규 `{content: 1~5000자}` 또는 구 호환 `{mood_level: 1~5, emotion_tags?: string[]≤10(각 20자), content?: ≤5000자}` → 201 `{mood, reward, safety_action}`. `mood_level`과 비어 있지 않은 본문이 모두 없으면 422. 본문만 보낸 경우 저장 mood_level은 3이지만 식물 분기에는 사용하지 않음. 안전 경로면 기록은 저장되고 분석 job은 생성하지 않아 `not_requested`, `safety_action` 포함 |
| GET `/moods/calendar?year=&month=` | `{year, month, days: [{date, entry_count, last_mood_level, last_mood_level_explicit, last_ai_emotion, last_analysis_status, pending_count}]}` — content-only 최신 기록은 `last_mood_level=null`, 표시 가능한 분석 라벨은 `last_ai_emotion` |
| GET `/moods?date=YYYY-MM-DD&cursor=` | 해당 일자 기록 목록(최신순) |
| GET `/moods/{id}` | MoodEntry |
| PATCH `/moods/{id}` | 기록 입력(`mood_level/emotion_tags/content`) 또는 라벨 설정(`ai_emotion_override/ai_label_hidden`)만 부분 수정. 읽은 MoodEntry의 `edit_version`을 `expected_version`으로 보내며 불일치하면 409 `MOOD_VERSION_CONFLICT`. 수락된 비어 있지 않은 PATCH는 `edit_version`을 정확히 +1. 기분·태그·본문 변경은 리포트용 `input_version`을 증가시키고, 본문 변경만 `analysis_version` 증가+재분석. 라벨 설정만이면 두 입력 버전과 분석은 유지 → 200 `{mood, reward, safety_action}` (일기 50자 조건 최초 충족 시 보상 가능) |
| DELETE `/moods/{id}` | 204. 관련 리포트는 stale 처리 |

## 식물

| Method/Path | 설명 |
|---|---|
| GET `/plant-species` | `{items: [{id, code, name, rarity, unlock_price, asset_manifest, is_unlocked}]}` |
| GET `/plants/me` | `{plant: ActivePlant \| null}` |
| GET `/plants?status=harvested&cursor=` | 전체 수확 목록. cursor 페이지의 각 항목은 MuseumPlant이며 `next_cursor`를 반환 |
| GET `/plants/museum?mode=recent\|featured&limit=10` | 박물관 전시. `limit`은 1~10(기본 10). `recent`는 최신 수확순, `featured`는 사용자가 고른 식물만 최신 수확순 → `{items: MuseumPlant[], mode, limit, max_featured: 10}` |
| POST `/plants` | `{species_id?, name?(1~20자)}` → 201 ActivePlant. 활성 식물 존재 시 409 |
| POST `/plants/{id}/harvest` (멱등) | exp≥450·active·pending_count=0이고 분석 표본 3건 이상일 때 성공. unavailable 본문이 있으면 영구 차단 방지를 위해 표본 부족 예외 허용. 생애 전체 프로필과 최종 형태를 함께 고정 → 200 `{plant: MuseumPlant+status, active_plant: null}` |
| PATCH `/plants/{id}/museum` | 수확 식물의 대표 전시 여부 변경. `{is_featured: boolean}` → `{plant: MuseumPlant, featured_count, max_featured: 10}`. 같은 값을 반복 전송해도 결과가 같은 자연 멱등 PATCH |

수확 스냅샷에는 `planted_at <= recorded_at_utc <= harvested_at`이고 본문이 있으며
`analysis_status=succeeded`인 기록의 원 분류기 `ai_emotion`과 `ai_scores`를 포함한다.
대표 라벨은 각 한 표, 명확한 라벨의 세부 점수는 합이 1인 다중 감정 분포로 누적한다.
`mood_level`, `emotion_tags`, `ai_emotion_override`, `ai_label_hidden`은 식물 집계에서
읽지 않는다. 상처는 sadness, 당황은 surprise, 저신뢰·고엔트로피·분류 점수 동률은
uncertain은 대표·가중 통계 모두 mixed 한 표로 정규화한다. 최초 안정 분기는 분석 표본 3건 이상, 단독 1위
60% 이상, 2위와 20%p 이상 차이일 때 정한다. 이미 안정 분기가 있으면 표본 5건 이상,
새 후보 67% 이상, 기존 분기보다 25%p 이상 앞설 때만 바꾼다. 전환 기준에 못 미치면
기존 분기를 유지하며, 안정 분기가 아직 없으면 만개 전까지 분기하지 않는다.

`pending_count>0`이면 409 `PLANT_ANALYSIS_PENDING`, 분석 가능한 표본이 3건 미만이고
`unavailable_count=0`이면 409 `PLANT_EMOTION_EVIDENCE_REQUIRED`다. 안전 경로·AI 비활성·
분석 최종 실패처럼 본문이 있지만 분석 불가능한 기록은 `unavailable_count`로 구분하며,
이 값이 있으면 사용자를 영구 차단하지 않고 안정 분기가 없을 때 `mosaic`으로 수확한다.
수확 직전 누적 프로필로 전환 완충 규칙을 한 번 적용한 뒤 마지막으로 화면에 보이던
안정 분기를 그대로 고정하므로, 수확 버튼을 누르는 순간 외형과 성격이 바뀌지 않는다.
본문이 없는 `empty_count`만으로는 이 예외를 적용하지 않는다. 수확 뒤 원본 일기를
수정·삭제해도 저장된 `final_form`, `growth_profile`, `growth_persona`는 다시 계산하지 않는다.

대표 전시는 사용자당 최대 10개다. PATCH는 사용자와 식물 row를 잠근 같은
트랜잭션에서 현재 개수를 확인한다. 서버는 수확 이력을 모두 보관하되 박물관
전용 GET은 렌더링·메모리 예산을 위해 한 번에 최대 10개만 반환한다.

## 식물 대화

| Method/Path | 설명 |
|---|---|
| POST `/chat/sessions` | `{plant_id?}`(생략 시 활성 식물) → 201 `{session, reward, greeting}`. `greeting`은 첫 식물 인사 메시지(서버 고정 페르소나 문구). 하루 첫 시작 +5 exp |
| GET `/chat/sessions/{id}/messages?cursor=` | `{items: [{id, role: "user"\|"plant", content, created_at}]}` (과거→최신) |
| POST `/chat/sessions/{id}/messages` (멱등) | `{content: 1~2000자, client_message_id: uuid, retry_failed?: boolean=false}` → 202 `{run_id, status, user_message}`. `retry_failed`는 확정 실패한 같은 run을 다시 큐잉할 때만 사용하며 동시 요청은 같은 run으로 합류한다. 이후 user turn/다른 active run/안전 상태가 있으면 409로 순서와 안전 하한을 보존한다. 안전 경로면 200 `{run_id: null, user_message, safety_action}` (LLM 미호출, 세션 safety 상태 갱신). 진행 중 run 있으면 409 |

stage 3 이상에서 성장 분기가 공개된 식물은 첫 인사와 생성 대화에
`growth_persona`의 이름·성격 축·대표 말투를 품종 기본 성격과 함께 적용한다.
stage 4부터는 `secondary_form`, 식물 기질, `conversation_profile`의 cadence·focus·
question_style을 적용한다. 최근 사용자 문장과 당일 일기 단서는 상황을 구체적으로
짚는 데만 쓰며, 같은 품종이라도 성장 단계·주결·보조결 조합에 따라 첫 인사와 질문이
달라진다. 앱은 세션을 시작한 식물 스냅샷을 끝날 때까지 유지한다.
stage 1~2 또는 미결정 상태는 품종 기본 인사를 유지한다. 이 성장 성격은 사용자의
감정을 진단하거나 평가하는 문구로 사용하지 않는다.
| GET `/chat/runs/{run_id}` | `{run_id, status: "queued"\|"generating"\|"succeeded"\|"failed", message: {…}\|null, error_code: null\|"LLM_TIMEOUT"\|"LLM_UNAVAILABLE"\|"GUARD_REJECTED"}` |
| GET `/chat/runs/{run_id}/events` | SSE. 이벤트: `status` → (`message`) → `done` 또는 `error`. 15초 간격 heartbeat 주석(`:hb`). 완료된 run에 다시 연결하면 `message`+`done` 재전송 |

```text
event: status
data: {"run_id": 7, "status": "generating"}

event: message
data: {"message_id": 42, "content": "검사를 통과한 최종 답변"}

event: done
data: {"run_id": 7}
```

세션 제한: 사용자 10턴 또는 30분. 초과 시 서버가 `status="closed"`로 전환하고 409 CHAT_SESSION_CLOSED.
session DTO: `{id, plant_id, reflection_stage, status: "active"|"closed", started_at, last_message_at}`.
`reflection_stage`: `greeting|emotion_check|explore|reframe_option|action|closing` (표시용 참고 값).

## 리포트

| Method/Path | 설명 |
|---|---|
| POST `/reports` (멱등) | `{period_type: "weekly"\|"monthly", period_start: "YYYY-MM-DD"}` → 같은 입력이면 200 기존 리포트, 새 입력이면 202 `{report(status="pending")}`. 통계는 동기 계산되어 즉시 포함, 요약만 비동기 |
| GET `/reports?period_type=&cursor=` | `{items: [{id, period_type, period_start, period_end, status, created_at}]}` |
| GET `/reports/{id}` | 아래 Report + `stale` (기록 변경·삭제로 입력이 달라졌으면 true — 재생성 유도) |

```json
{
  "id": 5, "period_type": "weekly", "period_start": "2026-07-06", "period_end": "2026-07-13",
  "status": "pending | succeeded | failed",
  "stats": {
    "total_entries": 12, "explicit_mood_entries": 4,
    "entries_with_text": 7, "analyzed_entries": 5,
    "mood_daily": [{"date": "2026-07-06", "avg_mood": 3.5, "count": 2, "entry_ids": [1, 2]}],
    "tag_distribution": [{"tag": "설렘", "count": 3, "entry_ids": [1, 4, 9]}],
    "ai_emotion_distribution": [{"emotion": "기쁨", "count": 2, "entry_ids": [4, 9]}],
    "time_of_day": [{"bucket": "morning | afternoon | evening | night", "count": 4, "entry_ids": [1]}],
    "streak": {"current": 4, "longest_in_period": 4},
    "keywords": [{"keyword": "산책", "score": 0.41, "entry_ids": [4]}]
  },
  "analysis_coverage": 0.71,
  "summary": {"overview": "…", "patterns": ["…"], "reflection_questions": ["…"]},
  "summary_model_version": "qwen3-8b-q4_K_M | null",
  "error_code": null,
  "stale": false,
  "created_at": "…", "updated_at": "…"
}
```

- `summary`는 요약 job 성공 전까지 null. 실패(`status="failed"`)여도 `stats`는 유효하며 앱은
  통계와 고정 안내 문구를 보여준다.
- 주간은 월요일 시작 7일, 월간은 1일 시작 한 달. `[start, end)`.
- 태그 분포(사용자 선택)와 AI 라벨 분포(보조)는 항상 분리 표시. `ai_label_hidden` 기록은 AI 분포에서 제외.
- `mood_daily` 평균은 `mood_level_explicit=true`인 구 호환/명시 입력만 집계한다.

## 상태 확인 (공개)

| Method/Path | 설명 |
|---|---|
| GET `/health/live` | `{status: "ok"}` |
| GET `/health/ready` | `{status: "ok"\|"degraded"\|"down", checks: {database: {status}, ai_worker: {status, last_heartbeat}, classifier: {status, mode}, ollama: {status, mode}}}` — DB 불능만 `down`, AI 의존성 불능은 `degraded` |

## 퀘스트·상점·컬렉션·마이팜·탐험 (P1)

| Method/Path | 설명 |
|---|---|
| GET `/quests/today` | KST 오늘의 퀘스트 1개를 반환. 최근 14일 동일 항목과 직전 2회 동일 category는 대안이 있으면 피한다. 완료 전 당일 일기 분석이 끝나면 같은 배정 ID를 유지하며 감정 맥락과 어울리는 category로 다시 연결한다. 당일 `concern/imminent` 안전 이벤트가 있으면 `suspended=true`, `items=[]` |
| POST `/user-quests/{id}/complete` (멱등) | 자기보고 완료 → +20 XP/+5 씨앗. `quest_daily:{user_id}:{date}`로 하루 한 번만 보상 |
| POST `/user-quests/{id}/skip` | 이유 입력이나 페널티 없이 건너뛰기 |
| GET `/shop/items` | 아이템 카탈로그, `owned`, 사용자별 `acquisition` 진행도, 현재 `seed_balance` |
| POST `/shop/items/{id}/purchase` (멱등) | `purchase` 항목의 잔액 차감·원장·인벤토리를 원자적으로 처리. 조건 해금 항목은 `ITEM_NOT_PURCHASABLE` |
| POST `/shop/items/{id}/claim` (멱등) | 달성한 `quest_count`, `streak`, `record_count`, `own_item`, `collection_count`, `harvest_form` 항목을 무상 해금. 구매 항목은 `ITEM_NOT_CLAIMABLE` |
| GET `/shop/plant-species` | 무료/유료 품종과 해금 여부 |
| POST `/shop/plant-species/{id}/purchase` (멱등) | 유료 품종 직접 해금 |
| GET `/collection` | 보유 인벤토리 `items`, 잠금 항목까지 포함한 전체 아이템 도감 `catalog_items`, 품종 도감, 현재 씨앗 잔액 |
| GET `/farm` | 현재 layout과 배치 가능한 보유 아이템 |
| PUT `/farm/layout` | `expected_version` 기반 전체 배치 저장. 소유권·아이템 유형·중복 배치와 회전각 범위 검증 |
| GET `/adventure` | 오늘의 일기 개방 상태, 주간 탐험 약속, 장기 탐험 발자국, 활성 캐릭터 스탯, 의상 성능, 순찰·던전·수집품·표본 연구, 최근 기록과 탐험 이야기 도감을 반환. 던전별 `approaches`에는 현재 캐릭터 기준 예상 수집량이 포함된다. 안전 지원 활성일에는 `suspended=true` |
| POST `/adventure/patrols` (멱등) | `{route_code}`로 하루 한 번 순찰 시작. 오늘 50자 이상 일기와 경로별 성장 단계가 필요하며, 경로별 발견 이야기는 출발 시 고정하되 귀환 전에는 공개하지 않음 |
| POST `/adventure/patrols/{id}/claim` (멱등) | 귀환 시 씨앗 3개와 수집품 지급, 경로의 던전을 처음 발견하면 해금. 고정된 발견 이야기 `encounter`와 표시 문구 `outcome_message`를 함께 반환 |
| POST `/adventure/dungeons/{code}/run` (멱등) | 선택 본문 `{approach_code}`로 발견된 던전을 하루 한 번 탐험해 +10 XP/+4 씨앗과 수집품 지급. 던전 내부 장면 `scene`과 결과 문구를 함께 반환하며, 본문이 없는 구버전 요청은 `steady` 방식으로 처리 |
| POST `/adventure/research/{code}/complete` (멱등) | 필요한 수집품을 원자적으로 차감하고 계정 단위 표본 연구를 영구 완성. 부족 재료는 `RESEARCH_MATERIALS_REQUIRED`의 `details.missing`으로 반환 |
| POST `/adventure/weekly-goals/{code}/claim` (멱등) | 완료한 이번 주 목표의 씨앗 보상을 한 번 수령. 오늘 일기 개방은 요구하지 않지만 안전 지원 활성일에는 중단 |
| POST `/adventure/donations` (멱등) | `{item_code}`의 연구 필요량을 제외한 여분 표본 3개를 하루 한 번 기증하고 씨앗 2개 수령. XP는 지급하지 않음 |

탐험은 오늘 50자 이상 마음 일기를 쓴 뒤에만 열린다. 일기 한 편의 합산 보상은
+40 XP/+15 씨앗이며, 퀘스트(+20/+5), 던전(+10/+4), 순찰(+0/+3)보다 크다.
감정 성장형별 스탯 추가 총합은 모두 4로 같고, 의상 보너스는 탐험 수집량에만
영향을 주므로 감정의 종류와 의상 유무가 일기 경험치·씨앗 효율을 바꾸지 않는다.
표본 연구도 경험치·씨앗을 직접 지급하지 않고 이후 순찰 또는 던전 수집량만 최대
3개 범위에서 높인다. 수집품 정리는 시간 제한 활동이 아니므로 일기 개방 여부와
무관하게 할 수 있다.

`weekly_board`는 월요일부터 일요일까지의 `week_start`, `week_end`와 `goals`를
반환한다. 각 목표는 `{code, name, description, progress, target, reward_exp,
reward_seeds, completed, claimed, can_claim}` 형태다. 일기 3일은 씨앗 20개,
순찰 귀환 3회는 8개, 던전 탐험 2회는 6개이며 모두 XP는 0이다. 일기 일수는 같은
날 여러 편을 써도 50자 이상 기록이 있는 서로 다른 날짜만 센다. 수령 여부는
`adventure_weekly:{user_id}:{week_start}:{goal_code}` 원장 키로 판정하므로 재요청이나
다른 기기에서의 동시 요청으로 중복 지급되지 않는다. 미완료는
`WEEKLY_GOAL_INCOMPLETE`, 이미 받은 목표는 `WEEKLY_GOAL_ALREADY_CLAIMED`를 반환한다.

`milestones`는 `{current_title, unlocked_count, total_count, items}` 형태의 읽기 전용
장기 발자국이다. 각 항목은 `{code, name, description, progress, target, unlocked,
title}`을 반환한다. 50자 일기 7일, 순찰 귀환 5회, 던전 탐험 5회, 표본 연구 3개,
`온실 밖 탐험 1장` 완성을 차례로 보여 준다. 일기·순찰·던전 진행도는 삭제 후에도
남는 기존 보상 원장 완료 이벤트를 세고 연구 진행도는 영구 연구 행을 사용한다.
칭호는 씨앗·XP·수집 성능을 추가하지 않으며 별도 claim API도 없다.

`donation`은 `{available_today, used_today, has_eligible_item,
required_quantity, reward_exp, reward_seeds, message}`를 반환한다. 각 `inventory` 항목에는
`reserved_quantity`, `donatable_quantity`, `can_donate`가 추가된다. 서버는 아직
완성하지 않은 모든 연구의 요구량을 아이템별로 합산해 먼저 예약하고, 현재 수량에서
예약분을 뺀 여분이 3개 이상일 때만 기증을 허용한다. 하루 한 번 여분 3개를 씨앗
2개로 바꾸며 XP는 0이다. 부족하면 `ADVENTURE_DONATION_EXCESS_REQUIRED`, 이미
기증했으면 `ADVENTURE_DONATION_DAILY_LIMIT`를 반환한다. 안전 지원 활성일에는 기증도
중단한다.

`starlight_greenhouse_clock` 연구는 예외적으로 수집량 대신 모든 순찰 시간을 5분
줄인다. 각 route는 적용 후 `duration_minutes`와 원래 시간
`base_duration_minutes`, 차이 `time_reduction_minutes`를 함께 반환하며 최소 시간은
5분이다.

각 route의 `performance_score`, `projected_quantity`, `best_match`는 현재 캐릭터의
성장 스탯과 장착 의상, 완료한 순찰 연구를 반영한 읽기 전용 미리보기다. 잠긴 경로는
두 수치를 0으로 반환한다. 열린 경로 중 성능 점수가 가장 높은 하나만
`best_match=true`이며 동률이면 요구 성장 단계가 높은 경로를 고른다. 이 값은
수집량에만 쓰고 route의 고정 XP·씨앗 보상은 바꾸지 않는다.

순찰을 시작하면 사용자·날짜·경로를 기준으로 경로별 세 가지 발견 이야기 중 하나를
결정해 `encounter_code`, `encounter_title`, `encounter_text`로 저장한다. 진행 중
`patrol.encounter`는 `null`이고 `encounter_pending=true`이며, 귀환 수령 뒤에만
`encounter={code,title,text,reaction}`을 공개한다. `reaction`은 출발 당시 활성
캐릭터의 `{form,speaker,text}`를 담는다. claim 응답의 루트 `encounter`와
`outcome_message`도 같은 스냅샷을 사용하므로 콘텐츠 문구가 바뀌어도 과거 기록은
달라지지 않는다. 이야기 선택은 씨앗·XP·수집량·던전 발견 확률에 영향을 주지 않는다.

탐험 상태의 `research_summary`는
`{completed_count, total_count, chapter_completed, chapter_name}`을 반환한다.
`chapter_completed`는 선택 연구를 전부 끝냈는지가 아니라 최종
`outside_greenhouse_atlas` 완성 여부를 뜻한다. 5단계 `새벽 수관 회랑`에서
`마음나무 관측실`을 발견하고 앞선 장소의 핵심 표본과 함께 연구하면
`온실 밖 탐험 1장`이 완성된다.

`journal`은 별도 보상을 만들지 않는 읽기 전용 탐험 기록이다.
`{discovered_count, total_dungeons, total_clear_count, recent_entries}`를 반환하며,
`recent_entries`는 완료한 순찰과 던전 탐험을 최신순으로 합친 최대 6건이다. 각 항목은
`{kind, title, description, occurred_at, location_code, item_code, item_name,
quantity, outcome_code}` 형태다. 진행 중 순찰은 기록에 포함하지 않는다.
발견 이야기가 저장된 순찰은 이야기 제목을 `title`로, 본문과 수집품을 묶은 문장을
`description`으로 사용한다. 캐릭터 반응 스냅샷이 있으면 이름과 대사를 본문 뒤에
함께 표시한다. 마이그레이션 이전 순찰은 저장된 범위까지만 기존 문구로 표시한다.

`story_collection`은 최근 6건에서 밀려난 장면까지 다시 읽는 무보상 도감이다.
`{collected_count, total_count, completed, chapters}`를 반환하며 전체 수는 순찰 이야기
12개와 던전 장면 12개를 합친 24개다. 각 장은
`{code, name, description, collected_count, total_count, items}` 형태이고, 항목은
`{kind, code, location_code, location_name, discovered, title, text, detail,
discovered_at}`을 담는다. 발견한 코드는 시간순으로 가장 먼저 남은 스냅샷을 사용한다.
미발견 항목은 위치만 공개하고 `title`, `text`, `detail`, `discovered_at`은 `null`로
숨긴다. 도감 완성과 다시 읽기에는 씨앗·XP·수집량 효과나 별도 claim이 없다.

던전 접근 방식은 `care`, `focus`, `courage`, `insight` 네 가지다. 해당 스탯의 현재
값에 장소 추천 보정과 장착 의상 보너스를 합산해 수집량만 결정한다. 선택과 결과는
던전 실행 행에 스냅샷으로 남고, 어떤 방식을 골라도 고정 경험치·씨앗은 동일하다.

각 던전에는 세 가지 내부 장면이 있다. 실행 시 사용자·날짜·던전·접근 방식을 기준으로
하나를 결정해 `dungeon_runs.scene_code`, `scene_title`, `scene_text`에 저장한다.
응답의 `run.scene={code,title,text}`와 `run.outcome_message`는 같은 스냅샷을 사용하고,
탐험 기록장도 장면 제목과 본문을 표시한다. 장면 선택은 공명 판정·수집량·보상에
영향을 주지 않으며 기존 실행 행은 던전 이름 중심의 이전 문구로 표시한다.

안전 지원이 활성화된 퀘스트 응답은
`{date, suspended:true, suspension_reason, items:[]}`이다. 일반 응답은
`{date, suspended:false, suspension_reason:null, context_status, context_emotion, items, journey}`이며
`context_status`는 `record_optional|analyzing|diary_matched|neutral`이다. 각 item은
`{id, quest_date, status, completed_at, quest:{id, code, title, description, category,
burden_level, estimated_minutes, reward_exp, reward_seeds}}` 형태다.

`journey`는 누적 `recorded_day_count`, `completed_quest_count`, 이번 주의
`weekly_recorded_days`, `weekly_completed_quests`, 그리고 가장 가까운 미보유
아이템 `next_unlock`을 담는다. `next_unlock`은
`{item_id, code, name, item_type, acquisition_type, label, current, target, eligible}`이며
모든 아이템을 보유했으면 `null`이다. 퀘스트 완료 응답의
`{user_quest, reward, journey}`는 방금 완료한 진행도까지 반영한다.

캐릭터 도감은 `아기 화분 뽀또`, `냉미남 화분 로제온`, `센터 아이돌 블루미`,
`선인장 츤데레 가시로`, `좀비 화분 시들잎`, `구미호 여우비`, `닌자 그림싹`,
`마법사 별솔`, `서리동백 설화`, `학생회장 하루`까지 10종을 포함한다. 캐릭터의
`asset_manifest`에는 렌더링 자산을 고르는 `asset_key`, 대사·연출에 쓰는
`personality`, `catchphrase`, `motion_key`, `palette`, `accent`가 들어간다.

상점 item의 `acquisition`은 카탈로그의 `asset_manifest.acquisition`을 서버가
현재 사용자 상태에 맞춰 계산한 값이다. 클라이언트는 label을 그대로 안내하되,
진행 막대와 버튼 상태는 구조화된 `current`, `target`, `eligible`을 사용한다.

```json
{
  "id": 21,
  "code": "room_sakura",
  "type": "room_theme",
  "name": "벚꽃 소풍 다락방",
  "price_seeds": 0,
  "owned": false,
  "acquisition": {
    "type": "record_count",
    "label": "마음을 기록한 날 누적 7일",
    "current": 4,
    "target": 7,
    "eligible": false
  }
}
```

`purchase`는 현재 씨앗 잔액/가격, `quest_count`는 완료한 일일 퀘스트 총수,
`streak`는 현재 연속 기록 일수, `record_count`는 서로 다른 기록 날짜의 누적 수,
`own_item`은 지정 item 보유 여부(0/1),
`collection_count`는 보유 item 종류 수, `harvest_form`은 지정 최종 형태의 수확
횟수를 사용한다. `harvest_form` 기념품 6종은 모두 가격 0·희귀도 2·목표 1이며
`asset_manifest.collection=mood_resonance`, `affinity_forms`, `reaction_copy`를
제공한다. 감정별 성장·재화 보너스는 없다. 조건 달성 전 claim은 409
`ITEM_ACQUISITION_NOT_MET`와 현재 진행도를 반환한다. 동시 claim과 재시도는
사용자 행 잠금, `UNIQUE(user_id, item_id)`, `Idempotency-Key`로 한 번만 반영한다.

`GET /collection`의 `items`는 기존 보유 아이템 계약을 유지한다. `catalog_items`는 모든
활성 아이템을 아래 형태로 반환하므로, 클라이언트는 `locked=true`인 항목을
실루엣으로 보여줄 수 있다.

```json
{
  "items": [
    {"id": 7, "item": {"code": "deco_cushion_leaf"}, "acquired_at": "2026-07-13T01:00:00Z"}
  ],
  "catalog_items": [
    {
      "id": 11,
      "code": "species_cactus",
      "type": "species_unlock",
      "name": "가시니 씨앗",
      "description": "씨앗부터 다섯 단계로 키우는 성장 캐릭터 품종",
      "price_seeds": 100,
      "rarity": 2,
      "asset_manifest": {
        "asset_key": "species/cactus",
        "species_code": "cactus"
      },
      "owned": false,
      "locked": true,
      "user_item_id": null,
      "acquired_at": null
    }
  ],
  "species": [],
  "seed_balance": 0
}
```

마이팜 layout은 다음 형태다.

```json
{
  "version": 1,
  "room_theme_user_item_id": null,
  "main_character_user_item_id": null,
  "companion_user_item_ids": [],
  "decorations": [
    {"user_item_id": 3, "x": 0.3, "y": 0.6, "scale": 1.0, "rotation": 0, "z_index": 2}
  ]
}
```

중앙 성장 캐릭터는 layout에 장착하지 않는다. 앱은 현재 활성 `plants.id`와 해당
단계 에셋을 자동으로 사용한다. `main_character_user_item_id`는 구버전 응답
호환을 위해 남아 있지만 신규 클라이언트는 읽거나 쓰지 않고 항상 `null`로 보낸다.

`decorations[].rotation`은 Flutter `Transform.rotate`와 같은 **라디안** 단위이며
`-pi <= rotation <= pi` 범위다. `expected_version`이 현재 서버 version과 다르면
409 `FARM_LAYOUT_VERSION_CONFLICT`와 `{expected_version, current_version}`를 반환한다.
클라이언트는 이때 로컬 초안을 덮어쓰지 않고 최신 배치를 별도로 받아, 사용자가
최신본을 불러올지 로컬 초안을 최신 version 위에 다시 저장할지 선택하게 한다.

## 직접 조작형 탐험 API

`/adventure/expeditions`는 기존 즉시 판정형 던전과 독립된 서버 권위형 런이다.
클라이언트가 지도 결과를 계산하지 않으며, 모든 이동·선택·스킬·귀환은 서버에 저장된
현재 상태와 `revision`을 기준으로 확정한다.

| 메서드 | 경로 | 역할 |
|--------|------|------|
| GET | `/adventure/expeditions/catalog` | 오늘의 일기·안전·보상 게이트와 지역 목록 |
| GET | `/adventure/expeditions/roster?cursor=&limit=` | 탐험 가능 캐릭터 목록. 서명된 커서, 기본 30·최대 50 |
| GET | `/adventure/expeditions/active` | 현재 진행 중인 런. 없으면 `{"expedition":null}` |
| GET | `/adventure/expeditions/{run_id}` | 완료 런을 포함한 소유 런 스냅샷 |
| POST | `/adventure/expeditions` | 1~3명 편성으로 런 시작. `Idempotency-Key` 필수 |
| POST | `/adventure/expeditions/{run_id}/move` | 인접하고 공개된 노드로 이동 |
| POST | `/adventure/expeditions/{run_id}/choices` | 사건 담당 캐릭터와 선택지 확정 |
| POST | `/adventure/expeditions/{run_id}/skills` | 담당 캐릭터의 고유·성장형 스킬과 효과 모드 사용 |
| POST | `/adventure/expeditions/{run_id}/extract` | 목표 확보 후 안전 지점에서 귀환·보상 확정 |
| POST | `/adventure/expeditions/{run_id}/retreat` | 보상 없이 안전 귀환 |

시작 본문은 `{region_code, mode, plant_ids, guide_count}`다. `mode`는
`tutorial|heart_resonance|free_explore`이며, 성장·씨앗·수집품을 지급하는 것은 오늘
50자 이상 마음 일기를 쓴 뒤 시작한 `heart_resonance`를 목표 확보 상태로 끝낸 경우뿐이다.
`tutorial`과 `free_explore`, 중도 귀환, 결의 소진 안전 귀환에는 경제 보상이 없다.

런 행동 본문에는 공통으로 `{expected_revision, client_action_id}`가 들어간다.
같은 `client_action_id`와 같은 본문을 재전송하면 첫 응답을 그대로 돌려주고, 같은 키로
다른 행동을 보내면 409 `EXPEDITION_ACTION_ID_CONFLICT`다. 화면이 오래돼 revision이
달라졌으면 409 `EXPEDITION_REVISION_CONFLICT`와 현재 revision을 반환한다. 앱은 이때
행동을 임의 재적용하지 않고 `/active`를 다시 읽는다.
스킬 행동은 `{member_id, skill_type: "signature"|"form", mode_code?}`를 추가로
보낸다. 서버가 내려 준 `party[].skills.*.modes[].code`만 허용하며,
복수 효과 스킬은 `mode_code`가 필수다.

런 응답은 `{run, region, party, map, current_event, available_actions, run_thread,
memory, loot, summary}`다. 숨은 노드는 `{code,status:hidden,type:unknown}`만 반환해
좌표와 사건을 미리 노출하지 않는다. `current_event.choices[].previews`는 탐험대원별
사용 스탯·현재 값·기준·스킬 보정을 제공한다. `available_actions`는 화면이 활성화할
수 있는 이동·귀환 행동의 단일 원본이다.
`party[]`는 출발 시점의 `raw_stats`, 지역 상한을 적용한
`effective_stats`, `stat_cap`을 함께 제공하고 판정은 effective 값을 쓴다.
완주 요약의 `return_scene`은 보상보다 먼저 보여 줄 파티원별 활약 스냅샷이다.
catalog의 `entry.tutorial_completed`는 완주 런을 기준으로 첫 조작 안내 노출을
결정한다.

## 마음결 기록서 — 소유와 장착

구매는 기존 상점을 그대로 쓴다. `POST /shop/items/{item_id}/purchase`로 `type`이
`skill_book`인 항목을 사면 `user_items`에 구매 기록이, `user_skill_books`에 보유가
함께 남는다. 보유의 단일 원본은 후자이며 `source_ref`가 씨앗 원장 entry를 가리킨다.
이미 가진 책은 씨앗을 차감하기 **전에** 409로 막는다
(`ITEM_ALREADY_OWNED` 또는 `SKILL_BOOK_ALREADY_OWNED`).

소유(계정이 무엇을 가졌나)와 장착(어느 캐릭터의 어느 프리셋에 넣었나)은 서로
다른 축이다. 보유해도 자동으로 장착되지 않는다.

| method | path | 설명 |
|---|---|---|
| GET | `/skill-books` | 카탈로그 + 보유 + 프리셋 + `unlock_progress`(해금 조건과 남은 진행도) |
| GET | `/skill-books/loadouts/{plant_id}?preset_code=` | 저장된 장착과 그 해석 결과 |
| PUT | `/skill-books/loadouts/{plant_id}` | 장착 저장. 출발 전·캐릭터 화면에서만 부른다 |

카탈로그 항목의 `combat_effect`는 그 책이 전투 판정에 연결됐는지다. `false`인 책도
구매·장착할 수 있지만 벨트에서 `효과를 준비하고 있어요`로 잠긴다. 모든 기록서
효과는 **정액**이고 캐릭터 등급·tier·지원 능력치로 자라지 않는다.

카탈로그는 보유 여부와 무관하게 **전체**를 내려보낸다. 획득 경로에 확률이 없어
사전 공개가 원칙이기 때문이다. 3등급은 `price_seeds`가 `null`이고 `tradeoff`를
반드시 가진다.

`GET`/`PUT` 응답은 `stored`(사용자가 고른 것)와 `resolved`(지금 그것이 어떻게
읽히는지)를 함께 준다. 둘이 다를 때 `resolved[slot].fell_back`이 `true`가 되고
`lock_reason`이 이유를 설명한다. 슬롯 결과는 다음과 같다.

```json
{
  "stored": {"slot_b1_code": "clear_aim", "slot_b2_code": null},
  "resolved": {
    "B1": {"slot": "B1", "source": "skillbook", "code": "clear_aim",
           "locked": true, "lock_reason": "때가 되면 스스로 펼쳐져요",
           "fell_back": false, "book": {"grade": 1, "activation_mode": "trigger"}},
    "B2": {"slot": "B2", "source": "default_book", "code": "field_note_echo",
           "locked": false, "lock_reason": null, "fell_back": false}
  },
  "revision": 1,
  "slot_unlock_level": {"B1": 9, "B2": 23}
}
```

`source`는 `skillbook|emotion|default_book|locked`다. `locked: true`는 오류가
아니라 **자동 발동** 표시다 — `opening`·`trigger` 기록서는 대원 행동을 소비하지
않으므로 벨트에서 누를 수 없지만 자리는 비우지 않는다.

`PUT`은 멱등 키를 요구하지 않는다. 같은 내용을 두 번 저장해도 결과가 같고 재화가
움직이지 않기 때문이다. 대신 `expected_revision`으로 다른 화면이 먼저 바꾼 경우를
잡는다(불일치 시 409 `LOADOUT_REVISION_CONFLICT`).

저장 단계의 거부 코드:

| 상태 | code | 언제 |
|---:|---|---|
| 403 | `LOADOUT_BOOK_NOT_OWNED` | 보유하지 않은 기록서 |
| 422 | `LOADOUT_SLOT_LOCKED` | B1 Lv9 · B2 Lv23 미만 |
| 422 | `LOADOUT_SLOT_GRADE` | 3등급을 B1에 |
| 422 | `LOADOUT_DUPLICATE_BOOK` | 같은 책을 두 칸에 |
| 422 | `LOADOUT_STACK_CONFLICT` | 두 칸이 같은 `stack_group` |
| 422 | `LOADOUT_BOOK_NOT_COMBAT` | 탐험 기록서를 전투 슬롯에 |
| 409 | `SKILL_BOOK_ALREADY_OWNED` | 중복 획득. 씨앗을 차감하기 전에 막는다 |

**해석은 막지 않고 저장은 막는다.** 이미 저장된 장착이 나중에 조건을 잃어도
(책을 잃거나 밸런스가 바뀌어도) 출발은 안전 기본값으로 계속된다. 반면 고르는
순간에는 왜 안 되는지 알려 주는 편이 낫다.

같은 책을 여러 캐릭터·프리셋에 저장하는 것은 허용한다. 계정 라이선스이기
때문이다. 실제로 **함께 출발하는 파티** 안에서만 중복을 막는다(422
`PARTY_DUPLICATE_SKILL_BOOK`).

## P1 남은 예정 범위

`/assessment-instruments/{code}`, `/assessments`
