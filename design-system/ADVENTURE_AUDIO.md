# 탐험 오디오 연출 기준

탐험 오디오는 장식이 아니라 **적을 발견하고, 공격이 닿고, 엉킴이 풀리고, 다음 장소로
전진했다는 사실을 눈을 떼어도 알게 하는 1차 피드백**이다. 다만 마음 일기 화면에는 배경
음악이나 입력음을 붙이지 않고 탐험 탭에 머무를 때만 사용한다. 전투 HUD의
`음악·효과음 → 효과음만 → 소리 꺼짐` 3단계 설정과 백그라운드 페이드가 연결된 뒤로는
탐험 탭 안에서 런타임 BGM을 기본 활성화한다(아래 `구현 상태` 참고).

직접 탐험의 파일 수, 폴더, skill frame cue와 검수 gate는
`design-system/EXPEDITION_ASSET_PRODUCTION.md`를 따른다. 이 문서는 작곡·음색·음량의
상위 원칙이다.

## 배경 음악

- 이끼 낀 기억서고: 58~64 BPM, 낮은 마림바·종이 넘기는 질감·한 음의 따뜻한
  드론. 60~90초 안에서 자연스럽게 반복한다. combat stem은 같은 박자의 낮은 나무
  click과 짧은 종이 pulse만 더하며 공포·군대식 전투·고음 스트링으로 긴장을 만들지 않는다.
- 메아리 우물정원: 60~66 BPM, 나무 플루트·빈 도자기를 손으로 스치는 소리·아주
  낮은 물결 질감. 반복되는 물방울이나 깊은 우물을 무섭게 만드는 저음은 쓰지 않는다.
- 별빛 보관고: 56~62 BPM, 펠트 피아노·짧은 셀레스타 한 음·부드러운 구리 브러시.
  유리 효과음을 반복하거나 우주·마법 분위기로 과장하지 않는다.
- 마음나무 관측실: 54~60 BPM, 펠트 피아노·낮은 나무 타악기·숨결이 짧은 플루트.
  완주를 크게 선언하는 팡파르 대신 새벽빛처럼 조용히 정리되는 두 마디로 마친다.
- 통합 음량은 약 -18 LUFS, true peak -2 dBTP 이하를 목표로 한다. 탭 진입·이탈은
  500ms 교차 페이드하고, 앱이 백그라운드로 가면 즉시 일시 정지한다.

네 지역 곡은 서로 다른 곡이어도 4음으로 된 `정원으로 돌아가는 동기`를 낮은 음량으로
한 번씩 공유한다. 뒤 지역일수록 악기 수와 음량이 커지는 수직 강화는 하지 않는다.
일반 조우와 수호자에서는 새 곡으로 끊지 않는다. 지역 combat stem과 20~30초 길이의
수호자 나무 타악·벨 stem을 기존 loop의 같은 재생 위치 위에 얹었다가 걷어 낸다.

### 연속 무대의 적응형 레이어

| 장면 | 재생 상태 | 전환 |
|---|---|---:|
| `approach` | 지역 BGM 100% + ambience A/B | 현재 위치 유지 |
| `encounter` | combat stem을 -18dB에서 목표치로 올리고 ambience를 2dB 낮춤 | 180~250ms |
| `command/combat` | 지역 BGM + combat stem, 적 의도에는 120ms 이하의 종별 preview cue | hard cut 없음 |
| `guardian` | combat stem 유지 + guardian stem 한 층 | 250~350ms |
| `release` | combat/guardian stem을 걷고 지역별 두 음 release cadence 1회 | 300~450ms |
| `advance` | 원래 BGM·ambience 위치로 복귀 | 250~350ms |

- stage 번호가 바뀌어도 BGM playhead를 0초로 되돌리지 않는다. 앱 중단·오디오 포커스
  변경·지역 pack 교체만 재생 세션 경계다.
