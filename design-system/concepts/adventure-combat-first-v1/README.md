# 전투 중심 모험 화면 ImageGen 시각 기준안 v1

최종 갱신: 2026-08-10
상태: **layout visual target only — production asset 아님**

## 산출물

- 파일: `combat-first-visual-target-v1.png`
- 실제 규격: 864×1821, 24-bit RGB PNG, 2,452,018 bytes
- SHA-256:
  `DA92DAB816C6BDD4D01DF9333AE619465DA498350F660B92A85F96B9750C29F7`
- 생성 도구: Codex 내장 ImageGen
- 목적: 세로형 기본 모험이 지도·설명 카드가 아니라 전투 무대를 중심으로 읽히는지 검토

## 입력 이미지와 역할

| 순서 | 프로젝트 파일 | 역할 |
|---:|---|---|
| 1 | `app/assets/adventure/expedition-monster-den-battle-v1-mobile.webp` | 빈 전장·식생·석조·조명 스타일 참조 |
| 2 | `app/assets/characters/baby-pot-v2.webp` | 뽀또 정체성 참조 |
| 3 | `app/assets/characters/pretty-pot-v2.webp` | 블루미 정체성 참조 |
| 4 | `app/assets/characters/handsome-pot-v2.webp` | 로제온 정체성 참조 |
| 5 | `app/assets/adventure/ledger-keeper-idle-v1-mobile.webp` | 장부지기 수호자 정체성 참조 |

입력은 모두 프로젝트 소유 에셋이다. 일기 원문·사용자 이름·감정 분석 문장·외부 IP
이미지는 사용하지 않았다.

## 생성 프롬프트

```text
Use case: ui-mockup
Asset type: polished portrait mobile RPG battle screen visual target, approximately 9:19.5
Input images:
- Image 1: base battle environment and painterly moss-archive style reference
- Image 2: Potto character identity reference
- Image 3: Bloomi character identity reference
- Image 4: Rozeon character identity reference
- Image 5: Ledger Keeper guardian identity reference
Primary request: create a shippable-looking combat-first adventure screen where exploration and battle happen in one continuous scene, not separated into cards or panels.
Scene/backdrop: extend Image 1 into a tall portrait composition while preserving its warm hand-painted forest-ruin mood, shared floor plane, roots, moss, stone, and soft lantern light. Keep the central battlefield open and readable.
Subjects: preserve the recognizable faces, outfits, silhouettes, and color palettes of Images 2–5. Arrange Potto, Bloomi, and Rozeon as a three-person party on the lower-left and center-left, all facing the Ledger Keeper on the upper-right. The guardian is non-horrific and readable at mobile size. Show Potto actively casting one tangible leafy vine projectile; the vine has a clear origin at Potto, a visible curved travel path, and a small contact burst near the guardian. Do not add extra characters.
UI hierarchy: the battlefield occupies about 76% of the screen. UI floats only at the edges:
- a very thin top progress rail with eight small pictorial stage nodes;
- three compact icon-only utility controls at the top-right;
- a small health bar, intent glyph, target marker, weakness glyph, and resistance glyph attached close to the guardian;
- subtle short health arcs near each party member's feet;
- a translucent dark-to-clear bottom gradient with three circular party portraits above six large, distinct painted skill icon slots in one row;
- one selected skill has a restrained luminous ring.
Style/medium: realistic product UI mockup over polished painterly 2D game art; premium Korean mobile collection RPG clarity; warm botanical fantasy; tactile hand-painted skill icons; subtle depth and soft contact shadows.
Composition/framing: portrait mobile screen, one camera and one floor plane; actors and projectile all visible simultaneously; bottom skill dock must not cover feet or impact path.
Lighting/mood: calm but exciting, rich forest greens and amber lantern light, focused highlights only on active skill and contact point.
Constraints: no written text, no letters, no numbers, no fake Korean, no logos, no watermark; no white cards, no opaque information panels, no split screen, no map panel, no dialog box, no paragraph areas, no sci-fi chrome, no extreme bloom, no screen-filling particles, no blood, no death pose. UI glyphs must be simple and readable. Preserve character identities; do not redesign their faces or costumes.
```

## 승인한 것

1. 배경·캐릭터·수호자가 한 원근과 한 바닥을 공유한다.
2. 전장이 세로 화면의 약 76%를 차지하고 UI가 가장자리로 물러난다.
3. 세 파티원·수호자·공격 origin·travel·contact가 한 프레임에서 읽힌다.
4. 상단 8점 progress rail과 하단 3초상+6스킬 구조가 무대를 별도 카드로 자르지 않는다.
5. 설명문 없이도 현재 적·행동자·선택 스킬·접촉점의 시선 순서가 생긴다.
6. 덩굴이 코드 곡선처럼 보이는 빛줄기가 아니라 잎·마디가 있는 실제 공격 물체로 보인다.

## 승인하지 않은 것

- 정확한 캐릭터 scale·pose·전투 anchor
- 생성 이미지 속 HP bar·progress glyph·utility glyph·스킬 아이콘의 최종 디자인
- 배경 geometry와 전경 뿌리의 최종 좌표
- 한 장에 합성된 빛·그림자·덩굴을 runtime layer로 사용하는 것
- PNG를 자른 character, guardian, VFX, UI 또는 store screenshot
- 스프라이트 연속성·alpha edge·contact timing·실제 기기 성능

이 이미지는 제품 화면처럼 보이지만 layout discussion을 위한 합성 콘셉트다. manifest에는
`production_ready:false`, `usage: visual_target`으로 기록하고 런타임 asset resolver가
참조하지 않게 한다.

## 다음 제작 순서

1. 같은 카메라의 `backplate/midground/floor/foreground/depth-mask`를 분리 제작한다.
2. 뽀또 `anticipate/cast/recovery`, 장부지기 `anticipate/hit/release` pose를 정리한다.
3. 덩굴 family는 `anticipation → travel_mid → first_contact → max_impact → fade`를 한
   키프레임씩 ImageGen으로 만들고 이전 승인본을 다음 호출의 참조로 사용한다.
4. chroma 제거·despill·paint-over 뒤 10F in-between과 atlas padding을 만든다.
5. 코드 HUD를 별도로 올려 390×844 1×·2×·짧은 연출·reduce motion 합성 영상을 검수한다.
6. layout, identity, alpha, blend, contact, audio sync, memory gate가 모두 통과한 뒤에만
   세로 슬라이스를 `production_ready:true`로 승격한다.
