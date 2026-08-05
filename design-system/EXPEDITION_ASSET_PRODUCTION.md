# 직접 탐험 에셋·이펙트·오디오 제작 실행서

최종 갱신: 2026-08-04
상태: 제작·구현 기준안
대상 버전: `interactive-expedition-v1.2`

이 문서는 `docs/interactive_adventure_design.md`의 그래픽·오디오 계약을 실제로
제작할 수 있는 단위로 풀어 쓴다. 캐릭터 원형은 `MONGROO_GROWTH_ART.md`, 성체
의상 레이어는 `concepts/wardrobe-v1/README.md`, 배경 원화 기록은
`ADVENTURE_ASSET_PROMPTS.md`, 음향 원칙은 `ADVENTURE_AUDIO.md`를 따른다.

## 1. 먼저 고정할 결정

1. 탐험 캐릭터는 `base → outfit → face/blink → effect` 순서로 합성한다. 효과를
   캐릭터나 의상 그림에 구워 넣지 않는다.
2. stage 2~4는 이미 있는 512×768 성장 원화를 재사용한다. 별도의 프레임 시트를
   대량 생성하지 않고, 현재 홈과 같은 pivot 기반 transform 모션을 탐험용으로
   조정한다.
3. stage 5는 움직임과 의상 식별이 중요한 완전체이므로 7개 action의 프레임
   애니메이션을 만든다. 의상은 wardrobe v2와 마찬가지로 같은 자세의 base를
   참조해 편집하고 사람의 피부·얼굴·팔다리를 포함하지 않는다.
4. stage 5 미만은 고유 성장 의상을 그대로 사용하며 탐험 wardrobe loadout을
   장착하지 않는다. 이 규칙은 성장기 캐릭터에 성체 의상을 억지로 합성하거나,
   화면에는 안 보이는 의상 성능만 적용되는 문제를 함께 막는다.
5. ImageGen은 지역 콘셉트와 승인용 캐릭터 key pose를 만드는 보조 수단이다.
   최종 8프레임 시트를 한 번에 생성하지 않는다. 프레임별 얼굴·팔다리·의상
   흔들림은 2D 리깅과 수작업 클린업으로 없앤다.
6. 지도선·선택 링·안개·스킬트리 가지·상태 표시는 코드 벡터로 그린다. 질감이
   필요한 캐릭터, 배경, 수호자, 유기적인 잎 효과만 래스터로 만든다.
7. 이미지에는 글자를 넣지 않는다. 이름·수치·사건 문장은 localization 리소스가
   소유한다.
8. 화려함은 픽셀 수나 섬광으로 표현하지 않는다. 한 효과는 주색 1개, 보조색
   1개, 크림색 하이라이트까지만 사용한다.

## 2. 화면별 자산 사용표

| 화면 | 캐릭터 | 배경·오브젝트 | 효과 |
|---|---|---|---|
| 파티 편성 | 기존 512×768 성장 원화 또는 wardrobe 합성 | 코드 UI | 선택 링, 스탯 변화만 코드 |
| 탐험 지도 | 72~112px 토큰. stage 2~4 transform, stage 5 frame strip | 3단 parallax 지도 | 이동 먼지, 발견 잎, 길 공개 |
| 사건 선택 | 144~220px 기존 원화/wardrobe pose | 사건 배경 1장 | 표정·blink, 선택 결과 accent |
| 수호자 | 현재 행동자 토큰 | 수호자 4 action | 지역 고유 반응 효과 |
| 목표 확보 | 파티 토큰 | 목표 아이템 cutout | 작은 부유·획득 궤적 |
| 귀환 결과 | 최대 3명 `return` 또는 기존 성장 원화 | 지역 지도 blur 없이 정지 | 획득 항목당 1회가 아닌 장면당 1회 |
| 스킬트리 | 기존 초상 | 코드 가지 | root/branch badge, 발동 미리보기 |

지도 토큰을 사건 초상 크기로 확대하지 않고, 사건 초상을 작은 지도 시트로 대체하지
않는다. 두 렌더의 역할과 해상도가 다르다.

## 3. 원본과 출력 디렉터리

```text
design-system/concepts/expedition-v1/
  manifest.source.json
  references/
    style/
    characters/{species}/
    regions/{region}/
  characters/{species}/
    stage5/base/{form}/{action}/frame-00.png
    stage5/outfits/{outfit-key}/{form}/{action}/frame-00.png
  effects/
    forms/{form}/{back|front}/frame-00.png
    signatures/{species}/{back|front}/frame-00.png
    common/{effect-key}/frame-00.png
  regions/{region}/
    map/{back|mid|front}.png
    events/{event-key}.png
    guardian/{action}/frame-00.png
    target.png
    particles/{particle-key}/frame-00.png
  ui/
    badges/{root|branch|module}/...
    items/...
    tools/...
    event-props/{region}/{event-key}.svg

app/assets/expedition/
  asset-manifest.json
  characters/{species}/base/{form}/{action}.webp
  characters/{species}/outfits/{outfit-key}/{form}/{action}.webp
  effects/{category}/{key}/{back|front}.webp
  regions/{region}/map-{back|mid|front}.webp
  regions/{region}/events/{event-key}.webp
  regions/{region}/guardian/{action}.webp
  regions/{region}/target.webp
  regions/{region}/particles/{particle-key}.webp
  ui/{badges|items|tools|event-props}/...
  audio/{music|ambience|sfx}/...
```

원본 PNG는 수정 이력과 검수를 위해 보존하고, 앱은 빌드된 WebP와 오디오 런타임
파일만 읽는다. `app/assets/expedition` 파일을 손으로 수정하지 않는다.

`species`는 다음 열 종으로 고정한다.

```text
baby-pot, handsome-pot, pretty-pot, tsundere-pot, zombie-pot,
gumiho-pot, ninja-pot, magical-pot, aloof-pot, student-pot
```

`form`은 `sunny, rainy, ember, moonlit, sparkling, mosaic`, `action`은
`idle, walk, interact, skill, react, tired, return` 순서다.

## 4. 성장 단계별 제작 방식

### 4.1 stage 2~4

- `app/assets/plants/{species}-25d-{sprout|branching|bloom}-{form}.webp`를
  그대로 사용한다.
