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

### 이끼 기억서고 통합 탐험 지형 v2 — 사용 중단

- 생성 방식: 2026-08-06 내장 ImageGen `stylized-concept` 편집 생성
- 스타일 참조: `app/assets/adventure/expedition-moss-archive-map.webp`
- 프로젝트 출력: `app/assets/adventure/expedition-moss-archive-terrain-v2.webp`,
  1600×900 RGB WebP, 품질 88
- 좌표 계약: 입구 `(.08,.50)`, 침수 동굴 `(.28,.27)`, 뿌리 땅굴
  `(.29,.72)`, 메아리 우물 `(.49,.19)`, 보물고 `(.50,.81)`, 장부지기
  소굴 `(.69,.50)`, 등반 탑 `(.84,.34)`, 귀환 터널 `(.93,.67)`
- 런타임 금지: 배경 pan·scale·parallax. 비콘과 캐릭터 좌표가 원화의 랜드마크에서
  벗어나기 때문이다. 안개·광점처럼 위치 의미가 없는 overlay만 허용한다.

```text
Use case: stylized-concept
Asset type: production-ready mobile game exploration environment map background
Primary request: Rebuild the referenced Moss Archive into one continuous explorable terrain. Physically embed a vine-covered garden gate, flooded cave mouth and stream, root-burrow mine, moonlit ruined well, half-buried treasure vault, moss-stone guardian den, climbable tree archive tower, and return tunnel at the contracted normalized coordinates. Connect them with believable winding paths, stepping stones, root bridges, stream crossings, ledges, and shortcuts. The entrance forks into upper and lower routes, reconnects at the guardian, then continues to tower and exit.
Style/medium: premium Korean mobile fantasy RPG environment painting, semi-realistic hand-painted storybook finish, grounded materials, teal-green shadow and restrained amber practical light; match the reference's visual language without copying its layout.
Composition/framing: 16:9 high oblique three-quarter map view, almost top-down, one continuous terrain with readable elevation and landmark silhouettes.
Constraints: environment only; no people, text, labels, UI, icons, map pins, circular node platforms, arrows, dotted route lines, isolated thumbnail landmarks, logos, watermark, gore, or modern objects.
```

v2는 반실사 질감과 개별 잎·돌의 미세 묘사가 346×195에서 모래처럼 뭉개져 더 이상
런타임에서 사용하지 않는다. 원본은 비교와 회귀 검수용으로만 보존한다.

### 이끼 기억서고 통합 탐험 지형·현장 원화 v3

- 생성 방식: 2026-08-06 내장 ImageGen 신규 생성 후 같은 구도를 참조한 `image-to-image`
  단순화 편집. 기존 v2는 스타일 참조에서 제외
- 스타일 참조: `patrol-garden-path.webp`와 실제 홈 캡처는 팔레트·캐릭터 크기만 참조
- 통합 지형 출력: `expedition-moss-archive-terrain-v3.webp`
- 현장 출력: `expedition-{dungeon-gate|flooded-cave|root-tunnel|echo-well|
  treasure-vault|monster-den|moon-tower}-v3.webp`
- 원본 생성 이력: 아래 `exec-*` 식별자와 최종 프롬프트로 추적
- 마감: `finalize_expedition_art.py`, 1600×900, median 3×3, 192색 no-dither,
  WebP quality 92

초안은 지형 구조는 통과했지만 작은 잎·돌·이끼가 390px 화면에서 고주파 얼룩으로
합쳐졌다. 최종본은 랜드마크와 통로를 고정한 채 아래 편집 지시로 한 번 더 단순화했다.

```text
Preserve the exact camera, landmark positions, route topology, entrances and walkable paths.
Restyle as a production-ready clean 2D cozy fantasy mobile-game environment with confident
smooth outlines, broad flat color planes, grouped foliage masses, simple two-step cel shading
and strong readable silhouettes. Replace tiny repeated leaves, pebble marks, moss flecks and
painterly chatter with a few intentional clusters and large clean surfaces. Every route and
landmark must read at 390 px phone width. Absolutely no grain, stippling, canvas texture,
watercolor bloom, fuzzy edges, pseudo-text, UI, particles or random decorative micro-detail.
```

