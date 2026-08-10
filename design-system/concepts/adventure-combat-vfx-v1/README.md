# 탐험 전투 VFX v1

> **2026-08-10 상태: prototype 기록, 정식 출시 사용 금지.** 이 세트는 8프레임 완성
> 시트를 한 번에 생성했고 플레이어 7효과와 공용 적 공격 `enemy_wave`만 제공하므로
> `stage-battle-v2.2`의 캐릭터 고유 20종·감정 6종·적별 공격·actor/contact/reaction 계약을
> 만족하지 않는다. 파일과 생성 ID는 비교·회귀 자료로 보존하되
> `production_ready:false`로 취급한다. 후속 제작은
> `design-system/EXPEDITION_ASSET_PRODUCTION.md` 7장·10장을 따른다.

전투 중 공격 궤적을 Flutter `CustomPainter`로 생성하지 않고, 검수한 8단계
래스터 시퀀스로 재생하기 위한 소스 계약이다. 플레이어 7종과 장부지기 반격
1종, 총 64프레임을 제공한다.

## 산출물

| 효과 키 | 접촉 시트 원본 | 생성 원본 ID |
|---|---|---|
| `care_vines` | `sources/care-vines-chroma.png` | `exec-4c87797e-06c8-4a63-a8fb-5c446b2095d2.png` |
| `safe_guard` | `sources/safe-guard-chroma.png` | `exec-895e6c6f-a7c5-4607-9d45-8c47dbebb2ce.png` |
| `ember_arc` | `sources/ember-arc-chroma.png` | `exec-9182b119-05a3-411f-ae75-15533f77cbf8.png` |
| `prism_burst` | `sources/prism-burst-chroma.png` | `exec-8ba8f636-1e2a-4175-aaed-b0b96e986742.png` |
| `mist_dash` | `sources/mist-dash-chroma.png` | `exec-b2ca2fe9-b963-4323-974b-264eed75fbf5.png` |
| `insight_arc` | `sources/insight-arc-chroma.png` | `exec-b72a5f06-46f4-46b6-820c-16ef6e61742f.png` |
| `echo_wave` | `sources/echo-wave-chroma.png` | `exec-40471f3f-5f66-41d3-8b6b-9b2e95f914d5.png` |
| `enemy_wave` | `sources/enemy-wave-chroma.png` | `exec-d8a29a9d-6fb9-40f6-8579-f7e29d44c614.png` |

- 생성 방식: 내장 ImageGen, 참조 이미지 기반 생성
- 검수 원본: 이 디렉터리의 `sources/*-chroma.png`
- 스타일 참조:
  - `app/assets/plants/baby-pot-25d-full-bloom-sunny-v4-idle.webp`
  - `app/assets/adventure/ledger-keeper-attack-v1.webp`
  - `app/assets/adventure/expedition-monster-den-battle-v1.webp`
  - 먼저 생성한 `care-vines` 시트는 나머지 효과의 VFX 선 굵기 참조로 사용
- 앱 출력: `app/assets/adventure/effects/{효과}/frame-00.webp` ~
  `frame-07.webp`, 프레임당 576×288 RGBA WebP

## 생성 프롬프트 계약

모든 효과는 아래 공통 프롬프트를 사용한다.

```text
Create a production-ready 8-frame hand-painted 2D mobile-game VFX sprite sheet,
effect only, for Mongroo. One 1536x1024 sheet arranged as exactly 2 equal columns
by 4 equal rows, reading left-to-right then top-to-bottom. Keep the same camera,
scale, origin, and impact point in every cell. No gutters, borders, labels,
numbers, or text. Every non-effect pixel must be a uniform flat chroma magenta
#FF00FF. Match the supplied Mongroo art: warm dark-brown ink contour, rounded
hand-painted shapes, matte gouache/cel shading, only 3 value bands, and large
clean silhouettes readable around 360x140 px. No character, hands, monster,
weapon, scenery, floor, UI, watermark, logo, checkerboard, black background,
micro-particle spray, grain, or neighboring-frame fragments.
```

각 시트의 프레임 1~8은 공통으로 `집결 → 형태 생성 → 1/3 이동 → 2/3 이동 →
첫 충돌 → 충돌 확장 → 최대 타격 → 잔상 소멸` 순서를 고정한다. 효과별로 다음
요소를 결합했다.

- `care_vines`: 왼쪽에서 오른쪽으로 연결된 굵은 덩굴, 큰 잎, 오른쪽 휘감기와
  잎 폭발. 세이지·모스·민트·절제된 금색.
- `safe_guard`: 왼쪽 캐릭터 자리를 비운 채 감싸는 타원형 잎 방패, 오른쪽 충돌,
  반동과 잎 소멸. 세이지·민트·크림.
- `ember_arc`: 여우 꼬리 모양 불꽃과 굵은 초승달 베기, 오른쪽 여우불 매듭.
  번트 코럴·감귤색·짙은 적갈색·크림.
- `prism_burst`: 세 개의 결정 꽃잎이 창 형태로 정렬되어 이동하고 오른쪽에서
  큰 네 갈래 결정로 파열. 라벤더·민트·크림·절제된 버터색.
- `mist_dash`: 굵은 물안개 칼날과 두 개의 물방울, 낮은 S자 이동, 오른쪽 물고리
  충돌. 슬레이트 블루·청록·옅은 시안.
- `insight_arc`: 사람 눈이 아닌 달 모양 관찰 렌즈, 두꺼운 붓 호, 오른쪽 표적
  봉인 충돌. 네이비·문 블루·청록·크림.
- `echo_wave`: 씨앗 모양 중심과 큰 산호색·청록 공명 띠, 오른쪽 하트 잎 공명.
  더스티 코럴·피치·청록·크림.
- `enemy_wave`: 오른쪽 장부지기 문양에서 왼쪽으로 이동하는 나선 기록 파동,
  양피지와 돌 문양 파편, 왼쪽 시안·로즈 충돌.

## 크로마 제거와 빌드

ImageGen 원본의 키 색은 가장자리 실측값이 `#FF00FF`와 조금 달라 자동 표본을
사용한다. 굵은 효과 외곽선을 보존하면서 분홍 잔상을 없애기 위해 다음 값으로
고정한다.

```powershell
python <imagegen-skill-root>/scripts/remove_chroma_key.py `
  --input sources/{effect}-chroma.png `
  --out alpha/{effect}.png `
  --auto-key border --soft-matte `
  --transparent-threshold 42 --opaque-threshold 160 `
  --edge-contract 2 --despill --force

python design-system/scripts/build_expedition_combat_vfx.py
python design-system/scripts/build_expedition_combat_vfx.py --report-only
```

빌더는 접촉 시트의 세로 경계를 넘은 큰 잎·충돌광을 64px bleed에서 복원하되,
셀 본체에 65% 이상 속하지 않은 이웃 프레임 컴포넌트는 버린다. 셀 면적의
0.1% 미만인 공중 부스러기도 제거한다. 빈 프레임, 비정상 알파 점유율,
런타임 프레임 가장자리 접촉은 실패로 처리한다.
