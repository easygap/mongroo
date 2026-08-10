# 직접 탐험 에셋·이펙트·오디오 제작 실행서

최종 갱신: 2026-08-10
상태: 몰입형 스테이지 전투 정식 제작 계약
대상 버전: `stage-battle-v2.2` / `character-skill-growth-v1.3`

이 문서는 `docs/expedition_stage_redesign.md`와
`docs/character_skill_growth_design.md`의 그래픽·오디오 계약을 실제로 제작할 수 있는
단위로 풀어 쓴다. `interactive_adventure_design.md`의 이전 수량·Canvas 표현과
충돌하면 이 문서가 우선한다. 캐릭터 원형은 `MONGROO_GROWTH_ART.md`, 성체
의상 레이어는 `concepts/wardrobe-v1/README.md`, 배경 원화 기록은
`ADVENTURE_ASSET_PROMPTS.md`, 음향 원칙은 `ADVENTURE_AUDIO.md`를 따른다. 2026 시장과
최신 게임 사례에서 도출한 제작 우선순위는
`../docs/adventure_game_trend_review_2026.md`를 참고하되, 실제 파일 수와 합격선은 이
문서가 단일 원본이다.

## 1. 먼저 고정할 결정

1. 탐험 캐릭터는 `base → outfit → face/blink → effect` 순서로 합성한다. 효과를
   캐릭터나 의상 그림에 구워 넣지 않는다.
2. stage 2~4의 idle·걷기·사건 대기는 기존 512×768 성장 원화를 재사용할 수 있다.
   그러나 전투의 `anticipate·cast·guard·hit·recovery`는 정적 원화를 흔드는 transform으로
   대신하지 않고 최소 4~6 pose frame을 갖는다.
3. stage 5는 움직임과 의상 식별이 중요한 완전체이므로 7개 action의 프레임
   애니메이션을 만든다. 의상은 wardrobe v2와 마찬가지로 같은 자세의 base를
   참조해 편집하고 사람의 피부·얼굴·팔다리를 포함하지 않는다.
4. stage 5 미만은 고유 성장 의상을 그대로 사용하며 탐험 wardrobe loadout을
   장착하지 않는다. 이 규칙은 성장기 캐릭터에 성체 의상을 억지로 합성하거나,
   화면에는 안 보이는 의상 성능만 적용되는 문제를 함께 막는다.
5. ImageGen은 지역·캐릭터 key pose뿐 아니라 덩굴·불꽃·서리·칼날·몬스터 발사체의
   **투명 공격 키프레임** 제작에 사용한다. 최종 8~16프레임 시트를 한 번에 생성하지
   않고, 앞선 승인 프레임을 참조해 핵심 단계별로 만든 뒤 2D 리깅·in-between·수작업
   클린업으로 연속성을 고정한다.
6. 지도선·선택 링·안개 마스크·스킬트리 가지·상태 표시는 코드 벡터로 그린다.
   캐릭터, 일반 적, 수호자, 유기적 공격 본체, impact, 피격 파편은 래스터로 만든다.
   코드 원·선·path·gradient 조합은 유기적 공격이나 몬스터의 정식 에셋이 될 수 없다.
7. 이미지에는 글자를 넣지 않는다. 이름·수치·사건 문장은 localization 리소스가
   소유한다.
8. 화려함은 픽셀 수나 섬광으로 표현하지 않는다. 한 효과는 주색 1개, 보조색
   1개, 크림색 하이라이트까지만 사용한다.
9. 플레이어와 적은 같은 품질 gate를 통과한다. 플레이어 고유 스킬만 제작하고 적은
   공용 파동이나 화면 흔들림으로 끝내지 않는다.
10. prototype은 앱에서 `PLACEHOLDER` 배지와 manifest `production_ready:false`를
    가진다. prototype이 보이는 빌드는 아트 완료율·스토어 스크린샷·릴리스 후보에서 제외한다.
11. 기본 모험의 지역 화면은 `backplate → midground → floor/shadow → actor → VFX →
    foreground → HUD`가 한 카메라에서 이어지는 **전투 중심 무대 패키지**다. 지도·사건·
    결과를 각각 불투명 배경 카드로 다시 만들지 않는다.
12. `design-system/concepts/adventure-combat-first-v1/combat-first-visual-target-v1.png`는
    전장 점유율·배치·깊이·공격 경로를 확인하는 ImageGen 시각 기준안이다. 이 PNG의 HUD나
    포즈를 그대로 잘라 런타임 에셋으로 쓰지 않는다.

## 2. 화면별 자산 사용표

| 화면 | 캐릭터 | 배경·오브젝트 | 효과 |
|---|---|---|---|
| 파티 편성 | 기존 512×768 성장 원화 또는 wardrobe 합성 | 코드 UI | 선택 링, 스탯 변화만 코드 |
| 기본 모험 접근·전진 | 전투와 같은 actor, walk/turn pose | 같은 지역의 back/mid/floor/front 무대 | 이동 먼지, 랜드마크 반응, stem 전환 |
| 깊은 조사 이동 | 72~112px 토큰. stage 2~4 transform, stage 5 frame strip | 현재 장소 원화 + 보조 경로 지도 | 이동 먼지, 발견 잎, 장면 교차 전환 |
| 사건 선택 | 144~220px 기존 원화/wardrobe pose | 전투와 같은 무대 + 사건 prop cutout | 표정·blink, 오브젝트 반응, 결과 accent |
| 일반 전투 | 아군 3명 actor pose, 엉킴 idle/attack/hit/release | 한 장의 연속 전장 배경·바닥 | 플레이어 4스킬·적별 공격·impact·피격 반응 |
| 수호자 | 아군 3명 actor pose | 수호자 idle/anticipate/attack/hit/release | 지역별 공격 2종·장벽 파괴·풀림 |
| 목표 확보 | 파티 토큰 | 목표 아이템 cutout | 작은 부유·획득 궤적 |
| 귀환 결과 | 최대 3명 `return` 또는 기존 성장 원화 | 지역 지도 blur 없이 정지 | 획득 항목당 1회가 아닌 장면당 1회 |
| 스킬트리 | 기존 초상 | 코드 가지 | root/branch badge, 발동 미리보기 |

지도 토큰을 사건 초상 크기로 확대하지 않고, 사건 초상을 작은 지도 시트로 대체하지
않는다. 두 렌더의 역할과 해상도가 다르다.

## 3. 원본과 출력 디렉터리

