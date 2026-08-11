# 탐험 전투 코어 설계서 — 쿨타임·계수·상성·모션·이펙트

최종 갱신: 2026-08-11
문서 상태: **D 설계 확정 / K1~K7 C 완료 / K8 진행**
(`adventure_100_point_execution_contract.md` 2장 용어)
관련 코드: `server/app/content/expeditions/combat.py`,
`server/app/content/expeditions/combat_balance.py`,
`server/app/content/expeditions/combat_identity.py`,
`server/app/content/expeditions/combat_motion.py`,
`server/app/content/expeditions/combat_simulator.py`,
`server/app/content/expeditions/tangles.py`,
`app/lib/features/expedition/domain/expedition_combat_models.dart`,
`app/assets/adventure/effects/manifest.json`,
`app/lib/features/expedition/presentation/expedition_combat_effect_catalog.dart`,
`app/lib/features/expedition/presentation/expedition_combat_timeline.dart`,
`app/lib/features/expedition/presentation/expedition_combat_sprites.dart`,
`design-system/scripts/generate_expedition_effect_catalog.py`

밸런스 증거: `docs/expedition_combat_balance_report.json`,
`server/scripts/simulate_expedition_combat_balance.py`

## 문서 적용 전제

이 문서는 전투의 **판정 수치와 연출 데이터** 다섯 축만 정의한다. 화면 레이아웃과
입력 문법은 `expedition_stage_redesign.md` 4·5장, 성장·진화·경제는
`character_skill_growth_design.md`, 완료 판정과 증거는
`adventure_100_point_execution_contract.md` 9장이 계속 원본이다.

충돌하면 이 문서가 **쿨타임·피해 계수·상성·모션 프로파일·VFX 해석**에 한해
우선하고, 그 외 모든 항목은 기존 문서를 따른다. 이 문서가 바꾸는 기존 계약은
2장 개정표에 전부 적었다. 개정표에 없는 계약은 바뀌지 않는다.

### 2026-08-10 C 구현 스냅샷

- `combat-kit-v6`/`battle-state-v2`, 20원소 전수 `ELEMENT_KEL`, 약점
  `×1.50`·굴절 `×1.30`·내성 `×0.60`, 조건 효과 배수와 tier 배수가 서버 판정에
  연결됐다.
- 고유 I CD 하한 1, T3 고유 II만 3→2, `ready_round` 권위 필드와 v5 alias가
  서버·앱에 연결됐다.
- 파티 평균 Lv 성장지수로 신규 전투 장벽을 최대 1.30배 snapshot하고, 진행 중 v1
  run은 기존 정액식을 유지한다. G≤10은 장벽 1.00배로 두어 초반 반올림 역성장을
  막는다.
- 서버 이벤트의 `motion_profile`을 앱이 받아 투척·돌진·격투·회전·채널링 동선을
  구분한다. 실제 캐릭터별 cast pose 제작은 A 단계 잔여다.
- `venom_seam`은 공용 안개에서 분리되어 ImageGen 독립 원화 7F runtime을 쓴다.
  이 기록은 아래 2026-08-11 K5~K8 구현 전 기준선이며 현재 상태는 다음 절을 따른다.

### 2026-08-11 K5~K8 구현 스냅샷

- 서버가 6개 모션 아키타입의 `anticipation → release → travel → contact → reaction
  → recovery` 구간, 이동률, 방향, 충격량을 kit와 전투 이벤트에 snapshot한다.
- 앱은 `motion_profile` 문자열을 비교하지 않고 서버의 `archetype`과 `phases`를
  해석한다. 저감 모션에서는 액터 이동·흔들림을 0으로 만들고 접촉 정보는 유지한다.
- `manifest.json` v2가 frame 수·시간·contact frame·pivot·anchor·hash의 단일
  원본이다. 생성 스크립트가 Dart 카탈로그를 만들며 과거 수동 상수 맵은 삭제됐다.
- VFX는 `vfx_family → kel_fallback_family → legacy effect_key → echo_wave` 순서로
  해석한다. 앞의 세 값이 없는 저장 run만 legacy 계층을 거친다.
- 엉킴 12종의 24개 의도는 고유 family·결·아키타입·모션을 모두 선언한다. 서버와
  앱의 한국어 공격명 분기는 0건이다.
- `tangled-ledger.paper-flurry`는 Imagegen 포즈 원본 7장, 알파 마스터, 576×288
  WebP, 밝은/어두운 배경 QA와 애니메이션 미리보기를 갖춘 K8 production
  candidate다. 실기 GPU 프로파일 전이므로 `production_ready:false`는 유지한다.
- K4는 지역별 장벽·의도 밴드, 레벨별 HP 3→6, 평균 Lv18 시작 집중력 4를
  `battle-state-v2`에 snapshot한다. 실제 서버 판정으로 28,800전투를 전수 계산했고
  스테이지 역할별 출시 게이트를 모두 통과했다.
- `tangled-ledger.ink-mist`도 Imagegen 포즈 원본·알파·런타임을 각각 7장 보존한다.
  `channel` 760ms와 프레임 시간 합을 맞췄고 접촉 뒤 세로 확산으로 광역 의도를
  읽힌다. 실기 승인 전까지 `production_ready:false`다.

### 2026-08-11 K1 재검증에서 확정한 보완

기존 K1은 현재 카탈로그를 기준으로 한 결 판정은 동작했지만, 장기 운영과 구버전
호환까지 포함한 완료 조건은 부족했다. 다음 네 결함을 K1 범위에 추가한다.

1. `ELEMENT_KEL`이 바뀌면 진행 중 v2 전투의 대원 kit가 새 매핑으로 다시 계산될 수
   있었다. 적의 약점·내성은 시작 snapshot인데 행동의 결만 바뀌는 비결정 상태다.
2. T3 다중 결이 약점과 내성을 함께 포함하면 서버는 약점 우선으로 판정하지만 앱은
   원시 `kels`를 다시 비교해 약점·내성을 동시에 표시할 수 있었다.
3. 서버는 `kel_labels`를 보내지만 앱은 단일 `kel_label`만 보존해 T3 융합의 두 결을
   상세 화면에서 설명하지 못했다.
4. `COMBAT-KEL-02/03`은 문서에만 있고 대립축 분포와 전체 품종×성장결 kit를 잠그는
   자동 검증이 없었다.

K1은 아래 원칙으로 닫는다.

- 새 전투는 `kel_map_version`을 시작 상태에 snapshot하고 전투 종료까지 바꾸지 않는다.
- 결 매핑은 버전별로 append-only 보존한다. 알 수 없는 버전은 현재 매핑으로 조용히
  대체하지 않고 판정을 중단한다.
- `weak_kel`을 가진 `battle-state-v2`에서 `matchup`은 서버 권위 값이다. 앱은
  `kels`로 판정을 다시 하지 않으며, 구버전 또는 결 필드가 없는 초기 수호전에서만
  원소·능력치 fallback을 쓴다.
- 다중 결은 중복을 제거한 순서를 보존하고 `kel_labels`도 같은 순서·길이를 가진다.
- K1은 판정·표시 계약이므로 새 bitmap을 완료 증거로 요구하지 않는다. 결 glyph는
  기존 코드 기반 아이콘을 쓰고, 래스터 스프라이트는 K5~K8의 모션/VFX gate에서 만든다.

---

## 0. 확정 결정 요약

| # | 결정 | 바뀌는 것 |
|---|---|---|
| D1 | 상성은 **결 6종** 층이 판정하고 **원소 20종** 층은 연출·서사만 담당한다 | 원소 20종 전부가 상성에 참여한다. 사문화된 원소 14종이 사라진다 |
| D2 | 약점·내성은 정액(`+7 / −4`)에서 **곱연산**(`×1.50 / ×0.60`)으로 바꾼다 | 상성 비중이 레벨과 무관하게 고정된다 |
| D3 | 스킬 고유 보너스도 전부 곱연산으로 바꾼다 | `+6/+5/+8` 정액 보너스가 후반에 무의미해지는 문제가 사라진다 |
| D4 | tier 상승은 **쿨타임을 0으로 만들지 않는다**. 기본 배수로 보상한다 | Lv16에서 고유 I이 무한 연타가 되는 절벽이 사라진다 |
| D5 | 쿨타임 필드명을 `ready_round`로 바꾸고 정의를 문서에 고정한다 | 판정은 그대로. 이름과 정의만 명확해진다 |
| D6 | 적 장벽에 **성장지수 스케일링**과 **지역 밴드**를 함께 적용한다 | 후반에 전투가 1라운드로 끝나는 역전 곡선을 막는다 |
| D7 | `motion_profile`을 **6 아키타입 + 파라미터** 데이터 계약으로 정의하고 앱이 실제로 읽는다 | 27종 스킬이 같은 돌진 한 동작을 쓰던 문제가 사라진다 |
| D8 | VFX는 **`vfx_family` → 결 fallback → `echo_wave`** 3단으로 해석한다 | 아트가 family 단위로 코드 수정 없이 승격된다 |
| D9 | frame 수·frame 길이·contact frame·pivot의 단일 원본은 **manifest.json**이다 | Dart 상수와 manifest가 갈라지는 이중 원본을 없앤다 |
| D10 | 적 의도도 `effect_key`·`vfx_family`·`motion_profile`을 카탈로그에 선언한다 | 앱이 한국어 스킬명을 문자열 비교하던 분기를 없앤다 |

