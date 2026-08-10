# 모험 RPG 100점 실행 계약

최종 갱신: 2026-08-10
문서 상태: **D100 — 구현 가능한 기준 문서**
제품 상태: 아래 `9. 구현 증거 대장`에서 별도 관리

이 문서는 모험·전투·성장·에셋 문서를 실제 코드와 검수 증거로 연결하는 실행
원본이다. 화면의 방향은 `expedition_stage_redesign.md`, 성장과 밸런스는
`combat_identity_progression_design.md`, 획득·경제는
`character_skill_growth_design.md`, 제작 규격은
`design-system/EXPEDITION_ASSET_PRODUCTION.md`가 정한다. 서로 충돌하면 사용자가
직접 체감하는 전투 계약은 스테이지 개편 문서가 우선하고, **완료 여부와 증거는 이
문서만** 따른다.

> `문서 100점`은 요구사항이 빠짐없이 결정되고 구현·검수 방법까지 추적된다는
> 뜻이다. 게임이 완성됐다는 뜻이 아니다. 제품 점수는 production 에셋, 실제 기기,
> 성능, 접근성, 밸런스 증거가 있어야만 오른다.

## 1. 최초 평가와 보완 결과

### 1.1 평가 척도

| 평가축 | 배점 | 최초 | D100 | 최초 감점 이유 | 보완 위치 |
| --- | ---: | ---: | ---: | --- | --- |
| 제품 비전·RPG 몰입 | 15 | 15 | 15 | — | 스테이지 개편 0·3·5장 |
| 전투 조작·정보 위계 | 15 | 15 | 15 | — | 스테이지 개편 4·5장 |
| 캐릭터 성장·밸런스 | 15 | 14 | 15 | 전투 슬롯과 서버 action 값 연결 없음 | 이 문서 4·5장 |
| 시각·오디오 제작 체계 | 15 | 14 | 15 | production/prototype 판정은 있으나 세로 슬라이스 증거 연결이 약함 | 이 문서 7·9장 |
| 발견·도서관·보상 공개 | 10 | 10 | 10 | — | 스테이지 개편 3.5장 |
| 데이터·API·호환 계약 | 10 | 5 | 10 | 6슬롯 스키마, 레거시 alias, 결손 슬롯 처리 없음 | 이 문서 4장 |
| 접근성·성능·실패 복구 | 10 | 7 | 10 | long-press 대체 action과 저감 모션은 있으나 테스트 ID·실패 상태가 불명확 | 이 문서 6·8장 |
| 구현 추적·완료 증거 | 10 | 4 | 10 | 역사적 완료와 현행 출시 완료가 섞이고 산출물 경로가 분산됨 | 이 문서 2·9장 |
| **합계** | **100** | **84** | **100** |  |  |

### 1.2 D100 합격 조건

다음 조건을 모두 만족했으므로 문서 상태를 D100으로 판정한다.

1. 모든 `MUST` 요구가 코드·데이터·에셋·검수 중 하나 이상의 산출물에 연결된다.
2. `설계 완료`, `코드 완료`, `production 에셋 완료`, `출시 완료`를 섞지 않는다.
3. 서버와 앱이 공유하는 여섯 행동 코드와 구버전 호환 규칙이 결정돼 있다.
4. 짧은 탭·350ms hold·접근성 대체 action·AUTO가 같은 판정 경로를 쓴다.
5. 코드 도형·공용 파동·일괄 시트를 정식 공격 에셋으로 세지 않는다.
6. 실제 기기·성능·접근성 증거가 없으면 제품 완료로 표시하지 않는다.

## 2. 상태 용어 — 한 단어 `완료` 금지

| 상태 | 의미 | 허용 증거 |
| --- | --- | --- |
| `D` 설계 | 사용자 흐름·수치·예외가 결정됨 | 승인 문서·스키마 |
| `C` 코드 | 서버 판정과 앱 UI가 연결되고 자동 테스트 통과 | 소스 경로·테스트명 |
| `A` 아트 | 정식 에셋 gate를 통과 | manifest·contact sheet·alpha QA |
| `Q` 품질 | 실제 기기·접근성·성능 기준 통과 | 캡처·trace·측정 보고서 |
| `R` 출시 | D+C+A+Q와 배포 pack 검증 통과 | release manifest·빌드 |

