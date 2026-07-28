# 감정 성장 캐릭터 아트·모션 규격

마음 식물, 대화 캐릭터, 정원 중앙 캐릭터, 수집 캐릭터는 서로 다른 분류가
아니다. 사용자가 상점에서 씨앗 품종을 해금해 심으면 하나의 개체가 태어나고,
그 개체가 누적 일기에서 읽힌 감정에 따라 다른 모습과 성격으로 자란다.

![기본 품종 감정 성장 루트](basic-sprout-emotion-growth-preview-v2.webp)

## 성장 구조

```text
공통 씨앗
  └─ 2단계: 최근 누적 감정의 미세한 징후
      └─ 3단계: 우세 감정으로 주 성장 루트 확정
          └─ 4단계: 주 루트의 성체 분위기 형성 + 보조 감정 장식
              └─ 5단계: 같은 루트의 완전체
```

- 단계는 경험치로 오른다. 감정 종류가 성장 속도나 보상량을 바꾸지 않는다.
- 1단계는 모든 루트가 같은 씨앗이다.
- 2단계 징후는 `emotion_profile.leading_cue`를 사용하며 아직 확정값이 아니다.
- 3단계부터 서버의 `dominant_form`을 주 성장 루트로 사용한다.
- 4단계부터 `secondary_form`은 잎 장식·빛·작은 꽃 같은 보조 레이어로만 더한다.
- 수확 시 5단계 주 성장 루트를 `final_form`으로 고정한다.
- 슬픔·분노·불안·혼합은 실패, 시듦, 저등급이 아니다.

## 여섯 성장 루트

| form | 누적 감정 | 2~3단계 방향 | 5단계 완전체 방향 |
|---|---|---|---|
| `sunny` | 기쁨 | 위로 열리는 잎, 노란 꽃눈, 밝은 표정 | 밝고 쾌활하며 귀엽고 예쁜 사람형 해바라기 정령 |
| `rainy` | 슬픔·상처 | 아래로 흐르는 푸른 잎과 이슬 | 차분한 반눈과 남청 꽃잎을 두른 사람형 빗꽃 정령 |
| `ember` | 분노 | 곧게 선 잎, 산호색 불꽃 봉오리 | 자신감 있는 시선과 불꽃 코트를 두른 사람형 불씨 정령 |
| `moonlit` | 불안 | 안쪽을 감싸는 잎, 은보라 단서 | 초승달 망토를 두른 사람형 밤의 수호자 |
| `sparkling` | 놀람 | 비대칭 새순, 작은 진주빛 꽃눈 | 민트·진주·분홍 봉오리의 사람형 탐험가 |
| `mosaic` | 혼합·동률 | 서로 다른 모양과 색의 잎이 균형 있게 등장 | 여러 감정을 통합한 사람형 만화경 예술가 |

5단계 v4에서는 색과 장식만 바꾸지 않고 얼굴, 실루엣, 태도, 움직임까지
다른 성체 원형으로 성장시킨다.

| form | v4 성체 원형 | 대표 인상 | 동작 방향 |
|---|---|---|---|
| `sunny` | 따뜻한 미남·미녀 | 다정함, 햇살형, 열린 미소 | 위로 열리는 손과 햇빛 꽃잎 |
| `rainy` | 차가운 우울미 | 냉미남·냉미녀, 고딕, 절제된 시선 | 아래로 흐르는 옷자락과 비꽃 해방 |
| `ember` | 강인한 글래머 | 섹시함, 걸크러쉬, 눈나, 존잘 | 단단한 중심과 불꽃잎 돌파 |
| `moonlit` | 경계하는 다크 로맨스 | 미스터리, 집착계, 보호적 실루엣 | 몸을 감싸며 펼쳐지는 달덩굴 |
| `sparkling` | 장난스러운 탐험가 | 귀여움, 반전 매력, 큰 표정 | 점프·회전과 프리즘 잎 |
| `mosaic` | 성숙한 이중 매력 | 중성적 우아함, 분석적 미소 | 따뜻함과 차가움을 양손에 균형 배치 |

각 원형은 `idle`, 일기를 읽고 반응하는 `diary`, 성장·수확을 축하하는
`grow` 세 자세를 가진다. 10캐릭터 × 6감정 × 3자세로 성체 원화는 총
180장이다. 실제 감정 분석과 원형 계약은
`growth-assets/emotion-archetypes-v4.json`을 기준으로 한다.