---

## 1. v5 기준선 진단 — 개정 근거 보존

아래 수치는 v6 개정 직전 코드를 실행해 측정한 기준선이다. 위 C 스냅샷에서 해결됐다고
표시한 항목의 현재 상태가 아니며, 왜 D1~D10을 채택했는지 회귀 근거로 보존한다.

### 1.1 다섯 축 상태

| 축 | 서버 | 앱 | 실제 상태 |
|---|---|---|---|
| 쿨타임 | 구현됨 | 아이콘 링·`재사용 N` 표시됨 | v5: tier 2에서 무력화 → **v6 해결** |
| 스킬 계수 | 구현됨 | 서버값 그대로 사용 | v5 정액 혼용 → **v6 배수식 해결** |
| 상성 | 구현됨 | 라벨 표시됨 | v5 14원소 사문화 → **v6 `ELEMENT_KEL` 해결** |
| 스킬 모션 | 6아키타입·6구간 phase snapshot | 서버 데이터 해석 | **K5 C 완료, 캐릭터별 pose A 잔여** |
| 스킬 이펙트 | exact·결·공용 family 선언 | manifest v2 자동 카탈로그 | **K6·K7 C 완료, K8 family 제작 진행** |

### 1.2 측정으로 확인한 결함

#### D-1. 고유 스킬 20종 중 16종이 상성에 참여하지 못한다

`TANGLE_ELEMENT_MATCHUPS`는 감정 주원소 6종(`fire light lightning steel water wind`)만
쓴다. 그런데 고유 스킬의 원소는 20종이다. 표에 없는 원소는 약점도 내성도 될 수
없으므로 **항상 중립**이다.

| 품종 | 고유 I | 고유 II |
|---|---|---|
| baby-pot | `nature` 사문화 | `nature` 사문화 |
| handsome-pot | `steel` 정상 | `sound` 사문화 |
| pretty-pot | `heart` 사문화 | `light` 정상 |
| tsundere-pot | `fire` 정상 | `strike` 사문화 |
| zombie-pot | `gravity` 사문화 | `decay` 사문화 |
| gumiho-pot | `heart` 사문화 | `moon` 사문화 |
| ninja-pot | `poison` 사문화 | `shadow` 사문화 |
| magical-pot | `arcane` 사문화 | `arcane` 사문화 |
| aloof-pot | `ice` 사문화 | `steel` 정상 |
| student-pot | `ink` 사문화 | `seal` 사문화 |

20종 중 정상 4종. tier 3(Lv25)에서 감정 주원소가 `elements`에 추가돼 뒤늦게
살아나지만, **Lv3~24 구간 전체에서 캐릭터 고유기로 약점을 찌를 수 없다.**
"약점을 보고 스킬을 고른다"는 핵심 루프가 성립하지 않는다.

#### D-2. 상성이 레벨에 따라 소멸한다

성장은 곱연산(`power × scale_bp`)인데 상성은 정액(`+7 / −4`)이다.

| 구간 | 고유 I 위력 | 약점 `+7`의 비중 | 내성 `−4`의 비중 |
|---|---:|---:|---:|
| Lv3 · 1등급 | 20 | 35.0% | 20.0% |
| Lv9 · 1등급 | 24 | 29.2% | 16.7% |
| Lv16 · 3등급 | 33 | 21.2% | 12.1% |
| Lv25 · 4등급 | 47 | 14.9% | 8.5% |
| Lv30 · 5등급 | 63 | **11.1%** | **6.3%** |

성장할수록 상성을 읽을 이유가 사라진다. 스킬 고유 보너스(`weakness_pierce +6`,
`steady_read +5`, `last_stand +8`)도 같은 이유로 함께 소멸한다.

#### D-3. tier 2가 고유 I의 쿨타임을 0으로 만든다

`resolve_skill`은 `source == "signature"`이고 `tier >= 2`이면
`cooldown_turns - 1`을 적용한다. 고유 I의 기본 쿨타임은 전 품종 1이므로
**Lv16에서 정확히 0이 된다.**

| 레벨 | tier | 고유 I cd | 고유 II cd |
|---|---:|---:|---:|
| Lv3~15 | 1 | 1 | 3 |
| **Lv16~24** | 2 | **0** | 2 |
| Lv25~30 | 3 | **0** | 2 |

Lv16부터 고유 I은 집중력만 있으면 매 라운드 연타된다. 쿨타임이라는 축이
설계 의도와 반대로 **성장 보상으로 삭제된다.**

#### D-4. 난이도 곡선이 역전된다

적 장벽은 카탈로그 고정값이고, `character_skill_growth_design.md` 9.1이 정의한
성장지수 스케일링(`× (1 + 0.18·G/100)`)은 **코드에 없다.** 적 의도 위력도 전
지역에서 1~2로 고정이고 대원 HP는 3으로 고정이다.

| 구간 | 3인 파티 기본 공격 합 | 3인 고유 I 합 | 1지역 일반 장벽 |
|---|---:|---:|---:|
| Lv3 · 1등급 | 33 | 55 | 34 |
| Lv9 · 1등급 | 36 | 67 | 34~36 |
| Lv16 · 3등급 | 51 | 94 | 34~36 |
| Lv25 · 4등급 | **66** | **134** | 34~40 |

파티 위력은 약 +100%, 장벽은 지역 4개를 통과해도 +18%(일반 34→40)다.
Lv25 파티는 **기본 공격만으로 일반 엉킴을 1라운드에 끝낸다.** 목표인
"3~6라운드, 45~90초"가 후반에 성립하지 않는다.

#### D-5. 모션이 데이터로 존재하지만 아무도 읽지 않는다

서버는 27종 스킬에 서로 다른 `motion_profile`을 보낸다.
앱은 `ExpeditionBattleAction.motionProfile`로 파싱까지 하지만,
**실제 사용처는 `expedition_battle_dock.dart`의 상세 시트 표시 한 곳뿐이다.**

연출은 `ExpeditionCombatTimeline.actorOffset()`의 하드코딩된 단일 동선을 쓴다.
`뿌리 포옹`(지원 채널링)과 `무영 처형`(그림자 돌진)이 **같은 30px 런지**로
재생된다. 100점 계약 3장 5항의 "플레이어와 적 모두 고유한
anticipation→…→recovery" 요구가 데이터만 있고 재생되지 않는다.

#### D-6. 이펙트가 원소 20종 → 공용 7종으로 붕괴한다

`ELEMENT_RUNTIME_EFFECTS`는 원소 20종을 공용 프로토타입 7종에 매핑한다.
`vfx_family` 27종은 판정에 쓰이지 않는다.

```
poison → mist_dash      shadow → mist_dash      decay  → mist_dash
water  → mist_dash      ice    → mist_dash      wind   → mist_dash
```

6개 원소가 같은 스프라이트다. 실제 번들도 `care-vines-v2`·`ledger-claw-v2`
2종만 10프레임 production candidate이고 나머지는 8프레임 공용이다.

추가로 두 개의 이중 원본이 있다.

- frame 길이가 `manifest.json`이 아니라 **Dart 상수 맵**
  (`_expeditionCombatEffectFrameDurationsMs`)에 있다. manifest에는 그 필드가 없다.
- 적 이펙트 선택이 **한국어 스킬명 문자열 비교**다.
  `expedition_action_cue.dart`: `combat?.attackName == '장부 발톱'`.
  적 이름을 한 글자만 고쳐도 연출이 조용히 공용 파동으로 떨어진다.

---

## 2. 기존 계약 개정표

| 문서 | 기존 조항 | 개정 | 이유 |
|---|---|---|---|
| `expedition_manual_combat.md` 4장 | 약점 `+7`, 내성 `−4`(최소 1) | **약점 `×1.50`, 내성 `×0.60`(최소 1)** | D-2. 정액은 성장과 함께 소멸한다 |
| `expedition_manual_combat.md` 4장 | 성장결 6종을 쓰고 탐험 능력치와 섞지 않는다 | 유지. 여기에 **원소 20종 → 결 6종 매핑**을 추가한다 | D-1. 원소가 판정에 참여할 통로가 필요하다 |
| `expedition_manual_combat.md` 5장 | 고유 판정 `피해 +8 / +6 / +5` | **`×1.45 / ×1.25 / ×1.30`** | D-2와 같은 이유 |
| `adventure_100_point_execution_contract.md` 5장 | 상성 `약점 +7, 내성 −4` | 위와 동일하게 개정 | 동일 |
| `character_skill_growth_design.md` 9.1 | `barrier × (1 + 0.18·G/100)` | **G≤10은 1.00, 이후 `×(1+0.30·(G−10)/90)`**, 상한 1.30 | 초반 반올림 역성장 없이 후반 1턴화를 막는다 |
| `character_skill_growth_design.md` 5장 | tier 2가 고유 쿨타임 −1 | **쿨타임 하한 1. tier 보상은 기본 배수로 이전** | D-3 |
| 신규 | — | 전투 상태 스키마 `battle-state-v2`, 전투 kit `combat-kit-v6` | 위 개정을 담을 그릇 |

개정표에 없는 항목(집중력 3/5, HP, 6라운드 상한, 6슬롯 고정 순서, 350ms hold,
접근성 기준, 순차 명령 계약, 실패 시 무손실)은 **전부 그대로다.**

