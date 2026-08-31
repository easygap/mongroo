# 모험 스킬 아이콘 v3 — 여섯 성장결과 서고 안내자

생성일: 2026-08-31
생성 도구: ChatGPT ImageGen(`gpt-image` 스킬 배치), `stylized-concept`
상태: **앱 연결 완료 / production candidate / 실기 Q 미완료**

## 왜 이 여덟 장인가

전투 명령 벨트에서 아이콘이 없는 행동은 효과 시트의 한 프레임을 잘라 대신
보여 준다. v2까지 남아 있던 구멍이 정확히 여덟 개였고, 그중 여섯이 **모든
사용자가 매 전투에서 보는 자리**였다.

| 구멍 | 누가 보나 |
| --- | --- |
| 여섯 성장결 스킬 (`선택 I`) | 전원. 자기 결의 스킬이 기본으로 장착된다 |
| 안내자 고유 I·II | 안내자를 편성한 전원 |

성장결 스킬은 품종이 아니라 마음이 정하는 자리라 `emotion/`에 따로 둔다. 열여섯
품종이 각자 폴더를 갖는 것과 같은 이유로, 이 여섯은 어느 품종에도 속하지 않는다.

## 산출물·해시

| code | 표시 | master SHA-256 | runtime SHA-256 |
| --- | --- | --- | --- |
| `sunny_radiant_heart` | 찬란한 하트 · 빛의 하트와 회복 광선 | `86275F165087E747D3232F630B9B883BE109C682E6BA6F956BEE5E8CA85A6505` | `03877E2A322338981621A08AAE639BF8AB6D41F80AD71400D5195DA133BB6578` |
| `rainy_frozen_tide` | 얼어붙은 파도 · 얼며 멈춘 물마루 | `7699B8A07577B8543EBF3DCD6AE3B6F01F9B7160006C8ACB3FBF813AE8EAD60B` | `71634E9FAC3A9E4D405C403A673201BB4666D056BD8055833C6FA3E4CD49ADC8` |
| `ember_rage_breaker` | 분노 파쇄권 · 장벽을 깨는 불꽃 정권 | `C559FBD802375156965EC66BC65D28D28A55C613B43DE86FEEC50748224DB7DA` | `45733D7E2127BD8B2FD1DD78364B3D36FE196C5CD3F519E3C00AA1F161D03207` |
| `moonlit_lonesome_tempest` | 고독의 돌풍 · 초승달을 품은 소용돌이 | `EB45B400688471BB5B39B77E5FDCC302F78E6893F285302C59A80CC3BFF46824` | `69185D935B9AE88AC185BB106480DED4F57236EFECC7D889151720DB66C54510` |
| `sparkling_shock_wonder` | 경이의 전격 · 약점에서 한 번 더 갈라지는 번개 | `020128DB237DA569DE7F066FCEADE878446F10AD2CEC8A2E73E83DBEE9AF594D` | `EBF48487335271D0FC2C0BD18D343AE32BE5927F9D6E888120BCEBEA141DFCB8` |
| `mosaic_steel_equilibrium` | 강철 평형장 · 면이 돌아가는 육각 강판 | `BC42864E977A9F26A0FAE139AC80943B773F6121C9C87DFF9B3A6E4F1ED98597` | `3A3658AAFBD8A8A2455EC5A0732A22147E339A28F7B72D127BD169B3038A340A` |
| `archive_lantern` | 기록 등불 · 낮게 두른 빛 띠 | `479B15F686DA16B0C0D609E85411746AD24D28776E3D227F8E72E10CD219ED3A` | `62F5FADE7AC3C5203C2B7FB1CF0A763785484B8087FE482D04FEC6CC228FD379` |
| `archive_seal` | 기록 봉인 · 밀랍으로 잠근 기록 띠 | `AEC8743A5E498D68E708D6BBD401537D2A592F342BBE2FB4DB45BBA90D6C6A09` | `50B285A6B6C10F92B23F3B08F3E5D968CAFE0E9BA8BB35E4E7E29569E018CC31` |

- master: `sources/{emotion|archive-guide}/*.png`, 1254×1254 RGB PNG
- runtime: `app/assets/adventure/skill-icons/{emotion|archive-guide}/*.webp`,
  256×256 RGB WebP, Lanczos, quality 88, method 6
- QA: `emotion-guide-icons-48px-qa.webp` — 밝은 면·어두운 면의 실제 48px 표시와
  128px 확대 한 줄
