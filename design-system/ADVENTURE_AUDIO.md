# 탐험 오디오 연출 기준

탐험 오디오는 마음 일기의 집중을 방해하지 않는 보조 피드백이다. 일기 작성 화면에는
배경 음악이나 입력음을 붙이지 않고, 탐험 탭에 머무를 때만 사용한다. 오디오 설정과
감각 자극 줄이기 옵션이 마련되기 전에는 런타임 BGM을 기본 활성화하지 않는다.

직접 탐험의 파일 수, 폴더, skill frame cue와 검수 gate는
`design-system/EXPEDITION_ASSET_PRODUCTION.md`를 따른다. 이 문서는 작곡·음색·음량의
상위 원칙이다.

## 배경 음악

- 이끼 낀 기억서고: 58~64 BPM, 낮은 마림바·종이 넘기는 질감·한 음의 따뜻한
  드론. 60~90초 안에서 자연스럽게 반복하며 공포, 전투, 긴장 상승을 암시하는
  타악기와 고음 스트링은 사용하지 않는다.
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
수호자에서는 새 곡으로 끊지 않고 20~30초 길이의 나무 타악·벨 stem을 기존 loop 위에
얹었다가 300ms로 걷어 낸다.

## 제작 파일과 납품 규격

| 분류 | 수량 | master | runtime |
|---|---:|---|---|
| 지역 BGM | 4 | 48kHz/24bit stereo WAV | AAC-LC M4A stereo |
| 수호자 stem | 4 | 48kHz/24bit stereo WAV | AAC-LC M4A stereo |
| 지역 ambience | 8 | 48kHz/24bit stereo WAV | AAC-LC M4A stereo |
| 발걸음·화분 재질 | 4 | 48kHz/24bit mono WAV | PCM16 WAV mono |
| 발견 일반/이야기/목표 | 3 | 48kHz/24bit mono WAV | PCM16 WAV mono |
| 품종 고유 skill | 10 | 48kHz/24bit mono WAV | PCM16 WAV mono |
| 트리 갈래 accent | 3 | 48kHz/24bit mono WAV | PCM16 WAV mono |
| UI 확정·회복·저장·귀환 | 4 | 48kHz/24bit mono WAV | PCM16 WAV mono |

출시 음원은 총 40개다. 90개 스킬트리 노드별 음원을 만들지 않고 품종 signature 10개와
길 읽기·상황 바꾸기·동행 잇기 accent 3개를 조합한다. 런타임 파일명은 다음 규칙을
쓴다.

```text
app/assets/expedition/audio/music/{region}.m4a
app/assets/expedition/audio/music/{region}-guardian.m4a
app/assets/expedition/audio/ambience/{region}-{a|b}.m4a
app/assets/expedition/audio/sfx/step-{leaf|pot|wood|stone}.wav
app/assets/expedition/audio/sfx/discover-{normal|story|target}.wav
app/assets/expedition/audio/sfx/skill-{species}.wav
app/assets/expedition/audio/sfx/branch-{read|change|link}.wav
app/assets/expedition/audio/sfx/ui-{confirm|recover|save|return}.wav
```

- BGM은 -18~-16 LUFS, ambience는 -28~-24 LUFS, 짧은 SFX는 -20~-16 LUFS 범위다.
- 모든 파일은 true peak -2dBTP 이하이며 DC offset, clip, 끝의 불필요한 무음이 없다.
- loop 파일은 파형 zero crossing만 맞추지 말고 잔향과 리듬까지 이어져야 한다. loop
  경계를 10회 반복한 render에 click이나 음색 도약이 없어야 한다.
- `skill` 첫 transient는 sprite manifest의 `effect_cue_frame`에서 ±50ms 안에 난다.
- 품종 signature가 120ms 안에 중복 요청되면 한 번만 재생한다.
- effect source는 직접 녹음한 나무·종이·도자기·마른 잎 foley와 단순 synth를 우선한다.
  외부 음원은 원본 URL, 라이선스, 내려받은 날짜와 편집 내용을 source manifest에 남긴다.
- 출처가 불명확한 생성 음원, 상업 sample pack의 라이선스 미확인 파일, 전투용 금속
  타격·폭발·과한 whoosh는 사용하지 않는다.

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

성장형은 음량이나 보상감의 차이가 아니라 같은 signature 뒤에 80~180ms의 짧은 질감만
바꾼다. `rainy`를 불협화음, `ember`를 더 크고 공격적인 음량으로 만들지 않는다.

## 효과음과 촉각

- 순찰 출발: 300ms 안쪽의 종이 지도 펼침과 가벼운 나무 발판 소리.
- 귀환·새 장소 발견: 450ms 안쪽의 작은 나무 걸쇠와 씨앗 두 알이 닿는 소리.
- 던전 완료: 400ms 안쪽의 무광 도자기 차임. 재화가 여러 개여도 소리를 반복하지 않는다.
- 표본 연구 완료: 350ms 안쪽의 나무 서랍 닫힘과 얇은 유리 차임. 재료 개수만큼
  반복하지 않고 한 번만 재생한다.
- 실패·잠금에는 경고음 대신 문구와 비활성 상태만 사용한다. 위기 안전 경로에서는
  축하음과 촉각을 모두 중단한다.
- 현재 구현은 출발에 선택 촉각, 귀환·던전 완료에 가벼운 촉각, 표본 연구 완료에
  중간 세기 촉각을 적용한다. 안전 지원 활성일에는 연구 완료 촉각도 생략한다.
  검수된 원본 음원이 준비된 뒤 위 기준으로 앱 오디오 설정과 함께 연결한다.

## 오디오 QA

- 음악·환경음·효과음 0/50/100%, 무음, 화면 잠금, 통화/다른 앱의 오디오 포커스,
  Bluetooth 연결 해제를 확인한다.
- 앱이 background로 가면 300ms 안에 fade out 후 정지하고, 복귀하면 재생 위치를
  유지한 채 500ms fade in한다.
- 일기 작성 화면과 안전 지원 화면에서 BGM·입력음·성취 촉각이 나오지 않는지 본다.
- 세 캐릭터 skill과 수호자 stem이 겹쳐도 master bus가 -2dBTP를 넘지 않고 대사가 있는
  사건에서는 BGM이 추가 4dB duck되는지 확인한다.
- 저사양 Android에서 첫 효과음 재생 지연 80ms 이하, 이후 30ms 이하를 목표로 한다.
- 소리를 전부 꺼도 시각·문구만으로 선택 확정, 발견, 저장, 안전 귀환을 알 수 있어야 한다.