`rainy`의 퇴폐미와 `ember`의 색기는 5단계의 시선, 색, 꽃잎 코트와 태도로
표현한다. 1~4단계는 성장 중인 단계이므로 성적 표현을 넣지 않는다. 사람형이
완성되는 5단계는 성인으로 읽히는 비율과 의상을 사용한다. 섹시 중심 성인형은
쇄골·어깨·허리·다리의 노출과 시스루 소재를 사용할 수 있지만 가슴·속옷은
불투명하게 가리고 핀업 포즈에 의존하지 않는다.

## 같은 게임으로 보이기 위한 공통 아트 바이블

| 항목 | 기준 |
|---|---|
| 파일 | 투명 배경 RGBA WebP |
| 캔버스 | 512×768 |
| 중심축 | x=256 |
| 바닥선 | y=718 |
| 안전 영역 | x=44~468, y=14~718 |
| 그림체 | 프리미엄 2.5D 동화풍 게임 일러스트 |
| 렌더링 | 부드러운 입체 셀 셰이딩, 얇은 온갈색 외곽선, 은은한 붓 질감 |
| 조명 | 좌상단의 넓고 부드러운 key light |
| 얼굴 | 둥근 얼굴, 타원 눈, 짧은 곡선 입, 옅은 복숭아색 볼 |
| 공통 DNA | 캐릭터 고유 씨앗, 토분 또는 화분 표식, 성장하며 확장되는 식물 의상 |
| 카메라 | 정면을 향한 3/4 입체감, 같은 눈높이와 화분 비율 |

루트가 바뀌어도 화분, 세 잎 표식, 얼굴 구성, 외곽선 두께, 광원과 붓 질감은
같다. 사실적인 식물이나 3D 피규어가 아니라 한 명의 캐릭터 원화가가 그린
2.5D 게임 캐릭터로 보여야 한다. 2단계는 화분에서 얼굴과 고유 장식이 드러나는
새싹, 3단계는 2~2.5등신의 유아기, 4단계는 사람형 실루엣이 분명한 성장기,
5단계는 성인으로 읽히는 완전체다. 사실적인 인체·젖은 피부·이빨·날카로운
관절은 사용하지 않는다.

## 다섯 단계

| 단계 | phase | 감정 정보 | 형태 변화 | 기본 idle |
|---|---|---|---|---|
| 1 씨앗 | `seed` | 숨김 | 공통 씨앗, 접힌 잎눈 하나 | 아주 느린 숨쉬기 |
| 2 새싹 | `sprout` | 임시 단서 | 얼굴 있는 새싹과 작은 잎팔, 꽃눈으로 암시 | 미세한 잎 흔들기 |
| 3 유아기 | `branching` | 주결 확정 | 짧은 팔다리와 고유 의상, 주색이 분명해짐 | 가볍게 솟았다 내려오기 |
| 4 성장기 | `bloom` | 주결 + 보조결 | 사람형 몸과 식물 의상·장식이 확장됨 | 장식별 작은 반응 |
| 5 성인 | `full-bloom` | 수확 형태 | 성인으로 읽히는 사람형 완전체와 고유 성격 완성 | 루트별 고유 idle |

씨앗과 사람형 완전체는 별도 캐릭터가 아니다. 같은 얼굴, 화분 표식과 식물
모티프를 유지한 한 개체가 팔다리와 의상을 얻으며 자라고, 누적 일기가 꽃·색·
표정과 완전체의 방향을 바꾼다.

## 파일 이름과 해석 우선순위

Flutter 번들 경로는 `app/assets/plants/`다.

```text
{species}-25d-seed.webp
{species}-25d-{phase}-{primary-form}.webp
{species}-25d-{phase}-{primary-form}-{secondary-form}.webp
```

`basic_sprout`의 1차 세트는 공통 씨앗 1장, 감정 단서가 아직 없는 관찰 중
새싹 1장, 여섯 루트의 2~5단계 24장으로 총 26장이다.

기존 캐릭터 10종은 캐릭터마다 고유 씨앗 1장과 여섯 감정 루트의
새싹·유아기·성장기 18장, 감정 성체 3자세 18장으로 총 37장을 사용한다.
현재 세트 370장의 계약은 `growth-assets/character-lineages.json`에서 관리하며,
이전 성체 v1~v3는 안전한 대체 파일로 유지한다.