---

## 3. 상성 — 결 6종 / 원소 20종 두 층 모델

### 3.1 왜 두 층인가

원소를 6종으로 줄이면 캐릭터 정체성(맹독·그림자·중력·먹빛)이 사라진다.
원소 20종을 그대로 상성표에 올리면 사용자가 20×20을 외워야 한다.

그래서 **판정하는 층과 표현하는 층을 분리한다.**

| 층 | 개수 | 역할 | 사용자에게 보이는 방식 |
|---|---:|---|---|
| **결** | 6 | 약점·내성 판정의 유일한 기준 | 적 HUD의 `↑약점 / ↓내성`, 명령 아이콘의 결 glyph |
| **원소** | 20 | VFX family·모션·서사·이름 | 스킬 상세 시트, 이펙트, 대사 |

맹독 단검은 계속 맹독이지만, 판정에서는 `빗물결`로 읽힌다. 사용자는
"닌자의 고유 I은 빗물결"만 알면 되고, 화면은 여전히 독이다.

### 3.2 결 6종

`expedition_manual_combat.md` 4장의 여섯 성장결을 그대로 쓴다. 탐험 능력치
`care|focus|courage|insight`와 절대 섞지 않는다.

| 결 코드 | 이름 | 감정 | 대표 원소 |
|---|---|---|---|
| `sunny` | 햇살결 | 기쁨 | light |
| `rainy` | 빗물결 | 슬픔 | water |
| `ember` | 불씨결 | 분노 | fire |
| `moonlit` | 달빛결 | 불안 | wind |
| `sparkling` | 별빛결 | 놀람 | lightning |
| `mosaic` | 모아결 | 중립 | steel |

### 3.3 원소 → 결 매핑

전체표는 부록 A. 이 매핑은 `combat_identity.py`의 `ELEMENT_KEL`에 두고
validator가 **20종 전수 매핑**을 강제한다. 미매핑 원소는 배포를 막는다.

| 결 | 원소 |
|---|---|
| 햇살결 | `light` `nature` `heart` |
| 빗물결 | `water` `ice` `poison` |
| 불씨결 | `fire` `decay` `strike` |
| 달빛결 | `wind` `moon` `shadow` |
| 별빛결 | `lightning` `sound` `arcane` |
| 모아결 | `steel` `force` `gravity` `ink` `seal` |

감정 discipline의 주·보조 원소는 반드시 같은 결에 속한다. 따라서 하트는 햇살결,
격투는 불씨결이다. 캐릭터의 상성 선택 폭은 원소 라벨을 직관과 다르게 비트는 방식이
아니라 기본 공격의 현재 성장결, 선택 슬롯, T3 융합, 파티 편성으로 만든다.

### 3.4 결 대립축

| 축 | 관계 |
|---|---|
| 햇살결 ↔ 달빛결 | 빛과 그늘 |
| 빗물결 ↔ 불씨결 | 물과 불 |
| 별빛결 ↔ 모아결 | 번쩍임과 무게 |

대립축은 **콘텐츠 작성 가이드**이지 자동 판정식이 아니다. 적의 약점·내성은
개별 선언이 계속 권위를 갖는다(첫 조우에 공개하는 계약 유지). 축은 12엉킴의
분포가 학습 가능하도록 다음 조건만 강제한다.

- 한 엉킴의 약점 결과 내성 결은 서로 다르다. *(기존 규칙 유지)*
- 12엉킴 전체에서 각 결이 약점 2회·내성 2회다. *(기존 규칙 유지)*
- 세 대립축이 각각 **최소 2회** 등장한다. *(신규)*
- 한 지역 3엉킴이 모두 같은 축을 쓰지 않는다. *(신규)*

### 3.5 캐릭터 결 분포 합격 조건

| 조건 | 기준 |
|---|---|
| 네 슬롯(고유 I·II, 선택 I·II) 전체 | **최소 2개 결**이 나온다 |
| 고유 I·II | 서로 다른 결을 **권장**한다 |

선택 I은 감정 성장 계열에서 오고 감정 주원소가 6종 서로 다르므로, 전체 kit와 파티는
결 하나에 갇히지 않는다. 고유 I·II는 캐릭터 판타지가 같은 결을 요구하면 억지로
분리하지 않는다. 같은 결인 5종은 아래 사유로 허용한다.

| 품종 | 결 | 허용 사유 |
|---|---|---|
| baby-pot | 햇살/햇살 | 입문·지원 역할. 두 고유기 모두 `support` |
| pretty-pot | 햇살/햇살 | 하트·빛 무대 판타지를 보존. 역할은 공격 회복/지속 회복으로 분리 |
| tsundere-pot | 불씨/불씨 | 불꽃·격투 판타지를 보존. 역할은 반격 방어/약점 관통으로 분리 |
| magical-pot | 별빛/별빛 | 두 고유기 모두 `prism_shift`로 결을 바꾼다. 3.6 참조 |
| student-pot | 모아/모아 | 역할이 피해가 아니라 집중력 환급 |

### 3.6 굴절 약점 — `prism_shift`

`prism_shift`는 스킬의 결을 현재 약점 결로 바꾼다. 곱연산 상성에서 이 효과를
그대로 두면 magical-pot이 **항상 `×1.50`을 확정**해 다른 아홉 품종을 지배한다.

굴절로 얻은 약점은 별도 배수를 쓴다.

| 상황 | 배수 |
|---|---:|
| 스킬의 원래 결이 약점과 일치 | `×1.50` |
| `prism_shift`로 굴절해 일치 | **`×1.30`** |
| 중립 | `×1.00` |
| 내성 | `×0.60` |

magical-pot은 확실성을, 나머지는 상한을 갖는다. 집중력 비용(3·4)이 이미 다른
품종(2·3)보다 한 칸 높으므로 추가 비용 조정은 하지 않는다.

### 3.7 다중 결

tier 3 고유기는 감정 주원소를 얻어 결이 둘이 된다(기존 동작 유지). 판정은
**가장 유리한 결 하나**만 적용한다.

```
약점 결이 하나라도 있으면 약점,
아니면 내성 결만 있을 때 내성,
그 외 중립
```

내성 결과 약점 결을 동시에 가지면 약점이 이긴다. tier 3 보상이 벌점이 되지
않게 한다.

### 3.8 K1 결 매핑 버전과 판정 권위

결 매핑은 단순 상수가 아니라 진행 중 전투의 판정을 재현하는 규칙 데이터다.
`ELEMENT_KEL_BY_VERSION`은 과거 버전을 지우거나 제자리에서 수정하지 않는
append-only 원본이며, 현재 버전은 `CURRENT_KEL_MAP_VERSION`으로 고른다.

```text
원소 카탈로그
  → ELEMENT_KEL_BY_VERSION[kel_map_version]
  → 전투 시작 snapshot
  → kit의 kel / kels / kel_labels / matchup
  → party_action의 kel_map_version / matchup
  → Flutter 표시
```

| 상황 | 서버 | 앱 |
|---|---|---|
| 신규 KEL `battle-state-v2` | 현재 `kel_map_version`을 상태에 저장 | `battle.version >= 2 && weak_kel != null`이면 `matchup`만 판정 권위로 사용 |
| 저장 중 v2 전투 | 상태에 저장된 버전의 매핑으로 매번 kit 재구성 | 약점/내성 badge를 동시에 표시하지 않음 |
| 버전 필드가 없는 기존 v2 전투 | 최초 버전 `1`로 해석 | 서버가 내려준 `matchup` 사용 |
| `weak_kel`이 없는 초기 v2 수호전 | 기존 4능력치 판정을 유지 | 능력치·원소 fallback으로 표시 |
| v1 전투 | 당시 원소 정액식·4능력치 fallback 유지 | `weak_element` 또는 `affinity`로만 표시 보조 |
| 알 수 없는 `kel_map_version` | 명시적 오류로 판정 중단, 운영 로그 기록 | 서버 응답을 임의 보정하지 않고 재시도 안내 |

`kel`은 스킬 원본의 대표 결, `kels`는 T3 융합까지 포함한 판정 후보 목록이다.
`kel_labels`는 `kels`와 같은 순서·길이여야 한다. 앱 상세 시트는 단일 `kel_label`이
아니라 `kel_labels` 전체를 보여 주고, `matchup_bp`로 실제 `×1.50`, `×1.30`,
`×1.00`, `×0.60`을 표시한다.

### 3.9 대립축 분포 validator

12엉킴은 약점·내성 횟수만 균등하면 끝이 아니다. 사용자가 세 대립축을 반복해서
학습할 수 있도록 다음을 import 시점과 단위 테스트에서 함께 검증한다.

- 각 결은 약점 2회·내성 2회다.
- 햇살↔달빛, 빗물↔불씨, 별빛↔모아의 **정방향·역방향이 각각 2회**다.
- 약점과 내성이 같은 결인 엉킴은 0개다.
- 카탈로그에 등장하는 모든 원소는 정확히 한 결에 속하고 모든 결에 한국어 라벨이 있다.
- Lv25 기준 모든 품종×성장결의 기본+고유2+선택2에는 최소 두 결이 있으며,
  `kels`와 `kel_labels`의 길이가 항상 같다.

