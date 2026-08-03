# 탐험 배경 에셋 생성 기록

프로젝트 출력은 모두 1440×810 RGB WebP다. 원본 생성 이미지는 별도 보관하고,
앱에는 리사이즈·WebP 변환본만 넣었다.

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