최종 편집 원본은 통합 지형 `exec-a7b2e9e5-db87-4395-934a-2279da02443f.png`, 석문
`exec-7e4d9045-fce7-4cde-9ed7-e9144b950fce.png`, 침수 동굴
`exec-79d5a4a4-0ccd-4dec-809c-2414d92bf769.png`, 뿌리 땅굴
`exec-a448f8fe-f4b7-4a79-8f0f-a8ed480f139a.png`, 수호자 소굴
`exec-ccc8e443-706e-46ff-8621-0e0cbb6103d9.png`, 보물고
`exec-4007931f-b2fe-49f7-b4c5-84792e344c3e.png`, 등반 탑
`exec-6bb72361-6678-45cf-9df9-6670003b6b92.png`, 메아리 우물
`exec-a07d6a7e-6948-4e5f-aa7a-64fd194bd089.png`이다.

통합 지형 최종 프롬프트는 다음과 같다.

```text
Use case: stylized-concept
Asset type: production 16:9 mobile-game explorable region map background for a 390 px wide Flutter viewport
Input images: Image 1 is a palette and broad-shape reference for the game's warm botanical environment; Image 2 is a UI and character-scale reference. Do not copy either composition, UI, text, or objects.
Primary request: Create one coherent, navigable "Moss Memory Archive" region as a clean authored 2.5D isometric diorama. A stone garden gate enters from the far left center and the dirt path physically forks into two routes. The upper route passes a clearly open flooded cave mouth and turquoise stream, then a ruined circular echo well. The lower route passes a timber-supported root burrow and a half-buried stone treasure vault with one shut chest visible through its doorway. Both routes reconnect at a large moss-covered guardian nest in the center-right. A substantial climbable archive tower grown around a tree stands at upper-right, with exterior stairs and three readable landings. A return tunnel opens at lower-right. Every landmark must be built into the terrain with rock foundations, roots, stairs, bridges, water flow, and continuous walkable paths — never isolated symbols or icon platforms.
Style/medium: clean hand-drawn mobile-game environment art, crisp dark-warm-brown ink contours, matte flat gouache shapes, restrained 2.5D cel shading, exactly three value bands per material, limited harmonious palette of sage green, moss, warm cream stone, muted teal water, charcoal shadow and amber lamps. Friendly storybook adventure tone compatible with a cute plant-character game.
Composition/framing: 16:9 landscape, high three-quarter isometric view, full region visible at once, strong large silhouettes, landmarks positioned approximately at entrance (.08,.50), cave (.28,.27), root tunnel (.29,.72), well (.49,.19), treasure vault (.50,.81), guardian den (.69,.50), tower (.84,.34), return tunnel (.93,.67). Keep every landmark at least 10% of image height and every playable path at least 3% of image height so they remain readable when displayed at 346x195.
Lighting/mood: clear moonlit garden evening with generous midtone visibility and small warm practical lights; mysterious but safe, inviting, and cute rather than grim.
Constraints: environment only; no people, characters, creatures, UI, text, labels, letters, runes, icons, pins, circles under landmarks, arrows, dotted routes, logos, watermark. No fake micro-detail. Use grouped foliage masses, not thousands of individual leaves.
Avoid: photorealism, cinematic concept art, generic fantasy wallpaper, glossy 3D, painterly brush noise, canvas grain, film grain, stippling, speckles, scratch texture, tiny repeated foliage, hyper-detailed rubble, ornate filigree, muddy values, crushed blacks, dramatic fog, bloom haze, neon, AI over-decoration, incoherent stairs or impossible architecture.
```

현장 일곱 장은 아래 공통 프롬프트와 장면별 `Primary request`를 결합한다.