고정 선택기인 `현장 기록: 되울림`은 먹빛 탄환과 기록 파형을 함께 쓰므로
`ink + sound`, 즉 `모아결 + 별빛결` 이중 결로 선언한다. 이 계약 덕분에
학생화분×모아결처럼 품종 고유기와 성장결이 완전히 겹쳐도 kit가 단일 결에
갇히지 않는다.

---

## 4. 계수 — 피해식

### 4.1 단일 피해식

모든 배수는 **basis point 정수 연산**이다. 부동소수를 쓰지 않으므로 서버와 앱의
예상 피해가 비트 단위로 일치한다.

```
round_bp(v, bp) = (v * bp + 5000) // 10000        # 반올림, 결정론적

S1 raw     = base_power + round_bp(stat[결], stat_coeff_bp)
S2 growth  = round_bp(raw,    growth_scale_bp)    # 레벨 × 등급 곡선 (기존 유지)
S3 tiered  = round_bp(growth, tier_bp)            # 성장 tier
S4 matched = round_bp(tiered, matchup_bp)         # 상성
S5 shaped  = round_bp(matched, effect_bp)         # 스킬 고유 효과
S6 final   = max(1, shaped)
```

적용 순서를 문서에 고정한다. 순서가 바뀌면 반올림 때문에 값이 달라진다.
`S4 → S5` 순서는 "상성을 먼저 판정하고 그 결과에 스킬 특성이 반응한다"는
의미이며, `weakness_pierce`가 약점 여부를 읽는 현재 동작과 일치한다.

### 4.2 계수표

| 기호 | 값 | 비고 |
|---|---|---|
| `stat_coeff_bp` | 스킬 `10000` / 기본 공격 `5000` | 기존 동작과 동일 |
| `growth_scale_bp` | `rarity_scale_bp(level, rarity)` | **기존 곡선 그대로 유지** |
| `tier_bp` | T1 `10000` · T2 `11000` · T3 `12200` | **신규.** D-3에서 회수한 쿨타임 보상의 이전분 |
| `matchup_bp` | 약점 `15000` · 굴절약점 `13000` · 중립 `10000` · 내성 `6000` | 개정 |

### 4.3 효과 배수 `effect_bp`

정액 보너스를 전부 곱연산으로 옮긴다.

| effect | 조건 | 기존 | 개정 |
|---|---|---|---|
| `weakness_pierce` | 약점 적중 | `+6` | `×1.25` |
| `steady_read` | 비약점 | `+5` | `×1.30` |
| `last_stand` | 자신 HP 1 | `+8` | `×1.45` |
| `shield_all` `focus_refund` `heal_lowest` `guard_self` `weaken_intent` `study_refund` `prism_shift` | — | 피해 보정 없음 | 유지 |

`steady_read`가 `×1.30`으로 내성(`×0.60`)을 완전히 상쇄하지 못하는 것은
의도다. 내성 회피는 다른 스킬을 고르는 것이지 한 스킬로 무시하는 것이 아니다.

### 4.4 검산

3인 파티, 고유 I 기준. `weakness_pierce` 보유 시.

| 구간 | 중립 | 약점 | 약점+관통 | 내성 | 약점/중립 |
|---|---:|---:|---:|---:|---:|
| Lv3 · 1등급 | 20 | 30 | 38 | 12 | 1.500 |
| Lv9 · 1등급 | 24 | 36 | 45 | 14 | 1.500 |
| Lv16 · 3등급 | 36 | 54 | 68 | 22 | 1.500 |
| Lv25 · 4등급 | 57 | 86 | 108 | 34 | 1.509 |
| Lv30 · 5등급 | 77 | 116 | 145 | 46 | 1.507 |

상성 비중이 전 구간에서 고정된다(D-2 해소). tier_bp가 붙어 중립 피해도
Lv16에서 33→36, Lv25에서 47→57로 올라 D-3에서 회수한 쿨타임 보상을 대체한다.

**반올림 오차.** 정수 연산이므로 비가 정확히 1.500이 되지는 않는다. 편차 상한은
중립 피해 크기에 따라 결정된다.

| 중립 피해 | 약점/중립 편차 상한 |
|---:|---:|
| 10 이상 | 0.046 |
| 20 이상 | 0.024 |
| 30 이상 | 0.017 |

전투에서 실제로 나오는 최소 피해가 10 이상이므로 **편차 상한 0.05**를 검수
기준으로 쓴다. 소수 배수를 쓰는 대신 정수 basis point를 유지하는 이유는 서버와
앱의 예상 피해가 반드시 같아야 하기 때문이다.

### 4.5 적 장벽

D-4를 풀려면 장벽이 두 축으로 자라야 한다.

**축 1 — 지역 밴드.** 카탈로그 고정값의 하한이다.

| 지역 | 일반 엉킴 | 큰 엉킴 |
|---|---:|---:|
| 1 이끼 기억서고 | 34~38 | 70~76 |
| 2 메아리 우물정원 | 44~50 | 88~96 |
| 3 별빛 씨앗금고 | 56~64 | 110~120 |
| 4 심재 관측소 | 70~80 | 136~148 |

현재 카탈로그는 일반 장벽을 지역별 `34/38`, `44/50`, `56/64`, `70/80`, 큰
엉킴을 `76`, `96`, `120`, `148`로 확정했다. import 시 validator가 밴드를
벗어난 콘텐츠를 즉시 거부한다.

**축 2 — 성장지수.** `character_skill_growth_design.md` 9.1의 미구현 조항을
구현하되 계수를 올린다.

```
G = 길잡이를 제외한 실소유 대원의 평균 성장지수 = round((level - 1) / 29 * 100)
B = max(0, G - 10) / 90
barrier = round_bp(base_barrier, 10000 + round(3000 * B))  # 상한 1.30배
enemy_power = 지역·난이도 고정. G를 읽지 않는다.
```

G≤10은 계수 반올림상 플레이어 위력이 그대로일 수 있어 장벽도 그대로 둔다. 적 위력이
G를 읽지 않는다는 원칙은 유지하며 성장의 안전 마진은 사용자에게 남는다.

**축 3 — 적 위력 지역 밴드.** 현재 전 지역 1~2 고정이다. 대원 HP가 3→6으로
자라는 설계(성장 설계서 9.3)와 함께 조정한다.

| 지역 | 일반 의도 위력 | 큰 엉킴 의도 위력 |
|---|---|---|
| 1 | 1 | 1~2 |
| 2 | 1~2 | 2 |
| 3 | 2 | 2~3 |
| 4 | 2~3 | 3 |

대원 HP는 Lv1~9 `3`, Lv10~18 `4`, Lv19~26 `5`, Lv27~30 `6`이다. 길잡이를
제외한 실소유 파티 평균이 Lv18 이상이면 표준 시작 집중력 `3`만 `4`로 올라간다.
이미 0~2 또는 4~5로 조정된 커스텀 encounter에는 중복 보너스를 주지 않는다.

세 축은 10장의 28,800전투 전수 시뮬레이션을 통과한 **balance version 1 승인
후보**다. 진행 중 run은 시작 당시 `balance_version`, 장벽, HP, 집중력 snapshot을
끝까지 유지한다.

---

## 5. 쿨타임

### 5.1 정의

```
ready_round = used_round + cooldown_turns + 1
사용 가능 조건: current_round >= ready_round
cooldown_remaining = max(0, ready_round - current_round)
```

`cooldown_turns = N`은 **다음 N개 라운드를 쉰다**는 뜻이다. 계산은 현재
`cooldown_until_round`와 동일하므로 판정은 바뀌지 않는다. 이름만
`ready_round`로 바꿔 의미를 코드에서 읽히게 한다.

### 5.2 tier와 쿨타임

```
effective_cd = max(1, base_cd - tier_reduction)      # base_cd >= 1 인 스킬
tier_reduction = T1 0 · T2 0 · T3 1
```

- **하한 1을 절대 깨지 않는다.** 고유 I은 전 구간에서 1라운드 리듬을 지킨다.
- tier 2의 보상은 쿨타임이 아니라 `tier_bp` 11000이다(4.2).
- `base_cd = 0`인 기본 공격·마음 지키기는 하한 규칙과 무관하게 계속 0이다.

| 레벨 | tier | 고유 I | 고유 II | 선택 I | 선택 II |
|---|---:|---:|---:|---:|---:|
| Lv3~15 | 1 | 1 | 3 | 2 | 3 |
| Lv16~24 | 2 | 1 | 3 | 2 | 3 |
| Lv25~30 | 3 | **1** | **2** | 2 | 3 |

### 5.3 라운드 예산과 사용 횟수

전투는 3~6라운드다. 쿨타임은 이 짧은 창 안에서만 의미가 있어야 한다.

| 슬롯 | cd | 6라운드 최대 사용 | 설계 의도 |
|---|---:|---:|---|
| 기본 공격 | 0 | 6 | 집중력 생성 |
| 고유 I | 1 | 3 (R1·R3·R5) | 주력. 격 라운드 리듬 |
| 고유 II | 3 → T3 2 | 2 (R1·R5) → 2 (R1·R4) | 결정기 |
| 선택 I | 2 | 2 (R1·R4) | 보조 |
| 선택 II | 3 | 2 (R1·R5) | 특수 |
| 마음 지키기 | 0 | 6 | 방어 |

**합격 조건**: 집중력 0~5 어느 상태에서도 최소 한 행동은 항상 합법이다
(기본 공격·지키기가 cd 0이므로 구조적으로 보장된다).