- stage 2는 좌우 잎 흔들기와 1~2px 상하 호흡, stage 3은 짧은 도약과 착지,
  stage 4는 상체 회전과 장식 지연만 합성한다.
- 이동은 캐릭터 전체가 경로를 따라 움직이는 동안 2~3px 수직 보행 진동을 사용한다.
  다리를 따로 걷게 보이도록 가짜 관절을 만들지 않는다.
- `interact`, `skill`, `react`는 350~700ms의 1회 transform과 별도 effect로
  구분한다. `tired`는 진폭을 절반으로 줄인 idle이다.
- 움직임 줄이기에서는 모든 transform을 멈추고 시작·결과 정지 pose만 바꾼다.
- stage 2~4에는 외부 wardrobe를 얹지 않는다. 파티 편성 화면에서
  `의상은 만개 뒤 탐험에서 입을 수 있어요`를 표시한다.

이 구간의 신규 래스터는 0장이다. 성장 원화의 얼굴과 체형을 유지하고, 성체용 의상
제작량이 성장 단계 수만큼 폭증하는 것도 막는다.

### 4.2 stage 5

성체는 128×192 셀 8개를 4×2로 배열한 512×384 투명 WebP strip을 사용한다.
한 파일은 품종·성장형·레이어·동작 하나만 담는다.

```text
frame 0  frame 1  frame 2  frame 3
frame 4  frame 5  frame 6  frame 7
```

- 바닥 pivot은 셀 기준 `(64, 180)`, 얼굴 anchor의 기본값은 `(64, 48)`이다.
- 실제 얼굴 anchor, 왼눈·오른눈 중심, effect anchor는 파일별 manifest에 기록한다.
- 6프레임 동작은 frame 6~7을 완전 투명으로 둔다.
- base와 outfit은 동일한 strip layout, 프레임 수, duration, pivot을 사용한다.
- 런타임은 현재 form의 strip만 디코딩한다. 여섯 form을 한 1024×1152 이미지로
  묶으면 쓰지 않는 다섯 행까지 약 4.5MB로 디코딩되므로 금지한다.

| action | 프레임 | 권장 길이 | 반복 | 역할 |
|---|---:|---:|---|---|
| `idle` | 6 | 2.1~2.8초 | 예 | 호흡·고유 부분 모션, blink는 별도 |
| `walk` | 8 | 720~880ms | 예 | 발 고정과 무게 이동 |
| `interact` | 6 | 780~1100ms | 아니오 | 관찰·돌봄·장치 조작 공용 |
| `skill` | 8 | 800~1200ms | 아니오 | 품종/성장형 effect 공용 몸동작 |
| `react` | 6 | 620~900ms | 아니오 | 놀람·기쁨·안도 중 캐릭터다운 반응 |
| `tired` | 6 | 2.4~3.2초 | 예 | 준비도 저하. 병듦·패배처럼 보이지 않음 |
| `return` | 8 | 900~1300ms | 아니오 | 뒤돌아 인사하거나 정원 방향으로 이동 |

프레임 duration은 균등하다고 가정하지 않고 manifest 배열로 저장한다. `skill`의
effect 발화 시점과 SFX cue도 같은 frame index를 사용한다.

### 4.3 stage 5 레이어 소유권

| 요소 | 레이어 | 주의 |
|---|---|---|
| 얼굴·머리·식물 모티프·피부 | base | action이 바뀌어도 정체성 고정 |
| 종 고유 도구 | base | 별솔 지팡이, 설화 표본 렌즈처럼 스킬과 항상 함께인 것만 |
| 상·하의·아우터·신발·스타킹·가방 | outfit | garden-daily와 city-night 디자인 유지 |
| 눈깜빡임 | face/blink 코드 | 실제 frame bbox에서 보정한 eye anchor 사용 |
| 빛·꽃잎·먼지·여우불 | effect | back/front pass로 분리 |
| 바닥 그림자 | 코드 | 모든 의상에 공통, 캐릭터 alpha에 굽지 않음 |

의상 프레임에는 사람의 손·손가락·팔·목·얼굴·머리·맨다리·맨발과 이들을 따라간
흰색·크림색 가이드 선이 1px도 없어야 한다. 빈 곳은 투명이어야 한다. base와 의상의
자세가 다르면 가로 이동이나 crop으로 맞추지 않고 해당 프레임을 base 참조
image-to-image 편집부터 다시 만든다.

## 5. 캐릭터 모션 원화표

모든 품종이 같은 걷기 cycle을 색만 바꿔 쓰지 않는다. 공통 action 의미는 유지하되
무게 중심, 준비 동작, 부분 모션을 아래처럼 구분한다.

| 품종 | idle·walk | interact·react | signature `skill` |
|---|---|---|---|
| `baby-pot` | 화분 중심의 작은 통통 뜀, 잎팔 교대 | 두 잎을 모아 크게 응원 | 잎눈이 원을 그리고 준비도 보호막을 감쌈 |
| `handsome-pot` | 곧은 보폭, 숨 뒤 자세를 정돈 | 열린 손으로 행동자를 다시 안내 | 한 걸음 앞으로 나와 길을 정렬 |
| `pretty-pot` | 발끝 중심의 가벼운 반회전 | 꽃받침처럼 팔을 열고 시선 전환 | 무대 막 대신 큰 잎 한 장이 장면을 넘김 |
| `tsundere-pot` | 시선을 피한 채 반 박자 늦게 따라감 | 등을 돌렸다 손만 내밂. 홍조는 호의가 드러난 `react`에만 | 가시 잎이 앞을 막고 본인은 옆을 봄 |
| `zombie-pot` | 어깨·머리가 보폭보다 늦게 따라옴 | 흔적에 귀를 기울인 뒤 천천히 고개 듦 | 달빛 잎맥이 어두운 길만 짧게 비춤 |
| `gumiho-pot` | S자 무게 이동과 꼬리 끝 지연 | 반쯤 감긴 시선, 부채/손끝으로 길 유도 | 꼬리와 여우불이 한 번 감고 숨은 길을 가리킴 |
| `ninja-pot` | 낮은 중심의 빠른 두 걸음, 잎 스카프 지연 | 멈춰 표식을 만지고 즉시 복귀 | 잔상 한 번 뒤 앞 노드 실루엣 공개 |
| `magical-pot` | 지팡이와 옷자락이 낮게 부유 | 지팡이로 요구 능력 표식을 교체 | 별 모양이 아니라 잎 여섯 점이 재배열됨 |
| `aloof-pot` | 진폭이 가장 작은 보행, 곁눈질 | 렌즈를 들고 표본을 확인한 뒤 짧게 끄덕임 | 얇은 잎 격자가 기준치를 감싸며 두 칸 줄어듦 |
| `student-pot` | 급히 걷다 한 번 자세를 바로잡음 | 메모 후 파티 쪽으로 페이지를 돌림 | 체크 두 개가 스킬/길빛 중 선택을 표시 |