- combat stem은 전투력을 과장하는 별도 곡이 아니라 명령과 접촉의 박자를 붙잡는 얇은
  layer다. 배속 2×에서도 음악 tempo는 바꾸지 않고 VFX/SFX cue만 타임라인을 따른다.
- `reduce sensory`에서는 combat·guardian stem을 끄고 base BGM과 contact cue만 남긴다.

## 제작 파일과 납품 규격

아래 `master`는 납품 **규격**이지 저장소에 두는 파일이 아니다. 코드로 합성하는
음원의 마스터는 `.gitignore`로 막고 스크립트와 manifest의 sha256으로 관리한다
(아래 `지역 BGM 12곡` 참고). 손으로 녹음한 foley를 도입한다면 그때는 원본을
저장소나 별도 저장소에 보관해야 한다 — 재생성할 수 없기 때문이다.

| 분류 | 수량 | master | runtime |
|---|---:|---|---|
| 지역 BGM | 4 | 48kHz/24bit stereo WAV | AAC-LC M4A stereo |
| 지역 combat stem | 4 | 48kHz/24bit stereo WAV | AAC-LC M4A stereo |
| 수호자 stem | 4 | 48kHz/24bit stereo WAV | AAC-LC M4A stereo |
| 지역 release cadence | 4 | 48kHz/24bit stereo WAV | PCM16 WAV stereo |
| 지역 ambience | 8 | 48kHz/24bit stereo WAV | AAC-LC M4A stereo |
| 발걸음·화분 재질 | 4 | 48kHz/24bit mono WAV | PCM16 WAV mono |
| 발견 일반/이야기/목표 | 3 | 48kHz/24bit mono WAV | PCM16 WAV mono |
| 품종 고유 skill | 20 | 48kHz/24bit mono WAV | PCM16 WAV mono |
| 감정 skill cue | 6 | 48kHz/24bit mono WAV | PCM16 WAV mono |
| 기록서 역할 cue | 8 | 48kHz/24bit mono WAV | PCM16 WAV mono |
| 트리 갈래 accent | 3 | 48kHz/24bit mono WAV | PCM16 WAV mono |
| UI 확정·회복·저장·귀환 | 4 | 48kHz/24bit mono WAV | PCM16 WAV mono |
| 엉킴 공격 signature | 16 | 48kHz/24bit mono WAV | PCM16 WAV mono |
| 수호짐승 공격 signature | 8 | 48kHz/24bit mono WAV | PCM16 WAV mono |
| 접촉 재질·guard | 6 | 48kHz/24bit mono WAV | PCM16 WAV mono |

> **2026-08-13 현황.** 아래 수량표는 캐릭터·적이 늘기 전에 쓰였다. 실제로 만든
> 것은 **지역 ambience 8, 발걸음 4·발견 3, 품종 signature 32(16품종 × 2), 적 공격
> signature 29(엉킴 24 + 수호자 5)**다. 표의 20·24를 그대로 따르면 여섯 캐릭터와
> 다섯 적이 소리 없이 남으므로 **실제 콘텐츠 전부**를 만들었다. 파일명은 서버의
> 스킬·적·공격 코드를 그대로 따르므로 코드가 이름의 단일 원본이다.
>
> ambience는 표와 달리 **A 32초 / B 40초로 길이를 다르게** 만들었다. 게임 오디오에서
> ambience는 30초~2분이 권장 범위이고 같은 소리가 15초마다 돌아오면 반복이 들리는데,
> 두 층 길이를 어긋내면 겹쳐 틀었을 때 실제 반복 주기가 **최소공배수 160초**로
> 늘어난다. 파일은 작게 두면서 귀에 들리는 주기만 길어진다. 도드라지는 사건(물방울
> 한 방울 같은 것)은 넣지 않았다 — loop를 들키게 하는 주범이라 검수기가 `짧은 창 최대
> RMS ÷ 중앙값`으로 막는다.
>
> 이음매는 **원형 필터링**으로 만든다. 잡음층을 만들 때 버퍼 끝으로 필터 상태를 먼저
> 데운 뒤 전체를 거르면 결과가 원형 합성곱과 같아져 경계에 자국이 남지 않는다.
> 검수기가 경계 계단을 내부 표본 변화량과 비교해 확인하고, 실측값은 내부 변화량의
> 0.07~0.24배다(임계 3.0배).