### 5.4 명시할 경계 규칙

현재 코드에 암묵적으로 존재하지만 문서에 없던 규칙을 확정한다.

- **웨이브 전환은 쿨타임을 초기화하지 않는다.** 웨이브를 깨면
  `round`가 1 증가하므로 쿨타임도 함께 1 진행한다. 한 전투는 연속된 교전이다.
- **전투 종료 시 쿨타임은 폐기한다.** 다음 전투는 전 슬롯 사용 가능으로 시작한다.
- **쿨타임은 대원별로 저장한다.** 같은 스킬 코드를 가진 두 대원의 쿨타임은
  독립이다(`party[].ready_round[skill_code]`).
- **쿨타임 중 슬롯은 숨기지 않는다.** 아이콘 위치는 고정, 링에 남은 라운드 수를
  표시하고 비활성 처리한다(현재 앱 동작 유지).
- **쿨타임 위반은 서버가 422 `EXPEDITION_COMBAT_COOLDOWN`으로 거절한다.**
  앱의 비활성화는 편의이지 권위가 아니다(현재 동작 유지).

---

## 6. 스킬 모션

### 6.1 원칙

27종 스킬마다 타임라인을 손으로 적으면 유지되지 않는다. **6개 아키타입 +
스킬별 소수 파라미터**로 정의하고, 앱은 아키타입 해석기 하나만 구현한다.

여섯 단계 이름은 100점 계약 3장 5항과 동일하다.

```
anticipation → release → travel → contact → reaction → recovery
```

### 6.2 아키타입 6종

| 아키타입 | 액터 동선 | 대표 | 일반 총 길이 | 결정기 총 길이 |
|---|---|---|---:|---:|
| `dash` 돌진 | 표적까지 전진 후 복귀 | 근접 참격·타격 | 820~900ms | 1,150~1,400ms |
| `draw` 발도 | 반보 전진 + 제자리 일섬 | 검·단검 | 680~760ms | 950~1,150ms |
| `cast` 시전 | 액터 정지, 투사체가 이동 | 마법·투사체 | 720~820ms | 1,000~1,250ms |
| `brace` 버팀 | 액터 고정, 역장·장판이 퍼짐 | 제어·강철 | 660~740ms | 950~1,150ms |
| `channel` 집중 | 액터 상승·개방, 광역 | 지원·회복 | 700~800ms | 1,000~1,200ms |
| `leap` 도약 | 포물선 이동 | 주술·환혹 | 780~860ms | 1,100~1,300ms |

일반 620~900ms, 결정기 950~1,400ms의 기존 밴드
(`expedition_manual_combat.md` 6장)를 그대로 지킨다.

### 6.3 데이터 계약

서버가 스킬마다 내려보내는 모션 payload다.

```json
"motion": {
  "profile": "ninja-pot.venom-draw",
  "archetype": "draw",
  "facing": "right",
  "travel_ratio": 0.34,
  "impact_shake_px": 2.8,
  "phases": [
    {"name": "anticipation", "ms": 120},
    {"name": "release",      "ms": 80},
    {"name": "travel",       "ms": 180},
    {"name": "contact",      "ms": 70},
    {"name": "reaction",     "ms": 140},
    {"name": "recovery",     "ms": 170}
  ]
}
```

| 필드 | 의미 | 기본값 |
|---|---|---|
| `profile` | 기존 `motion_profile` 문자열. 로그·검수 키 | 필수 |
| `archetype` | 6종 중 하나. 앱의 해석 분기 | 필수 |
| `facing` | 액터 기준 발사 방향 | `right` |
| `travel_ratio` | 액터가 이동하는 거리 비율(0=제자리, 1=표적까지) | 아키타입 기본값 |
| `impact_shake_px` | 접촉 흔들림 진폭. 상한 3.5px | 2.8 |
| `phases` | 여섯 단계 길이(ms). 합이 아키타입 밴드 안이어야 한다 | 아키타입 기본값 |

- **`phases` 합이 밴드를 벗어나면 validator가 배포를 막는다.**
- 스킬이 `phases`를 생략하면 아키타입 기본 타임라인을 쓴다. 27종 중 대부분은
  생략하고, 정체성이 필요한 스킬만 덮어쓴다.
- 앱은 `archetype`을 모르면 `cast`로 fallback하고 판정은 유지한다.

### 6.4 앱 구현 계약

- `ExpeditionCombatTimeline.actorOffset()`의 하드코딩 분기를 제거하고
  `archetype`+`phases`를 읽는 해석기로 대체한다.
- `ExpeditionActionCue`에 `motion` 필드를 추가한다. 현재 큐는 모션 정보를
  전혀 옮기지 않아 연출 레이어가 스킬을 구분할 방법이 없다(D-5의 직접 원인).
- `contact` 단계의 시작 프레임에서 피해 숫자·SFX·햅틱이 **동시에** 발생한다.
  `contact` 이전에 HP·장벽·피해 숫자를 갱신하지 않는다(기존 계약 유지).
- **저감 모션**에서는 `release`·`contact`·`reaction` 대표 프레임만 240~700ms에
  보여 준다. 액터 이동과 흔들림은 0으로 만들되 단계 순서와 정보는 유지한다.
- **2× 배속**은 모든 `ms`를 절반으로 줄인다. 판정과 단계 순서는 바뀌지 않는다.

### 6.5 배정

27종 전체 배정은 부록 B.

---

## 7. 스킬 이펙트

### 7.1 3단 해석 사슬

```
1. vfx_family   — 스킬 전용 검수 완료 family. manifest에 있으면 이것을 쓴다
2. kel_fallback — 결 6종의 공용 family. 아직 전용 아트가 없는 스킬
3. echo_wave    — 최종 fallback. 판정은 유지하고 연출만 공용으로 떨어진다
```

- **서버는 세 값을 모두 내려보낸다**(`vfx_family`, `kel`, `effect_key`).
- **앱은 위에서부터 manifest 조회에 성공한 첫 값을 쓴다.**
- 새 family가 검수를 통과해 manifest에 들어가면 **코드 수정 없이** 자동
  승격된다. 이것이 62종 family를 점진 제작할 수 있는 유일한 구조다.

### 7.2 결 fallback 6종

현재의 원소 20 → 프로토타입 7 매핑(`ELEMENT_RUNTIME_EFFECTS`)을 폐기하고
결 6종 공용 family로 대체한다.

| 결 | fallback family | 현재 재사용 가능한 프로토타입 |
|---|---|---|
| 햇살결 | `kel.sunny` | `care-vines` 계열 |
| 빗물결 | `kel.rainy` | `mist-dash` |
| 불씨결 | `kel.ember` | `ember-arc` |
| 달빛결 | `kel.moonlit` | `insight-arc` |
| 별빛결 | `kel.sparkling` | `prism-burst` |
| 모아결 | `kel.mosaic` | `echo-wave` |

같은 결의 스킬은 전용 아트가 나오기 전까지 같은 이펙트를 공유한다. 지금처럼
**서로 다른 결이 같은 이펙트를 쓰는 일은 없어진다.** 사용자가 화면만 보고
상성을 오독하지 않는다.

### 7.3 manifest 단일 원본

`app/assets/adventure/effects/manifest.json` 스키마를 확장한다. Dart 상수
`_expeditionCombatEffectFrameDurationsMs`는 **삭제**하고 manifest에서 읽는다.

```json
{
  "version": 2,
  "effects": [
    {
      "family": "baby-pot.care-vines",
      "kel": "sunny",
      "directory": "care-vines-v2",
      "frame_count": 10,
      "frame_size": [576, 288],
      "frame_durations_ms": [90, 70, 70, 65, 65, 70, 75, 105, 80, 110],
      "contact_frame": 5,
      "pivot": [0.12, 0.62],
      "anchor": "origin",
      "production_ready": false,
      "source_hash": "…",
      "runtime_hash": "…"
    }
  ]
}
```

| 필드 | 왜 필요한가 |
|---|---|
| `frame_durations_ms` | 현재 Dart에만 있는 값. 이중 원본 제거 |
| `contact_frame` | **접촉 시점이 데이터가 된다.** 현재는 `enemyContactProgress`의 `.72/.62` 매직 넘버 |
| `pivot` `anchor` | 발사점·접촉점 고정. 100점 계약 7장 2항 |
| `production_ready` | `A` 승격 여부. `false`면 스토어 영상·완료율에 넣지 않는다 |
| `*_hash` | `COMBAT-ASSET-01` 검수 |

`contact_frame`이 데이터가 되면 SFX·햅틱·피해 숫자가 family마다 실제 아트의
충돌 프레임에 맞는다. 지금은 모든 family가 같은 시점을 쓴다.

### 7.4 적 이펙트

적 의도도 카탈로그에서 연출을 선언한다. 12엉킴 × 2의도 = **24 family**.

```python
{
    "code": "paper_flurry",
    "name": "종잇장 회오리",
    "telegraph": "낱장들이 맨 앞 대원 쪽으로 몰려가요.",
    "target": "front",
    "power": 1,
    "kel": "moonlit",              # 신규 — 적 공격도 결을 가진다
    "vfx_family": "tangled-ledger.paper-flurry",   # 신규
    "motion_profile": "tangle.paper-flurry",       # 신규
    "archetype": "leap",                           # 신규
}
```