```text
design-system/concepts/expedition-v1/
  manifest.source.json
  model-sheets/{player|enemy}/{family-code}.md
  references/
    style/
    characters/{species}/
    regions/{region}/
  characters/{species}/
    stage5/base/{form}/{action}/frame-00.png
    stage5/outfits/{outfit-key}/{form}/{action}/frame-00.png
  effects/
    forms/{form}/{back|front}/frame-00.png
    signatures/{species}/{path|guard}/{tier}/{cast|travel|impact}/frame-00.png
    enemies/{enemy-key}/{attack-key}/{cast|travel|impact}/frame-00.png
    common/{effect-key}/frame-00.png
  combat/
    actors/{species}/{path|guard}/{action}/frame-00.png
    tangles/{region}/{enemy-key}/{idle|anticipate|attack|hit|release}/frame-00.png
  regions/{region}/
    map/overview.png
    scenes/{scene-key}.png
    events/{event-key}.png
    guardian/{action}/frame-00.png
    target.png
    particles/{particle-key}/frame-00.png
  ui/
    badges/{root|branch|module}/...
    items/...
    tools/...
    event-props/{region}/{event-key}.svg

design-system/concepts/character-skill-vfx-v1/
  icons/sources/signature/{family-code}/t{tier}.png
  icons/sources/emotion/{form}.png
  icons/sources/book/{book-code}.png
  icons/qa/{icon-code}-{sizes|grayscale|battlefields}.webp

design-system/concepts/adventure-combat-first-v1/
  combat-first-visual-target-v1.png
  README.md

app/assets/expedition/
  asset-manifest.json
  characters/{species}/base/{form}/{action}.webp
  characters/{species}/outfits/{outfit-key}/{form}/{action}.webp
  effects/{category}/{key}/{back|front}.webp
  combat/actors/{species}/{path|guard}/{action}.webp
  combat/tangles/{enemy-key}/{action}.webp
  combat/enemies/{enemy-key}/{attack-key}/frame-00.webp
  regions/{region}/map-overview.webp
  regions/{region}/scenes/{scene-key}.webp
  regions/{region}/events/{event-key}.webp
  regions/{region}/guardian/{action}.webp
  regions/{region}/target.webp
  regions/{region}/particles/{particle-key}.webp
  ui/{badges|items|tools|event-props}/...
  audio/{music|ambience|sfx}/...

app/assets/adventure/skills/
  icon-manifest.json
  icons/signature/{family-code}/t{tier}-{128|64}.webp
  icons/emotion/{form}-{128|64}.webp
  icons/book/{book-code}-{128|64}.webp
```

원본 PNG는 수정 이력과 검수를 위해 보존하고, 앱은 빌드된 WebP와 오디오 런타임
파일만 읽는다. `app/assets/expedition` 파일을 손으로 수정하지 않는다.
기억서고 M1은 기존 번들 경로와의 호환을 위해 임시로
`app/assets/adventure/expedition-*.webp`를 읽는다. 지역 팩 분리 시 동일 `scene_key`를
`app/assets/expedition/regions/moss_archive/scenes/`로 이관하고 콘텐츠 코드는 바꾸지 않는다.

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
| `flourish\|clear` | 캐릭터다운 기쁨·안도 | `grow` |
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
| `build_combat_attack_assets.py` | 프레임별 RGBA master를 atlas/WebP로 빌드하고 release/travel/contact/reaction event 병합 |
| `validate_expedition_assets.py` | 레이어·프레임·크롭·파편·오염·용량 계약 검사 |
| `validate_combat_continuity.py` | 키프레임 본체 두께·부품 수·광원·pivot·event 순서·production flag 검사 |
| `render_expedition_previews.py` | 실제 크기 GIF/MP4, contact sheet, onion-skin 비교 |
| `validate_expedition_audio.py` | 포맷·LUFS·peak·loop seam·무음 tail 검사 |

후처리는 다음 순서를 고정한다.

```text
원본 읽기 → 정확한 canvas/pivot 정규화 → chroma/alpha 추출
→ 크롭 가장자리에 닿은 비본체 컴포넌트 제거
→ 본체 대비 2% 미만 비의도 공중 파편 제거
→ 마젠타/흰 가이드 fringe 제거 → layer ownership 검사
→ strip 조립 → WebP 압축 → manifest/hash → 프리뷰
```

투피스·분리된 신발·꼬리 끝처럼 정상 부품이 있으므로 가장 큰 컴포넌트 하나만 남기는
방식은 금지한다. 크롭선 접촉과 본체 면적 비율을 함께 사용한다.

## 7. effect 제작 규격

### 7.1 렌더 순서

```text
region backplate(graded) → far ambience → midground(graded) → floor(graded)
→ route overlay(optional) → effect back → contact shadow → character base → outfit → blink/face
→ projectile body → contact/impact → reaction debris → effect front
→ foreground occluder(graded) → HUD
```

effect가 의상 뒤와 앞을 모두 지나가야 하면 `back`과 `front` 두 파일로 나눈다. 한
레이어의 z-order를 프레임 도중 바꾸지 않는다.

#### 7.1.1 알파·블렌딩·깊이 계약

- source master는 **straight-alpha RGBA PNG**다. 사람이 RGB를 미리 premultiply하지
  않으며, 런타임 디코더가 premultiplied texture를 만들면 build report에 기록한다. 같은
  파일을 두 번 premultiply해 생기는 검은 테두리는 출시 차단이다.
- 기본 blend는 `srcOver`다. `multiply`는 바닥 접촉 그림자에만 opacity 10~35%로 쓰고,
  `screen`은 contact 핵심광처럼 화면 면적 4% 미만·120ms 이하인 한 pass에만 허용한다.
  additive bloom, color dodge, 렌즈 플레어, 화면 전체 overlay는 쓰지 않는다.
- 캐릭터 그림자는 캐릭터와 분리한 타원/형상 mask이며 발 pivot 아래에 붙는다. 공격 자체가
  바닥에 닿는 순간만 별도 contact shadow를 켜고, 원화에 구운 그림자와 동시 사용하지 않는다.
- 덩굴이 캐릭터 뒤에서 출발해 앞으로 감기는 효과는 하나의 sprite z-order를 바꾸지 않고
  `effect back`과 `projectile/effect front` 두 pass로 분리한다. target depth mask가 몸통·
  팔·앞잎의 가림 순서를 소유한다.
- 모든 atlas cell은 투명 padding 4px, edge color extrusion 2px를 갖고 bilinear 축소에서도
  이웃 프레임 색이 새지 않아야 한다. crop bbox가 달라도 pivot·origin·contact anchor는
  논리 좌표로 고정한다.
- ImageGen chroma 원본은 soft-matte·despill 뒤 key color 잔류 0을 확인한다. 밝은 배경,
  어두운 배경, region palette 네 곳에서 200% 확대했을 때 녹색/자홍 fringe와 흰 halo가
  보이면 paint-over로 고치며 blur로 숨기지 않는다.