출시 음원은 총 **102개**다. 90개 스킬트리 노드별 음원을 만들지 않고 고유 스킬 signature 20개,
감정 skill cue 6개, 기록서 역할 cue 8개, 길 읽기·상황 바꾸기·동행 잇기 accent 3개를
조합한다. 적 공격도 종류와 예고를 귀로 구분해야 하므로 일반 엉킴 8공격·큰 엉킴
8공격·수호짐승 8공격이 각자 signature를 가진다. 런타임 파일명은 다음 규칙을 쓴다.

```text
app/assets/expedition/audio/music/{region}.m4a
app/assets/expedition/audio/music/{region}-combat.m4a
app/assets/expedition/audio/music/{region}-guardian.m4a
app/assets/expedition/audio/sfx/release-{region}.wav
app/assets/expedition/audio/ambience/{region}-{a|b}.m4a
app/assets/expedition/audio/sfx/step-{leaf|pot|wood|stone}.wav
app/assets/expedition/audio/sfx/discover-{normal|story|target}.wav
app/assets/expedition/audio/sfx/skill-{species}-{skill-key}.wav
app/assets/expedition/audio/sfx/skill-emotion-{sunny|rainy|ember|moonlit|sparkling|mosaic}.wav
app/assets/expedition/audio/sfx/skill-book-{sound_key}.wav
app/assets/expedition/audio/sfx/branch-{read|change|link}.wav
app/assets/expedition/audio/sfx/ui-{confirm|recover|save|return}.wav
app/assets/expedition/audio/sfx/enemy-{enemy-key}-{attack-key}.wav
app/assets/expedition/audio/sfx/guardian-{guardian-key}-{attack-key}.wav
app/assets/expedition/audio/sfx/contact-{leaf|paper|water|wood|stone|guard}.wav
```

- BGM은 -18~-16 LUFS, ambience는 -28~-24 LUFS, 짧은 SFX는 -20~-16 LUFS 범위다.
- 모든 파일은 true peak -2dBTP 이하이며 DC offset, clip, 끝의 불필요한 무음이 없다.
- loop 파일은 파형 zero crossing만 맞추지 말고 잔향과 리듬까지 이어져야 한다. loop
  경계를 10회 반복한 render에 click이나 음색 도약이 없어야 한다.
- `skill` 첫 transient는 sprite manifest의 `effect_cue_frame`에서 ±50ms 안에 난다.
- 공격 signature의 release transient는 `release_frame`, 접촉 재질음·햅틱·HP 변화는
  `contact_frame`에서 실제 기기 기준 ±1 frame 안에 난다.
- 품종 signature가 120ms 안에 중복 요청되면 한 번만 재생한다.
- effect source는 직접 녹음한 나무·종이·도자기·마른 잎 foley와 단순 synth를 우선한다.
  외부 음원은 원본 URL, 라이선스, 내려받은 날짜와 편집 내용을 source manifest에 남긴다.
- 출처가 불명확한 생성 음원, 상업 sample pack의 라이선스 미확인 파일, 전투용 금속
  타격·폭발·과한 whoosh는 사용하지 않는다.

### 전투 믹스 우선순위

1. `contact/guard/release` — 실제 결과가 난 순간
2. 적 의도 preview — 다음 선택에 필요한 정보
3. 현재 시전자 signature — 누가 무엇을 했는지
4. 캐릭터 짧은 대사 — 관계와 감정
5. combat stem·ambience — 공간과 박자

- 한 순간에 또렷한 transient는 최대 3개다. 같은 접촉에 공격 signature, target material,
  UI confirm을 모두 같은 음량으로 쌓지 않고 UI confirm은 생략한다.