- 글자·비용·쿨타임·tier·약점·내성·잠금은 원화에 굽지 않고 Flutter가 올린다.

## 여섯이 서로 갈리는 방식

같은 자리에 번갈아 들어오므로, 48px에서 **실루엣만으로** 갈려야 한다. 여섯을
서로 다른 기본 도형에 배정했다.

| 결 | 실루엣 | 주 색(서버 `EMOTION_VFX_PALETTES`) |
| --- | --- | --- |
| 햇살결 | 앞으로 날아가는 하트 + 꼬리 | `#FFD48A` / `#FF8FA8` |
| 빗물결 | 왼쪽에서 말려 오는 물마루 | `#8FD8F2` / `#B7C8FF` |
| 불씨결 | 사선 정권 + 갈라진 판 | `#FF7B61` / `#FFC05C` |
| 달빛결 | 도는 소용돌이 | `#9DA7E8` / `#71C6C8` |
| 별빛결 | 꺾인 번개 + 별 | `#C6A8FF` / `#FFE37A` |
| 모아결 | 서 있는 육각 판 | `#A8C5BE` / `#D8C9B7` |

색은 서버 팔레트를 그대로 받았다. 아이콘과 그 결의 VFX가 다른 색을 쓰면 같은
행동이 두 가지로 보인다.

## 공통 프롬프트 계약

v1·v2와 같은 계약을 쓰되, 성장결은 품종 모티프를 물려받지 않으므로 식물 금지
조항을 유지했다. 한 호출에 한 아이콘만 생성했고 배치로 여덟을 함께 돌렸다.

```text
Use case: stylized-concept
Asset type: production mobile RPG skill UI icon master
Input images: the attached existing skill icons are style, paint handling,
ink-edge weight, contrast, and 48px readability references only; do not copy or
reuse their motifs.
Style/medium: premium 2.5D hand-painted storybook mobile-game icon, matte
dimensional cel shading, fine warm-brown ink outline, restrained painterly
texture, polished released-game quality
Composition/framing: 1024x1024 square full-bleed icon; exactly one coherent
motif occupying 64-70% of the canvas; strong readable silhouette at 48px;
generous inner safe margin
Constraints: no character face; no leaves, vines, flowers, roots, seeds,
sprouts or botanical shapes; no typography, letters, numbers, UI border, badge,
cost, watermark, logo, mockup, grid, multiple icons, photorealism, neon bloom,
smoke, transparent background
```

레퍼런스로는 성장결에 `sunny-warmth-share-v1.png`(같은 선택 슬롯의 옛 아이콘),
안내자에 `root-embrace-v1.png`·`field-note-echo-v1.png`(보호·기록 계열)를
붙이고, 붓질 대조군으로 `nine-tail-eclipse-v1.png`·`shadow-execution-v1.png`·
`venom-seam-v1.png` 중 하나를 함께 넣었다.

### `sunny_radiant_heart`

```text
Primary request: emotion growth-branch skill "Radiant Heart" for a sunlight
temperament; one bold heart shaped entirely from warm solid daylight launches
toward the upper right as a real projectile attack, and a single slim mending
ray peels off its lower-left trail to reach a companion. It must read at a
glance as an attack that also gives one small heal, never as a pure healing
bloom or a romantic sticker.
Palette/material: warm honey-gold #FFD48A as the dominant light body, soft
rose-coral #FF8FA8 accent on the mending ray, deep amber shadows, muted
cream-to-warm-brown radial backdrop; painted stained-glass light and matte
gilded rim, not glossy plastic.
```

### `rainy_frozen_tide`

```text
Primary request: emotion growth-branch skill "Frozen Tide" for a rain
temperament; one low broad wave rolls in from the left and its crest freezes
mid-curl into three blunt pale ice shards, so the eye reads water becoming ice
in a single shape. It must feel quiet, heavy and controlled rather than stormy
or explosive, and it must read as an attack that locks the enemy in place.
Palette/material: pale sky-blue #8FD8F2 water body, cool periwinkle #B7C8FF
frozen crest, deep slate-teal shadow trough, muted mist-grey to deep-blue
radial backdrop; painted matte water with frosted, slightly translucent ice, no
sparkle glitter.
추가 금지: no rain droplets falling as separate small dots
```

### `ember_rage_breaker`