- region color grade는 back/mid/floor/foreground를 같은 값으로 묶되 HUD에는 적용하지
  않는다. actor에는 현장광 tint 8~16%와 rim 1개만 별도 적용하고, VFX 고유색과 약점 glyph는
  색 인지가 바뀌지 않도록 grade 뒤에 합성한다.
- 카메라 parallax 계수는 `back 0.15 · mid 0.45 · floor/actor 1.0 · front 1.12`를 기본으로
  하고 3.5px 이하 shake는 floor부터 front까지만 적용한다. HUD와 long-press drawer는 흔들지 않는다.

### 7.2 종류와 재사용

| 종류 | 제작량 | 방식 | 재사용 원칙 |
|---|---:|---|---|
| 이동 선택 링·경로 pulse·안개 | 공용 1세트 | 코드 벡터 | 지역 palette만 변경 |
| 성장형 탐험 스킬 | 6세트 | 8프레임 래스터, 필요 시 back/front | 모든 품종이 같은 form set 사용 |
| 감정 전투 스킬 | 6 family | 10프레임 RGBA VFX + 품종별 공용 cast pose 4F | 탐험 family와 모티프를 공유하되 전투 contact·impact는 별도 제작 |
| 품종 고유 I·II | 20 family × 3tier | 10~12프레임 RGBA VFX + 8 pose frame | family끼리 공격 본체 공유 금지. T2 overlay만 같은 family T1 위에 합성 |
| 기록서 전투 모듈 | 12세트 | 10프레임 RGBA | 표지 문양만 바꾸되 고유 스킬보다 낮은 우선순위 |
| 일반 엉킴 공격 | 일반 8종 × 1공격 | 종별 10~12프레임 RGBA + actor attack | `enemy_wave` 공용 몸체·색상 교체 금지 |
| 큰 엉킴 공격 | 4종 × 2공격 | 공격별 12~16프레임 RGBA + 서로 다른 anticipate | 같은 지역 일반 적과 silhouette 공유 금지 |
| 수호짐승 공격 | 4종 × 2공격 | 공격별 12~16프레임 RGBA + hit/release | 기존 4상태 정지 원화는 prototype fallback만 |
| 트리 갈래 accent | 3세트 | 코드 벡터 | 길 읽기/상황 바꾸기/동행 잇기 |
| 판정 결과 | 4세트 | 코드+작은 leaf cutout | flourish/clear/detour/safe, 색만으로 구분 금지 |
| 목표 획득·귀환 | 공용 2세트 | 코드 경로+래스터 잎 | 보상 개수만큼 반복하지 않음 |
| 지역 수호자 반응 | 지역당 1세트 | 래스터 | 수호자 몸과 별도 |
| 전경 분위기 | 지역당 2세트 | 저속 래스터 | 사건 선택을 가리지 않을 때만 |

90개 스킬트리 노드는 새 전신 sprite나 새 effect를 갖지 않는다. 뿌리 badge 10개,
branch badge 30개, 허용 effect module 14개를 조합한다. tier는 잎눈 1~3개로 표시한다.

출시 전투의 최소 논리 공격 family는 플레이어 고유 20 + 감정 전투 6 + 기록서 모듈 12 +
일반 엉킴 8 + 큰 엉킴 8 + 수호짐승 8 = **62세트**다. 탐험 성장형·판정·목표/귀환은
이 수량 밖이다.
family 수를 맞추기 위해 같은 프레임을 복사하고 색만 바꾸지 않는다. back/front가
필요한 효과만 두 pass로 나누고 빈 pass 파일을 만들지 않는다.

### 7.3 effect strip

- source master는 프레임별 RGBA PNG다. 빌더가 atlas 또는 개별 WebP로 파생하며,
  사람이 검수하지 않은 생성 접촉 시트를 그대로 런타임 strip으로 쓰지 않는다.
- 플레이어 기본기는 10F, 결정기·일반 적은 12F, 큰 엉킴·수호짐승은 최대 16F다.
  필요 프레임이 적은 정지 방어도 `시동·성립·접촉·회수` 4 event는 모두 가진다.
- source canvas는 256×256 또는 384×384 중 content bbox가 잘리지 않는 최소 규격을
  선택한다. 런타임은 bbox crop과 pivot을 기록하고 전장 anchor 사이를 이동시킨다.
- origin anchor는 `feet|chest|hand_l|hand_r|head|mouth|weapon|world`, target anchor는
  `feet|center|weak_point|front_edge` 중 하나다. 각 공격은 `origin`, `release_frame`,
  `travel_frames`, `contact_frames`, `reaction_frame`, `recovery_frame`을 manifest에 가진다.
- 덩굴·탄환·칼날이 화면을 가로지르는 것은 코드가 path를 그리는 것이 아니다. 코드는
  승인된 투명 공격 프레임의 위치·회전만 anchor 곡선에 따라 보간한다.
- 동시에 보이는 독립 파티클은 캐릭터당 12개, 화면 전체 24개 이하다.
- `BlendMode.srcOver`를 기본으로 하고 7.1.1의 제한된 contact `screen` 외 additive bloom,
  렌즈 플레어, 색수차는 쓰지 않는다.
- 화면 면적 25% 이상이 한 프레임에서 흰색으로 변하거나, 3Hz 이상 명멸하는 효과를
  금지한다.
- reduced motion은 마지막 형태를 120ms 이하로 fade하고 경로·결과 문구를 즉시
  표시한다. 의미 있는 정보는 particle 궤적에만 넣지 않는다.
- 공격 본체 alpha bbox와 target hitbox가 처음 겹치는 프레임이 서버 결과 적용·SFX·
  햅틱·피해 숫자의 단일 `contact`다. 먼저 HP가 줄거나 뒤늦게 맞는 소리가 나면 실패다.

#### 7.3.1 덩굴 공격 세로 슬라이스

`baby-pot / 고유 I / T1 / care-vines-v2`를 모든 공격 제작의 첫 표본으로 삼는다.

2026-08-10 후보 구현은 여섯 독립 key pose와 인접 승인본을 참조한 네 technical
in-between을 각각 한 장씩 생성해 총 10F로 만들었다. source·alpha·runtime hash와
light/dark QA는 `concepts/adventure-combat-vfx-v2/`에 있다. 같은 절차로 돌비늘
장부지기의 첫 고유 공격 `ledger_claw-v2` 10F도 만들었으며, 둘 다 실제 기기·contact
동기화·profile 전에는 production으로 세지 않는다.

1. 캐릭터 손 앞에서 말린 새순, 50% 지점의 굵은 줄기, 타깃을 감는 덩굴, 잎 impact,
   풀리며 회수되는 끝의 다섯 키프레임을 각각 ImageGen으로 만든다.
2. 모든 키프레임은 배경·캐릭터·UI 없는 투명 효과 본체만 남기고, 마디 수·주 줄기
   굵기·큰 잎 위치·빛 방향을 model sheet에 고정한다.