- contact 순간 ambience와 비핵심 signature를 80~140ms 동안 2~4dB duck한다. 대사가
  나오면 BGM·stem은 6~8dB duck하되 contact 결과까지 지우지 않는다.
- 적 공격 signature는 같은 공용 파동의 pitch·EQ 변형으로 세지 않는다. 발사 재질,
  길이, transient 간격 중 둘 이상이 달라야 하며 무음으로 봐도 sprite silhouette가 같다.
- stereo 위치는 actor 화면 위치의 20~35%만 반영해 헤드폰에서 과도하게 좌우로 붙지 않게
  하고, mono 합산에서 6dB 이상 사라지는 위상 상쇄를 금지한다.
- 긴 꼬리음은 다음 명령의 의도 cue를 가리지 않게 700ms 안에 -24dB 아래로 감쇠한다.

## 품종 signature 음색표

| 품종 | 핵심 재료 | 금지 방향 |
|---|---|---|
| 뽀또 | 씨앗 두 알, 짧은 잎 튕김 | 아기 목소리·장난감 경적 |
| 로제온 | 얇은 나무판 정렬, 낮은 펠트 건반 | 지휘봉 타격·군대 북 |
| 블루미 | 종이 꽃 펼침, 짧은 도자기 음 | 화려한 관객 환호 |
| 가시로 | 마른 줄기 스침 뒤 작은 천 소리 | 날카로운 찌르기·금속 가시 |
| 시들잎 | 낮은 잎마찰, 역방향이 아닌 부드러운 숨 | 공포 drone·신음 |
| 여우비 | 부채 천 스침, 작은 나무 방울 | 불꽃 폭발·유혹 음성 |
| 그림싹 | 짧은 잎 채찍과 대나무 click | 칼 소리·타격음 |
| 별솔 | 유리 한 음, 나무 지팡이 회전 | 우주 laser·과한 반짝임 |
| 설화 | 종이 넘김, 작은 렌즈 유리 click | 차가운 경고 buzzer |
| 하루 | 연필 한 획, 노트 덮는 소리 | 학교 종·시험 알림음 |

감정 cue는 품종 signature 뒤에 겹치는 80~180ms의 짧은 질감이며 모두 같은 loudness·
길이 예산을 쓴다.

같은 품종의 고유 I·II는 나무·잎·도자기 같은 핵심 재료를 공유해 가족성을 유지하되,
attack envelope·transient 간격·contact phrase 중 둘 이상을 다르게 만든다. 한 파일의
pitch만 바꿔 두 스킬로 납품하지 않는다.

| 성장결 | 핵심 질감 | 피할 방향 |
|---|---|---|
| 햇살결 | 얇은 나뭇잎 두 장이 넓게 펴지는 숨 | 보상 팡파르·과한 장조 |
| 빗물결 | 도자기 가장자리의 낮은 물결 한 번 | 불협화음·울음소리 |
| 불씨결 | 마른 씨앗 껍질의 또렷한 짧은 튕김 | 폭발·금속 타격·더 큰 음량 |
| 달빛결 | 천 위 작은 나무 방울의 감쇠 | 공포 drone·경고음 |
| 별빛결 | 유리구슬 한 번과 민트색을 연상시키는 가벼운 잎 click | 슬롯머신 반짝임·연속 고음 |
| 모아결 | 서로 다른 두 종이 질감이 한 박자로 합쳐짐 | 혼란스러운 겹침·불안정 pitch |

`rainy`를 불협화음, `ember`를 더 크고 공격적인 음량으로 만들지 않는다.
기록서 8개 cue는 등급이 아니라 회복·방어·집중·변환 등 역할을 구분한다. 3등급이라고
더 크거나 긴 소리를 쓰지 않고, 표지 문양의 짧은 종이/나무 질감만 앞에 덧붙인다.

### 성장결 signature 6종 (2026-08-31)