```text
basic-sprout-25d-seed.webp
basic-sprout-25d-sprout.webp
basic-sprout-25d-sprout-sunny.webp
...
basic-sprout-25d-full-bloom-mosaic.webp
```

앱은 다음 순서로 파일을 찾는다.

1. 모든 10개 계보의 감정별·자세별 `full-bloom` v4
2. 여우비·가시로의 감정별 `full-bloom` v3
3. 나머지 사람형 계보의 감정별 `full-bloom` v2
4. `25d` 주결+보조결
5. `25d` 주결
6. `25d` 단계 공통
7. 이전 `cute` 파일
8. 기존 단계 파일
9. `CustomPaint` 대체 렌더

보조결 조합 파일을 모두 굽지 않는다. 기본 세트는 주결 이미지를 사용하고,
보조결은 코드 기반 색점·빛·작은 장식 레이어로 합성한다. 특별 조합만
`primary-secondary` 파일로 승격한다.

단계·pivot·모션 값의 기계 판독 원본은
`design-system/growth-assets/basic-sprout.json`에 둔다.

10종 성장 계보는 다음 평면 파일 이름을 사용한다.

```text
{character-slug}-25d-seed.webp
{character-slug}-25d-{sprout|branching|bloom|full-bloom}-{form}.webp
{character-slug}-25d-full-bloom-{form}-v2.webp
{gumiho-pot|tsundere-pot}-25d-full-bloom-{form}-v3.webp
{character-slug}-25d-full-bloom-{form}-v4-{idle|diary|grow}.webp
```

## ImageGen 원본과 에셋 빌드

기준 원본은 `design-system/concepts/emotion-growth-humanoid-v2/`에 둔다.

- `emotion-human-final-lineup-v2.png`: 여섯 사람형 완전체의 공통 화풍 기준
- `shared-seed-v2-alpha.png`: 모든 루트가 공유하는 씨앗
- `shared-sprout-v2-alpha.png`: 감정 단서가 아직 없는 관찰 중 새싹
- `{form}-route-chroma-v2.png`: 루트별 2~5단계 ImageGen 원본
- `{form}-route-chroma-v2-alpha.png`: 배경 제거 후 빌드 입력

제작 순서는 다음과 같다.

1. 여섯 완전체를 한 장에 생성해 공통 화풍과 루트 차이를 먼저 잠근다.
2. 완전체 기준표를 참조해 공통 씨앗을 만든다.
3. 씨앗과 완전체 기준표를 함께 참조해 루트별 2~5단계 한 세트를 만든다.
4. 배경은 캐릭터와 겹치지 않는 단색으로 만들고 chroma key로 제거한다.
5. `design-system/scripts/build_growth_assets.py`로 네 패널을 분리하고
   512×768 투명 WebP와 검수용 contact sheet를 만든다.
6. 120px 카드, 2:3 홈, 정사각 채팅 아바타, 마이팜, 박물관에서 확인한다.

감정 원형 v4의 ImageGen 원본은
`design-system/concepts/emotion-archetype-growth-v4/{character-slug}/`에
`idle-chroma.png`, `diary-chroma.png`, `grow-chroma.png`로 보관한다.
`extract_magenta_sprite.py`로 투명 원본을 만든 뒤
`build_emotion_archetype_sprites_v4.py`가 여섯 패널 분리, 이웃 패널 조각 제거,
세 자세 크기 정규화, 512×768 WebP 출력과 검수용 연락시트 생성을 담당한다.

v4 캐릭터 보정은 `growth-assets/emotion-archetypes-v4.json`의
`character_overrides`를 따른다. 가시로는 기본 홍조를 제거하고 23N 피부를
유지하며 `sunny diary`, `sparkling idle`, `sparkling diary`에서만 옅게
붉어진다. 여우비는 여섯 감정 모두에서 열린 목선·어깨선·허리선·다리선을
기본으로 두고 `ember`를 가장 대담하게 만든다. 여우비 `moonlit`과 블루미
`ember`는 검정 반투명 스타킹과 가는 힐을 사용한다.

기존 캐릭터 10종은
`design-system/concepts/character-lineages-v1/{character-slug}/`의 고유 씨앗과
여섯 성장 시트를 입력으로 사용한다. `build_character_lineages.py`가 각 시트를
네 단계로 분리하고 `app/assets/plants/`의 250개 투명 WebP와
`design-system/character-lineage-previews/`의 도감 미리보기를 만든다.