- `combat.py`의 `"ledger_claw" if intent.code in {...} else "enemy_wave"`
  하드코딩을 제거하고 의도가 선언한 값을 그대로 이벤트에 싣는다.
- `expedition_action_cue.dart`의 `attackName == '장부 발톱'` **한국어 문자열
  비교를 제거한다.** 서버가 보낸 `vfx_family`/`effect_key`만 읽는다.
- 적 공격의 `kel`은 연출·서사용이다. **대원 HP 피해에는 상성을 적용하지
  않는다**(기존 계약: 상성은 장벽 피해에만 적용).

### 7.5 제작 범위

| 구분 | 개수 | 비고 |
|---|---:|---|
| 고유 I·II | 20 | 품종 10 × 2 |
| 선택 I(감정) | 6 | 결 6종 |
| 기본 공격 | 6 | 결 6종 |
| 기록서 | 6+ | 스킬북 확장분 |
| 적 의도 | 24 | 엉킴 12 × 2 |
| 공용 | 6 | 결 fallback |
| **합계** | **68+** | 100점 계약 10장의 "62 공격 family"와 정합 |

제작 순서는 12장. 한 family가 `A` 승격에 필요한 조건은 100점 계약 7장을 그대로
따른다.

---

## 8. 데이터 모델과 API

### 8.1 `combat-kit-v6`

`version: 5` → `6`. 추가·변경 필드만 적는다.

```json
{
  "kel_map_version": 1,
  "slot": "unique_1",
  "code": "venom_seam",
  "element": "poison",
  "element_label": "독",
  "kel": "rainy",                        // 신규 — 판정 기준
  "kel_label": "빗물결",                  // 신규
  "kels": ["rainy"],                     // 신규 — tier 3에서 2개
  "kel_labels": ["빗물결"],               // 신규 — kels와 같은 순서·길이
  "matchup": "weak",                     // 신규 — 현재 적 기준 미리 계산
  "matchup_bp": 15000,                   // 신규
  "power": 38,                           // 상성·효과까지 반영된 예상 최종값
  "power_neutral": 25,                   // 신규 — 중립 기준값
  "cooldown_turns": 1,
  "cooldown_remaining": 0,
  "ready_round": 0,                      // 신규 (기존 cooldown_until_round 대체)
  "vfx_family": "ninja-pot.venom-seam",
  "kel_fallback_family": "kel.rainy",    // 신규
  "effect_key": "venom_seam",
  "motion": { "...": "6.3 참조" }         // 신규
}
```

- `power`는 **현재 적 기준 예상 최종 피해**다. 앱은 이 값을 재계산하지 않는다.
- `power_neutral`은 상세 시트에서 "중립 25 → 약점 38"을 보여 주기 위한 값이다.
- `kel_map_version`은 action마다 반복하지 않고 kit 최상위에 한 번 둔다. 위 예시는
  필드 관계를 함께 보여 주기 위한 축약이다.
- `affinity`/`affinity_label`(4능력치)은 v5 앱을 위한 **읽기 전용 deprecated alias**다.
  v6 판정과 새 UI는 읽지 않으며 `combat-kit-v7`에서 제거한다. 즉시 제거하면 저장 중
  v1 run과 구버전 앱이 깨지므로, 제거 시점을 호환 계약으로 분리한다.

### 8.2 `battle-state-v2`

```json
{
  "version": 2,
  "kel_map_version": 1,
  "enemy": {
    "weak_kel": "ember",       "weak_kel_label": "불씨결",
    "resist_kel": "rainy",     "resist_kel_label": "빗물결"
  },
  "party": [
    { "member_id": 1, "ready_round": {"venom_seam": 3} }
  ]
}
```

- `weakness`/`weakness_cycle`(4능력치 순환)은 **v2에서 제거한다.**
  라운드마다 약점이 도는 v3 이하 동작은 이미 "첫 조우에 공개하고 돌리지 않는다"는
  계약과 모순이다.
- `weak_element`/`resist_element`는 `weak_kel`/`resist_kel`로 대체한다.
- `cooldown_until_round` → `ready_round`.
- `kel_map_version`이 없는 초기 v2 snapshot은 `1`로 읽는다. 그 외 알 수 없는 값은
  최신 버전으로 추정하지 않는다.

### 8.3 이벤트

`party_action` 이벤트에 추가한다.

```json
{
  "kel_map_version": 1,
  "kel": "rainy",
  "matchup": "weak",
  "matchup_bp": 15000,
  "power_neutral": 25,
  "damage": 38,
  "vfx_family": "ninja-pot.venom-seam",
  "motion": { "...": "" }
}
```

`enemy_action` 이벤트에도 `vfx_family`·`motion`을 싣는다(7.4).
`party_action.kel_map_version`은 리플레이·운영 로그가 당시 판정을 재현하기 위한
증거이며, 전투 상태의 버전과 다르면 validator가 실패한다.

---

## 9. 마이그레이션

진행 중 run을 깨지 않는 것이 최우선이다.

| 대상 | 처리 |
|---|---|
| `battle-state` v1 (진행 중 전투) | 시작 snapshot 유지 계약에 따라 **끝까지 v1 판정**으로 재생한다. 정액 `+7/−4`와 `cooldown_until_round`를 그대로 쓴다 |
| `kel_map_version` 없는 초기 v2 전투 | 최초 버전 `1`을 주입해 같은 판정을 재현한다 |
| 알 수 없는 `kel_map_version` | 최신 매핑으로 추정하지 않고 `EXPEDITION_COMBAT_KEL_MAP_UNSUPPORTED`로 중단한다 |
| `combat-kit` v5 응답을 읽는 구버전 앱 | `kel` 필드가 없으면 `element`로 결을 역산해 표시한다. 판정은 서버가 하므로 안전하다 |
| 신규 run | `battle-state-v2`·`combat-kit-v6`와 현재 `kel_map_version`으로 시작한다 |
| `weakness_cycle` | 카탈로그에서 제거하지 않고 **읽지 않는다.** v1 재생 경로만 참조한다 |
| `affinity`(4능력치) | KEL 전투 판정에서는 제거한다. v1·`weak_kel` 없는 초기 수호전 호환 경로와 탐험 능력치에만 남는다 |
| 원소 20종 | 값·이름 그대로 유지. 결 매핑만 추가된다 |
| `motion_profile` 문자열 27종 | 그대로 유지하고 `archetype`·`phases`를 덧붙인다. 폐기하지 않는다 |
| Dart frame duration 상수 | manifest v2 도입과 **같은 커밋에서 삭제**한다. 두 원본이 공존하는 기간을 만들지 않는다 |

전환 완료 후 v1 판정 경로는 **모든 진행 중 run이 종료된 뒤**에 제거한다.
제거 시점은 운영 지표로 판단한다.

---

## 10. 밸런스 검증

### 10.1 시뮬레이션 계약

전투 엔진은 난수를 쓰지 않는다. 같은 상태와 명령을 seed만 바꿔 10,000번
반복하면 같은 결과 10,000개가 생기므로 확률 시뮬레이션처럼 해석하지 않는다.
K4는 다음 identity cell을 **중복 없이 전수 계산**한다.

```
품종 10 × 감정 6 × 등급 5 × 지역별 권장 레벨 경계 2
× 지역 4 × 스테이지 형태 4 = 정책당 9,600전투
정책 3종 합계 = 28,800전투
```

- 파티 fixture: 실소유 대원 1명 + Lv16 기록 안내자 2명. 길잡이는 성장지수와
  평균 레벨에서 제외하지만 실제 HP·스킬·쿨타임은 서버 규칙대로 사용한다.
- 스테이지 형태: `tutorial` 일반 1웨이브, `standard` 일반 2웨이브, `elite` 큰
  엉킴 1웨이브, `mixed` 일반+큰 엉킴 2웨이브.
- 정책: 중립 위력만 보는 `max_damage`, 약점 결을 먼저 고르는
  `weakness_first`, 치명 예고 시 방어·위력 감소를 우선하는 `survival`.
- 실제 `new_guardian_battle → guardian_battle_payload → submit_guardian_action`
  경로만 호출한다. 시뮬레이터 안에 피해식 복제품을 만들지 않는다.
- 기록: 승률, P10/P50/P90, 1라운드 완료, 남은 HP, 사용 가능 시 슬롯 선택률,
  약점 적중·추가 피해, 품종별 승률·종료 라운드 격차.

### 10.2 합격선

튜토리얼 1웨이브와 혼합 2웨이브를 같은 P50으로 묶지 않는다. 아래 값은
`expedition_combat_balance_report.json`의 balance version 1 결과다.

| 게이트 | 정책·합격 기준 | 현재 결과 | 판정 |
|---|---|---:|---|
| 튜토리얼 완주 | 약점 우선, 승률 100%, P90 1~2R | 100%, P90 2R | 통과 |
| 일반 진행 | 약점 우선, 승률 95~100%, P50 2~4R, 1R 완료 0 | 100%, P50 3R, 0건 | 통과 |
| 큰 엉킴 | 약점 우선, 승률 90~100%, P50 2~4R, 1R 완료 0 | 98.58%, P50 2R, 0건 | 통과 |
| 혼합 숙련 | 생존, 승률 70~85%, P50 3~6R | 76.33%, P50 3R | 통과 |
| 약점 피해 | 일반 1.50·굴절 1.30 혼합 실피해 +40~50% | +42.67% | 통과 |
| 약점 선택 | 적중률 +10%p 이상, 빨라진 셀 ≥ 느려진 셀 | +15.77%p, 9.85% ≥ 4.55% | 통과 |
| 슬롯 커버리지 | 사용 가능 시 기본·고유·선택·방어 각각 5% 이상 | 최저 16.60% | 통과 |
| 품종 커버리지 | 약점 우선 승률 격차 5%p 이하 | 4.27%p | 통과 |
| 품종 종료 속도 | 평균 score round 격차 0.30R 이하 | 0.17R | 통과 |