3. 5개 승인 키프레임 사이를 10F로 보간하고 손으로 선·잎 겹침·알파 가장자리를
   정리한다. 프레임 독립 생성으로 10장을 채우지 않는다.
4. `hand_r → target.center`에 실제 비행시키고 접촉 프레임에만 타깃 hit pose·SFX·숫자를
   낸다. 단순 초록 곡선, blur trail, particle spray는 덩굴 본체를 대신할 수 없다.
5. 390×844 실제 전장에서 1×·2×·짧은 연출·reduced motion 영상을 승인한 뒤에만
   나머지 61 공격 family를 시작한다.

### 7.4 이펙트 모양 언어

- 길 읽기: 속이 빈 눈 모양이 아니라 두 잎 사이의 좁은 창과 점선 경로
- 상황 바꾸기: 막힌 선이 휘어 다른 홈에 연결되는 한 번의 변형
- 동행 잇기: 두 캐릭터 사이에 맞물리는 잎 두 장
- 회복: 위로 쏟아지는 빛 대신 화분 가장자리에서 새 잎 한 장이 펴짐
- 목표 확보: 보물 폭발 대신 목표가 천천히 작아져 기록장 표식으로 이동
- detour: 붉은 실패 폭발 대신 길이 옆으로 완만하게 우회하고 준비도 숫자만 갱신

### 7.5 전투 중심 무대 패키지

각 `current scene`은 논리 자산 하나지만 아래 파생 pass를 가진다. 전 화면 RGBA 네 장을
그대로 겹치지 않고 backplate 외 pass는 content bbox로 잘라 decoded peak를 줄인다.

| pass | 내용 | 규격·예산 |
|---|---|---|
| `backplate` | 하늘·먼 벽·큰 나무·고정 조명 | opaque WebP, 세로 안전 master 1170×2532 이상 |
| `midground` | 아치·서가·수로·전투 뒤쪽 가림물 | sparse alpha WebP, 화면 coverage 45% 이하 |
| `floor` | 공용 바닥·보행로·전투 anchor zone | opaque 또는 1bit mask 병행, actor bbox와 겹침 금지 |
| `foreground` | 가까운 뿌리·잎·난간 | sparse alpha WebP, 전투 중 actor 얼굴 coverage 0 |
| `depth-mask` | 뒤/앞 VFX·actor 가림 판정 | 8bit grayscale, 색 정보 없음 |
| `reaction` | 잎 눕기·물결·서랍 열림·통로 회복 | 4~8F RGBA, contact 뒤에만 재생 |

- logical 390×844에서 전장 가시 영역 72~78%, 하단 UI 안전영역 22%를 보장한다. actor
  발·projectile 경로·target contact point 중 하나라도 HUD 아래로 내려가면 배경 구도를
  다시 잡고 UI opacity로 가리지 않는다.
- 같은 장소의 `approach/combat/release`는 파일을 바꾸지 않고 camera anchor와 reaction
  pass만 바꾼다. 탐색용 원화와 전투용 원화를 따로 생성해 문·나무 위치가 순간 이동하는
  것을 금지한다.
- full scene decoded peak는 9MiB 이하, 현재 actor+VFX+HUD를 포함한 전투 전체는 기존
  24MiB 캐시 상한 안에 들어야 한다. 보이지 않는 이전 stage pass는 350ms fade 뒤 해제한다.

## 8. 지역·수호자·아이템 제작표

출시 지역은 `moss_archive`, `echo_well`, `starlight_seed_vault`,
`heartwood_observatory` 네 곳이다.

| 자산 | 지역당 | 규격 | 제작 방식 |
|---|---:|---|---|
| 통합 탐험 지형 | 1 | 1600×900 WebP | 랜드마크와 실제 보행로를 그리되 노드·문자는 비움 |
| 현재 장소 무대 패키지 | 6~8 | 1600×900 landscape 원본 + 세로 안전 master·파생 pass | 접근/전투/사건/풀려남이 같은 landmark 좌표 공유 |
| 수호자 action | 4 | 256px 셀 8프레임 strip | idle/reveal/respond/resolve |
| 목표 아이템 | 1 | 512×512 투명 WebP | 정적 cutout, hover는 코드 |
| 전경 particle | 2 | 256px 셀 최대 8프레임 | 낮은 대비, 선택 사용 |
| 발견 beacon | 공용 1세트 | 7~15px 코드 벡터, 44px 터치 영역 | 지형을 가리지 않는 상태·비용 보조 표식 |

지역 logical raster는 총 56~64개다: 통합 지형 4, 현재 장소 24~32, 수호자 16,
목표 4, particle 8. 기억서고 M1은 통합 지형 1장과 같은 아트 디렉션의 장소 원화
7장을 사용하고, 단일 지도에 노드 아이콘만 바꿔 다른 방으로 대체하지 않는다. 7.5의
back/mid/floor/front/mask는 이 logical source의 빌드 파생본이므로 콘텐츠 수량으로
중복 집계하지 않되, 파일 누락과 decoded memory는 별도로 검사한다.

사건 15종마다 배경을 새로 만들지 않는다. 지역별 6~8개 장소 key를 콘텐츠
manifest가 공유한다. 같은 key를 쓰더라도 노드명·심도·사건 prop·수호자 오버레이로
맥락을 구분하며, 실루엣이 다른 던전·동굴·탑을 하나의 원화로 재사용하지 않는다.

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

수호자 본체는 상처·죽음 프레임을 갖지 않는다. 대신 별도 `hit`은 장벽 충돌의 방향을
몸동작으로 읽게 하고, `resolve`는 다치지 않은 채 몸을 낮추거나 길을 비키는 동작이다.
`respond`에서 600ms 이상 읽을 수 있는 공격 예고 뒤 반격한다. 캐릭터와 수호자
이펙트는 `back|front` pass로 분리하고 한 번의 충돌 섬광, 3.5px 이하 화면 흔들림,
데미지 숫자와 막대 변화가 같은 서버 판정 값을 사용해야 한다.

기억서고 세로 슬라이스는 배경과 수호자를 다음처럼 분리한다.

- `expedition-monster-den-battle-v1.webp`: 수호자와 캐릭터가 없는 빈 16:9 전투 무대
- `ledger-keeper-idle-v1.webp`: 투명 배경의 깨어 있는 대기 자세
- `ledger-keeper-attack-v1.webp`: 같은 개체·같은 광원의 반격 준비 자세
- `ledger-keeper-hit-v1.webp`: 왼쪽 충돌에 오른쪽으로 반응하는 장벽 피격 자세
- `ledger-keeper-defeated-v1.webp`: 다치지 않고 몸을 낮춰 길을 여는 장벽 해제 자세