절제형 성인 v2는
`design-system/concepts/character-redesign-v2/emotion-adult-sources/`의
10개 여섯 감정 시트를 입력으로 사용한다.
`build_character_emotion_adults_v2.py`가 이를 분리해 60개 v2 WebP와
`emotion-adults-v2-preview.webp`를 만든다. 기존 1~4단계 190장은 유지한다.

여우비·가시로의 정체성 보강본은
`design-system/concepts/character-redesign-v3/`에 둔다. 여우비는 반쯤 감긴
직접 시선, 작은 미소, S자 자세, 부채와 시스루 현대 한복으로 성인 요염함을
강화한다. 가시로는 외면과 팔짱을 유지하면서 씨앗주머니·손수건·수선 화분을
몰래 건네는 행동으로 츤데레의 모순을 드러낸다. v3의 상시 홍조는 레거시
표현이며 현재 v4에서는 특정 호감·당황 반응에만 사용한다. v3 12장을 먼저
찾고 누락 시 같은 감정의 v2로 내려간다.

공통 프롬프트의 핵심 문장은 다음과 같다.

```text
The exact same emotion-plant character growing from a potted seedling
into a cute humanoid complete form at stage N of 5.
Premium 2.5D storybook mobile-game character illustration.
Soft dimensional cel shading, fine warm-brown outline, subtle painterly texture.
The same short wide peach terracotta pot and embossed three-leaf emblem.
The same tiny oval-eye construction, camera, scale, and top-left key light.
Stage 3 gains leaf-glove arms and root boots; stage 4 becomes compact humanoid;
stage 5 is a clearly adult-coded humanoid complete character.
No creepy hybrid, realistic anatomy, generic 3D toy, or sexualized juvenile form.
```

## 모션 계약

첫 배포는 한 단계당 검수한 cutout 한 장에 Flutter transform을 적용한다.

```json
{
  "motion_key": "emotion_idle",
  "frames": 1,
  "loop_ms": 2700,
  "transform_only": true,
  "pivot": [0.5, 0.935],
  "reduced_motion": "static"
}
```

- `sunny`: 위로 작게 튀며 꽃잎이 열린다.
- `rainy`: 잎 망토가 낮고 느리게 좌우로 흐른다.
- `ember`: 불꽃 왕관이 짧게 올라오고 자신 있게 멈춘다.
- `moonlit`: 감싸는 잎이 아주 천천히 호흡한다.
- `sparkling`: 비대칭으로 가볍게 튀고 작은 반짝임이 생긴다.
- `mosaic`: 좌우 어느 쪽에도 치우치지 않는 완만한 흔들림을 쓴다.

감정 모션 위에 캐릭터 고유 모션을 합성한다. 뽀또의 화분 통통 뛰기,
로제온의 코트 플러리시, 블루미의 꽃 포즈, 가시로의 외면, 시들잎의 졸린
흔들림, 여우비의 꼬리 부유, 그림싹의 짧은 대시, 별솔의 지팡이 호버,
설화의 곁눈질, 하루의 자세 고쳐잡기는 서로 다른 주기와 transform을 쓴다.
10종 모두 탭 `react`가 있으며 도감의 완전체 미리보기에서도 작동한다.

프레임 애니메이션은 외형 기준이 잠긴 뒤 `idle`, `react`, `grow`만 추가한다.
모든 프레임은 같은 캔버스, 중심축, 바닥선과 화분 좌표를 유지한다.

## 완료 조건

- 공통 씨앗·관찰 중 새싹 2장과 여섯 루트 24장이 모두 512×768 RGBA WebP다.
- 투명 영역에 보이는 마젠타 후광·사각 잔상·내부 구멍이 없다.
- 모든 단계의 화분, 얼굴 문법, 외곽선, 붓 질감과 조명 방향이 같다.
- 2단계는 단서만 보이고 3단계부터 여섯 루트가 120px에서도 구분된다.
- 4단계부터 사람형이 분명하고 5단계는 여섯 루트 모두 사람형 완전체다.
- `rainy`, `ember`의 성숙한 분위기는 5단계에서만 나타난다.
- 홈·채팅·마이팜·도감·박물관이 같은 개체의 같은 에셋을 사용한다.
- reduced motion에서 ticker와 transform이 멈춘다.
- 파일 누락이나 디코딩 실패 시 이전 래스터 또는 벡터 대체가 표시된다.
