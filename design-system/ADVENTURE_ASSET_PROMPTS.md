# 탐험 배경 에셋 생성 기록

프로젝트 출력은 모두 1440×810 RGB WebP다. 원본 생성 이미지는 별도 보관하고,
앱에는 리사이즈·WebP 변환본만 넣었다.

아래 다섯 장은 현재 순찰·던전 카드용 배경의 생성 기록이다. 직접 탐험의 캐릭터,
parallax 지도, 수호자, 이펙트 제작은
`design-system/EXPEDITION_ASSET_PRODUCTION.md`를 우선한다. 직접 탐험 지도는
1920×1080 master를 back/mid/front로 분리하므로 이 1440×810 파일을 확대해 대신하지
않는다.

## 직접 탐험 공통 생성 규칙

- ImageGen은 스타일 콘셉트와 한 자세씩의 key pose 초안에 사용한다. 여러 action과
  8프레임 완성 sprite sheet를 한 번에 요구하지 않는다.
- 캐릭터는 프로젝트의 같은 품종·성장형 reference를 반드시 넣는다. 얼굴, 머리,
  식물 모티프, 체형, 피부색, 광원, 외곽선 두께를 새로 해석하지 않는다.
- stage 5 base는 현재 wardrobe v2 base를 건드리지 않고 새 탐험 action 원본으로
  파생한다. outfit은 승인된 탐험 base frame을 geometry reference로, 기존 wardrobe
  outfit을 design reference로 넣는다.
- character·guardian·item·effect cutout은 단색 `#FF00FF` 배경으로 만들고, 바닥
  그림자·글자·패널선·프레임 번호를 넣지 않는다.
- 이미지에 UI, 한글, 영문, 숫자, 로고, watermark를 넣지 않는다.
- 노출과 성숙한 분위기는 기존 stage 5 성인형 계약 안에서만 유지한다. `baby-pot`과
  stage 1~4에는 성인 노출·관능 지시를 사용하지 않는다.
- 안전 필터에 막히면 같은 프롬프트를 반복하거나 표현을 바꿔 우회하지 않는다. 기존
  pose를 2D rig로 변형하거나 고피복 reference를 유지한다.
- 현존 작가나 상업 캐릭터 이름으로 스타일을 요구하지 않는다. 사용자의 일기 원문이나
  개인정보를 prompt에 넣지 않는다.

## 캐릭터 action key pose

입력 1은 해당 품종·성장형의 wardrobe base 합성, 입력 2는 v4 성체 원형, 입력 3은
승인된 stick-pose storyboard다. 한 번에 한 캐릭터·한 key pose만 만든다.

```text
Use case: character-key-pose
Asset type: one isolated stage-5 mobile game character key pose for 2D animation cleanup
Input images: Image 1 is the exact approved base-layer identity and proportions. Image 2 is the exact emotion-form character reference. Image 3 is pose geometry only. Do not copy any unrelated clothing or background.
Primary request: draw the exact same {species}/{form} character performing the {action} key pose at the {key_phase} moment.
Identity lock: preserve the exact face construction, eye shape, hairstyle, hair color, plant motif, body proportions, skin tone, approved minimal base coverage, warm-brown outline thickness, and top-left soft key light. Do not redesign or beautify the character.
Pose lock: follow Image 3's head, shoulder, elbow, wrist, pelvis, knee, ankle, weight-bearing foot, and facing direction. Keep the feet on the same baseline and leave enough margin for a 128x192 cell.
Style/medium: Mongroo premium 2.5D storybook mobile-game character, matte dimensional cel shading, fine warm-brown ink outline, restrained painterly texture, simple readable silhouette at 96px.
Expression: {expression}; keep it consistent with the approved form and action, not a new personality.
Screen: exactly one full-body character, solid #FF00FF background, no cast shadow, no floor, no text, no panel border, no props except the species-owned signature prop.
Avoid: identity drift, different costume, extra fingers or limbs, realistic anatomy, glossy 3D toy rendering, photoreal skin, neon rim light, ornate accessories, motion blur, cropped hair, cropped feet.
```

생성 결과는 최종 프레임이 아니다. 관절·손·얼굴·색을 정리하고 승인 key pose 사이를
2D rig로 보간한 뒤 `build_expedition_sprites.py` 입력으로 사용한다.

## 탐험 outfit frame

입력 1은 승인된 탐험 base frame, 입력 2는 같은 품종·성장형·의상 키의 기존 wardrobe
합성 프리뷰다. base와 다른 자세를 새로 만들지 않는다.