배경에 잠든 수호자가 남아 있으면 별도 idle/attack과 이중으로 보이므로 금지한다. 수호자
레이어는 WebP `VP8X` alpha 플래그를 가져야 하고 모서리 배경 픽셀은 완전 투명이어야 한다.
앱은 idle 호흡을 코드 transform으로 만들고 attack/hit/defeated를 타임라인 구간마다
교차 페이드한다. 피격 flash와 흔들림은 수호자·현장 레이어에만 적용하며 HUD와 선택
UI는 고정한다. 네 파일은 화면 진입 시 미리 디코드해 첫 교체 프레임의 공백을 막는다.

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

### 9.1 스킬 아이콘 — ImageGen 도색 master

전투·캐릭터 상세의 고유 60개(20 family×3tier), 감정 6개, 기록서 36개는 별도
**래스터 스킬 아이콘 102개**를 갖는다. 기본 공격·지키기·AUTO·잠금처럼 제품 전체에서
의미가 고정된 조작만 semantic vector를 쓴다.

- 아이콘 하나당 ImageGen 호출 하나를 사용한다. 여러 스킬 grid·contact sheet·한 호출의
  `n` 변형을 서로 다른 아이콘으로 잘라 쓰지 않는다.
- source master는 1024×1024 PNG, runtime은 128×128·64×64 WebP다. 그림은 full-bleed
  정사각으로 만들고 라운드 마스크·비용·횟수·tier·잠금·상성 표시는 앱이 올린다.
- 입력 역할을 prompt와 manifest에 남긴다. Image 1은 승인된 프로젝트 아이콘 스타일,
  Image 2는 정확한 캐릭터/스킬/기록서 모티프, Image 3은 같은 family의 직전 승인 tier다.
  최초 tier·감정·기록서에는 Image 3을 넣지 않는다.
- 한 개의 큰 주모티프가 면적 58~72%를 차지하고 사방 12% 안전 여백을 둔다. 얼굴·전신
  캐릭터·전장 배경·UI 테두리·글자·숫자·tier 잎눈·워터마크·여러 장면을 넣지 않는다.
- 생성 결과는 `$CODEX_HOME/generated_images/`에서 승인 즉시
  `design-system/concepts/character-skill-vfx-v1/icons/sources/`로 복사하고 source hash,
  prompt, 입력 참조, 승인자, tier 계보를 manifest에 기록한다.
- `icon-manifest.json`의 각 항목은 `icon_code`, `category`, `family_code`, 선택 `tier`,
  `source_sha256`, `prompt_log`, `reference_sha256[]`, 선택 `parent_icon_code`,
  `runtime_128_sha256`, `runtime_64_sha256`, `approved_by`, `approved_at`을 가진다.
- full-bleed 도색 아이콘은 투명 배경이 필요 없다. cutout 예외만 10.3.1의 chroma 제거와
  alpha QA를 사용하며 true-alpha CLI로 몰래 우회하지 않는다.
- 128·64·48·32px, 흑백·저채도, 밝고 어두운 전장 6종 위의 접촉 시트에서 검수한다.
  48px에서 1초 안에 주모티프가 구분되지 않거나 색상만 바꾼 두 아이콘은 반려한다.

## 10. ImageGen 사용과 원화 통제

### 10.1 사용하는 곳

- 지역 전체의 스타일 승인용 콘셉트 1장
- 전투 중심 세로 화면의 전장 점유율·actor 배치·HUD 깊이·공격 경로를 검증하는 시각
  기준안. `adventure-combat-first-v1`처럼 prompt·입력 역할·hash를 함께 보존
- 사건 배경의 구도 초안
- 수호자와 목표 아이템의 정면/3분기 turnaround
- 기존 성체 base를 참조한 action key pose 초안
- 고유·감정·기록서별 도색 스킬 아이콘 한 개. 최초 승인 뒤 같은 family tier만 직전
  승인 아이콘을 참조해 실루엣을 유지
- 플레이어·일반 적·수호짐승 공격 본체의 `anticipation|travel|contact|impact|fade`
  키프레임. 내장 ImageGen에서는 family 팔레트와 겹치지 않는 완전 평면 chroma 원본을
  만들고 로컬 제거 후 효과만 있는 RGBA master로 승인
- 엉킴 12종의 idle·anticipate·attack·hit·release 핵심 자세

### 10.2 사용하지 않는 곳

- 8프레임 완성 sprite strip을 한 번에 생성
- 각 프레임을 이전 승인 프레임 참조 없이 따로 생성
- outfit을 base 없이 새로 생성
- 글자·숫자를 포함해야 하는 UI, 스탯·잠금·비용·AUTO 같은 semantic 아이콘
- 경로선·선택 링·안개 같은 코드로 정확히 만들 수 있는 도형
- 프레임 사이 보간과 최종 edge cleanup
- 생성된 덩굴·불꽃·몬스터를 코드 path로 다시 그려 "최적화"하는 것

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

각 공격은 family별 `model-sheet.md`를 먼저 만든다. 다음 값은 키프레임이 바뀌어도
프롬프트와 사람 QA가 고정한다.

```yaml
family_code: baby-pot.sprout-cheer
object: one thick living vine with three large leaves
main_stem_width_px_at_256: 18-24
leaf_count: 3
outline: warm dark brown, 3-4px at 256
light_direction: upper-left
palette: [moss, sage, cream]
origin_anchor: hand_r
target_anchor: center
forbidden: [character, pot, floor, text, particle spray, glow beam]
```

- 첫 호출은 model sheet·프로젝트 캐릭터·전장 crop만 참조한다. 다음 호출은 그것에 더해
  직전 승인 키프레임을 포함하고 "같은 물체가 다음 시점에 어떻게 변하는지"만 요청한다.
- 내장 ImageGen에는 native alpha를 전제로 지시하지 않는다. 단색 chroma는 **중간
  추출용**으로만 허용하고 최종 source 파일과 WebP alpha는 straight-alpha 기준으로
  검수한다. 런타임 디코더가 GPU texture를 premultiply하는 것은 7.1.1처럼 별도 기록한다.
- 한 키프레임에서 마디·잎·무늬가 바뀌면 prompt seed를 반복해 운에 맡기지 않고 바로
  image-to-image 수정 또는 수작업 paint-over로 돌아간다.
- prompt, reference hash, 생성 ID, 승인/반려 사유, paint-over 파일 hash를 manifest에
  남긴다. "AI 생성"만 적고 어떤 프레임에서 무엇을 고쳤는지 잃지 않는다.

#### 10.3.1 투명 공격 원본 실행 경로

1. 기본 경로는 내장 `image_gen`이다. 한 호출에는 family 하나의 키프레임 하나만 넣고,
   첫 프레임은 model sheet와 스타일 보드, 다음 프레임은 직전 승인 이미지를 참조한다.