`C 완료/A 미완료`는 정상적인 중간 상태다. 이때 앱은 기능적으로 동작하더라도
`prototype`이며 스토어 영상·출시 노트·완료율에 정식 전투로 넣지 않는다.

## 3. 100점 사용자 경험 불변식

1. 모험의 기본 화면은 설명 목록이 아니라 **한 카메라의 전장**이다.
2. 전투 중 상시 텍스트는 진행, HP/장벽, 집중력, 적 의도·대상·위력, 잠금 사유,
   600ms 안쪽 시전명뿐이다. 스킬 이름·효과 전문은 상시 노출하지 않는다.
3. 전장 가시 영역은 390×844 기준 화면 높이의 72% 이상이다. HUD와 명령 벨트는
   배경을 새 카드로 밀지 않고 가장자리에 겹친다.
4. 행동 대원을 고른 뒤 여섯 아이콘 중 하나를 탭하면 즉시 서버 판정과 연출이
   시작된다. 대상 자동 행동은 최대 두 탭이다.
5. 플레이어와 적 모두 `anticipation → release → travel → contact → reaction →
   recovery`를 가진다. 공격 본체가 실제로 이동하고 접촉 프레임에서 수치·SFX·햅틱이
   일치한다.
6. `약점`과 `내성`은 첫 조우부터 공정한 선택 정보로 공개한다. 생태·전체 패턴·히든
   보상은 관찰·획득 뒤 도서관에서 열린다.
7. 감정은 보상/벌점이 아니다. 여섯 성장결은 동등한 전술 언어이고 어느 결도 범용
   상위호환이 될 수 없다.
8. AUTO·2×·짧은 연출은 판정을 바꾸지 않는다. 저감 모션은 정보를 줄이지 않는다.

## 4. 전투 데이터와 API 계약 `combat-kit-v6` / `battle-state-v2`

### 4.1 고정 슬롯

| 순서 | UI 슬롯 | API `action` | 출처 | 기본 판정 |
| ---: | --- | --- | --- | --- |
| 1 | 기본 공격 | `attack` | 캐릭터 성장결 | 집중력 +1 |
| 2 | 고유 I | `unique_1` | 품종 고유 | 집중력 비용·품종 효과 |
| 3 | 고유 II | `unique_2` | 품종 고유 | 고유 I과 다른 역할 |
| 4 | 선택 I | `selected_1` | 장착 감정/기록서 | 교체 가능 |
| 5 | 선택 II | `selected_2` | 장착 감정/기록서 | 교체 가능 |
| 6 | 마음 지키기 | `guard` | 공통 | 방어 +2, 집중력 +1 |

서버는 위 여섯 값을 권위 있게 판정한다. 구버전 `skill`은 한시적으로
`unique_1`과 동일하게 해석하고 응답에는 새 슬롯을 모두 돌려준다. 앱은 새 서버에서
`skill`을 전송하지 않는다.

### 4.2 응답 스키마

```json
{
  "kit": {
    "version": 6,
    "level": 25,
    "rarity": 4,
    "signature_tier": 3,
    "primary_element": "wind",
    "affinity": "care",
    "affinity_label": "돌봄",
    "basic": {"code": "attack", "...": "..."},
    "unique_skills": [
      {"slot": "unique_1", "code": "sprout_cheer", "element": "nature", "kel": "sunny", "...": "..."},
      {"slot": "unique_2", "code": "root_embrace", "...": "..."}
    ],
    "selected_skills": [
      {"slot": "selected_1", "source": "emotion", "...": "..."},
      {"slot": "selected_2", "source": "skillbook", "...": "..."}
    ],
    "guard": {"code": "guard", "...": "..."}
  }
}
```

각 행동은 `slot, code, name, description, raw_power, power_scale_bp,
tier_power_bp, power_neutral, matchup, matchup_bp, effect_power_bp, power,
focus_cost, focus_delta, cooldown_turns, cooldown_remaining, ready_round, tier,
tier_label, element, elements, kel, kels, damage_type, motion_profile, vfx_family,
effect_key, effect, guard, source`를 가질 수 있다. 수치가 없는
필드는 `0` 또는 `null`로 직렬화한다. 피해·집중력·부가 효과는 앱이 다시 계산하지
않고 서버 결과를 최종값으로 사용한다. 앱의 예상 피해는 선택 보조 표시일 뿐이다.