```text
Use case: outfit-layer-edit
Asset type: one isolated garment layer matched pixel-for-pixel to an approved animation frame
Input images: Image 1 is the exact body pose and canvas geometry. Image 2 is the approved {outfit_key} garment design reference only.
Primary request: dress Image 1 in the exact same {outfit_key} design from Image 2, adjust the fabric folds to Image 1's pose, then remove the entire person and leave only the garment, footwear, stockings, gloves, and outfit-owned accessories.
Pose lock: preserve Image 1's canvas size, character position, limb angles, floor baseline, and silhouette. Do not move, rotate, or rescale the pose.
Design lock: preserve the garment type, cut, hem, neckline, materials, shoes, and palette of Image 2. This is the same outfit in a new animation frame, not a redesign.
Empty body rule: no face, hair, neck, shoulder, arm, hand, finger, bare leg, or bare foot pixels. Do not leave cream or white guide outlines around the missing body. Every body opening must be solid #FF00FF background.
Layer rule: draw only the clothing layer. Do not bake glow, particles, cast shadow, or skin-colored translucent fill into it.
Screen: solid #FF00FF background, no text, no panel line, no mannequin, no hanger.
Avoid: pose drift, different outfit, extra cloth floating away from the body, body-color fill, white edge halo, AI-generated catalog layout.
```

반투명 스타킹·시스루 소재는 실제 alpha를 낮추지 않고 불투명 레이어 안의 명도·색
패턴으로 표현한다. 그래야 base 피부가 프레임마다 달라지지 않는다.

## 지역 parallax master

한 지역의 승인 콘셉트와 기존 몽그루 배경 두 장을 스타일 reference로 넣는다. 먼저
전체 master를 만든 뒤 사람이 back/mid/front를 분리한다. 세 레이어를 각각 새로 생성해
원근이 달라지는 방식은 쓰지 않는다.

```text
Use case: stylized-concept
Asset type: 16:9 mobile game exploration map environment master for later three-depth parallax separation
Input images: Images 1 and 2 are the exact Mongroo style references; Image 3 is the approved {region} concept. Preserve the visual language without copying a previous layout.
Primary request: a readable node-exploration environment for {region}, with one entrance area, two visibly different route bands, a restrained central landmark, and enough empty ground for 8 to 16 code-rendered nodes and links.
Style/medium: hand-inked warm-brown outlines, matte gouache and cel shading, restrained paper texture, practical botanical architecture, subdued detail, cozy storybook mobile game.
Composition: 1920x1080 master, slightly elevated view, back architecture with no thin foreground overlap, middle traversal ground with large simple shapes, sparse foreground framing only at outer edges. Keep the lower 28 percent and side gutters free of essential objects for UI and camera crop.
Lighting/mood: {lighting}; use one broad top-left key light and no separate neon rim lights.
Constraints: no people, characters, creatures, code nodes, path lines, text, letters, numbers, logos, UI, watermark, motion blur, or particle effects.
Avoid: photorealism, game-board squares painted into the art, excessive flowers, fantasy portal, glowing runes, ornate gold, perfect symmetry, dramatic fog, glossy plastic, AI-overdecorated clutter.
```

## 수호자와 목표 아이템

수호자는 적이 아니라 지역의 규칙을 확인하는 비폭력적 식물 존재다. 먼저 정지
turnaround를 승인하고 `idle|reveal|respond|resolve` key pose를 한 장씩 만든다.

```text
Use case: guardian-key-pose
Asset type: one isolated nonviolent botanical guardian key pose for a cozy mobile exploration game
Input images: Image 1 is the approved guardian turnaround. Image 2 is the exact Mongroo style reference. Image 3 is pose geometry only.
Primary request: the exact same {guardian} performing {action}; it is checking, listening, or opening a route, never attacking or being defeated.
Identity lock: preserve the same plant species, pot or root construction, face marks, size, palette, material, outline, and light direction.
Pose lock: follow Image 3 and keep the root/foot pivot fixed. One guardian only, full silhouette visible.
Style/medium: matte 2.5D storybook cel shading, fine warm-brown ink, restrained gouache texture, large readable shapes.
Screen: solid #FF00FF background, no floor shadow, no character, no UI, no text, no weapon, no damage marks.
Avoid: boss monster, combat stance, horror, teeth, skull, weapon, explosion, neon magic, extra limbs, glossy 3D render.
```

