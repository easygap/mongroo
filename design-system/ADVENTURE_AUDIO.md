# 탐험 오디오 연출 기준

탐험 오디오는 장식이 아니라 **적을 발견하고, 공격이 닿고, 엉킴이 풀리고, 다음 장소로
전진했다는 사실을 눈을 떼어도 알게 하는 1차 피드백**이다. 다만 마음 일기 화면에는 배경
음악이나 입력음을 붙이지 않고 탐험 탭에 머무를 때만 사용한다. 오디오 설정과 감각 자극
줄이기 옵션이 마련되기 전에는 런타임 BGM을 기본 활성화하지 않는다.

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
- 현재 구현은 출발에 선택 촉각, 귀환·던전 완료에 가벼운 촉각, 표본 연구 완료에
  중간 세기 촉각을 적용한다. 안전 지원 활성일에는 연구 완료 촉각도 생략한다.
  검수된 원본 음원이 준비된 뒤 위 기준으로 앱 오디오 설정과 함께 연결한다.

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