```text
Use case: stylized-concept
Asset type: production 16:9 mobile-game traversal or encounter background, displayed at about 346x195
Input image: the approved v3 region map is an art-direction reference only. Match its limited sage/cream/teal/amber palette, crisp warm-brown contours, matte flat shapes and friendly 2.5D isometric world. Do not copy its layout.
Style/medium: clean hand-drawn mobile-game environment art, crisp consistent ink contours, flat matte gouache blocks, restrained 2.5D cel shading with exactly three value bands per material, large authored shapes, limited palette, friendly all-ages storybook adventure.
Constraints: environment only except the sleeping guardian in monster_den; no people, player characters, UI, text, labels, letters, runes, icons, arrows, logos or watermark. Group foliage, roots and stones into large simple masses.
Avoid: photorealism, generic cinematic concept art, glossy 3D, brush noise, grain, speckles, stippling, scratch texture, tiny repeated foliage, hyper-detailed rubble, ornate clutter, muddy values, crushed blacks, opaque fog, bloom, AI over-decoration, impossible stairs or disconnected paths.
```

| 키 | 장면별 최종 `Primary request` |
|---|---|
| `dungeon_gate` | 넓은 정원길이 낮은 언덕의 이끼 석문으로 이어지고 철문은 열린다. 문 안의 넓은 계단이 지하로 내려가며 굵은 뿌리 뒤 측면 정비 통로와 두 실용 등불, 하단 3인 대기 바닥이 보여야 한다. |
| `flooded_cave` | 상단 동굴 입구에서 터콰이즈 물길이 하단까지 흐른다. 큰 디딤돌 길과 오른쪽 뿌리·판자 다리 길, 왼쪽 마른 쉼터가 서로 실제로 연결되고 수정·버섯은 큰 묶음만 둔다. |
| `root_tunnel` | 하단 진입로와 굵은 뿌리 천장, 목재 지주, 중앙 광차 레일이 상단 작업실로 이어진다. 레일은 왼쪽 낮은 굴과 오른쪽 판자 경사로로 갈라지고 빈 수레 한 대와 등불 세 개만 둔다. |
| `echo_well` | 중앙 원형 우물과 좁은 수로, 우물을 도는 길이 왼쪽 디딤돌과 오른쪽 뿌리 다리로 갈라진다. 빈 청음 그릇 세 개와 등불이 있는 쉼터, 하단 대기 바닥을 둔다. |
| `treasure_vault` | 하단 석재 통로와 압력판 세 개가 중앙의 닫힌 씨앗 상자로 이어진다. 뒤에는 열린 표본 벽감, 잠긴 철창 금고, 봉인 석문이 구분되고 오른쪽에 작은 선택 보관함 하나만 둔다. 의사 문자는 0이어야 한다. |
| `monster_den` | 하단과 중앙은 전투 이펙트를 위한 넓은 빈 바닥이다. 상단 둥지에는 단순한 거북형 이끼 돌 수호자가 잠들고, 좌우 출구·발톱 흔적 하나·부서진 실용 목책만 둔다. 해부학적 묘사와 공포 요소는 금지한다. |
| `moon_tower` | 거대한 나무 내부 절개도에 하나의 연속 나선 계단과 정확히 세 착륙장을 둔다. 1층 원형문, 2층 열린 발코니, 3층 달빛 관측대와 1층에 멈춘 로프 승강기가 물리적으로 연결돼야 한다. |

보물고 초안의 왼쪽 의사 문자 액자는 `precise-object-edit`로 같은 돌벽과 넓은 잎 식물로
교체했고 나머지 구도·상자·압력판·금고는 고정했다.

### 장부지기 수호전 분리 레이어 v1