2. 녹색 덩굴처럼 피사체에 초록이 있으면 `#FF00FF`, 그 외에는 기본 `#00FF00`을 쓴다.
   어떤 경우에도 key color가 피사체 팔레트에 들어가면 안 된다.
3. 프롬프트에는 `완전히 균일한 단색`, `그림자·그라데이션·바닥면·반사·질감 없음`,
   `충분한 바깥 여백`, `워터마크·문자 없음`을 매 호출 반복한다.
4. 승인 후보는 `$CODEX_HOME/generated_images/`에서 프로젝트의 `tmp/imagegen/` 또는
   해당 family source 디렉터리로 복사한다. 프로젝트가 참조하는 원본을 Codex 기본
   생성 폴더에만 남기지 않는다.
5. 설치된 `$CODEX_HOME/skills/.system/imagegen/scripts/remove_chroma_key.py`를 사용한다.
   인자는 `--auto-key border`, `--soft-matte`, `--transparent-threshold 12`,
   `--opaque-threshold 220`, `--despill`로 고정한다.
   가장자리에 key fringe가 남을 때만 `--edge-contract 1`로 한 번 재처리한다.
6. alpha channel 존재, 네 모서리 완전 투명, 본체 coverage, 외곽선 보존, key color 잔류
   0을 검사한 결과만 RGBA master로 승격한다.

연기·반투명 얼음·유리·액체처럼 chroma 제거로 경계와 내부 투명도가 훼손되는 family는
자동으로 다른 모델 경로로 바꾸지 않는다. true native alpha가 꼭 필요하면 제작 책임자의
사용자와 제작 책임자의 명시적 승인 뒤에만 `gpt-image-1.5` CLI fallback을 사용하며,
별도 `OPENAI_API_KEY`가
필요하다는 점을 작업 티켓에 남긴다. fallback을 쓰더라도 키프레임별 생성·참조 연속성·
paint-over·QA 계약은 동일하다.

### 10.4 출시작에서 가져온 원칙과 이미지 마감

2026-08-06 기준으로 작품의 고유 미술을 모사하지 않고 다음 구조 원칙만 참고한다.