제작·검수: `build_emotion_signatures.py`, `verify_emotion_signatures.py`.
manifest는 `design-system/audio/emotion-signature-manifest.json`이다.

여섯은 **크기와 길이를 공유하고 음색으로만 갈린다.** 기획의 `어느 결도 범용
상위호환이 될 수 없다`를 소리에서 지키는 방법이 그것뿐이다. 더 크거나 더 오래
우는 결이 하나라도 있으면 귀가 먼저 서열을 만든다. 그래서 감쇠 봉투
(140/84/44ms)와 마찰 길이(96ms)를 여섯이 함께 쓰고, 검수기가 **크기 편차 8%,
길이 편차 10%** 안을 강제한다.

| 성장결 | 스킬 | 스펙트럼 무게중심 | 유효 길이 | 50ms 최대 RMS |
|---|---|---:|---:|---:|
| 빗물결 | `rainy_frozen_tide` | 364Hz | 380ms | 0.108 |
| 달빛결 | `moonlit_lonesome_tempest` | 615Hz | 377ms | 0.106 |
| 불씨결 | `ember_rage_breaker` | 993Hz | 364ms | 0.107 |
| 햇살결 | `sunny_radiant_heart` | 2,339Hz | 360ms | 0.107 |
| 모아결 | `mosaic_steel_equilibrium` | 2,924Hz | 357ms | 0.108 |
| 별빛결 | `sparkling_shock_wonder` | 3,972Hz | 363ms | 0.107 |

밝기 순서가 위 음색표의 재료에서 그대로 나온다 — 도자기 물결이 가장 낮고
유리구슬이 가장 높다. 불씨결이 가운데인 것은 음색표가 `마른 씨앗 껍질의 또렷한
짧은 튕김`을 적었기 때문이다. 또렷함은 어택의 속도이지 높이가 아니라서, 여기서
가장 밝게 만들면 금지 방향인 `금속 타격`으로 미끄러진다.

### 만든 소리를 실제로 울리기 (2026-08-31)

품종 32 · 성장결 6 · 적 공격 38, 모두 76개 signature가 번들에 있었지만 앱은
tier 대체음 3종만 알고 있었다. 즉 **모든 스킬이 크기만 다른 같은 소리로**
들렸다. 이제 서버가 전투 이벤트에 `skill_code`를 실어 보내고 앱이 그 코드로
전용 음원을 고른다.

- 단일 원본은 manifest다. `build_signature_audio_map.py`가 세 manifest를 읽어
  `expedition_signature_audio.g.dart`를 만들고, 그때 파일 존재·sha256·코드 중복·
  서버 카탈로그 대조를 함께 본다. 앱에서 파일 이름을 다시 조립하지 않는다.
- 76개를 미리 pool에 올리지 않는다. 한 판에서 실제로 쓰는 것은 대여섯이라
  **처음 울린 소리만** pool을 만들고 12개까지 LRU로 들고 있는다.
- 코드가 없거나(구버전 응답) 아직 음원이 없는 행동은 기존 tier 대체음·재질
  예고음으로 떨어진다. 비슷한 파일을 대신 고르지 않는다 — 그러면 `소리가 있는
  스킬`과 `없는 스킬`이 섞여 무엇이 남았는지 알 수 없게 된다.

## 효과음과 촉각

- 순찰 출발: 300ms 안쪽의 종이 지도 펼침과 가벼운 나무 발판 소리.
- 귀환·새 장소 발견: 450ms 안쪽의 작은 나무 걸쇠와 씨앗 두 알이 닿는 소리.
- 던전 완료: 400ms 안쪽의 무광 도자기 차임. 재화가 여러 개여도 소리를 반복하지 않는다.
- 표본 연구 완료: 350ms 안쪽의 나무 서랍 닫힘과 얇은 유리 차임. 재료 개수만큼
  반복하지 않고 한 번만 재생한다.