- 빈 무대 출력: `app/assets/adventure/expedition-monster-den-battle-v1.webp`
- 수호자 출력: `app/assets/adventure/ledger-keeper-{idle|attack|hit|defeated}-v1.webp`
- 빈 무대 편집 원본: `exec-d14b975b-26bb-4b4c-811d-99479d04455c.png`
- idle 원본: `exec-6491ce52-04df-45bc-b201-15ee7cc66b22.png`
- attack 원본: `exec-ed4abd54-a1fc-4dae-996f-fc26dd8b8ccf.png`
- hit 원본: `exec-b56f844e-c096-46a4-91ee-84e4bd4754af.png`
- defeated 원본: `exec-07319eb4-f6f0-49a1-a64a-7d01ae8c1307.png`
- 원본 생성 이력: 위 `exec-*` 식별자와 최종 프롬프트로 추적

빈 무대는 승인된 `monster-den-v3`를 참조해 잠든 수호자만 제거했다. 둥지, 통로, 목책,
팔레트, 카메라와 넓은 하단 전투 바닥은 고정했으며 새로운 장식을 생성하지 않았다.
수호자는 같은 이끼 돌거북 개체를 깨어 있는 idle, 앞발을 들어 기록 파동을 준비하는
attack, 왼쪽에서 충돌을 받아 오른쪽으로 반응하는 hit, 장벽이 풀려 안전하게 몸을 낮춘
defeated 한 자세씩 생성했다. defeated는 죽거나 다친 모습이 아니라 길을 내주는 종료
상태다. 네 자세 모두 그림자·이펙트·글자 없이 `#FF00FF` 단색 배경을 사용했다.

```text
Keep the exact same friendly moss-and-stone turtle guardian identity, shell silhouette,
sage/cream/teal palette, warm-brown outline weight, three-value cel shading and front-left
arena light in both poses. Draw one isolated full-body mobile-game cutout centered with every
limb and shell edge visible. For idle, eyes are open and alert with a grounded readable stance.
For attack, lift one foreleg and lean forward in a clear anticipation pose for a cyan record-wave
counterattack; do not draw the wave itself. Flat solid #FF00FF background only. No ground shadow,
particles, UI, letters, pseudo-text, extra limbs, grain, speckles, ornate micro-detail or watermark.
```

hit과 defeated는 승인된 idle/attack 두 장을 동시에 참조한 내장 ImageGen
image-to-image로 만들었다. 사용 프롬프트는 다음과 같다.

```text
Keep the exact same friendly stone-scale ledger keeper from both reference images: same mossy
shell silhouette, face, sage/cream/teal palette, warm-brown outline, three-value painted cel
shading and front-left light. Create one strong HIT-REACTION pose, struck from screen-left and
recoiling toward screen-right, eyes safely squeezed shut, with only 4-6 large readable stone
chips. Keep the complete body and every limb inside the canvas. Flat solid #FF00FF background.
No floor shadow, text, UI, blood, wound, weapon, extra limb, glossy 3D finish, noisy grain,
micro-detail, fake letters or watermark.
```

```text
Keep the exact same friendly stone-scale ledger keeper from both reference images: same mossy
shell silhouette, face, sage/cream/teal palette, warm-brown outline, three-value painted cel
shading and front-left light. Create one BARRIER-BROKEN resolution pose: safely yielded rather
than injured or dead, crouched low with a readable dizzy spiral-eye expression, two or three
cyan barrier cracks and only a few large stone chips. Keep the complete body inside the canvas.
Flat solid #FF00FF background. No floor shadow, text, UI, blood, wound, weapon, extra limb,
glossy 3D finish, noisy grain, micro-detail, fake letters or watermark.
```

수호자 원본은 `remove_chroma_key.py --auto-key border --soft-matte`로 알파 분리한 뒤
동일한 3×3 median·192색 no-dither·WebP 마감을 적용했다. 최종 파일은 `VP8X` alpha
플래그와 0 alpha 모서리를 검사하며, 346×195 앱 렌더에서 분홍 fringe와 자글거림이
없어야 한다. 빈 배경과 네 수호자 자세는 각각 독립 프리로드하고 런타임에서 합성한다.

### 직접 이동 장소용 2.5D 배경 v2 — 사용 중단