### 4.3 결손·구버전·오프라인 처리

- 새 슬롯이 빠진 구버전 응답: 기본·기존 `skill`·지키기는 동작시키고 나머지 슬롯은
  잠금 glyph와 `업데이트 필요`만 표시한다. 빈 버튼을 숨겨 위치를 바꾸지 않는다.
- 알 수 없는 `effect_key`: `echo_wave` 래스터 fallback을 쓰고 판정은 유지한다.
- 아이콘 누락: 같은 공격 family의 검수된 fallback 래스터를 쓴다. 코드 유기체나
  이모지를 대신 그리지 않는다.
- 네트워크 실패: 제출한 아이콘을 원상 복귀하고 같은 행동을 재시도할 수 있게 한다.
  클라이언트가 낙관적으로 HP·장벽을 확정하지 않는다.
- 중복 탭: `interactionLocked`와 idempotency key로 한 행동만 제출한다.

### 4.4 장착과 획득의 단계적 계약

`selected_1/2`는 저장된 `combat_loadout`을 우선하고, 아직 장착 기능을 열지 않은
계정은 `성장결 기본 스킬 + 현장 기록서`를 안전 기본값으로 받는다. 이후 상점 구매,
해금 조건, 던전 획득은 동일한 스킬북 소유권 테이블에 기록한다.

- 소유권과 장착은 분리한다. 보유해도 자동 장착하지 않는다.
- 전투 중에는 장착을 바꾸지 않는다. 출발 전·캐릭터/스킬북 화면에서만 교체한다.
- 유료 캐릭터는 초기 사용감과 성장 상한을 높일 수 있지만 동일 성장 구간에서 무료
  캐릭터의 역할을 제거하거나 승률을 독점하면 안 된다.
- 밸런스 수치는 콘텐츠 버전으로 고정하고 진행 중 run은 시작 snapshot을 유지한다.

## 5. 밸런스와 성장 합격선

| 항목 | 합격 기준 |
| --- | --- |
| 캐릭터 정체성 | 고유 I은 대표 공격/지원, 고유 II는 다른 전술 역할 |
| 선택 폭 | 선택 I·II 중 하나 이상은 현재 약점 대응 또는 생존 선택을 제공 |
| 비용 | 집중력 0~5에서 최소 한 행동은 항상 합법 |
| 상성 | 약점 ×1.50, 내성 ×0.60, 최종 피해 최소 1; 색 외에 glyph와 화살표 병기 (`expedition_combat_core_design.md` 4장) |
| 가격 | 동일 레벨·성장 단계의 평균 승률 격차 5%p 이내, 역할 독점 0 |
| 진화 | 성장 단계는 외형·기본 수치·스킬 tier를 함께 올리되 이전 콘텐츠를 무효화하지 않음 |
| 실패 | 패배 시 캐릭터 소실·장비 파괴·감정 벌점 없음 |

자동 시뮬레이션은 캐릭터·성장결·장착 조합별 10,000회 이상 실행하고 P10/P50/P90
클리어 라운드, 승률, 사용 스킬 분포를 남긴다. 평균만으로 합격시키지 않는다.

## 6. UI·입력·접근성 계약

### 6.1 여섯 아이콘 벨트

- 360px 이상: 한 줄 6개. 320~359px 또는 150% 이상 글자: 3×2.
- 각 터치 영역 48×48dp 이상, 인접 영역 간 8dp를 목표로 하되 320px에서는 겹치지
  않는 것을 우선한다.
- 기본 화면에는 아이콘, 비용 링, 약점/내성 glyph, 잠금 사유 한 단어만 둔다.
- 짧은 탭은 실행, 350ms hold는 높이 40% 이하 상세 시트다. hold 뒤 손을 떼어도
  실행되지 않는다.