성장형은 같은 품종 동작의 리듬을 조절한다.

| form | 실루엣·속도 보정 | effect 방향 |
|---|---|---|
| `sunny` | 위로 열리고 easing-out이 부드러움 | 크림·해바라기색 잎이 바깥으로 |
| `rainy` | 하향 곡선, 옷자락과 잎이 한 박자 늦음 | 남청 물방울이 떨어지지 않고 잔향 원으로 |
| `ember` | 준비가 짧고 전진 정지가 분명함 | 산호 잎이 한 방향으로 갈라짐 |
| `moonlit` | 몸 안쪽에서 시작해 천천히 펼침 | 은보라 초승달이 아닌 덩굴 호 |
| `sparkling` | 좌우 비대칭 bounce와 빠른 회수 | 민트·진주 점이 숨은 방향으로 |
| `mosaic` | 양손·양쪽 무게가 균형을 이룸 | 두 색의 잎이 중앙에서 맞물림 |

감정형은 성공 등급이 아니다. `sunny`만 빠르고 `rainy`만 느려 조작 성능이 달라지지
않도록 action 총 길이 차이는 같은 action 중앙값의 ±15% 이내로 제한한다.

### 5.1 표정 계약

별도의 범용 얼굴 스티커를 피부 위에 덮지 않는다. base action 원화가 표정을 소유하고
outfit은 얼굴 영역을 완전히 비운다. 작은 지도 토큰에서는 눈썹·눈매·입 방향을 크게
읽히게 하고, 사건 초상은 기존 고해상도 `idle|diary|grow`를 다음처럼 매핑한다.

| 상태 | 지도 action 표정 | 사건 초상 pose |
|---|---|---|
| 대기·이동 | 품종 기본 표정, 이동은 시선만 진행 방향 | `idle` |
| 단서 확인 | 눈을 좁히거나 크게 뜨는 집중 | `diary` |
| 스킬 | 힘주는 얼굴이 아니라 결심·확신 | `diary` 후 effect |
| `flourish|clear` | 캐릭터다운 기쁨·안도 | `grow` |
| `detour` | 짧은 난처함 뒤 다시 집중 | `diary` |
| `safe`·귀환 | 긴장이 풀린 작은 미소 | `idle` 또는 `grow` |
| 준비도 낮음 | 졸림·숨 고르기. 병듦·공포 금지 | `idle` + `tired` 리듬 |

- blink는 `idle|walk|tired`에서만 독립 overlay로 사용하고 3.3~5.7초의 품종별 주기를
  유지한다. `skill|react` 도중 임의 blink로 핵심 표정을 가리지 않는다.
- eye anchor는 원본 v4 좌표를 그대로 쓰지 않고 현재 frame의 얼굴 bbox에서 계산한다.
- 가시로는 기본·이동·집중에서 홍조가 없다. 도움을 들킨 `react`와 일부 sunny/sparkling
  호감 장면에서만 옅은 홍조 overlay를 사용한다.
- 여우비는 반쯤 감긴 직접 시선과 작은 미소를 기본으로 하되 모든 장면을 같은 유혹
  표정으로 만들지 않는다. `interact`는 관찰, `skill`은 자신감, `react`는 여유로 나눈다.
- 뽀또는 눈·입을 과장할 수 있지만 눈물, 겁먹은 얼굴, 성인형 표정 문법을 사용하지 않는다.
- `rainy|moonlit|zombie-pot`의 차분함을 무표정·병색·공포로 표현하지 않는다.

허용 action 전이는 `idle↔walk`, `idle→interact→react→idle`,
`idle→skill→react→idle`, `idle↔tired`, `idle→return`이다. 서버 응답이 늦으면 현재
idle을 유지하고, 중간 action을 건너뛴 경우에도 base/outfit/effect queue를 함께 비운 뒤
같은 idle frame으로 복귀한다.

## 6. 스프라이트 제작 절차

### 6.1 세로 슬라이스

전량 제작 전에 아래 한 조합을 끝까지 만든다.

```text
gumiho-pot / moonlit / city-night
idle → walk → interact → skill → react → tired → return
이끼 낀 기억서고 지도 + 사건 1개 + 여우불 effect + SFX
```

꼬리, 반투명 스타킹, 긴 옷자락, 성숙한 실루엣이 함께 있어 가장 어려운 조합이다.
여기서 pose-lock, strip 규격, 실제 기기 메모리, effect 가독성이 통과하기 전에는
다른 59개 품종×form 조합을 시작하지 않는다. 이어서 `baby-pot/sunny/garden-daily`로
아동 안전성과 작은 체형 pivot을 검증하고 `magical-pot`으로 착의형 base 전신 가림을
확인한다.

### 6.2 base key pose

1. wardrobe의 같은 품종·form `idle|diary|grow` 합성 프리뷰와 원형 v4를 모은다.
2. 7개 action의 실루엣 storyboard를 stick pose로 먼저 승인한다.
3. 기존 base를 참조해 action의 contact, passing, anticipation, impact key pose를
   개별 이미지로 만든다. 한 이미지에 한 캐릭터·한 자세만 둔다.
4. 얼굴, 머리, 식물 모티프, 체형, 피부색, 최소 가림, 광원은 참조에서 바꾸지 않는다.
5. 승인 key pose를 2D bone/mesh rig에 맞추고 in-between을 만든다.
6. 손가락·관절·얼굴 흔들림, 선 두께 변화, 프레임별 색 변화는 100% 확대에서 직접
   정리한다.