- 실패·잠금에는 경고음 대신 문구와 비활성 상태만 사용한다. 위기 안전 경로에서는
  축하음과 촉각을 모두 중단한다.
- 스킬 선택은 가벼운 선택 촉각 1회, 일반 contact는 짧은 가벼운 촉각 1회, guard는
  중간 세기의 둔한 촉각 1회, 수호자 장벽 해제는 `약-중` 두 pulse까지만 사용한다.
  연속 공격은 실제 contact가 여러 번이어도 120ms보다 촘촘하게 촉각을 반복하지 않는다.
- 적 anticipation에는 촉각을 넣지 않는다. 예고는 소리·pose·glyph로 읽고, 사용자가
  조작하지 않은 순간에 진동을 계속 발생시키지 않는다.
- 위 네 순간은 **소리와 촉각이 함께 연결됐다**(2026-08-12). 출발에 선택 촉각,
  귀환·던전 완료에 가벼운 촉각, 표본 연구 완료에 중간 세기 촉각을 쓰고, 같은
  자리에 `cue-{patrol-depart|patrol-return|dungeon-clear|research-complete}.wav`가
  난다. 주간 약속 수령은 귀환과 같은 `보상을 받았다` 순간이라 귀환 소리를 함께
  쓴다. 안전 지원 활성일에는 연구 완료의 촉각과 소리를 **둘 다** 생략한다.
  효과음을 끈 사용자에게는 문구와 촉각만 남는다.
- 보상이 여러 개여도 소리는 한 번이다. 400ms 안에 같은 cue가 다시 요청되면
  재생하지 않는다.

## 구현 상태 — 접촉 재질·예고·풀려남 (2026-08-12, 재생 배선 2026-08-31)

런타임 경로는 이 문서의 `app/assets/expedition/audio/` 계획안이 아니라 실제
번들 경로 `app/assets/adventure/sfx/`를 쓴다. 파일 이름 규칙은 계획안 그대로다.

| 분류 | 계획 | 만든 것 | 앱이 재생 | 남은 것 |
|---|---:|---:|:---:|---|
| 접촉 재질·guard | 6 | **6** | ✅ | — |
| 적 의도 preview(재질) | 5 | **5** | ✅ | — |
| 지역 풀려남 cadence | 4 | **4** | ✅ | — |
| 지역 BGM·combat·guardian stem | 12 | **12** | ✅ | — |
| 지역 환경음 | 8 | **8** | ✅ | — |
| 모험 확정 cue | 4 | **4** | ✅ | — |
| 발걸음 cue | 4 | **4** | ✅ | — |
| 발견 cue | 3 | **3** | ❌ | 발견 순간의 훅 |
| 품종 고유 skill signature | 32 | **32** | ✅ | — |
| 여섯 성장결 skill signature | 6 | **6** | ✅ | — |
| 엉킴·수호짐승 공격 signature | 38 | **38** | ✅ | — |

`앱이 재생` 열이 이 표의 핵심이다. 2026-08-31 이전까지 품종·성장결·엉킴
signature 76종은 **번들에는 있는데 한 번도 울리지 않았다.** 앱이 tier 대체음
3종만 알고 있었기 때문이다. 만든 것과 들리는 것은 다른 칸이므로 따로 센다.

- 제작·검수 스크립트: `design-system/scripts/build_expedition_contact_audio.py`,
  `design-system/scripts/verify_expedition_contact_audio.py`.
  manifest와 검수 보고서는 `design-system/audio/adventure-contact-v1/`에 남긴다.
- 합성 방식은 **모달 합성**(재질별 감쇠 사인 모드) + 대역 제한 노이즈 여기다.
  물은 시간에 따라 공명이 올라가는 기포 모형을 쓴다. 외부 샘플·생성형 오디오
  원본을 쓰지 않아 라이선스 추적 대상이 없다.