- 스크린리더·키보드에는 `실행`과 `상세 보기`를 별도 semantic action으로 제공한다.
- 누르는 동안 150ms 안에 `scale 0.96`; 잠금 상태는 움직이지 않는다.

### 6.2 상세 시트

상세 시트만 이름, 설명, 현재 비용, 예상 피해, 약점/내성 보정, source, tier를 보여
준다. 열려 있는 동안 전투 제출과 AUTO 타이머를 멈추고, 닫은 뒤 원래 선택 대원과
포커스를 복원한다.

### 6.3 저감 모션

저감 모션은 `release/contact/reaction` 대표 프레임을 순서대로 240~700ms 안에
보여 준다. 화면 흔들림·카메라 이동·ambient drift는 제거하지만 적 의도, 피해,
방어, 약점, 결과 callout은 유지한다.

## 7. 아트·스프라이트·오디오 gate

정식 공격 family 하나는 다음을 모두 가진다.

1. `anticipation 2F+`, `release 2F+`, `travel 3F+`, `contact 1F+`,
   `reaction 2F+`, `recovery 2F+` 또는 manifest가 정의한 동등 타임라인.
2. 투명 배경, 고정 canvas·pivot·anchor·발사점·접촉점.
3. frame별 독립 ImageGen key pose 또는 승인 원화를 기반으로 한 in-between.
4. contact frame에 SFX·햅틱·피해 숫자·reaction이 ±1 frame 안에서 일치.
5. 1×·2×·짧은 연출·저감 모션에서 판정 프레임 누락 0.
6. 390×844 실제 합성 영상과 48px 아이콘 접촉 시트.

기존 8프레임 공용 effect와 `enemy_wave`, 절차적 엉킴 몸체는 **C는 가능하지만 A는
prototype**이다. `care_vines-v2`와 `ledger_claw-v2`는 각각 단일 pose 원본 10장,
투명 runtime 10장, light/dark QA와 hash manifest를 가진 **production candidate**다.
실제 기기 contact 동기화·actor pose·profile 증거 전에는 production으로 승격하지 않는다.

P1 대표 세로 슬라이스는 뽀또의 고유 I 덩굴, 고유 II, 선택 I·II 아이콘, 돌비늘
장부지기의 장부 발톱, 적 hit/release, 플레이어·적 signature SFX까지 한 세트로
검수한다. 이후 같은
pipeline을 나머지 family에 복제한다.

## 8. 자동 검수 ID

| ID | 자동/수동 | 합격 조건 |
| --- | --- | --- |
| `COMBAT-SLOT-01` | 서버 단위 | 여섯 action과 legacy `skill`이 같은 판정기로 들어감 |
| `COMBAT-SLOT-02` | Flutter 위젯 | 정확히 6슬롯, 순서 고정, 기본 화면 스킬 설명 0 |
| `COMBAT-HOLD-01` | Flutter 위젯 | 350ms hold 상세, 실행 0회, 닫은 뒤 포커스 복원 |
| `COMBAT-A11Y-01` | Flutter semantics | 48dp, 실행/상세 label, 색 외 약점 표시 |
| `COMBAT-VIEW-01` | golden/수동 | 390×844에서 전장 72% 이상, 동일 카메라에 양측·공격 본체 |
| `COMBAT-MOTION-01` | 위젯/수동 | release→travel→contact→reaction 순서와 저감 모션 정보 보존 |
| `COMBAT-ASSET-01` | 빌더/Flutter | family별 원본·alpha·runtime hash, 4px padding, fringe 0, 선언 frame 전부 번들 로드 |
| `COMBAT-CONTACT-01` | 서버/Flutter | 적 `effect_key`와 전용 family 연결, manifest duration 기준 contact frame에서 SFX·햅틱 판정 |
| `COMBAT-AUDIO-01` | manifest/수동 | contact cue ±1 frame, 무음에서도 정보 손실 0 |
| `COMBAT-PERF-01` | profile | 기준 기기 p95 16.7ms 이하, 저사양 30fps, OOM 0 |
| `DISCOVERY-01` | 위젯/API | 첫 조우 약점·내성 공개, 생태·히든 보상 잠금 |
| `BALANCE-01` | 시뮬레이션 | 가격·성장결별 승률/클리어 라운드 밴드 통과 |