- 생성 방식: 2026-08-05 내장 ImageGen `stylized-concept` 신규 생성
- 스타일 참조: `app/assets/adventure/expedition-moss-archive-map.webp`
  한 장을 스타일 참조로만 사용하고 구도와 오브젝트는 복제하지 않음
- 프로젝트 출력: 1600×900 RGB WebP, 품질 84
- 공통 구도: 16:9 가로, 중앙 안전 크롭, 하단 UI 영역과 모바일 세로 화면에서도
  심도·통로·핵심 랜드마크가 읽히도록 중앙 60% 안에 배치
- 공통 제약: 인물, 캐릭터, UI, 아이콘, 글자, 의사 문자, 로고,
  워터마크 없음. 사진풍·글로시 3D·네온·장식 과밀·과도한 안개 금지
- 아래 파일은 비교용으로 보존하며 런타임은 같은 이름의 `-v3.webp`를 사용한다.

| `scene_key` | 프로젝트 출력 | 핵심 장면 |
|---|---|---|
| `dungeon_gate` | `app/assets/adventure/expedition-dungeon-gate.webp` | 버려진 유리온실 아래의 석문·우리문·횟불·깊은 계단 |
| `flooded_cave` | `app/assets/adventure/expedition-flooded-cave.webp` | 터콰이즈 빛 침수 동굴·수정·발광 균류·디딘돌·두 통로 |
| `root_tunnel` | `app/assets/adventure/expedition-root-tunnel.webp` | 목재 지주·굵은 뿌리·광차 레일·제한된 랜턴·측면 굴 |
| `monster_den` | `app/assets/adventure/expedition-monster-den.webp` | 뿌리 둥지·발톱 흔적·임시 방어물·잠든 이끼 돌비늘 수호자 |
| `treasure_vault` | `app/assets/adventure/expedition-treasure-vault.webp` | 중앙의 큰 발광 보물상자·잠긴 측면 금고·표본·씨앗 보석 |
| `moon_tower` | `app/assets/adventure/expedition-moon-tower.webp` | 거대 나무 내부·중앙 나선 계단·3개 이상 착륙장·층별 문·달빛 |

공통 최종 프롬프트 헤더는 다음과 같다.

```text
Use case: stylized-concept
Asset type: production Flutter mobile game exploration environment background
Input image: style reference only. Preserve the warm hand-painted botanical dark-fantasy language, matte 2.5D depth, restrained practical detail, and readable large shapes. Do not copy the reference layout or objects.
Composition/framing: 16:9 landscape, center-safe mobile crop, readable traversal depth and landmark, lower UI-safe band, premium released-game environment quality.
Constraints: environment only; no people, characters, UI, icons, readable text, pseudo-text, logos, or watermark.
Avoid: photorealism, glossy generic 3D, neon, decorative clutter, excessive filigree, and opaque cinematic fog.
```

각 파일은 공통 헤더에 다음 장면 지시를 결합해 생성했다.