튜토리얼의 1라운드 완료는 학습 구간의 의도된 성공 경험이므로 허용한다. 1라운드
완료 금지는 `standard`, `elite`, `mixed`에만 적용한다. 실패해도 캐릭터 소실,
장비 파괴, 감정 벌점은 없다.

### 10.3 상성 기여도 측정법

정책 차이와 계수 자체를 분리한다. 최대 피해 비교군은 **최종 피해가 아니라
`power_neutral`**만 보고 행동을 고른다. 최종 피해를 보면 약점 배수가 이미 섞여
약점 우선 정책과 같은 행동을 고르는 측정 오류가 생긴다.

```
정책 A: 중립 위력이 가장 큰 슬롯 선택 (상성 정보 미사용)
정책 B: 약점 결 슬롯 우선, 없으면 최대 피해
선택 효과 = B 약점 적중률 - A 약점 적중률
피해 효과 = sum(약점 최종 피해 - 중립 피해) / sum(약점 중립 피해)
```

클리어 라운드는 정수이고 대부분 2~4라운드라 정책별 median이 둘 다 3이 되기 쉽다.
따라서 과거의 “median −0.8R”을 단독 합격선으로 쓰지 않는다. paired score round는
진단값으로 보존하고, 적중률 상승과 실제 추가 피해가 **D-2 재발 방지 게이트**다.
현재 약점 우선은 적중률을 22.62%에서 38.39%로 올렸고 약점 행동의 실피해를
42.67% 높였다.

---

## 11. 자동 검수 ID

100점 계약 8장의 표에 이어붙인다.

| ID | 자동/수동 | 합격 조건 |
|---|---|---|
| `COMBAT-KEL-01` | 서버 단위 | 버전별 원소 20종이 결 6종에 **전수 매핑**되고, 최초·현재 버전이 보존되며 미지 버전은 실패한다 |
| `COMBAT-KEL-02` | 서버 단위 | 12엉킴에서 각 결이 약점 2회·내성 2회이고, 세 대립축의 정·역방향이 **각각 정확히 2회**다 |
| `COMBAT-KEL-03` | 서버 단위 | Lv25 품종 10×성장결 6 전수에서 기본+4스킬 kit가 최소 2개 결을 갖고 `kels`·`kel_labels`가 같은 순서·길이다 |
| `COMBAT-KEL-04` | Flutter 위젯 | KEL v2의 다중 결이 약점·내성을 함께 가져도 서버 `matchup`에 따라 badge 하나만 표시하고 실제 `matchup_bp` 배수를 쓴다 |
| `COMBAT-SCALE-01` | 서버 단위 | 피해식 6단계 순서와 `round_bp` 반올림이 fixture와 일치 |
| `COMBAT-SCALE-02` | 서버 단위 | 약점/중립 비가 전 레벨·등급·품종에서 `1.50 ± 0.05` (4.4 반올림 상한) |
| `COMBAT-CD-01` | 서버 단위 | 전 tier에서 `base_cd >= 1`인 스킬의 `effective_cd >= 1` |
| `COMBAT-CD-02` | 서버 단위 | `ready_round` 계산이 웨이브 전환을 넘어 연속한다 |
| `COMBAT-CD-03` | Flutter 위젯 | 쿨타임 중 슬롯이 위치를 유지하고 남은 라운드 수를 표시한다 |
| `COMBAT-MOTION-02` | 서버 단위 | 27종 `phases` 합이 아키타입 밴드 안에 있다 |
| `COMBAT-MOTION-03` | Flutter 위젯 | 아키타입 6종이 서로 다른 액터 동선을 만든다. 미지 아키타입은 `cast` fallback |
| `COMBAT-MOTION-04` | Flutter 위젯 | 저감 모션에서 단계 순서·피해·상성 정보가 보존된다 |
| `COMBAT-VFX-01` | Flutter 단위 | 해석 사슬이 `vfx_family` → `kel_fallback` → `echo_wave` 순서다 |
| `COMBAT-VFX-02` | 빌더 | frame 길이·`contact_frame`의 원본이 manifest뿐이다. Dart 상수 0건 |
| `COMBAT-VFX-03` | 서버/Flutter | 서로 다른 결이 같은 fallback family를 쓰지 않는다 |
| `COMBAT-VFX-04` | 서버 단위 | 적 의도 24종이 `vfx_family`·`motion_profile`을 선언한다. 한국어 이름 분기 0건 |
| `BALANCE-02` | 시뮬레이션 | 9,600 identity cell × 정책 3종과 10.2 스테이지 게이트 전 항목 |
| `BALANCE-03` | 시뮬레이션 | 약점 적중률 +10%p, 실피해 +40~50%, 빨라진 paired cell이 느려진 cell 이상 |

---

## 12. 구현 순서

각 단계는 **앞 단계의 테스트가 녹색일 때만** 다음으로 간다.

| 단계 | 상태 | 범위 | 산출물 | 검수 |
|---|---|---|---|---|
| **K1** | C 재검증 완료 | 버전 고정 매핑, 대립축, 이중 결 kit, 서버 권위 상성 표시 | 서버·앱·설계서 | `COMBAT-KEL-01~04` |
| **K2** | C 완료 | 6단계 정수 배수식 | `battle-state-v2`, v1 재생 경로 | `COMBAT-SCALE-02` |
| **K3** | C 완료 | 하한 1, `ready_round`, `tier_bp` | 서버 + 앱 표시 | CD 단위·위젯 |
| **K4** | C 완료 | HP·집중력 이정표, 성장지수 장벽, 지역/의도 밴드, 전수 시뮬레이터 | 카탈로그 + JSON 리포트 | `BALANCE-02~03` 통과 |
| **K5** | C 완료 | 6아키타입·6구간 phase, 서버 시간·방향·이동·충격 snapshot | 앱 연출 해석기 | 6동선·미지 `cast` fallback 통과, pose A 잔여 |
| **K6** | C 완료 / A 진행 | 3단 resolver, manifest v2→Dart 생성, 수동 상수 제거 | 아트 승격 파이프라인 | 번들·alpha·contact 통과 |
| **K7** | C 완료 | 적 의도 24종 code key·family·결·motion 선언 | 카탈로그 + 앱 | `COMBAT-VFX-04` 통과 |
| **K8** | 진행 | family 68종 점진 제작 | `production_ready` 승격 | 5 family 후보, 전체 잔여 |

K1~K4는 판정, K5~K7은 연출 배선, K8은 제작이다. **K5~K7은 아트가 하나도
없어도 완료할 수 있다.** 배선이 먼저 끝나야 K8이 코드 수정 없이 굴러간다.

### K1 완료 증거 — 2026-08-11

- 신규 전투 상태·kit·행동 이벤트에 동일한 `kel_map_version`이 남는다.
- 버전 없는 초기 v2는 1로 복원하고, 미지 버전은 명시적 규칙 오류로 중단한다.
- 12엉킴의 6개 방향 대립축이 각각 2회이며, 60개 품종×성장결 kit를 전수 검증한다.
- Flutter는 T3 다중 결을 재판정하지 않고 `matchup` 하나와 실제 `matchup_bp`를 표시한다.
- 서버 K1 회귀와 Flutter 전투 모델·위젯 29건이 통과했다. 전체 회귀도 서버
  423건·Flutter 290건, Ruff·Flutter 정적 분석까지 모두 통과했다.
- K1에는 새 래스터 원본이 필요하지 않아 Imagegen 산출물을 완료 증거로 만들지 않았다.
  실제 스프라이트 제작은 접촉 프레임과 블렌딩 규칙을 검수하는 K5~K8에서 진행한다.

### K4 완료 증거 — 2026-08-11

- `combat_balance.py`가 HP 3→6, 평균 Lv18 집중력 4, 네 지역 장벽·의도·권장 레벨
  밴드를 단일 원본으로 관리한다. 커스텀 시작 집중력과 진행 중 snapshot은 유지한다.
- 엉킴 12종은 일반 `34/38`, `44/50`, `56/64`, `70/80`, 큰 엉킴
  `76/96/120/148`이며 모든 의도 위력은 지역·난이도 밴드 validator를 통과한다.
- 실제 전투 엔진으로 9,600 identity cell을 정책 3종, 총 28,800전투 재생했다.
  튜토리얼·일반·큰 엉킴·혼합 게이트, 상성 피해·선택, 슬롯·품종 격차가 모두
  `balance_gates.all_passed:true`다.
- 프리즘의 1.30배 확실성과 일반 약점 1.50배 상한을 실제 기대 피해로 맞추기 위해
  magical 고유 I/II raw power를 `20/18`, 지역 약점이 적은 zombie 고유 I/II를
  `20/18`로 보정했다. 품종 승률 격차는 7.29%p에서 4.27%p로 줄었다.