## 9. 구현 증거 대장

증거가 생길 때만 상태를 올린다. 날짜만 적거나 “동작함”이라고 쓰지 않는다.

| 범위 | D | C | A | Q | 증거/잔여 |
| --- | :---: | :---: | :---: | :---: | --- |
| 한 카메라 통합 전장 | ✅ | ✅ | 배경·수호자만 | 부분 | `expedition_battle_scene.dart`; 390×844 불투명 명령 덱 위 가시 전장 72% 이상 자동 검증, 실제 기기 합성 영상·profile 미완료 |
| 여섯 행동 판정 | ✅ | ✅ | 아이콘 8종 후보 | 부분 | `combat-kit-v6`; 서버 여섯 action+legacy alias, 앱 고정 순서·48dp·에셋 연결 검증. 나머지 품종 아이콘·실기 접근성 미완료 |
| 350ms 상세/상시 설명 0 | ✅ | ✅ | 해당 없음 | 부분 | 349ms 미노출→351ms 상세, hold 제출 0회, 평상시 이름·전문 0 자동 검증. 스크린리더 포커스 복원 수동 검수 미완료 |
| 플레이어 공격 family | ✅ | ✅ | 10F+7F 후보 | 부분 | `care_vines-v2` 10F와 비식물 `venom_seam-v1` 7F 독립 pose·alpha/runtime·QA·앱 연결. actor pose·실기 contact/SFX/profile 미완료 |
| 적 공격·피격 | ✅ | 부분 | 10F 후보 | 부분 | 첫 의도 `ledger_claw`를 공용 파동에서 분리해 10F·오른쪽 pivot·앱/서버 key 연결. `record_wave`·`seal_crush`와 실기 hit/release 미완료 |
| 8점 battle trail | ✅ | 부분 | 기준안만 | 미측정 | 기본 화면이 선택 overlay/연속 무대인지 검증 필요 |
| 캐릭터×감정×레벨 정체성 | ✅ | ✅ | 비식물 4아이콘·1공격 후보 | 미측정 | `combat-kit-v6`; 10종×고유 2, 감정 6계열, Lv1~30·희귀도·T3 융합. 전체 family 에셋 미완료 |
| T3 캐릭터×감정 융합 | ✅ | ✅ | 6레이어 미제작 | 미측정 | 10캐릭터×6성장결×고유 2 = `fusion_variant` 120키 전수 고유, 앱 hold에 융합 상태 연결 |
| 감정 6결 약점·내성 | ✅ | ✅ | glyph·prototype | 부분 | 20원소 전수 6결 매핑, 12엉킴 균등 분포, ×1.50/×0.60 서버·앱 표시 검증 |
| 스킬 쿨타임 | ✅ | ✅ | timer glyph | 부분 | `ready_round`, CD 하한 1, T3 결정기 −1, AUTO·상세 UI 연결 |
| 스킬북 소유·장착 | ✅ | 미구현 | 아이콘 미제작 | 미측정 | 안전 기본 loadout만 먼저 연결 |

### 9.1 2026-08-10 구현 스냅샷

- `S0-C`: **C 완료**. 서버 `combat-kit-v6`와 앱 6아이콘 벨트가 같은 여섯 action을
  사용하고, 구버전 `skill`은 `unique_1`로 해석한다.
- `S1-I`: **C 완료 / A·Q 진행 전**. 캐릭터 10종의 고유 20기와 서로 다른
  `motion_profile`·`vfx_family`, 감정 6계열, Lv1~30, 희귀도 계수, 서버 쿨타임,
  고정 약점·내성이 연결됐다. Lv25 T3는 고유기를 교체하지 않고 120개
  `{species}.{form}.{slot}.t3` 융합 variant를 보낸다. 단일 원본은
  `combat_identity_progression_design.md`다.
- `S0-V`: **overlay C 완료 / 단계 진행 중**. 전투 AppBar를 제거하고 전장·상단 HUD·하단 명령
  덱을 한 Stack에 겹쳤다. 390×844에서 실제 위젯 좌표로 72% 가시 전장을 보장하고,
  320×720·200% 글자에서는 3×2 덱과 세로 스크롤을 쓴다.
