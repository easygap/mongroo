# 모험 스킬 아이콘 v1 — P1 뽀또 세로 슬라이스

생성일: 2026-08-10
생성 경로: Codex 내장 ImageGen, `stylized-concept`
상태: **P1 앱 연결 완료 / 네 아이콘만 production 후보**
범위 밖: 전체 102개 아이콘, T2·T3, 나머지 품종, 기록서 전체

각 아이콘은 한 호출에 하나씩 생성했다. 글자·비용·잠금·약점·테두리는 이미지에
굽지 않았고 Flutter가 상태 레이어로 올린다. 1024px PNG master는 `sources/baby-pot`,
앱용 128px WebP는 `app/assets/adventure/skill-icons/baby-pot`에 있다.

## 산출물

| action code | 역할 | master SHA-256 | runtime SHA-256 |
| --- | --- | --- | --- |
| `sprout_cheer` | 고유 I · 실제 덩굴 발사 | `6CDB6F45DD7CA0CFA31301562556C237586CA54E1302191FABC3EAD98FFAAD65` | `AECA3AE9AAAC9DEE423CC8E477CD7EDFF2E8819AB8C9613DBF7E8894E5C6DF4D` |
| `root_embrace` | 고유 II · 회복 | `721A93CD3B50F8CF550E4EBEDC3758B6D714CD5D67B5274491BC3582EB88F2A4` | `9577124073D55E263B19028BE3615B717C63B2137EA24F76E7172C015A55C5DA` |
| `sunny_warmth_share` | 선택 I · 성장결 | `D6F5E218ECFB70A0E28C80CE131C8F8213BB127AE7BB834155AF46A50F95A3BB` | `8861BD386264866BC1D837EEF1467944B98C5D0DB5403F85117B441F8937CFBE` |
| `field_note_echo` | 선택 II · 스킬북 | `CDD106D2DAFFB84439406AD81409AFF75438499E64008E28ADA14404D200EB1E` | `D6091CAC16FD38106A2122B624375CB97127AAAD6DF17750A1829B446E7FFDFA` |

`baby-pot-icons-48px-qa.webp`는 앱 표시 크기에서 실루엣 중복과 뭉개짐을 보는
검수 접촉 시트다. 네 아이콘은 투사체·보호/회복·공유·기록서 실루엣이 서로 다르고
48px에서 핵심 사물이 남는다.

## 최종 프롬프트

공통:

```text
Use case: stylized-concept
Asset type: production mobile RPG skill UI icon master
Style/medium: premium 2.5D hand-painted storybook mobile-game icon, matte dimensional cel shading, fine warm-brown ink outline, restrained painterly texture, polished released-game quality
Composition/framing: 1024x1024 square full-bleed icon; motif occupies 62–70% of canvas; strong readable silhouette at 48px; generous inner safe margin
Constraints: exactly one coherent motif; no character face; no typography, letters, numbers, UI border, badge, cost, watermark, logo, mockup, grid, multiple icons, photorealism, neon bloom, smoke, transparent background
```

### `sprout_cheer`

```text
Primary request: Baby-Pot unique skill I “Sprout Cheer”; a compact young olive-green vine bud launching one lively curling vine toward the upper-right, conveying a real projectile attack that will become a vine sprite sequence
Subject: one dominant spiral vine bud, two broad leaves, one clean curling vine tip, tiny warm-gold impact seed
Lighting/mood: warm gentle courage, focused action, clear rim light
Color palette: olive green, pale leaf green, warm gold, deep moss shadows; muted cream-to-deep-moss radial backdrop
Materials/textures: soft leaf veins, matte plant surface, no glossy plastic
```

### `root_embrace`

```text
Primary request: Baby-Pot unique skill II “Root Embrace”; two strong olive-green roots sweep upward and interlock into a protective cradle, holding one warm amber dew seed, clearly different from a projectile attack and readable as healing protection
Subject: one coherent pair of intertwined roots, two small leaves, one amber dew seed, subtle protective halo
Lighting/mood: nurturing, grounded, quietly powerful
Color palette: olive green, pale leaf green, warm amber, deep moss shadows; muted cream-to-deep-moss radial backdrop
Materials/textures: soft root fibers and leaf veins, matte plant surface
```

### `sunny_warmth_share`

```text
Primary request: equipped emotion skill “Warmth Share”; one broad fresh leaf shaped like a gentle cup passes a glowing sun-warm droplet toward a smaller leaf, instantly readable as sharing healing warmth
Subject: two leaves in one diagonal gesture, one soft golden droplet traveling between them, three restrained sun-ray accents
Lighting/mood: sunny, kind, restorative, active rather than passive
Color palette: fresh leaf green, pale mint, butter gold, warm cream, deep moss shadows; soft golden-green radial backdrop
Materials/textures: matte leaves with sparse veins, soft painted light
Avoid: heart symbol
```

### `field_note_echo`

```text
Primary request: equipped skillbook skill “Field Note: Echo”; a small folded leaf-paper field note releases one precise concentric echo ring that becomes a focused seed projectile, readable as knowledge converted into a returning combat resource
Subject: one compact leaf-paper note with a simple blank embossed spiral, one seed-shaped quill, two concentric teal-gold echo arcs
Lighting/mood: observant, clever, calm impact
Color palette: parchment cream, muted teal, warm gold, deep moss and ink-brown shadows; desaturated teal-to-moss radial backdrop
Materials/textures: fibrous leaf paper, matte seed shell, restrained painted glow
Constraints addition: blank note with no readable writing
```

## 런타임 파생

- master: 1024×1024 RGB PNG
- runtime: 128×128 RGB WebP, Lanczos, quality 88, method 6
- 표시: 44px 기본, 64px 상세 시트
- 원본은 덮어쓰지 않는다.
- 전체 102개 제작 때는 이 네 장을 스타일·명암 기준으로 사용하되 모티프를 복제하지
  않는다.