```text
Use case: isolated-object
Asset type: one 512x512 transparent-ready exploration objective item
Primary request: {item}, a practical botanical keepsake from {region}, shown at a clear three-quarter angle with a simple silhouette readable at 48px.
Style/medium: Mongroo matte gouache/cel shading, fine warm-brown outline, soft top-left light, restrained paper texture.
Composition: centered object, 12 percent safe margin, solid #FF00FF background, no cast shadow.
Constraints: no text, letters, numbers, logo, UI, character, hands, treasure pile, glow, or particle effect.
Avoid: photorealism, ornate gold, gemstone loot, neon, glossy plastic, fantasy weapon.
```

## 스킬·환경 effect 원본

정확한 경로선, 선택 링, 안개, 갈래 아이콘은 생성하지 않고 코드로 그린다. 생성형
원본은 잎, 종이 섬유, 이끼, 물결처럼 유기적인 cutout에만 쓴다.

```text
Use case: vfx-element
Asset type: one isolated hand-painted organic effect element for a 2D mobile game
Primary request: {effect_element}, designed as a restrained Mongroo {form_or_region} accent that can be animated around a character without hiding the face or action.
Style/medium: matte cel-painted leaf or paper texture, fine warm-brown edge where appropriate, one primary color, one secondary color, small cream highlight, no realistic lighting.
Composition: centered organic element with generous empty margin, solid #FF00FF background, no character, no shadow, no UI.
Constraints: one element only, simple silhouette readable at 32px, no text, no symbol that carries gameplay meaning by itself.
Avoid: lens flare, bloom, neon, lightning, galaxy, magic circle, particles filling the entire canvas, glossy 3D, motion blur.
```

effect 8프레임은 이 원본을 코드 경로와 2D transform으로 움직여 만든다. frame마다
새로 생성해 형태가 끓어오르는 현상을 만들지 않는다.

## 순찰 정원길

- 프로젝트 출력: `app/assets/adventure/patrol-garden-path.webp`
- 스타일 참조: `app/assets/rooms/day-greenhouse-ink.webp`,
  `app/assets/rooms/night-museum-ink.webp`

```text
Use case: stylized-concept
Asset type: 16:9 mobile game patrol environment background
Input images: Image 1 and Image 2 are style references only; do not copy their layout or objects.
Primary request: a quiet patrol trail just outside Mongroo's greenhouse, with two gently branching paths that imply future discoveries.
Scene/backdrop: a cozy botanical garden at early morning, low stone borders, fern beds, small wooden signposts with no writing, one distant greenhouse arch, and a subtle path leading toward a mossy gate.
Style/medium: match the references' hand-inked outlines, matte gouache/cel shading, restrained paper texture, warm storybook game background; polished but not glossy or AI-ornate.
Composition/framing: 16:9 wide scene, eye-level slightly elevated view, clear central walking path, calm open lower-center area for Flutter UI overlays, no close foreground obstruction.
Lighting/mood: soft natural dawn light, warm cream highlights, sage green foliage, muted blue-gray shadows.
Constraints: no people, no characters, no creatures, no text, no letters, no logos, no UI, no watermark; practical believable garden construction; simple large shapes; keep decoration restrained.
Avoid: photorealism, neon, fantasy particles, excessive flowers, gold trim, ornate filigree, symmetry, glassmorphism, dramatic cinematic fog.
```

## 이끼 낀 기억서고

- 프로젝트 출력: `app/assets/adventure/dungeon-moss-archive.webp`
- 스타일 참조: `app/assets/rooms/day-greenhouse-ink.webp`,
  `app/assets/rooms/night-museum-ink.webp`

```text
Use case: stylized-concept
Asset type: 16:9 mobile game dungeon environment background
Input images: Image 1 and Image 2 are style references only; do not copy their layout or objects.
Primary request: the first discovered dungeon, an old botanical memory archive reclaimed by soft moss.
Scene/backdrop: a small underground conservatory archive with curved stone walls, two rows of low wooden specimen drawers, pressed-leaf frames, a sealed round moss-covered door at the back, a single readable path through the center, and a few unlabeled glass seed jars.
Style/medium: match the references' hand-inked outlines, matte gouache/cel shading, restrained paper texture, cozy storybook game environment; mysterious but safe, not horror.
Composition/framing: 16:9 wide room, eye-level symmetrical architecture softened by controlled asymmetry in moss and papers, open lower-center floor for Flutter UI overlays, large simple shapes.
Lighting/mood: muted moon-blue ambient light with two warm amber reading lamps, sage and deep navy palette, calm discovery mood.
Constraints: no people, no characters, no creatures, no readable text, no letters, no logos, no UI, no watermark; no treasure explosion; practical storage furniture; restrained detail.
Avoid: photorealism, horror, skulls, weapons, neon, magical particle clutter, excessive gold, ornate filigree, glossy plastic, dramatic fog.
```