- `P1-A`: **production candidate 3 family 완료 / A 승격 대기**. 뽀또 4종과
  구미호·닌자 4종 아이콘을 연결했고, `care_vines-v2`·`ledger_claw-v2` 10F에 더해
  비식물 `venom_seam-v1` ImageGen 독립 pose 7장→투명 576×288 WebP 7장을 연결했다.
  세 family 모두 light/dark alpha·padding·coverage gate를 통과했지만
  실제 기기 합성·contact 동기화·profile 전에는 `production_ready:false`를 유지한다.

검증 증거:

- Flutter 전체 `289 passed`, `dart analyze` 문제 0. 전용 테스트가 두 10F family의
  번들·alpha·576×288 canvas와 장부 발톱의 서버 contact 시점→runtime frame 5 연결을
  검증한다.
- 서버 전체 `416 passed`, 서버 `app`·`tests` 전체 Ruff 문제 0.
- VFX 빌더 `--report-only`에서 세 family source 27장·pivot·padding·coverage·fringe를
  다시 검증한다.
- 아이콘 제작 로그·prompt·hash:
  `design-system/concepts/adventure-skill-icons-v1/README.md`와
  `design-system/concepts/adventure-skill-icons-v2/README.md`.
- 공격 pose·ImageGen ID·prompt contract·alpha/runtime hash·QA:
  `design-system/concepts/adventure-combat-vfx-v2/`와
  `design-system/concepts/adventure-combat-vfx-v3/`의 README·manifest.
- 전투 화면 시각 목표와 금지된 재사용 범위:
  `design-system/concepts/adventure-combat-first-v1/README.md`.

## 10. 개발 순서와 중단 기준

1. **S0-C — C 완료**: combat-kit-v6, 여섯 슬롯, 상시 설명 0, 350ms 상세,
   AUTO 동등성.
2. **S0-V — overlay C 완료/단계 진행 중**: 전장 72% overlay shell, 390×844/320×720
   반응형. 실제 기기·스크린리더·성능 검수와 8점 rail 연속성은 남아 있다.
3. **P1-A — 후보 3 family 완료/승격 대기**: 뽀또·구미호·닌자 8스킬 아이콘과
   플레이어 덩굴·맹독 단검, 장부지기 발톱을 연결했다. actor pose·실기 합성·contact
   audio/haptic·profile을 통과하면 family를 A로 승격한다.
4. **S1 — 판정 C 완료 / 아트 진행 전**: 여섯 성장결 약점·내성, 20개 고유기,
   Lv1~30·희귀도·쿨타임. 다음은 비식물 대표 family와 발견 상태·장착 저장이다.
5. **S2**: 연속 battle trail과 선택 route overlay.
6. **S3+**: 12엉킴·62 공격 family·102 아이콘·102 오디오 확장.

판정이 바뀌었는데 서버 단위 테스트가 실패하거나, UI가 320px에서 행동을 가리거나,
production 에셋 증거가 없는 상태에서 출시 완료로 표시하려는 경우 다음 단계로
넘어가지 않는다.

## 11. 이번 구현의 완료 정의

이번 작업은 전체 게임 출시가 아니라 첫 실행 가능한 수직 절편이다. 다음을 모두
만족하면 `S0-C`를 완료로 올릴 수 있다.

- 서버 응답에 고유 2·선택 2가 있고 여섯 행동이 실제 판정된다.
- 앱은 여섯 아이콘을 고정 순서로 보여 주며 평상시 스킬 이름·설명을 표시하지 않는다.
- 잠금·약점·비용은 glyph/숫자로 읽히고 48dp hit area를 가진다.
- 길게 누른 행동은 실행되지 않고 상세 시트만 열린다.
- AUTO가 네 스킬 중 합법적인 최선 행동을 선택하되 미래 정보를 읽지 않는다.
- 기존 `skill` 요청과 저장 중 run이 깨지지 않는다.
- 서버 전투 단위 테스트와 문서 링크·표·UTF-8 검사가 통과한다.
- Flutter SDK가 있는 환경에서는 관련 위젯 테스트와 `flutter analyze`가 통과한다.