7. loop action의 첫/마지막 접선과 발 pivot을 맞춘다.

ImageGen이 key pose에서 안전 필터에 막히면 같은 프롬프트로 반복하거나 우회하지 않는다.
기존 승인 pose를 리깅해 사용하고, wardrobe `PROMPTS.md` 0.5의 고피복/기존 base 유지
규칙을 따른다.

### 6.3 outfit

1. 승인된 base frame과 기존 wardrobe outfit 합성을 함께 참조한다.
2. 새 옷을 디자인하지 않고 garden-daily 또는 city-night의 재단·색·소재를 유지한다.
3. 각 base frame 위에서 의상만 편집한다. 옷 주름은 팔다리 각도와 무게 중심에 맞춘다.
4. base를 제거하고 의상·신발·의상 소품만 남긴다.
5. 반투명 소재는 알파를 낮추지 않는다. 바디가 비치는 시각은 불투명한 픽셀 안의
   명도·색 패턴으로 그려야 레이어 겹침과 압축에서 피부색이 변하지 않는다.
6. base/outfit 합성 overlay를 100%, 지도 실제 크기 96px, 사건 크기 180px에서 본다.

### 6.4 빌드·후처리

계획하는 스크립트는 다음과 같다.

| 스크립트 | 책임 |
|---|---|
| `build_expedition_sprites.py` | PNG frame 정규화, 4×2 strip, WebP 압축, manifest 생성 |
| `build_expedition_effects.py` | back/front pass strip 생성, anchor와 cue 병합 |
| `validate_expedition_assets.py` | 레이어·프레임·크롭·파편·오염·용량 계약 검사 |
| `render_expedition_previews.py` | 실제 크기 GIF/MP4, contact sheet, onion-skin 비교 |
| `validate_expedition_audio.py` | 포맷·LUFS·peak·loop seam·무음 tail 검사 |

후처리는 다음 순서를 고정한다.

```text
원본 읽기 → 정확한 canvas/pivot 정규화 → chroma/alpha 추출
→ 크롭 가장자리에 닿은 비본체 컴포넌트 제거
→ 본체 대비 2% 미만 공중 파편 제거
→ 마젠타/흰 가이드 fringe 제거 → layer ownership 검사
→ strip 조립 → WebP 압축 → manifest/hash → 프리뷰
```

투피스·분리된 신발·꼬리 끝처럼 정상 부품이 있으므로 가장 큰 컴포넌트 하나만 남기는
방식은 금지한다. 크롭선 접촉과 본체 면적 비율을 함께 사용한다.

## 7. effect 제작 규격

### 7.1 렌더 순서

```text
region back → region mid → map links/nodes → effect back
→ shadow → character base → outfit → blink/face → effect front
→ region front → UI
```

effect가 의상 뒤와 앞을 모두 지나가야 하면 `back`과 `front` 두 파일로 나눈다. 한
레이어의 z-order를 프레임 도중 바꾸지 않는다.

### 7.2 종류와 재사용

| 종류 | 제작량 | 방식 | 재사용 원칙 |
|---|---:|---|---|
| 이동 선택 링·경로 pulse·안개 | 공용 1세트 | 코드 벡터 | 지역 palette만 변경 |
| 성장형 스킬 | 6세트 | 8프레임 래스터, 필요 시 back/front | 모든 품종이 같은 form set 사용 |
| 품종 고유 스킬 | 10세트 | 8프레임 래스터 | outfit과 무관하게 같은 anchor 사용 |
| 트리 갈래 accent | 3세트 | 코드 벡터 | 길 읽기/상황 바꾸기/동행 잇기 |
| 판정 결과 | 4세트 | 코드+작은 leaf cutout | flourish/clear/detour/safe, 색만으로 구분 금지 |
| 목표 획득·귀환 | 공용 2세트 | 코드 경로+래스터 잎 | 보상 개수만큼 반복하지 않음 |
| 지역 수호자 반응 | 지역당 1세트 | 래스터 | 수호자 몸과 별도 |
| 전경 분위기 | 지역당 2세트 | 저속 래스터 | 사건 선택을 가리지 않을 때만 |

90개 스킬트리 노드는 새 전신 sprite나 새 effect를 갖지 않는다. 뿌리 badge 10개,
branch badge 30개, 허용 effect module 14개를 조합한다. tier는 잎눈 1~3개로 표시한다.

논리 effect는 성장형 6 + 품종 10 + 판정 결과 4 + 목표/귀환 2 + 수호자 4로 26세트다.
각 세트는 front 한 장을 기본으로 하고 캐릭터 뒤를 지나야 하는 성장형·품종·수호자만
back을 추가한다. runtime raster effect 파일은 최대 46개다. 비어 있는 pass 파일을
수량을 맞추기 위해 만들지 않는다. 이동·안개·갈래 accent는 이 수량에 포함하지 않는
코드 효과다.

### 7.3 effect strip

- 셀 256×256, 4×2, 전체 1024×512 투명 WebP, 최대 8프레임이다.
- anchor는 캐릭터 셀의 `feet`, `chest`, `hand_l`, `hand_r`, `head`, `world` 중 하나와
  normalized offset으로 기록한다.
- 캐릭터 bbox 밖 확장은 일반 스킬 12px, 품종 고유 스킬 20px, 수호자 32px 이하다.
- 동시에 보이는 독립 파티클은 캐릭터당 12개, 화면 전체 24개 이하다.
- `BlendMode.srcOver`를 기본으로 하고 additive bloom, 렌즈 플레어, 색수차는 쓰지 않는다.
- 화면 면적 25% 이상이 한 프레임에서 흰색으로 변하거나, 3Hz 이상 명멸하는 효과를
  금지한다.
- reduced motion은 마지막 형태를 120ms 이하로 fade하고 경로·결과 문구를 즉시
  표시한다. 의미 있는 정보는 particle 궤적에만 넣지 않는다.

### 7.4 이펙트 모양 언어