### 직접 조작 지도용 2.5D 배경

- 생성 방식: 내장 ImageGen 신규 생성 후, 이미지 안의 가짜 글자·표식만 같은 원본을
  참조해 제거
- 원본 생성 파일: 로컬 생성 이력에 보존
- 프로젝트 출력: `app/assets/adventure/expedition-moss-archive-map.webp`
- 출력 규격: 1600×800 RGB WebP, Flutter 코드 노드·경로 오버레이 전용
- 검수: 인물·UI·읽을 수 있는 글자 0, 좌우 갈림길과 중앙 출입구 유지, 모바일
  390×844 준비 화면과 346×223 활성 지도 크롭 확인

```text
Use case: stylized-concept
Asset type: wide 2.5D mobile exploration-map environment background
Primary request: an old moss-covered botanical archive and glasshouse library with a clear entrance, two readable branching paths, practical drawers and blank paper tags, and open ground for code-rendered nodes and links.
Style/medium: Mongroo hand-inked warm-brown outlines, matte gouache and cel shading, restrained paper texture, cozy storybook mobile game, subdued practical detail.
Composition: wide 2:1 canvas, slightly elevated view, strong midground paths, central landmark, safe edge crop, no essential object in the lower UI band.
Constraints: no people, creatures, path lines, nodes, icons, UI, letters, numbers, logos, watermark, or readable writing. Paper labels must remain completely blank.
Avoid: photorealism, glossy 3D, neon, magical runes, ornate gold, excessive flowers, perfect symmetry, dramatic fog, AI-overdecorated clutter.
```

## 메아리 우물정원

- 프로젝트 출력: `app/assets/adventure/dungeon-echo-well.webp`
- 스타일 참조: `app/assets/adventure/patrol-garden-path.webp`,
  `app/assets/adventure/dungeon-moss-archive.webp`

```text
Use case: stylized-concept
Asset type: 16:9 mobile game dungeon environment background
Input images: Image 1 and Image 2 are style references only; preserve their hand-inked matte gouache visual language without copying their layouts.
Primary request: a second discovered dungeon called the Echo Well Garden, clearly different from a botanical archive.
Scene/backdrop: a sheltered circular night garden built around a low old stone well, curved stepping stones, four shallow water channels, trimmed ferns and moonflowers, small plain copper listening tubes, and a half-open vine-covered garden gate in the distance. The well is safe and inviting, not bottomless or frightening.
Style/medium: hand-inked outlines, matte gouache/cel shading, restrained paper texture, cozy storybook mobile game environment; practical believable garden construction; restrained detail.
Composition/framing: 16:9 wide scene, slightly elevated eye-level view, the well offset just right of center for controlled asymmetry, open lower-center paving for Flutter UI overlays, large readable shapes.
Lighting/mood: muted moon-blue ambient light, warm amber path lanterns, sage foliage, quiet curiosity and gentle discovery.
Constraints: no people, no characters, no creatures, no readable text, no letters, no logos, no UI, no watermark; no weapons or treasure pile.
Avoid: photorealism, horror, skulls, neon, magical particle clutter, glowing fantasy portal, excessive flowers, ornate gold, glossy plastic, dramatic fog.
```

## 별빛 씨앗 보관고

- 생성 방식: 내장 ImageGen, 기존 던전 두 장을 스타일 참조로 사용
- 프로젝트 출력: `app/assets/adventure/dungeon-starlight-seed-vault.webp`
- 스타일 참조: `app/assets/adventure/dungeon-moss-archive.webp`,
  `app/assets/adventure/dungeon-echo-well.webp`