- 0.1~0.3초 one-shot은 EBU R128의 momentary 창(400ms)보다 짧아 integrated LUFS로
  맞출 수 없다. 대신 **50ms 창 최대 RMS**로 여섯 재질의 체감 음량을 맞추고
  true peak −2dBTP 한도를 따로 지킨다. `verify_…` 스크립트가 두 값을 모두 잰다.
- 재질이 "같은 파동의 pitch 변형"이 되지 않도록 검수 스크립트가 스펙트럼
  무게중심과 감쇠 시간을 재서 두 축이 함께 붙은 쌍을 반려한다. 현재 값:

  | 재질 | 스펙트럼 무게중심 | 감쇠(-20dB) |
  |---|---:|---:|
  | guard | 139Hz | 184ms |
  | wood | 401Hz | 289ms |
  | stone | 1,438Hz | 163ms |
  | water | 2,870Hz | 115ms |
  | leaf | 5,632Hz | 74ms |
  | paper | 8,385Hz | 33ms |

- 재질의 단일 원본은 서버 `app/content/expeditions/tangles.py`의
  `TANGLE_CONTACT_MATERIAL`(엉킴 몸체 12)과
  `TANGLE_INTENT_CONTACT_MATERIAL`(예고 24)이다. 앱은 재질을 추론하지 않고
  이벤트의 `contact_material`을 그대로 재생한다. 구버전 응답에는 값이 없으므로
  기존 공용 타격음으로 떨어진다.
- 풀려남 cadence 네 곡은 `정원으로 돌아가는 동기`(C-G-A-E)의 마지막 두 음
  `A → E`를 지역 음색으로 다시 들려준다. 음정 관계가 같아 어느 지역에서든
  "제자리로 돌아갔다"로 읽히고, 지역마다 음색·옥타브·속도만 다르다.
- 앱 오디오 설정은 `음악·효과음 → 효과음만 → 소리 꺼짐` 세 단계다. 백그라운드
  진입 시 300ms fade out 후 정지, 복귀 시 같은 재생 위치에서 500ms fade in한다.

### 지역 BGM 12곡 (2026-08-12)

제작·검수: `build_expedition_music.py --region all`,
`verify_expedition_music.py`. manifest는
`design-system/audio/adventure-{slug}-v1/`에 남긴다.

**마스터 WAV는 저장소에 두지 않는다.** 48kHz/24bit 마스터는 지역당 14MB라
12곡이면 53MB인데, 합성이 결정론적이라 언제든 같은 바이트로 되살아난다.
그래서 파일 대신 **스크립트와 manifest의 `master_sha256`**을 출처 기록으로 삼고
`.gitignore`가 `design-system/audio/**/*-master.wav`를 막는다. 런타임 M4A는
그대로 추적한다 — 앱이 번들에 싣는 실제 산출물이기 때문이다.

```bash
# 마스터가 필요할 때 되살린다(런타임 M4A도 함께 다시 만든다)
python design-system/scripts/build_expedition_music.py --region all

# 아무것도 쓰지 않고 기록된 sha256과 대조만 한다
python design-system/scripts/build_expedition_music.py --region all --check
```

`--check`는 임시 폴더에만 렌더링해 manifest의 `master_sha256`과 맞춰 본다.
빌더를 고쳤는데 산출이 달라졌다면 여기서 잡힌다. 곡을 의도적으로 바꿨다면
`--check`가 실패하는 것이 정상이므로, 다시 렌더링해 manifest를 갱신하고
`verify_expedition_music.py`로 순환·음량을 다시 검수한다.

| 지역 | BPM | 16초 안 박자 | 악기 | 악보 |
|---|---:|---:|---|---|
| 이끼 낀 기억서고 | 60 | 16 | 낮은 마림바·종이 넘김 | C4 G3 A3 E4 D4 A3 G3 C4 |
| 메아리 우물정원 | 63.75 | 17 | 나무 플루트·빈 도자기·한 박 뒤 메아리 | C5 G4 A4 E5 B4 A4 G4 E4 |
| 별빛 씨앗 보관고 | 56.25 | 15 | 펠트 피아노·셀레스타 한 음·구리 브러시 | C4 G4 A4 E4 F4 D4 B3 C4 |
| 마음나무 관측실 | 56.25 | 15 | 펠트 피아노·낮은 나무 타악·짧은 숨 플루트 | C4 G3 A3 E4 D4 G3 + 정리하는 두 음 |