- 길 읽기: 속이 빈 눈 모양이 아니라 두 잎 사이의 좁은 창과 점선 경로
- 상황 바꾸기: 막힌 선이 휘어 다른 홈에 연결되는 한 번의 변형
- 동행 잇기: 두 캐릭터 사이에 맞물리는 잎 두 장
- 회복: 위로 쏟아지는 빛 대신 화분 가장자리에서 새 잎 한 장이 펴짐
- 목표 확보: 보물 폭발 대신 목표가 천천히 작아져 기록장 표식으로 이동
- detour: 붉은 실패 폭발 대신 길이 옆으로 완만하게 우회하고 준비도 숫자만 갱신

## 8. 지역·수호자·아이템 제작표

출시 지역은 `moss_archive`, `echo_well`, `starlight_seed_vault`,
`heartwood_observatory` 네 곳이다.

| 자산 | 지역당 | 규격 | 제작 방식 |
|---|---:|---|---|
| 지도 back/mid/front | 3 | 1920×1080 WebP | 한 원화를 세 depth로 수작업 분리 |
| 사건 배경 | 6 | 1280×960 WebP | 정적 1장, 중앙·하단 UI 안전영역 |
| 수호자 action | 4 | 256px 셀 8프레임 strip | idle/reveal/respond/resolve |
| 목표 아이템 | 1 | 512×512 투명 WebP | 정적 cutout, hover는 코드 |
| 전경 particle | 2 | 256px 셀 최대 8프레임 | 낮은 대비, 선택 사용 |
| 노드 icon | 공용 8종 | 96×96 코드 벡터 | 지역별 색·작은 모티프만 manifest |

지역 raster는 총 64개다: 지도 12, 사건 24, 수호자 16, 목표 4, particle 8.
현재 `app/assets/adventure`의 다섯 배경은 삭제하지 않고 스타일 기준과 프로토타입
사건 배경으로 사용한다. 직접 탐험 지도용 parallax 원본은 별도 제작한다.

사건 15종마다 배경을 새로 만들지 않는다. 지역별 여섯 배경 key를 콘텐츠 manifest가
공유한다.

| event background key | 쓰임 |
|---|---|
| `route` | 다리·계단·문·바람길 같은 이동 장애물 |
| `device` | 서랍·밸브·거울·시계·렌즈 같은 장치 |
| `specimen` | 씨앗·잎맥·기록·표본 발견 |
| `visitor` | 달팽이·잎손님·물고기·새싹 같은 비폭력 존재 |
| `rest` | 쉼터·대화·준비도 회복 |
| `guardian` | 수호자 단계와 목표 직전 |

한 사건에서 고유한 것은 배경 전체가 아니라 중앙 prop, 수호자/목표 cutout, 문구,
캐릭터 action이다. 각 지역의 핵심 장치 네 개, 총 16개를
`events/props/{event-key}.svg` 96px 벡터로 만든다.

| 지역 | prop event code 4개 |
|---|---|
| 기억서고 | `wet_label_order`, `root_catalogue`, `snail_librarian`, `spore_curtain` |
| 우물정원 | `three_note_echo`, `reed_valve`, `sleeping_bellfish`, `water_chime_gate` |
| 보관고 | `tilted_star_mirror`, `backward_clock_hand`, `constellation_tubes`, `dormant_sprout_array` |
| 관측실 | `split_growth_ring`, `four_season_lens`, `overlapping_compass`, `sealed_field_note` |

나머지 사건은 이 prop을 같은 지역 안에서 재사용하거나 배경·문구·선택 아이콘으로
구분한다. prop 모양에만 판정 정보가 들어가서는 안 된다.

지역별 shot list는 다음을 고정한다.

| 지역 | 지도 중심 실루엣 | 수호자 | 목표 | 입자 |
|---|---|---|---|---|
| 이끼 낀 기억서고 | 둥근 서고문·낮은 표본 서랍 | 이끼 책등지기 | 봉인된 압화 표본 | 먼지, 작은 이끼 조각 |
| 메아리 우물정원 | 우물에서 네 갈래 수로 | 물결 청음초 | 메아리 씨앗병 | 수면 고리, 달꽃 잎 |
| 별빛 씨앗 보관고 | 지붕 온실·발아대 | 구리 발아지기 | 새벽 보관병 | 씨앗 껍질, 유리 빛점 |
| 마음나무 관측실 | 나무줄기·측정 원형대 | 나이테 기록자 | 마음나무 관측판 | 종이 섬유, 작은 잎맥 |

수호자는 공격받거나 쓰러지는 프레임을 갖지 않는다. `respond`는 사용자의 방법을
확인하고, `resolve`는 길을 열거나 몸을 비키는 동작이다.

## 9. UI 아이콘과 스킬트리

- node 8종, resource 4종, 결과 4종, 안전/저장/연결 6종은 Flutter vector path 또는
  기존 Material icon을 감싼 프로젝트 전용 벡터로 만든다. 이 22개는 별도 래스터
  파일이 아니라 semantic icon definition이다.
- 품종 root badge 10개와 branch badge 30개는 64×64 master SVG로 만들고 필요 시
  1x/2x WebP를 빌드한다.
- 허용 effect module 14개는 32×32 glyph다. 90개 노드는 badge, branch, tier,
  module glyph, 이름 조합으로 표현한다.
- 인벤토리에는 기존 탐험 재료 8개의 64×64 SVG가 필요하다.

| 분류 | 코드 |
|---|---|
| 자동 순찰 재료 | `pressed_leaf_map`, `moon_dew`, `glass_leaf_vein`, `dawn_bark_rubbing` |
| 지역 목표 재료 | `moss_key`, `echo_seed`, `starlight_pollen`, `heartwood_seed_sample` |

지역 목표 4개 아이콘은 512×512 목표 item master에서 단순화해 파생하고, 순찰 재료
4개는 같은 재료 문법으로 새 SVG를 그린다. 수량이나 등급 숫자는 이미지에 넣지 않는다.
- 연구 도구 `pressed_leaf_guide`, `echo_listener`, `memory_case`, `starlight_clock`,
  `outside_atlas`는 64×64 SVG 5개를 만든다. 도구를 해금한 재료 아이콘과 혼동되지
  않도록 테두리가 있는 실제 도구 실루엣으로 구분한다.
- discovery 32개마다 별도 item icon을 만들지 않는다. 사건 배경 thumbnail, 공용
  discovery glyph, localized title을 조합한다.