```text
Primary request: emotion growth-branch skill "Rage Breaker" for an ember
temperament; one compact fist made of compressed flame drives diagonally to the
upper right and cracks a slab-like barrier plate at the contact point, with a
short guard ring of the same flame wrapping back around the wrist. It must read
as a decisive barrier-breaking punch that also shields the user, not as a
fireball or an explosion.
Palette/material: hot coral-red #FF7B61 flame core, warm amber #FFC05C edge
flare, charred deep-brown barrier slab, muted ash-to-deep-ember radial
backdrop; painted matte flame with soft carbon edges.
추가 금지: no visible human skin or knuckles rendered realistically
```

### `moonlit_lonesome_tempest`

```text
Primary request: emotion growth-branch skill "Lonesome Tempest" for a moonlit
temperament; three slim wind arcs spiral counter-clockwise into one tight
vortex whose empty centre is shaped by a thin crescent of pale moonlight, as if
the wind is searching a gap in the enemy's stance. It must read as a probing
control wind, calm and watchful, not as a tornado disaster or a cute breeze
swirl.
Palette/material: dusky periwinkle #9DA7E8 wind bands, cool jade-teal #71C6C8
inner rim, pale ivory crescent, muted indigo-to-slate radial backdrop; painted
matte air ribbons with a faint pearl sheen, no particles and no dust specks.
추가 금지: do not draw a full circular moon disc
```

### `sparkling_shock_wonder`

```text
Primary request: emotion growth-branch skill "Shock Wonder" for a starlight
temperament; one bold angular bolt strikes down from the upper left, and at the
moment it lands it forks once more into a shorter second bolt that pierces a
small four-point star-shaped weak point. It must read as an unpredictable
strike that hits twice when it finds a weakness, not as a generic thunder
symbol.
Palette/material: soft violet #C6A8FF bolt body, warm pale-gold #FFE37A
ignition core and star, deep plum shadow, muted lilac-to-midnight radial
backdrop; painted matte voltage with crisp faceted edges, no glow spray and no
lens flare.
추가 금지: no cloud shapes
```

### `mosaic_steel_equilibrium`

```text
Primary request: emotion growth-branch skill "Steel Equilibrium" for a
many-feelings temperament; one hexagonal brushed-steel field plate stands
upright and slightly turned, and three of its facets have already rotated out
of alignment into a new arrangement, so the eye reads a shield that reshapes
itself to match whatever is coming. It must feel balanced and unshowy, never a
magic barrier bubble or a sci-fi hologram.
Palette/material: soft sage-steel #A8C5BE plate, warm sand-beige #D8C9B7
rotated facets, deep graphite shadow seams, muted stone-grey to deep-slate
radial backdrop; painted brushed metal with matte finish and faint
hand-hammered texture, no chrome reflection and no glowing lines.
```

### `archive_lantern`

```text
Primary request: archive-guide unique skill I "Record Lantern"; one small
aged-brass reading lantern hangs slightly tilted and throws a wide low ring of
warm library light that closes into a thin protective band around it, so the
eye reads a lantern that covers a whole party rather than a single lamp. It
must feel like a librarian's quiet protection, an old tool doing careful work,
not a magic staff or a holy relic.
Palette/material: aged brass and warm copper body, ivory parchment light,
restrained honey-amber halo, deep walnut-brown shadows, muted
bookbinding-brown to deep-sepia radial backdrop; painted oxidised metal, waxed
paper and worn leather, matte rather than polished.
추가 금지: no candle flame drawn as a separate teardrop; no readable text
```

### `archive_seal`

```text
Primary request: archive-guide unique skill II "Record Seal"; one long band of
aged record paper unfurls diagonally to the upper right like a thrown ribbon
and its far end loops closed under a single deep-red wax seal, so the eye reads
one strike that binds and then holds. It must read as an offensive binding
band, heavier and sharper than a gentle lantern glow, and never as a gift
ribbon or a scroll being politely read.
Palette/material: aged ivory parchment band, deep oxblood wax seal, restrained
brass edge trim, walnut-brown ink shading, muted archive-brown to deep-sepia
radial backdrop; painted fibrous paper, cooled wax and worn metal, matte
finish.
추가 금지: no readable text or written lines on the band
```

## 남은 것

- 실제 기기에서 48dp 탭 영역·명암 대비·스크린리더 라벨 검수(Q).
- 성장결 스킬의 T2·T3 표시 변화는 아직 원화가 아니라 Flutter 상태 레이어가
  올린다. tier별 원화는 이 범위 밖이다.