```text
dungeon_gate: An abandoned glasshouse ruin above a deep underground stone gate, a closed iron portcullis, descending stairs, two warm torches, moss and roots. The gate and stair depth are the unmistakable focal point.
flooded_cave: A turquoise flooded cavern with shallow reflective water, crystalline formations, bioluminescent fungi, stepping stones, and two clearly readable passages. Safe enough for an all-ages adventure, not a horror cave.
root_tunnel: A root-filled underground mine tunnel with practical timber supports, an old cart rail, restrained lanterns, and side burrows. Make the traversable tunnel depth and branching route obvious.
monster_den: A tense root cavern nest with claw marks, broken practical barricades, and one large sleeping plant-and-stone guardian with mossy armor. No gore, exposed anatomy, or horror violence.
treasure_vault: A sealed botanical vault with one large glowing ornate chest as the central objective, several locked side chests, old relics, coins, and seed gems. Keep the treasure readable without a cluttered loot explosion.
moon_tower: The interior of a climbable tower grown around a giant tree, with one continuous central spiral staircase, at least three visible landings, distinct floor doors, high moonlight, and clear upward progression for a future tower-climb mode.
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

## 전투 중심 모험 화면 v1 — ImageGen 시각 기준안

- 생성 방식: 내장 ImageGen, 프로젝트 소유 배경 1장·캐릭터 3명·수호자 1종을 역할별
  참조로 사용
- 출력:
  `design-system/concepts/adventure-combat-first-v1/combat-first-visual-target-v1.png`
- 실제 규격: 864×1821 RGB PNG(390×844 논리 화면에 가까운 세로 비율)
- 출력 SHA-256:
  `DA92DAB816C6BDD4D01DF9333AE619465DA498350F660B92A85F96B9750C29F7`
- 전체 프롬프트·입력 역할·승인/비승인 범위:
  `design-system/concepts/adventure-combat-first-v1/README.md`

이 이미지는 `한 카메라·한 바닥`, 세 캐릭터와 수호자의 동시 가시성, 세로 화면 약 76%의
전장, 상단 진행 rail, 하단 반투명 스킬 dock, 뽀또 손에서 수호자까지 실제로 이어지는 덩굴
비행 경로를 한 장에서 검토하기 위해 만들었다. 화면 안에는 설명문·가짜 한글·던전 카드·
별도 지도 패널을 요청하지 않았다.

승인 대상은 **배치·시선 순서·깊이·공격 경로**뿐이다. 생성 결과의 캐릭터 pose, 크기,
스킬 아이콘 그림, HP bar, stage glyph, 배경 픽셀은 production 에셋이 아니다. PNG에서
아이콘·캐릭터·배경을 잘라 쓰거나 한 장의 raster HUD로 앱에 넣지 않는다. 실제 제작은
배경 pass, actor action, VFX keyframe, UI semantic layer를 각각 분리하고
`EXPEDITION_ASSET_PRODUCTION.md`의 alpha·blend·contact QA를 통과해야 한다.

## 스킬 아이콘 v1 — ImageGen 도색 master

대상은 고유 스킬 60개(20 family×3tier), 감정 스킬 6개, 기록서 36개로 총 102개다.
기본 공격·지키기·AUTO·잠금·비용은 생성형 그림이 아니라 semantic vector와 런타임
overlay를 사용한다. 한 호출에는 아이콘 하나만 만들며, 서로 다른 스킬을 grid·여러
패널·`n` 변형으로 한꺼번에 생성한 뒤 잘라 쓰지 않는다.

공통 프롬프트 골격:

```text
Use case: stylized-concept
Asset type: one production mobile RPG skill icon for {family_code}, {tier_or_base}
Input images: Image 1 is the exact approved Mongroo skill-icon style board. Image 2 is the exact
{character|emotion-family|skill-book} motif reference. Image 3 is the previous approved icon for
this same family and is included only when creating T2 or T3; preserve its identity, not its pixels.
Primary request: paint one instantly readable icon for {skill_name}: {single_dominant_motif} performing
{clear_action_verb}. Keep one motif and one direction of motion; this must still read at 48 px.
Scene/backdrop: a restrained full-bleed square vignette that supports the motif and is part of the
painting, with no separate UI frame, no landscape, and no transparent checkerboard.
Composition: 1024x1024 square master, one dominant motif occupying 58 to 72 percent of the canvas,
at least 12 percent safe margin on every side, centered visual weight, strong silhouette, no cropping.
Style/medium: Mongroo premium 2.5D storybook mobile-game icon, warm dark-brown ink contours,
matte gouache and cel-painted volume, broad clean shapes, restrained paper texture, one primary
family color, one secondary accent, soft cream highlight, top-left key light.
Tier continuity: {T1 establishes the motif | T2 keeps the silhouette and adds one authored motif layer |
T3 keeps the family identity and adds one decisive finishing shape}. Do not express tier by brightness alone.
Constraints: exactly one icon painting; no text, letters, numbers, skill name, tier number, pips, border,
button chrome, rarity frame, cost badge, cooldown, lock, UI, logo, watermark, full-body character,
face portrait, battlefield scene, multiple panels, or neighboring icon.
Avoid: generic elemental orb, generic magic circle, neon bloom, lens flare, glossy 3D emblem,
photorealism, ornate gold, tiny particles, noisy foliage, low-contrast silhouette, palette swap of
another skill, fake typography, cropped motif.
```

제작·검수 순서는 다음으로 고정한다.

1. T1·감정·기록서 최초 아이콘은 Image 1 스타일 보드와 Image 2 모티프만 참조한다.
2. 같은 고유 family의 T2·T3는 직전 승인본을 Image 3으로 넣어 실루엣·방향·핵심 사물을
   잠그고, 새 모티프 한 층만 추가한다. 이전 tier와 단순 색상 차이만 나면 반려한다.
3. 생성 결과를 `$CODEX_HOME/generated_images/`에 방치하지 않고 승인 즉시
   `design-system/concepts/character-skill-vfx-v1/icons/sources/`로 복사한다.
4. prompt 원문, 입력 이미지 역할·hash, 출력 source hash, 승인자, tier parent를 manifest에
   기록한 뒤 사람 paint-over와 색상 정리를 수행한다.
5. full-bleed 아이콘에는 alpha를 만들지 않는다. cutout 예외만 평면 chroma 원본과
   `remove_chroma_key.py` soft matte·despill 절차를 사용한다.
6. 128·64·48·32px, 흑백·저채도, 밝고 어두운 전장 6종 위에서 확인한다. 48px에서
   1초 안에 주모티프와 다른 장착 스킬을 구분할 수 있어야 승인한다.

## 탐험 전투 공격 VFX v1

> **prototype 기록.** 아래 2×4 일괄 생성 방식과 공용 `enemy_wave`는 2026-08-10부터
> 정식 제작에 쓰지 않는다. 생성 ID 재현·비교용으로만 보존하며 v2 계약은 다음 절을
> 따른다.

- 생성 방식: 내장 ImageGen, 참조 이미지 기반 2×4 접촉 시트
- 소스·프롬프트·후처리 계약:
  `design-system/concepts/adventure-combat-vfx-v1/README.md`
- 런타임 출력: `app/assets/adventure/effects/{효과}/frame-00.webp` ~
  `frame-07.webp`
- 범위: 플레이어 7효과와 장부지기 `enemy_wave`, 총 64프레임

전투 중 공격 모양은 위 래스터 프레임만 사용한다. 캔버스 코드는 바닥 명암과
입력 전 예고 범위처럼 에셋 정체성을 갖지 않는 보조 UI에만 허용한다.

## 탐험 전투 공격 VFX v2 — 단계별 투명 키프레임

한 요청에는 family 하나의 keyframe 하나만 만든다. 먼저
`design-system/EXPEDITION_ASSET_PRODUCTION.md` 7.3.1의 model sheet를 승인하고,
`anticipation → travel_mid → first_contact → max_impact → fade` 순서로 진행한다.
두 번째 호출부터는 model sheet·프로젝트 스타일 참조와 **직전 승인 프레임**을 함께
참조한다. 완성 sprite sheet, 여러 칸, 여러 프레임, 캐릭터와 공격 합성 화면을 한 번에
요청하지 않는다.

공통 프롬프트 골격:

```text
Use case: stylized-concept
Asset type: production 2D game VFX keyframe for {family_code}, stage {anticipation|travel_mid|first_contact|max_impact|fade}
Input images: Image 1 is the project style reference; Image 2 is the approved family model sheet;
Image 3 is the previous approved keyframe and must be omitted only for the first keyframe.
Primary request: Draw only the same {attack_object} at the requested next moment.
Preserve exactly: main silhouette identity, {part_count}, main body thickness {px_range},
warm dark-brown outline thickness, upper-left light direction, {palette}, origin-facing direction.
Motion state: {stage_specific_shape_change}. The object must read as one continuous attack
that can travel from {origin_anchor} to {target_anchor}.
Scene/backdrop: one perfectly flat solid {key_color} chroma-key field for local background removal.
Use #FF00FF for green subjects and #00FF00 otherwise; the selected key color must not occur in the subject.
Composition: one effect object, centered with safe padding, no cropping, no floor perspective.
Constraints: the background is one uniform color with no shadow, gradient, texture, reflection,
floor plane, or lighting variation; crisp padded silhouette; no cast shadow or contact shadow.
Avoid: character, monster, hand, weapon holder, scenery, UI, text, number, border, panel,
checkerboard, watermark, glow beam, lens flare, grain, micro-particle spray, neighboring frame,
or any use of {key_color} inside the attack object.
```

단계별 지시는 다음 의미만 바꾼다.

| 단계 | 모양 변화 | 금지 |
|---|---|---|
| `anticipation` | origin 가까이 말리거나 응축, 발사 방향이 읽힘 | 이미 화면 중앙까지 뻗은 본체 |
| `travel_mid` | 같은 본체가 50% 지점까지 펴지거나 이동, 부품 수 유지 | impact 파편·타깃 흔적 |
| `first_contact` | 선단만 타깃을 감싸거나 처음 부딪힘 | 최대 폭발·본체 소멸 |
| `max_impact` | 승인된 접촉점에서 가장 큰 타격 형태, 파편 수 상한 준수 | 전면 백색 섬광·무관한 새 문양 |
| `fade` | 같은 부품이 풀리거나 작아져 회수, silhouette의 흔적 유지 | 다른 물체로 변형·갑자기 빈 프레임 |

- 플레이어 고유 20종, 감정 전투 6종, 기록서 모듈 12종, 일반 엉킴 8종,
  큰 엉킴 8종, 수호짐승 8종의 62 family가 같은 절차를 쓴다.
- 적 공격 프롬프트도 품질·투명도·연속성 기준이 동일하다. `enemy_wave`라는 공용
  파동을 이름·색만 바꿔 생성하지 않는다.
- ImageGen 결과는 승인 keyframe일 뿐 runtime frame이 아니다. 2D animator가
  in-between을 만들고 테크니컬 아트가 alpha·pivot·anchor·contact event를 검수한
  뒤에만 `production_ready:true`가 된다.
- 내장 ImageGen 산출물은
  `$CODEX_HOME/skills/.system/imagegen/scripts/remove_chroma_key.py`의 soft matte·despill
  경로로 alpha PNG로 변환한다. 네 모서리 투명·key fringe 0·외곽선 보존을 확인하기
  전에는 해당 family의 RGBA master로 승격하지 않는다. ImageGen 배경이 단색 지시와 달리
  명도 기울기를 가져 기본 soft matte가 본체까지 반투명하게 만들면, v2 빌더의 채널 분리·
  1px core 수축·RGB dilation·0.75px feather를 사용하고 light/dark QA를 다시 통과해야 한다.
  반투명 연기·유리·액체처럼 chroma 제거가 부적합한 family만 제작 책임자의 명시적 승인 뒤
  true-alpha CLI fallback을 검토한다.

### 2026-08-10 v2 production candidate

- 제작 기록·ImageGen ID·재현 prompt:
  `concepts/adventure-combat-vfx-v2/README.md`
- 기계 판정·source/alpha/runtime hash:
  `concepts/adventure-combat-vfx-v2/manifest.json`
- 플레이어: `care_vines`, 단일 pose 원본 10장 → 576×288 alpha WebP 10장.
- 적: 돌비늘 장부지기 `ledger_claw`, 단일 pose 원본 10장 → 576×288 alpha WebP 10장.
- 두 family 모두 코드 생성 공격 픽셀은 0이며 light/dark contact sheet를 통과했다.
- 실제 기기 합성, actor attack/hit, contact SFX·햅틱, profile 전에는
  `production_ready:false`다. `record_wave`·`seal_crush`는 아직 기존 prototype fallback이다.