- 외곽선은 64px에서 2px, 32px에서 optical 1.5px로 보정한다.
- 비활성은 opacity만 낮추지 않고 비어 있는 잎눈과 점선 가지를 함께 쓴다.
- 아이콘 안에 숫자와 문자를 굽지 않는다.

출시 master SVG는 badge·module 54개 + 재료 8개 + 도구 5개 + 사건 prop 16개로
83개다. 코드 기반 semantic icon 22개를 합치면 검수할 의미 단위는 105개다.

## 10. ImageGen 사용과 원화 통제

### 10.1 사용하는 곳

- 지역 전체의 스타일 승인용 콘셉트 1장
- 사건 배경의 구도 초안
- 수호자와 목표 아이템의 정면/3분기 turnaround
- 기존 성체 base를 참조한 action key pose 초안

### 10.2 사용하지 않는 곳

- 8프레임 완성 sprite strip을 한 번에 생성
- outfit을 base 없이 새로 생성
- 글자·UI·스탯 아이콘
- 경로선·선택 링·안개 같은 코드로 정확히 만들 수 있는 도형
- 프레임 사이 보간과 최종 edge cleanup

### 10.3 프롬프트와 이력

각 원본은 manifest에 다음을 남긴다.

```json
{
  "asset_id": "character.gumiho-pot.moonlit.skill.key-02",
  "source_type": "image_to_image",
  "references": ["sha256:...", "sha256:..."],
  "prompt_file": "ADVENTURE_ASSET_PROMPTS.md#캐릭터-action-key-pose",
  "generated_at": "2026-08-04T00:00:00Z",
  "review": {"identity": true, "pose": true, "safety": true},
  "license_note": "project-owned references only"
}
```

사용자의 일기 원문, 감정 분석 문장, 이름 같은 개인정보를 프롬프트에 넣지 않는다.
특정 현존 작가나 저작권 캐릭터의 스타일을 요구하지 않는다. 필터를 우회하거나 같은
실패 프롬프트를 반복하지 않는다. `baby-pot`은 모든 pose와 의상에서 비성적
마스코트이며 성인 노출 지시를 절대 공유하지 않는다.

## 11. 오디오 제작 실행안

### 11.1 파일 수와 역할

| 분류 | 수량 | 런타임 |
|---|---:|---|
| 지역 BGM | 4 | AAC-LC `.m4a`, stereo |
| 수호자 stem | 4 | AAC-LC `.m4a`, stereo |
| 지역 ambience | 8 | AAC-LC `.m4a`, stereo |
| 발걸음·화분 재질 | 4 | PCM16 `.wav`, mono |
| 발견 일반/이야기/목표 | 3 | PCM16 `.wav`, mono |
| 품종 signature | 10 | PCM16 `.wav`, mono |
| 스킬 갈래 accent | 3 | PCM16 `.wav`, mono |
| UI 확정·회복·저장·귀환 | 4 | PCM16 `.wav`, mono |

출시 오디오는 총 40개다. 90개 트리 노드의 별도 음원은 만들지 않는다.

### 11.2 제작·마스터링

- 원본 master는 48kHz/24bit WAV로 보관한다.
- BGM은 60~90초 seamless loop, -18~-16 LUFS, true peak -2dBTP 이하다.
- ambience는 15초 이상, -28~-24 LUFS로 만들고 반복 지점을 무음이 아니라 실제
  질감의 zero crossing에 둔다.
- 짧은 SFX는 700ms 이하, -20~-16 LUFS 범위에서 품종 간 체감 크기를 맞춘다.
- `skill` manifest의 cue frame과 소리의 첫 명확한 transient 차이는 50ms 이하다.
- 세 캐릭터가 연속 반응해도 같은 signature를 120ms 안에 중복 재생하지 않는다.
- 효과음은 직접 녹음한 종이·나무·도자기·마른 잎 foley와 단순 synth를 조합한다.
  출처와 라이선스가 불명확한 음원, 과한 판타지 whoosh, 금속 전투 타격음은 쓰지 않는다.
- 일기 작성 화면에는 BGM과 입력음을 넣지 않는다.

오디오의 감정형 차이는 장·단조 우열로 만들지 않는다. `rainy`가 불협화음이거나
`ember`가 더 큰 음량이 되지 않도록 음량·길이 예산을 같다.

## 12. 런타임·프리로드·메모리

- 512×384 RGBA strip 하나의 decoded 상한은 약 0.75MB다.
- 현재 동작과 다음 동작만 base/outfit 각각 preload한다. 일반 파티 3명 기준
  `3명 × 2동작 × 2레이어 × 0.75MB = 약 9MB`다.
- 인접 사건 배경은 다음 후보 2장까지만 decode하고, 지나간 배경은 캐시 압력에 따라
  해제한다.
- 지도 back/mid/front는 화면 크기에 맞는 `cacheWidth`로 decode한다. 1920 원본을
  360px 기기에서도 원본 크기로 풀지 않는다.
- 프레임 전환은 `gaplessPlayback`과 동일 frame index의 원자적 base/outfit swap을
  사용한다. 캐릭터 전체 opacity를 0으로 만드는 교차 fade는 쓰지 않는다.
- action 전환은 이전 action의 종료 pose와 다음 action 첫 pose를 같은 pivot에 둔다.
  네트워크 지연 중에는 idle을 유지하고 base만 먼저 바꾸지 않는다.
- 파티가 60fps를 안정적으로 유지하지 못하는 기기에서는 frame duration을 유지한 채
  30fps ticker로 낮춘다. 프레임을 건너뛰어 몸과 의상 index가 달라지면 안 된다.

압축 목표는 stage 5 캐릭터 1260 strip 전체 24MB 이하다. 이는 strip당 평균 약
19KB이고 hard limit는 30KB다. hard limit를 넘으면 프레임을 삭제하지 않고 96px에서
보이지 않는 종이 질감, 유사색, 내부 노이즈를 줄인다. 지역 raster는 16MB, 오디오는
12MB, effect는 4MB, UI vector/WebP 파생본은 1MB 이하를 목표로 한다. 직접 탐험의
신규 install 증가량은 합계 57MB 이하가 release gate다. 기존 wardrobe 약 45MB는 사건
초상에 재사용하고 탐험용으로 복제하지 않는다. Android App Bundle의 압축 후 실제
증가량도 release report에 별도로 기록한다.