- 네 악보 모두 **앞 네 음이 정원 복귀 동기 C-G-A-E**를 지난다. 빌더가
  `_validate_regions`에서 이 조건과 BPM 범위를 강제해, 어기면 렌더링 전에 멈춘다.
- 순환이 이어지려면 두 조건이 필요하다. 드론 주기가 16초 안의 정수여야 하고,
  16초 안의 박자 수도 정수여야 한다. `BPM = 3.75 × 박자 수`라서 문서 범위에
  들어오는 값은 60·63.75·56.25뿐이다.
- 뒤 지역이 더 크게 들리는 수직 강화를 막기 위해 정규화 목표는 지역과 무관한
  `MIX_TARGETS` 하나만 쓴다. 실측 결과 같은 상태끼리 지역 간 편차는 0.5LU
  이내다(base −20.2~−20.5, combat −19.1~−19.5, guardian −18.3~−18.8 LUFS).
- 앱은 전투 응답의 `region_code`로 곡을 고른다. 같은 지역 안에서 stem이 바뀔
  때는 재생 위치를 지키고, **지역이 바뀔 때만** 새 재생 세션을 연다. 지역마다
  BPM과 마디가 달라 재생 위치를 물려받을 수 없기 때문이다.

**이번에 함께 고친 기존 결함 두 가지**

1. 수호자 층의 타점을 `4박마다`로 찍고 있어, 16초 안의 박자 수가 4의 배수가
   아닌 지역에서 순환 경계의 타점 간격만 짧아졌다. 박이 아니라 **loop를 정확히
   나눈 자리**(4등분·2등분)에 찍도록 바꿨다.
2. `loudnorm`의 true peak 리미터가 목표를 정확히 맞추지 못해 수호자 stem이
   −1.8~−1.9dBTP까지 새어 나가 문서 상한 −2dBTP를 넘고 있었다. 목표를 −2.5dBTP로
   낮춰 실측 −2.4dBTP 이하로 들어왔다. 이끼 기억서고 곡도 같은 결함이 있어 함께
   다시 렌더링했다(마스터 WAV는 세 곡 모두 이전과 바이트 단위로 동일하다).

## 오디오 QA

- 음악·환경음·효과음 0/50/100%, 무음, 화면 잠금, 통화/다른 앱의 오디오 포커스,
  Bluetooth 연결 해제를 확인한다.
- 앱이 background로 가면 300ms 안에 fade out 후 정지하고, 복귀하면 재생 위치를
  유지한 채 500ms fade in한다.
- 일기 작성 화면과 안전 지원 화면에서 BGM·입력음·성취 촉각이 나오지 않는지 본다.
- 세 캐릭터 skill, 적 signature와 수호자 stem이 겹쳐도 master bus가 -2dBTP를 넘지 않고
  대사가 있는 사건에서는 BGM·stem이 6~8dB duck되는지 확인한다.
- 저사양 Android에서 첫 효과음 재생 지연 80ms 이하, 이후 30ms 이하를 목표로 한다.
- 1×·2×·짧은 연출에서 62개 플레이어/적 공격 family의 release/contact cue가 manifest
  frame에서 ±1 frame이고, stage 전환 때 BGM restart·click·stem phase jump가 0건인지 본다.
- 신규 사용자 12명 중 10명 이상이 화면을 보지 않고도 `우리 공격 접촉`, `적 공격 예고`,
  `guard`, `풀려남` 네 상황을 80% 이상 구분해야 한다.
- 소리를 전부 꺼도 시각·문구만으로 선택 확정, 발견, 저장, 안전 귀환을 알 수 있어야 한다.
