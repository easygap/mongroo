# 모험 스킬 아이콘 v2 — 첫 비식물 캐릭터 세로 슬라이스

생성일: 2026-08-10
생성 도구: Codex 내장 ImageGen, `stylized-concept`
상태: **앱 연결 완료 / production candidate / 실기 Q 미완료**

`combat_identity_progression_design.md`의 첫 비식물 정체성 검증이다. 구미호는
하트·달, 닌자는 독·그림자로 읽혀야 하며 기존 잎·덩굴·뿌리 모티프를 재사용하지
않는다. 한 호출에 한 아이콘만 생성했고, 결과를 128px WebP로 파생했다.

## 산출물·해시

| code | 표시 | master SHA-256 | runtime SHA-256 |
|---|---|---|---|
| `heart_moon_charm` | 심월 매혹 · 초승달+하트 참 | `16CD92EF892B80C10EE146A5072AEE05C96DD2285F6C8AA4352EF4AC4BC4950D` | `D7A221F123A2E43B8936FEA7CED81089ED60688C6F15F521073DF40FBCC3B9AA` |
| `nine_tail_eclipse` | 구미 월식 · 아홉 달그림자 | `880318063C685A512206935828CBB0CC48C11890D2412190EE27BFF30E9610E1` | `F76916BD3C49E9E1CB362C7195B620730E3BE9BA65A2D90111E9197B9A0FAFC0` |
| `venom_seam` | 맹독 틈베기 · 독 홈 단검 | `F0FAD2849BFA198247D4DAFBF66DC7418B08DB3D2D453962ADED6F38785FE3E3` | `E84934205A67A8DA535C224B24E7F5588095E7CF34ABD98122F2D66A6EEF66D6` |
| `shadow_execution` | 무영 처형 · 교차 단검 잔상 | `0EB351A8018FC0141046D3333E0226ACA581D95EB24C8972A08CC34ADF5154B8` | `79446442E3DD98D0AD4688F5065FF0F34EED35989B2FBFFE216EB278AA1B436E` |

- master: `sources/{gumiho-pot|ninja-pot}/*.png`, 1536×1536 RGB PNG
- runtime: `app/assets/adventure/skill-icons/{gumiho-pot|ninja-pot}/*.webp`,
  128×128 RGB WebP, Lanczos, quality 88, method 6
- QA: `non-plant-icons-48px-qa.webp`, light/dark 배경에서 실제 48px 표시
- 글자·비용·쿨타임·tier·약점·내성·잠금은 원화에 굽지 않고 Flutter가 올린다.

## 공통 프롬프트 계약

```text
Use case: stylized-concept
Asset type: production mobile RPG skill UI icon master
Input images: existing baby-pot icons are style, paint handling, edge, contrast,
and small-size readability references only; do not reuse plant motifs.
Style/medium: premium 2.5D hand-painted storybook mobile-game icon, matte
dimensional cel shading, fine warm-brown ink outline, restrained painterly
texture, polished released-game quality
Composition/framing: 1024x1024 square full-bleed icon; one coherent motif
occupies 64–70%; strong silhouette at 48px; generous inner safe margin
Constraints: no character face; no leaves, vines, flowers, roots, seeds,
branches, sprouts, botanical shapes; no typography, numbers, UI border,
badge, cost, watermark, logo, mockup, grid, multiple icons, photorealism,
excessive bloom, smoke
```

### `heart_moon_charm`

```text
Primary request: Gumiho unique skill I “Heart Moon Charm”; a sharp crescent
moon made of warm ivory light interlocks with one elegant rose-coral
heart-shaped charm, sending a focused magical slash toward the upper right.
It must read as seductive moon sorcery and a real attack, not healing.
Palette/material: deep plum and midnight indigo, warm ivory moonstone,
rose-coral silk-ribbon magic, restrained gold; matte rather than glossy.
```

### `nine_tail_eclipse`

```text
Primary request: Gumiho unique skill II “Nine-Tail Eclipse”; nine slim
crescent-moon shadows fan outward like supernatural tails around one dark
eclipsed moon, forming a decisive control spell; no heart symbol.
Palette/material: midnight indigo, muted violet, warm ivory moon rim,
restrained copper-gold; painted moonstone and silk-like shadow arcs.
```

### `venom_seam`

```text
Primary request: Ninja unique skill I “Venom Seam”; one compact black kunai
with a deep violet poison groove slices diagonally upward, leaving one precise
toxic seam and a small sharp contact spark. It must read as a real poison
weapon attack, not nature magic.
Palette/material: charcoal, blue-black, muted toxic violet, acid-lime only
inside the groove, restrained silver; matte forged metal and viscous poison.
```

### `shadow_execution`

```text
Primary request: Ninja unique skill II “Shadow Execution”; two matte-black
short blades cross in one silent X-shaped execution slash, with one offset
indigo X afterimage suggesting a shadow clone; no poison.
Palette/material: blue-black, midnight indigo, cold silver edges, muted violet
contact glint; matte forged metal and cloth-like shadow.
```

## 검수 결과와 남은 gate

- 48px light/dark에서 네 실루엣이 `초승달+하트 / 아홉 달꼬리 / 독 단검 /
  교차 단검`으로 구분된다.
- 식물 모티프와 문자·수치가 없다.
- 네 runtime 파일이 앱 asset manifest와 행동 code에 연결됐다.
- 아직 tier별 아이콘, 실제 기기 대비, 색각·스크린리더, 캐릭터 cast pose,
  travel/contact sprite, SFX 동기화가 없으므로 `production_ready`로 승격하지 않는다.