### 12.1 배포 팩

현재 `app/assets` 원본은 약 138MB이므로 신규 57MB를 모두 기본 번들에 넣지 않는다.
같은 `asset-manifest.json` 경로 계약을 유지하되 빌드 산출물을 다음 팩으로 나눈다.

| pack | 내용 | 압축 목표 | 설치 시점 |
|---|---|---:|---|
| `expedition-core-v1` | stage 5 base 420 strip, 공용/form/signature effect, UI, 공용 SFX 24개 | 17MB | 앱 기본 또는 기능 첫 진입 전 |
| `expedition-outfit-garden-daily-v1` | 해당 outfit 420 strip | 8MB | 소유 의상으로 첫 출발 전 |
| `expedition-outfit-city-night-v1` | 해당 outfit 420 strip | 8MB | 소유 의상으로 첫 출발 전 |
| `expedition-region-{region}-v1` | 지역 raster 16개, BGM 1·stem 1·ambience 2 | 지역당 6MB | 지역 해금 또는 첫 진입 시 |

Android/iOS에서 동작을 다르게 만들지 않기 위해 플랫폼 전용 asset delivery보다 앱
관리형 versioned pack cache를 기본으로 한다. 서버/CDN manifest는 `pack_id`, `version`,
`compressed_bytes`, `sha256`, `files`, `minimum_app_version`, `signature`를 제공한다.
앱은 포함된 공개키로 manifest 서명을 확인한 뒤에만 pack을 받는다.

```text
다운로드 .part → 전체 sha256 확인 → 임시 디렉터리에 안전하게 해제
→ 파일별 hash 확인 → version 디렉터리 원자적 rename → active manifest 교체
```

- zip entry의 절대 경로와 `..`를 거절하고 application support의 expedition cache
  아래만 쓴다.
- 진행 중 run이 참조하는 pack version은 삭제하지 않는다. 새 version은 다음 run부터
  사용한다.
- 지역·의상 pack이 준비되지 않았으면 출발 버튼에 정확한 용량과 진행률을 표시한다.
  다운로드 중 캐릭터 base만 먼저 보이는 화면으로 넘어가지 않는다.
- 네트워크 오류나 오프라인이면 기존 512×768 성장 원화 또는 wardrobe의 base+outfit
  합성을 한 덩어리로 사용한 정적 지도 토큰으로 탐험할 수 있다. 의상을 벗겨 보이는
  fallback은 금지한다.
- 정적 fallback에서도 이동 위치, 사건 결과, blink 중단 상태는 동일하고 보상·판정은
  달라지지 않는다. pack 준비 뒤 다음 action 경계에서 원자적으로 animation으로 바꾼다.
- 설정의 저장 공간 화면에서 미사용 지역·의상 팩만 지울 수 있다. core와 active run
  pack은 삭제하지 않는다.
- `ExpeditionAssetResolver`는 같은 논리 path를 bundled `AssetImage`, 검증된 cache의
  `FileImage`, 정적 fallback 중 하나로 해석한다. 화면 widget이 CDN URL이나 로컬 pack
  경로를 직접 조합하지 않는다.

## 13. 기계 판독 manifest

`asset-manifest.json`의 최소 항목은 다음과 같다.

```json
{
  "schema_version": 1,
  "id": "character.gumiho-pot.moonlit.city-night.skill",
  "path": "characters/gumiho-pot/outfits/city-night/moonlit/skill.webp",
  "canvas": [512, 384],
  "cell": [128, 192],
  "layout": [4, 2],
  "frame_count": 8,
  "durations_ms": [90, 90, 110, 150, 180, 140, 110, 100],
  "loop": false,
  "pivot": [64, 180],
  "anchors": {"face": [64, 48], "hand_r": [83, 91]},
  "effect_cue_frame": 4,
  "layer": "outfit",
  "paired_base": "character.gumiho-pot.moonlit.base.skill",
  "reduced_motion_frame": 5,
  "byte_size": 18420,
  "sha256": "..."
}
```

앱의 enum과 파일명을 수동으로 이중 관리하지 않는다. builder가 manifest에서 Dart asset
index를 생성하고, 없는 action·form·outfit은 CI에서 실패시킨다.

## 14. 자동 검수

### 14.1 정적 검사

- 모든 PNG/WebP의 canvas, alpha, 색공간, 파일명, frame count 일치
- 투명 영역의 `#FF00FF` 오염과 1~2px 흰색·크림색 guide fringe 0
- 크롭 가장자리에 닿은 비본체 컴포넌트 0
- 본체 대비 2% 미만 공중 파편 0. 단, 안쪽 motif allowlist가 아니라 source mask로 증명
- outfit의 얼굴·피부·손·발 픽셀 0
- base/outfit alpha pose-lock 거리 2px 이하
- 연속 프레임 bbox 높이 변화 4% 이하, 중심축 흔들림 2px 이하
- 걷기 접지 발 pivot slip 3px 이하
- loop 첫/끝 속도 불연속 15% 이하
- 프레임별 얼굴 landmark 편차 2px 이하
- manifest cue, duration, paired layer, 파일 hash 누락 0
- strip 30KB, effect 100KB, region 개별 450KB hard limit 준수

프레임 하나에 이름을 박은 예외 상수로 검사를 무력화하지 않는다. 품종별 차이가 실제
규칙이면 manifest의 구조화된 `motion_profile`이나 `layer_ownership`으로 설명하고 전
프레임에 같은 검사를 적용한다.

### 14.2 시각 검사

builder는 다음 QA 산출물을 임시 디렉터리에 만든다.

- 10품종×6형×7 action base contact sheet
- 두 의상 합성 contact sheet
- 96px 1배속, 0.25배속 loop 영상
- base는 청록, outfit은 주황으로 칠한 onion-skin pose 비교
- effect back/base/outfit/front를 각각 켜고 끈 compositing preview
- region별 320×640, 390×844, tablet landscape 화면
- reduced motion 정지 상태와 스크린리더 label 목록

사람이 반드시 보는 고위험 조합은 여우비의 꼬리·시스루·moonlit 스타킹, 블루미
ember 스타킹, 별솔의 전신 슈트, 뽀또의 모든 form, 가시로의 상시 홍조 여부, 긴
소매·긴 치마가 있는 모든 walk다.