- [TUNIC 공식 Nintendo 페이지](https://www.nintendo.com/us/store/products/tunic-switch/):
  작은 캐릭터가 있는 등각 지형에서도 숲·유적·지하 입구의 큰 실루엣과 숨은 길이 먼저
  읽혀야 한다.
- [Infinity Nikki Boneyard Exploration Journal](https://infinitynikki.infoldgames.com/en/news/480):
  호수 입구, 동굴, 유적과 이동 수단을 같은 지역의 물길·고도·서사에 붙여 랜드마크가
  메뉴 아이콘처럼 분리되지 않게 한다.
- [Hades II 공식 페이지](https://www.supergiantgames.com/games/hades-ii/): 어두운
  던전에서도 플레이 공간의 큰 값 덩어리와 스킬 궤적·피해 숫자의 색을 분리한다.
- [Monster Hunter Wilds 공식 PlayStation 페이지](https://www.playstation.com/en-us/games/monster-hunter-wilds/):
  서로 연결된 지역마다 물·식생·지형과 수호 생물의 관계를 보여 주고, 같은 장식 세트를
  반복해 지역을 채우지 않는다.

생성 원본은 그대로 출시하지 않는다. `finalize_expedition_art.py`가 16:9 중앙 크롭,
1600×900 정규화, 3×3 median 잡티 제거, 디더링 없는 192색 팔레트, WebP 마감을 한다.
346×195 축소본의 Gaussian residual을 기록하고 원본보다 고주파 노이즈가 늘어나면
반려한다. 팔레트를 96색까지 줄여 넓은 면이 계단처럼 보이는 것도 반려한다.

후처리는 잘못된 미술 방향을 구제하는 수단이 아니다. 축소본에서 개별 잎·자갈·이끼가
점무늬로 합쳐지면 랜드마크와 통로를 고정한 image-to-image 편집으로 넓은 색면과 묶음
식생부터 다시 만든다. 필터 수치를 키워 뭉개거나 선명도 보정으로 미세 질감을 강조하지
않는다. 최종 승인 순서는 `구조 고정 편집 → 390px 실기 렌더 확인 → 제한 팔레트 마감`이다.

```powershell
python design-system/scripts/finalize_expedition_art.py `
  <imagegen-source.png> `
  app/assets/adventure/<asset>-v3.webp `
  --preview output/asset-qa/<asset>-raw-vs-clean.png

# 승인된 원본은 그대로 두고 모바일 런타임 파생본을 다시 만든다.
python design-system/scripts/build_expedition_runtime_assets.py
```

런타임 파생본은 장소·통합 지형 960px, 투명 수호자 768px 너비다. 앱은 화면 물리
픽셀에 15% 여유를 둔 목표 너비가 파생본 이하일 때만 `-mobile.webp`를 사용하고,
고밀도 모바일·태블릿·데스크톱은 1600px 원본을 유지한다. 새 원화를 승인하거나 파일명을
바꾸면 `build_expedition_runtime_assets.py`의 명시적 목록과 번들 테스트를 함께 갱신한다.

배경과 장소 원화는 다음을 모두 만족해야 한다.

- 일관된 짙은 갈색 외곽선, 재질당 3단 명암, sage/cream/teal/amber 중심 팔레트
- 346×195에서 핵심 입구·다리·계단·상자가 각각 36px 이상으로 식별됨
- film grain, stippling, scratch, 수천 개의 개별 잎, 의미 없는 잔해와 장식 0
- 390px 화면에서 2px 이하로 뭉치는 무작위 잎·돌·이끼 무늬 0
- 글자·의사 문자·UI·룬·워터마크 0
- 맵 변형 사이 랜드마크 좌표 이동 0, 캐릭터·발자국 경로 좌표원 단일화

## 11. 오디오 제작 실행안

### 11.1 파일 수와 역할

| 분류 | 수량 | 런타임 |
|---|---:|---|
| 지역 BGM | 4 | AAC-LC `.m4a`, stereo |
| 지역 combat stem | 4 | AAC-LC `.m4a`, stereo |
| 수호자 stem | 4 | AAC-LC `.m4a`, stereo |
| 지역 release cadence | 4 | PCM16 `.wav`, stereo |
| 지역 ambience | 8 | AAC-LC `.m4a`, stereo |
| 발걸음·화분 재질 | 4 | PCM16 `.wav`, mono |
| 발견 일반/이야기/목표 | 3 | PCM16 `.wav`, mono |
| 고유 스킬 signature | 20 | PCM16 `.wav`, mono |
| 감정 스킬 cue | 6 | PCM16 `.wav`, mono |
| 기록서 역할 cue | 8 | PCM16 `.wav`, mono |
| 스킬 갈래 accent | 3 | PCM16 `.wav`, mono |
| UI 확정·회복·저장·귀환 | 4 | PCM16 `.wav`, mono |
| 엉킴 공격 signature | 16 | PCM16 `.wav`, mono |
| 수호짐승 공격 signature | 8 | PCM16 `.wav`, mono |
| 접촉 재질·guard | 6 | PCM16 `.wav`, mono |

출시 오디오는 총 **102개**다. 90개 트리 노드의 별도 음원은 만들지 않는다. 고유 I·II
20개와 적 공격 24개는 각각 구분되는 release signature를 가지며, 공용 cue의 pitch만
바꿔 납품하지 않는다. 접촉음은 공격 signature와 target material cue를 contact frame에
겹쳐 만든다.

### 11.2 제작·마스터링

- 원본 master는 48kHz/24bit WAV로 보관한다.
- BGM은 60~90초 seamless loop, -18~-16 LUFS, true peak -2dBTP 이하다.
- ambience는 15초 이상, -28~-24 LUFS로 만들고 반복 지점을 무음이 아니라 실제
  질감의 zero crossing에 둔다.
- 짧은 SFX는 700ms 이하, -20~-16 LUFS 범위에서 품종 간 체감 크기를 맞춘다.
- `skill` manifest의 cue frame과 소리의 첫 명확한 transient 차이는 50ms 이하다.
- 공격의 `contact_frame`과 impact transient·햅틱·HP 갱신은 실제 기기에서 ±1 frame이다.
- combat/guardian stem은 BGM 재생 위치를 유지한 채 180~350ms로 교차하고, release에는
  두 음 cadence를 한 번 재생한다. 새 스테이지마다 BGM을 0초에서 다시 시작하지 않는다.
- impact가 재생되면 ambience와 비핵심 signature를 80~140ms 동안 2~4dB duck한다. 대사는
  BGM/stem을 6~8dB duck하며 impact를 키워 대사를 덮지 않는다.
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
12MB, **62개 전투 family를 포함한 effect는 12MB**, UI vector/WebP 파생본은 1MB 이하를
목표로 한다. 직접 탐험의 전 지역·두 의상 신규 install 증가량은 합계 75MB 이하가
release gate다.
기존 wardrobe 약 45MB는 사건
초상에 재사용하고 탐험용으로 복제하지 않는다. Android App Bundle의 압축 후 실제
증가량도 release report에 별도로 기록한다.

### 12.1 배포 팩

현재 `app/assets` 원본은 약 138MB이므로 신규 75MB를 모두 기본 번들에 넣지 않는다.
같은 `asset-manifest.json` 경로 계약을 유지하되 빌드 산출물을 다음 팩으로 나눈다.

| pack | 내용 | 압축 목표 | 설치 시점 |
|---|---|---:|---|
| `expedition-core-v2` | stage 5 base 420 strip, 고유/기록서 effect index, UI, 공용 SFX | 21MB | 앱 기본 또는 기능 첫 진입 전 |
| `expedition-outfit-garden-daily-v1` | 해당 outfit 420 strip | 8MB | 소유 의상으로 첫 출발 전 |
| `expedition-outfit-city-night-v1` | 해당 outfit 420 strip | 8MB | 소유 의상으로 첫 출발 전 |
| `expedition-region-{region}-v2` | 지역 raster, BGM 1·stem 1·ambience 2 | 지역당 6MB | 지역 해금 또는 첫 진입 시 |
| `expedition-combat-{region}-v2` | 엉킴 몸체·종별 공격, 수호짐승 2공격, impact·SFX | 지역당 3MB | 해당 지역 첫 전투 전 |

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
- 전투 pack은 정식 몸체·공격·피격을 한 묶음으로 원자 설치한다. 하나라도 없으면 전투
  진입 전에 다운로드를 마치게 하고, 코드 도형 몬스터·공용 파동·정적 공격으로 대신
  입장시키지 않는다. 진행 중 run은 시작 snapshot의 검증된 pack을 캐시에 고정한다.
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

공격 effect 항목은 위 캐릭터 항목에 더해 다음 필드를 반드시 가진다.

```json
{
  "id": "vfx.baby-pot.sprout-cheer.t1",
  "production_ready": true,
  "source_frames": 5,
  "runtime_frames": 10,
  "origin_anchor": "hand_r",
  "target_anchor": "center",
  "release_frame": 2,
  "travel_frames": [2, 3, 4, 5],
  "contact_frames": [6],
  "reaction_frame": 6,
  "recovery_frame": 9,
  "source_refs": ["sha256:..."],
  "prompt_log": "model-sheets/baby-pot.sprout-cheer.md",
  "reduced_motion_frame": 6,
  "sha256": "..."
}
```

`production_ready:false`이거나 위 event가 빠진 항목은 debug 빌드에서만 resolver가 읽는다.
릴리스 빌드는 공용 impact로 조용히 폴백하지 않고 CI에서 실패해 미완성 공격이 숨어
들어가지 않게 한다.

## 14. 자동 검수

### 14.1 정적 검사

- 모든 PNG/WebP의 canvas, alpha, 색공간, 파일명, frame count 일치
- 투명 영역의 `#FF00FF` 오염과 1~2px 흰색·크림색 guide fringe 0
- 크롭 가장자리에 닿은 비본체 컴포넌트 0
- model sheet에 없는 본체 대비 2% 미만 비의도 공중 파편 0. 의도한 잎·불씨·파편은
  source mask와 component id로 증명
- outfit의 얼굴·피부·손·발 픽셀 0
- base/outfit alpha pose-lock 거리 2px 이하
- 연속 프레임 bbox 높이 변화 4% 이하, 중심축 흔들림 2px 이하
- 걷기 접지 발 pivot slip 3px 이하
- loop 첫/끝 속도 불연속 15% 이하
- 프레임별 얼굴 landmark 편차 2px 이하
- manifest cue, duration, paired layer, 파일 hash 누락 0
- 스킬 아이콘 source 102·128px 102·64px 102개가 `icon-manifest.json`과 1:1이고,
  source/prompt/reference/parent/runtime hash·승인 필드 누락 0. 한 source의 다중 패널·
  문자·숫자·UI 테두리와 서로 다른 icon code의 동일 source hash는 0건
- 모든 공격의 `production_ready=true`, origin/target/release/travel/contact/reaction/
  recovery event 누락 0, event index 순서 역전 0
- 같은 family 연속 키프레임의 주 본체 두께 변화 12% 이하, 주요 부품 수 불일치 0,
  광원 방향 반전 0. 의도된 impact 분열은 model sheet에 예외가 구조화되어 있어야 함
- character strip 30KB, 공격 family effect 240KB, region 개별 450KB hard limit 준수

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
- 플레이어 고유 20·감정 6·기록서 12 family와 적 공격 24종의
  `actor → travel → contact → reaction` 접촉 시트
- 스킬 아이콘 102개의 128·64·48·32px, 흑백·저채도, 전장 배경 6종 접촉 시트
- 0.25× onion-skin에서 덩굴 마디·칼날 폭·불씨 중심·몬스터 얼굴 landmark 연속성 영상
- 각 공격을 밝은/어두운 지역 배경, 작은/큰 타깃, 좌→우/우→좌에 합성한 영상
- region별 320×640, 390×844, tablet landscape 화면
- reduced motion 정지 상태와 스크린리더 label 목록

사람이 반드시 보는 고위험 조합은 여우비의 꼬리·시스루·moonlit 스타킹, 블루미
ember 스타킹, 별솔의 전신 슈트, 뽀또의 모든 form, 가시로의 상시 홍조 여부, 긴
소매·긴 치마가 있는 모든 walk다.

### 14.3 실제 기기 검사

Android 저사양 1대, 기준 Android 1대, iPhone 1대에서 다음을 녹화한다.

1. 세 캐릭터 idle 30초 동안 호흡·blink·부분 모션
2. 20개 노드 연속 이동과 방향 전환
3. `idle → interact → react → idle`, `idle → anticipate → cast → recovery → idle`
4. 의상 두 벌을 다음 run에서 교체한 뒤 같은 경로 반복
5. 뽀또 고유 I 덩굴의 손→적 비행·접촉, 고유 II, 감정 스킬 1종·기록서 2종을
   1×·2×·짧은 연출로 반복
6. 일반 엉킴 3종의 서로 다른 공격과 큰 엉킴·수호짐승 공격 2종, hit·release
7. 앱 백그라운드·복귀, 네트워크 지연, 움직임 줄이기 전환

합격 기준은 레이어 이탈·바디 단독 flash·잘린 꼬리/손발·눈 밖 blink 0, 30분 동안
OOM 0, 기준 기기 p95 frame time 16.7ms 이하, 저사양 30fps 유지다. 문제가 있으면
`품종/form/outfit/action/frame index/기기`를 기록한다.

## 15. 제작 순서와 완료 gate

| 단계 | 산출물 | 다음 단계로 가는 조건 |
|---|---|---|
| P0 규격 | manifest schema, builder skeleton, 코드 vector prototype | 빈 샘플로 CI 동작 |
| P1 전투 세로 슬라이스 | 뽀또 고유 I 덩굴 10F + actor pose 8F, 장부지기 발톱 10F + hit/release, 통합 전장, SFX | 실제 비행·contact 동기화, 코드 유기체 0, 실제 기기 10분, 신규 첫 contact p95 15초, 실제 빌드 15초 clip |
| P1W 의상 세로 슬라이스 | 여우비 moonlit city-night 7 action, 1지역, 1수호자 | 자동 위반 0, 실제 기기 10분 |
| P2 안전 슬라이스 | 뽀또 sunny, 별솔 covered base | 아동/착의형 계약 위반 0 |
| P3 캐릭터 base | 10종×6형×7 action | base 420 strip 위반 0 |
| P4 의상 | garden-daily, city-night | outfit 840 strip, 합성 위반 0 |
| P5 플레이어 effect·UI | 고유 20·감정 6·기록서 12 family, 스킬 아이콘 102, VFX 712F·actor pose 200F, branch 코드 3, SVG 83·코드 icon 22 | family·아이콘 색상 복제 0, reduced motion/광과민 검사 통과 |
| P5E 적 전투 에셋 | 엉킴 12종 5동작·공격 12, 큰 엉킴 추가 공격 4, 수호짐승 공격 8 | 공용 enemy wave 0, 예고/접촉/피격/풀림 전수 승인 |
| P6 지역 | 네 지역 raster 64개 | 안전영역·가독성·크롭 통과 |
| P7 오디오 | 102개 runtime 파일 | loudness·loop·stem 전환·contact sync·focus 통과 |
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
| ImageGen 스킬 아이콘 승인 master | 고유 60 + 감정 6 + 기록서 36 | 102 |
| 공격 VFX 승인 keyframe | 62 family × 5단계 | 310 |
| 플레이어 VFX runtime frame | 고유 500 + 감정 60 + 기록서 120 + 경고 32 | 712 |
| 플레이어 actor pose logical frame | 고유 20스킬×8 + 감정 공용 10품종×4 | 200 |
| 스킬 아이콘 raster | 고유 60 + 감정 6 + 기록서 36 | 102 |
| 일반/큰 엉킴 몸체 frame | 12종×(idle 6 + anticipate 4 + attack 12 + hit 4 + release 8) | 408 이상 |
| 적 공격 VFX frame 상한 | 일반 8×12 + 큰 엉킴 8×16 + 수호짐승 8×16 | 352 |
| 수호짐승 몸체 frame | 4지역×(idle 6 + anticipate 4 + attack 16 + hit 4 + release 8) | 152 |

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
| 사운드 | 원본·라이선스, 102개 납품, cue·loudness·loop·stem·contact sync |
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

- stage 2~4가 기존 성장 정체성을 유지하고 비전투 transform fallback과 전투 pose
  frame의 경계가 명확히 동작한다.
- stage 5 base 420, 두 의상 840 runtime strip이 모두 존재한다.
- 캐릭터·의상·effect의 frame index와 anchor가 하나의 manifest로 동기화된다.
- 열 품종의 고유 모션과 여섯 성장형 리듬이 실제 크기에서도 구분된다.
- 전투 공격 family 62세트와 탐험 성장형·판정·목표 효과가 모두 있고 색상 복제·공용
  `enemy_wave`·코드 유기체·정적 idle 공격이 0건이다.
- region logical raster 64와 7.5 파생 pass, 스킬 아이콘 102, UI SVG 83·코드 icon 22,
  audio 102의 누락이 없다.
- edge fragment, outfit body pixel, pose-lock, pivot slip, alpha fringe 위반이 모두 0이다.
- 움직임 줄이기와 무음으로도 같은 선택과 결과를 이해할 수 있다.
- ImageGen 원본은 참조·프롬프트·검수 이력이 있고 최종 프레임은 수작업/자동 QA를
  통과한다.
- 모든 플레이어·적 공격은 실제 origin→target 비행 또는 actor 접촉을 가지며, contact
  이전 HP/장벽 갱신과 피해 숫자가 0건이다.
- `production_ready:false`, PLACEHOLDER 배지, 누락 pack, 공용 impact fallback이 릴리스
  manifest에 0건이다.
- 실제 기기에서 의상 이탈, blink 오프셋, 교체 flash, 프레임 드롭이 없다.