```text
Use case: stylized-concept
Asset type: 16:9 mobile game dungeon environment background
Input images: Image 1 and Image 2 are style references only. Preserve their hand-inked outlines, matte gouache/cel shading, restrained paper texture, practical architecture, subdued detail density, and cozy storybook game visual language. Do not copy their layouts.
Primary request: a third, higher-growth dungeon called the Starlight Seed Vault, clearly different from the moss archive and echo well garden.
Scene/backdrop: a compact rooftop seed conservatory above an old greenhouse at pre-dawn. Weathered dark stone and muted copper frames support a partially open glass roof. A low circular stone germination table sits slightly left of center, holding several simple unlabeled ceramic seed trays. Along the back wall are practical shallow seed cabinets and one closed round brass-and-wood vault door with a restrained star-shaped ventilation pattern, not a magical portal. A narrow rooftop garden path enters from the right. A few pale seed husks and two plain glass cloches catch starlight.
Style/medium: hand-inked outlines, matte gouache/cel shading, restrained paper texture, cozy storybook mobile game environment; polished but not glossy, ornate, or AI-overdecorated.
Composition/framing: wide 16:9 establishing view, slightly elevated eye level, readable large shapes, controlled asymmetry, open lower-center stone floor for Flutter UI overlays, no close foreground obstruction. Keep the main visual interest in the middle third so a 16:9 image remains readable when cropped into a 126px-tall card.
Lighting/mood: deep muted indigo pre-dawn sky, soft cream starlight through the glass roof, two small warm amber work lamps, sage foliage, desaturated copper, quiet anticipation and earned discovery.
Materials/textures: worn stone, aged matte copper, slightly dusty glass, unfinished wood cabinets, paper-soft foliage.
Constraints: no people, no characters, no creatures, no readable text, no letters, no numbers, no logos, no UI, no watermark; practical believable conservatory construction; simple large shapes; safe and inviting rather than ominous.
Avoid: photorealism, horror, skulls, weapons, treasure piles, neon, glowing fantasy portals, floating particles, excessive stars, galaxy effects, excessive flowers, ornate gold filigree, glossy plastic, dramatic cinematic fog, perfect symmetry.
```

## 마음나무 관측실

- 생성 방식: 내장 ImageGen, 기존 탐험 배경 세 장을 스타일 참조로 사용
- 프로젝트 출력: `app/assets/adventure/dungeon-heartwood-observatory.webp`
- 스타일 참조: `app/assets/adventure/patrol-garden-path.webp`,
  `app/assets/adventure/dungeon-moss-archive.webp`,
  `app/assets/adventure/dungeon-starlight-seed-vault.webp`

```text
Use case: stylized-concept
Asset type: 16:9 mobile game final dungeon environment background
Input images: Images 1, 2, and 3 are style references only. Preserve their hand-inked outlines, matte gouache/cel shading, restrained paper texture, practical botanical architecture, subdued detail density, and cozy storybook game visual language. Do not copy their room layouts or focal objects.
Primary request: a final growth-stage exploration location called the Heartwood Observatory, a calm place for reviewing years of plant growth rather than a boss room or treasure chamber.
Scene/backdrop: a compact timber-and-stone botanical observation room built around one mature living tree trunk that passes naturally through the floor and open rafters, positioned slightly left of center. A low circular wooden measuring platform surrounds the trunk without harming it. The back wall has one wide horizontal window overlooking greenhouse treetops at sunrise. Practical sloped workbenches hold unlabeled growth-ring samples, plain ceramic seed dishes, a simple brass magnifying lens on a stand, and analog measuring tools with no writing. A narrow wooden walkway enters from the right. Shelves and architecture are functional, worn, and restrained.
Style/medium: hand-inked outlines, matte gouache/cel shading, restrained paper texture, cozy storybook mobile game environment; polished but not glossy, ornate, or overdecorated.
Composition/framing: wide 16:9 establishing view, slightly elevated eye level, strong readable silhouette from the tree trunk and sunrise window, controlled asymmetry, open lower-center floor for Flutter UI overlays, no close foreground obstruction. Keep the trunk, measuring platform, window, and main workbench inside the middle horizontal band so the scene remains clear when cropped into a 126px-tall card.
Lighting/mood: gentle peach-and-cream sunrise through the wide window, muted sage foliage, weathered walnut wood, blue-gray stone shadows, small warm work lamp accents; reflective, earned, comforting, and quietly conclusive.
Materials/textures: rough living bark, worn matte wood, aged stone, brushed muted brass, handmade ceramic, paper-soft foliage.
Constraints: no people, no characters, no creatures, no readable text, no letters, no numbers, no logos, no UI, no watermark; believable safe conservatory construction; large simple shapes; the living tree must look healthy and naturally integrated, not imprisoned or cut.
Avoid: photorealism, fantasy throne room, boss arena, horror, skulls, weapons, treasure piles, neon, glowing tree, magical runes, floating particles, excessive flowers, excessive gold, ornate filigree, galaxy effects, glossy plastic, dramatic cinematic fog, perfect symmetry.
```