### K5~K7 완료 및 K8 두 번째 적 의도 구현 증거 — 2026-08-11

- 서버 `combat_motion.py`가 6아키타입의 일반기·결정기 시간 밴드를 import 시점에
  검증하고, action·event가 같은 motion payload를 보존한다.
- `TANGLE_INTENT_PRESENTATION` 24개와 실제 의도 code 집합이 정확히 같고 모든
  `vfx_family`가 서로 다르다.
- 앱 `ExpeditionCombatTimeline`은 family의 실제 contact frame에 피해 숫자·SFX·
  햅틱·피격 흔들림을 맞춘다. 액터 동선에는 한국어 이름이나 profile substring
  분기가 없다.
- `generate_expedition_effect_catalog.py`가 manifest v2의 family 중복, frame 시간,
  contact 범위, pivot, 런타임 파일 수를 검증한 뒤 Dart 상수를 생성한다.
- `paper-flurry-v1`은 포즈별 원본 7장과 알파 7장, 런타임 7장, source/runtime
  aggregate SHA-256, light/dark QA, animated WebP를 보존한다.
- `ink-mist-v1`도 같은 증거 묶음을 가지며 7프레임 합계 760ms와 서버 `channel`
  모션이 일치한다. 접촉 프레임은 4이고 결 블러만 `srcIn`으로 혼합한다.
- `COMBAT-MOTION-02/03`, `COMBAT-VFX-01/02/04` 회귀 테스트를 추가했다.
- 전체 회귀는 서버 447건·Flutter 290건, Flutter 정적 분석, 전투 에셋 5종
  report-only 검증을 통과했다.

### 중단 기준

- K2에서 v1 재생 경로 테스트가 깨지면 진행 중 run이 손상되므로 즉시 중단한다.
- K4 시뮬레이션이 합격선을 못 넘으면 전투 수치의 출시 승격을 중단한다. 판정을
  바꾸지 않는 K5~K7 연출 배선은 병렬 진행할 수 있지만 K8 출시 완료로 세지 않는다.
- K6에서 Dart 상수와 manifest가 한 커밋 이상 공존하면 되돌린다.

---

## 13. 금지하는 지름길

1. **원소를 6종으로 줄여 상성을 맞추지 않는다.** 캐릭터 정체성이 사라진다.
   결 층을 얹어서 푼다.
2. **정액 보너스를 남겨 두고 배수만 추가하지 않는다.** 두 체계가 공존하면
   D-2가 절반만 풀린 채 영구화된다.
3. **tier 보상으로 쿨타임을 0으로 만들지 않는다.** 어떤 성장 단계도 슬롯의
   리듬을 삭제하지 못한다.
4. **파티가 강해진 만큼 적을 강하게 만들지 않는다.** 장벽 상한 1.30배를 넘기지
   않고, 적 위력은 성장지수를 읽지 않는다.
5. **모션·이펙트를 코드 분기로 늘리지 않는다.** 스킬이 늘 때 코드가 늘면
   68종에서 무너진다. 데이터로만 늘린다.
6. **연출 이름을 한국어 문자열로 비교하지 않는다.** 코드 키만 쓴다.
7. **frame 길이·접촉 시점을 앱 상수로 다시 적지 않는다.** manifest가 유일한
   원본이다.
8. **아트가 없다고 판정을 바꾸지 않는다.** fallback은 연출만 낮추고 수치는
   그대로다.
9. **`production_ready:false` family를 완료로 세지 않는다.**
10. **시뮬레이션 없이 밸런스 수치를 확정하지 않는다.** 수치 변경 시 28,800전투
    전수 리포트를 다시 만들고 모든 게이트를 통과시킨다.

---

## 부록 A. 원소 → 결 전체 매핑

| 원소 | 라벨 | 결 | 사용처 |
|---|---|---|---|
| `light` | 빛 | 햇살결 | pretty 고유 II, sunny 주원소·선택 I |
| `nature` | 생명 | 햇살결 | baby 고유 I·II |
| `water` | 물 | 빗물결 | rainy 주원소·선택 I |
| `ice` | 얼음 | 빗물결 | aloof 고유 I, rainy 부원소 |
| `poison` | 독 | 빗물결 | ninja 고유 I |
| `fire` | 불 | 불씨결 | tsundere 고유 I, ember 주원소·선택 I |
| `decay` | 쇠락 | 불씨결 | zombie 고유 II |
| `wind` | 바람 | 달빛결 | moonlit 주원소·선택 I |
| `moon` | 달 | 달빛결 | gumiho 고유 II, moonlit 부원소 |
| `shadow` | 그림자 | 달빛결 | ninja 고유 II |
| `lightning` | 번개 | 별빛결 | sparkling 주원소·선택 I |
| `sound` | 음파 | 별빛결 | handsome 고유 II, sparkling 부원소 |
| `arcane` | 마력 | 별빛결 | magical 고유 I·II |
| `heart` | 하트 | 햇살결 | pretty 고유 I, gumiho 고유 I, sunny 부원소 |
| `steel` | 강철 | 모아결 | handsome 고유 I, aloof 고유 II, mosaic 주원소·선택 I |
| `force` | 역장 | 모아결 | mosaic 부원소 |
| `gravity` | 중력 | 모아결 | zombie 고유 I |
| `ink` | 먹빛 | 모아결 | student 고유 I, 기록서 |
| `seal` | 봉인 | 모아결 | student 고유 II, 길잡이 고유 II |
| `strike` | 격투 | 불씨결 | tsundere 고유 II, ember 부원소 |

## 부록 B. 27 스킬 모션·이펙트 배정

### 고유 I

| 품종 | 스킬 | 결 | 아키타입 | `vfx_family` |
|---|---|---|---|---|
| baby-pot | 새싹 응원 | 햇살 | `channel` | `baby-pot.care-vines` |
| handsome-pot | 지휘검 일섬 | 모아 | `draw` | `handsome-pot.command-blade` |
| pretty-pot | 하트 스포트라이트 | 햇살 | `cast` | `pretty-pot.heart-spotlight` |
| tsundere-pot | 홍련 카운터 | 불씨 | `dash` | `tsundere-pot.blazing-counter` |
| zombie-pot | 묘지 중력장 | 모아 | `brace` | `zombie-pot.grave-gravity` |
| gumiho-pot | 심월 매혹 | 햇살 | `leap` | `gumiho-pot.heart-moon-charm` |
| ninja-pot | 맹독 틈베기 | 빗물 | `draw` | `ninja-pot.venom-seam` |
| magical-pot | 프리즘 메테오 | 별빛→굴절 | `cast` | `magical-pot.prism-meteor` |
| aloof-pot | 절대영도 간파 | 빗물 | `brace` | `aloof-pot.absolute-zero` |
| student-pot | 먹빛 공식탄 | 모아 | `cast` | `student-pot.ink-formula` |

### 고유 II

| 품종 | 스킬 | 결 | 아키타입 | `vfx_family` |
|---|---|---|---|---|
| baby-pot | 뿌리 포옹 | 햇살 | `channel` | `baby-pot.root-embrace` |
| handsome-pot | 지휘의 크레센도 | 별빛 | `channel` | `handsome-pot.command-crescendo` |
| pretty-pot | 리본 앙코르 | 햇살 | `leap` | `pretty-pot.ribbon-encore` |
| tsundere-pot | 철벽 어퍼컷 | 불씨 | `dash` | `tsundere-pot.iron-uppercut` |
| zombie-pot | 불사의 사슬 | 불씨 | `dash` | `zombie-pot.undying-chain` |
| gumiho-pot | 구미 월식 | 달빛 | `leap` | `gumiho-pot.nine-tail-eclipse` |
| ninja-pot | 무영 처형 | 달빛 | `dash` | `ninja-pot.shadow-execution` |
| magical-pot | 시공 접힌 혜성 | 별빛→굴절 | `cast` | `magical-pot.timefold-comet` |
| aloof-pot | 강철 판결 | 모아 | `cast` | `aloof-pot.steel-verdict` |
| student-pot | 봉인식 재작성 | 모아 | `brace` | `student-pot.seal-rewrite` |

### 선택 I(감정) · 선택 II(기록서) · 공통

| 슬롯 | 스킬 | 결 | 아키타입 | `vfx_family` |
|---|---|---|---|---|
| 선택 I | 찬란한 하트 | 햇살 | `cast` | `emotion.sunny-radiant-heart` |
| 선택 I | 얼어붙은 파도 | 빗물 | `brace` | `emotion.rainy-frozen-tide` |
| 선택 I | 분노 파쇄권 | 불씨 | `dash` | `emotion.ember-rage-breaker` |
| 선택 I | 고독의 돌풍 | 달빛 | `leap` | `emotion.moonlit-lonesome-tempest` |
| 선택 I | 경이의 전격 | 별빛 | `cast` | `emotion.sparkling-shock-wonder` |
| 선택 I | 강철 평형장 | 모아 | `brace` | `emotion.mosaic-steel-equilibrium` |
| 선택 II | 현장 기록: 되울림 | 모아 | `cast` | `skillbook.field-note-echo` |
| 기본 공격 | 결별 공명 공격 6종 | 결 그대로 | `cast` (620~700ms) | `emotion.<form>-<원소>` |
| 마음 지키기 | — | — | `brace` (이동 0) | `common.safe-guard` |