### 14.3 실제 기기 검사

Android 저사양 1대, 기준 Android 1대, iPhone 1대에서 다음을 녹화한다.

1. 세 캐릭터 idle 30초 동안 호흡·blink·부분 모션
2. 20개 노드 연속 이동과 방향 전환
3. `idle → interact → react → idle`, `idle → skill → react → idle`
4. 의상 두 벌을 다음 run에서 교체한 뒤 같은 경로 반복
5. 수호자 4 action과 목표 획득, 귀환
6. 앱 백그라운드·복귀, 네트워크 지연, 움직임 줄이기 전환

합격 기준은 레이어 이탈·바디 단독 flash·잘린 꼬리/손발·눈 밖 blink 0, 30분 동안
OOM 0, 기준 기기 p95 frame time 16.7ms 이하, 저사양 30fps 유지다. 문제가 있으면
`품종/form/outfit/action/frame index/기기`를 기록한다.

## 15. 제작 순서와 완료 gate

| 단계 | 산출물 | 다음 단계로 가는 조건 |
|---|---|---|
| P0 규격 | manifest schema, builder skeleton, 코드 vector prototype | 빈 샘플로 CI 동작 |
| P1 세로 슬라이스 | 여우비 moonlit city-night 7 action, 1지역, 1수호자, 음향 | 자동 위반 0, 실제 기기 10분 |
| P2 안전 슬라이스 | 뽀또 sunny, 별솔 covered base | 아동/착의형 계약 위반 0 |
| P3 캐릭터 base | 10종×6형×7 action | base 420 strip 위반 0 |
| P4 의상 | garden-daily, city-night | outfit 840 strip, 합성 위반 0 |
| P5 effect·UI | 논리 effect 26세트·runtime 최대 46, branch 코드 3, SVG 83·코드 icon 22 | reduced motion/광과민 검사 통과 |
| P6 지역 | 네 지역 raster 64개 | 안전영역·가독성·크롭 통과 |
| P7 오디오 | 40개 runtime 파일 | loudness·loop·focus 통과 |
| P8 통합 | 네 지역 E2E, device recording, 성능 report | 모든 출시 gate 통과 |

P3부터는 품종 하나를 base 7 action → 두 outfit 14 action → effect 합성 → QA 순서로
완료한 뒤 다음 품종으로 간다. base만 열 종 만든 뒤 의상을 한꺼번에 시작하면 pose
오류를 늦게 발견하므로 금지한다.

### 15.1 실제 작업량

action 한 세트의 사용 프레임 합은 48개다. 따라서 숫자는 다음과 같다.

| 작업 | 계산 | 수량 |
|---|---|---:|
| stage 5 base runtime frame | 10품종×6형×48 | 2,880 |
| outfit runtime frame | 2벌×10품종×6형×48 | 5,760 |
| 캐릭터 runtime frame 합계 | base+outfit | 8,640 |
| 캐릭터 runtime strip | base+두 의상 세트(3)×10×6×7 | 1,260 |
| base key pose | action당 2/4/3/4/3/2/4 = 22×60조합 | 1,320 |
| outfit key pose 편집 | 1,320×2벌 | 2,640 |
| guardian frame | 4지역×4action×8 | 128 |
| 논리 effect frame 상한 | 26세트×8 | 208 |

8,640장을 독립 원화로 그리는 계획이 아니다. 3,960개의 승인 base/outfit key pose를
만들고 같은 rig로 in-between을 낸 뒤 모든 runtime frame을 검수하는 계획이다. 그래도
작은 부가 기능 수준의 작업량은 아니므로 P1 세로 슬라이스가 재미·가독성·성능을
입증하지 못하면 전량 제작을 승인하지 않는다.

역할은 다음 책임으로 나눈다. 한 사람이 모두 맡더라도 gate를 섞지 않는다.

| 책임 | 승인하는 것 |
|---|---|
| 아트 디렉션 | 품종·form 정체성, 배경 palette, AI스럽지 않은 절제 |
| 2D 애니메이션 | key pose, 무게 중심, loop, 표정, 고유 motion |
| 테크니컬 아트 | base/outfit/effect 분리, strip, anchor, 압축, validator |
| UI 일러스트 | SVG 83, code icon 22, 48/64/96px 가독성 |
| 사운드 | 원본·라이선스, 40개 납품, cue·loudness·loop |
| Flutter 통합 | pack resolver, preload, atomic swap, reduced motion, device QA |

## 16. CI와 완료 정의

다음 경로가 바뀌면 임시 output root로 전체 build와 validator를 실행한다.

```text
design-system/concepts/expedition-v1/**
design-system/scripts/build_expedition_*.py
design-system/scripts/validate_expedition_*.py
design-system/EXPEDITION_ASSET_PRODUCTION.md
app/lib/**/expedition_character.dart
```

CI는 생성된 래스터를 커밋하지 않고 manifest와 위반 report만 검사한다. release asset
갱신 PR에서는 빌드 출력 hash가 커밋된 `app/assets/expedition`과 같은지도 검사한다.

완료 조건은 다음과 같다.

- stage 2~4가 기존 성장 정체성을 유지하고 transform fallback이 명시적으로 동작한다.
- stage 5 base 420, 두 의상 840 runtime strip이 모두 존재한다.
- 캐릭터·의상·effect의 frame index와 anchor가 하나의 manifest로 동기화된다.
- 열 품종의 고유 모션과 여섯 성장형 리듬이 실제 크기에서도 구분된다.
- 논리 effect 26세트가 모두 있고 runtime pass는 46파일을 넘지 않는다.
- region raster 64, UI SVG 83·코드 icon 22, audio 40의 누락이 없다.
- edge fragment, outfit body pixel, pose-lock, pivot slip, alpha fringe 위반이 모두 0이다.
- 움직임 줄이기와 무음으로도 같은 선택과 결과를 이해할 수 있다.
- ImageGen 원본은 참조·프롬프트·검수 이력이 있고 최종 프레임은 수작업/자동 QA를
  통과한다.
- 실제 기기에서 의상 이탈, blink 오프셋, 교체 flash, 프레임 드롭이 없다.
