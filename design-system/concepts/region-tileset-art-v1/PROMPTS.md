# 던전 타일셋 ImageGen 프롬프트 — 지역별 24장 · 사용 중단 (2026-08-19)

**이 경로는 지금 쓰지 않는다.** 여기 적힌 `import_region_tileset.py`가 없어졌고,
지금 아틀라스는 지역마다 여섯 장씩 스물네 장이 아니라 **공용 열한 장**을 읽어
지역 색을 코드로 입힌다. 쓸 프롬프트는
`design-system/ADVENTURE_ASSET_PROMPTS.md`의 `던전 타일셋 원본 v2` 절이다.

남겨 두는 이유는 두 가지다. `sources/`에 이미 뽑아 둔 그림이 있고, 지역마다
그림을 따로 그리는 쪽으로 다시 갈 수도 있다.

## 팔레트가 새던 것 (2026-08-19 고침)

앞 판은 지역 다섯 색을 **모든 재료의 STYLE에 통째로** 넣었다. 그래서 벽 프롬프트에
물빛(`#004B73`)이 들어가 돌에 파란 얼룩이 끼고, 물 프롬프트에는 모래빛이 들어가
연못이 모래색으로 나왔다. 뽑은 다섯 장 중 셋을 못 쓰게 만든 원인이 이것이다.

지금은 재료마다 갈라 놓았다 — 땅·벽·물건은 흙과 돌 색만, 물은 물색만 쓴다.
가르는 기준은 파랑이 가장 세면서 **채도까지 있는가**다. 파랑이 세다는 것만 보면
파란 기가 도는 회색 돌(`#8F8C95`)까지 물로 넘어가 지역의 주된 돌빛을 잃는다.

## 이끼 기억서고 `moss_archive`

팔레트: `#907C5B, #A99875, #E2B170, #8E8D38, #004B73`

### 방 안 바닥 → `moss_archive__floor-room.png`

```
A seamless tileable top-down pixel-art floor texture for a 2D RPG dungeon.

SURFACE: warm sand-colored flagstones laid in a neat grid with fine mortar seams, a few blades of moss growing in the joints

DETAIL: irregular hand-placed detail — the wear is NOT uniform. Some areas are
smoother, some carry small chips, hairline cracks, or a scatter of tiny stones.
Detail covers roughly one fifth of the surface; the rest stays calm. Avoid any
regular repeating motif that the eye can lock onto.

TILING: the texture must tile seamlessly — the left edge continues into the right
edge, and the top edge into the bottom edge, with no visible seam.

CANVAS: 512 x 512 pixels, filling the frame edge to edge.

STYLE: true pixel art. Hard-edged pixels, no anti-aliasing, no gradients, no
dithering noise, no blur, no glow, no photographic texture, no JPEG-like speckle.
Limited palette of at most 12 colors drawn from: #907C5B, #A99875, #E2B170, #8E8D38. NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
a single light source from the upper left. Every flat color region is at least
4x4 pixels. The result must read cleanly when scaled down to a 24x24 pixel tile.

VIEW: strict top-down orthographic. No perspective, no vanishing point, no camera
tilt, no drop shadow cast outside the tile.

BACKGROUND: no border, no frame, no label, no caption, no watermark, no grid lines.
```

### 복도 바닥 → `moss_archive__floor-path.png`

```
A seamless tileable top-down pixel-art floor texture for a 2D RPG dungeon.

SURFACE: packed sandy earth worn smooth down the middle, loose grit and small pebbles toward the edges, scattered patches of moss

DETAIL: irregular hand-placed detail — the wear is NOT uniform. Some areas are
smoother, some carry small chips, hairline cracks, or a scatter of tiny stones.
Detail covers roughly one fifth of the surface; the rest stays calm. Avoid any
regular repeating motif that the eye can lock onto.

TILING: the texture must tile seamlessly — the left edge continues into the right
edge, and the top edge into the bottom edge, with no visible seam.

CANVAS: 512 x 512 pixels, filling the frame edge to edge.

STYLE: true pixel art. Hard-edged pixels, no anti-aliasing, no gradients, no
dithering noise, no blur, no glow, no photographic texture, no JPEG-like speckle.
Limited palette of at most 12 colors drawn from: #907C5B, #A99875, #E2B170, #8E8D38. NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
a single light source from the upper left. Every flat color region is at least
4x4 pixels. The result must read cleanly when scaled down to a 24x24 pixel tile.

VIEW: strict top-down orthographic. No perspective, no vanishing point, no camera
tilt, no drop shadow cast outside the tile.

BACKGROUND: no border, no frame, no label, no caption, no watermark, no grid lines.
```

### 벽 앞면 → `moss_archive__wall-face.png`

```
A seamless horizontally-tiling pixel-art wall face for a 2D RPG dungeon, seen
straight from the front as if standing in front of it.

SURFACE: stacked sandstone blocks in two courses, moss creeping down from the top edge, one or two blocks sitting slightly out of line

LIGHT: the top of the wall face catches light and is clearly brighter; the bottom
where it meets the floor is clearly darker. This vertical falloff is what makes
the wall read as tall.

TILING: tiles seamlessly left to right. The top and bottom edges do NOT tile —
they are the crest and the base of the wall.

CANVAS: 512 x 512 pixels, filling the frame edge to edge.

STYLE: true pixel art. Hard-edged pixels, no anti-aliasing, no gradients, no
dithering noise, no blur, no glow, no photographic texture, no JPEG-like speckle.
Limited palette of at most 12 colors drawn from: #907C5B, #A99875, #E2B170, #8E8D38. NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
a single light source from the upper left. Every flat color region is at least
4x4 pixels. The result must read cleanly when scaled down to a 24x24 pixel tile.

VIEW: strict top-down orthographic. No perspective, no vanishing point, no camera
tilt, no drop shadow cast outside the tile.

BACKGROUND: no border, no frame, no label, no caption, no watermark, no grid lines.
```

### 벽 윗면 → `moss_archive__wall-top.png`

```
A seamless tileable pixel-art texture of the TOP surface of a dungeon wall, seen
from directly above.

SURFACE: dark mossy stone rubble packed flat This is the flat top of a thick wall, in shadow — clearly
darker than the floor so that the player reads it as "cannot walk here".

TILING: seamless in both directions.

CANVAS: 512 x 512 pixels, filling the frame edge to edge.

STYLE: true pixel art. Hard-edged pixels, no anti-aliasing, no gradients, no
dithering noise, no blur, no glow, no photographic texture, no JPEG-like speckle.
Limited palette of at most 12 colors drawn from: #907C5B, #A99875, #E2B170, #8E8D38. NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
a single light source from the upper left. Every flat color region is at least
4x4 pixels. The result must read cleanly when scaled down to a 24x24 pixel tile.

VIEW: strict top-down orthographic. No perspective, no vanishing point, no camera
tilt, no drop shadow cast outside the tile.

BACKGROUND: no border, no frame, no label, no caption, no watermark, no grid lines.
```

### 물 → `moss_archive__water.png`

```
A seamless tileable top-down pixel-art water surface for a 2D RPG dungeon.

SURFACE: a shallow clear stream running over a sandy bed Gentle ripple lines in two or three tones. No foam, no
reflections of objects, no sky reflection.

TILING: seamless in both directions.

CANVAS: 512 x 512 pixels, filling the frame edge to edge.

STYLE: true pixel art. Hard-edged pixels, no anti-aliasing, no gradients, no
dithering noise, no blur, no glow, no photographic texture, no JPEG-like speckle.
Limited palette of at most 10 colors: #004B73, plus lighter and darker tints of those blues for the ripple bands. NO sand, stone, or brown tones anywhere in the frame — this tile is water only. Flat cel shading with
a single light source from the upper left. Every flat color region is at least
4x4 pixels. The result must read cleanly when scaled down to a 24x24 pixel tile.

VIEW: strict top-down orthographic. No perspective, no vanishing point, no camera
tilt, no drop shadow cast outside the tile.

BACKGROUND: no border, no frame, no label, no caption, no watermark, no grid lines.
```

### 물건 6종 → `moss_archive__objects.png`

```
Six separate top-down pixel-art dungeon objects for a 2D RPG, arranged in one row
of six evenly spaced cells, each object centered in its own cell with generous
empty space around it. The objects do NOT touch or overlap.

OBJECTS, left to right:
1. a short flight of stone stairs descending away from the viewer
2. a dark doorway arch with deep shadow inside, set into a wall
3. a stone pillar seen from a high angle, base and capital both visible
4. the corner of a woven floor rug, showing two straight edges and a braided trim
5. a small pile of rubble and broken stones
6. a clump of tall grass or ferns

All six objects are made of warm sandstone, aged wood, and moss.

CANVAS: 1536 x 1024 pixels. Six cells of 256 x 1024 side by side, each object
centered in its cell.

BACKGROUND: fully transparent. No ground, no shadow blob painted into the
background, no cell borders, no labels.

STYLE: true pixel art. Hard-edged pixels, no anti-aliasing, no gradients, no
dithering noise, no blur, no glow, no photographic texture, no JPEG-like speckle.
Limited palette of at most 12 colors drawn from: #907C5B, #A99875, #E2B170, #8E8D38. NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
a single light source from the upper left. Every flat color region is at least
4x4 pixels. The result must read cleanly when scaled down to a 24x24 pixel tile.

VIEW: strict top-down orthographic. No perspective, no vanishing point, no camera
tilt, no drop shadow cast outside the tile.

BACKGROUND: no border, no frame, no label, no caption, no watermark, no grid lines.
```

## 메아리 우물정원 `echo_well`

팔레트: `#726347, #8F7356, #9E805D, #16516E, #054D73`

### 방 안 바닥 → `echo_well__floor-room.png`

```
A seamless tileable top-down pixel-art floor texture for a 2D RPG dungeon.

SURFACE: damp grey-brown cut stone slabs, a thin film of water in the seams, faint algae in the corners

DETAIL: irregular hand-placed detail — the wear is NOT uniform. Some areas are
smoother, some carry small chips, hairline cracks, or a scatter of tiny stones.
Detail covers roughly one fifth of the surface; the rest stays calm. Avoid any
regular repeating motif that the eye can lock onto.

TILING: the texture must tile seamlessly — the left edge continues into the right
edge, and the top edge into the bottom edge, with no visible seam.

CANVAS: 512 x 512 pixels, filling the frame edge to edge.

STYLE: true pixel art. Hard-edged pixels, no anti-aliasing, no gradients, no
dithering noise, no blur, no glow, no photographic texture, no JPEG-like speckle.
Limited palette of at most 12 colors drawn from: #726347, #8F7356, #9E805D. NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
a single light source from the upper left. Every flat color region is at least
4x4 pixels. The result must read cleanly when scaled down to a 24x24 pixel tile.

VIEW: strict top-down orthographic. No perspective, no vanishing point, no camera
tilt, no drop shadow cast outside the tile.

BACKGROUND: no border, no frame, no label, no caption, no watermark, no grid lines.
```

### 복도 바닥 → `echo_well__floor-path.png`

```
A seamless tileable top-down pixel-art floor texture for a 2D RPG dungeon.

SURFACE: wet cobbles pressed into mud, shallow puddles catching a little light

DETAIL: irregular hand-placed detail — the wear is NOT uniform. Some areas are
smoother, some carry small chips, hairline cracks, or a scatter of tiny stones.
Detail covers roughly one fifth of the surface; the rest stays calm. Avoid any
regular repeating motif that the eye can lock onto.

TILING: the texture must tile seamlessly — the left edge continues into the right
edge, and the top edge into the bottom edge, with no visible seam.

CANVAS: 512 x 512 pixels, filling the frame edge to edge.

STYLE: true pixel art. Hard-edged pixels, no anti-aliasing, no gradients, no
dithering noise, no blur, no glow, no photographic texture, no JPEG-like speckle.
Limited palette of at most 12 colors drawn from: #726347, #8F7356, #9E805D. NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
a single light source from the upper left. Every flat color region is at least
4x4 pixels. The result must read cleanly when scaled down to a 24x24 pixel tile.

VIEW: strict top-down orthographic. No perspective, no vanishing point, no camera
tilt, no drop shadow cast outside the tile.

BACKGROUND: no border, no frame, no label, no caption, no watermark, no grid lines.
```

### 벽 앞면 → `echo_well__wall-face.png`

```
A seamless horizontally-tiling pixel-art wall face for a 2D RPG dungeon, seen
straight from the front as if standing in front of it.

SURFACE: wet dark stone blocks with water stains running down the face, a thin line of algae where the wall meets the floor

LIGHT: the top of the wall face catches light and is clearly brighter; the bottom
where it meets the floor is clearly darker. This vertical falloff is what makes
the wall read as tall.

TILING: tiles seamlessly left to right. The top and bottom edges do NOT tile —
they are the crest and the base of the wall.

CANVAS: 512 x 512 pixels, filling the frame edge to edge.

STYLE: true pixel art. Hard-edged pixels, no anti-aliasing, no gradients, no
dithering noise, no blur, no glow, no photographic texture, no JPEG-like speckle.
Limited palette of at most 12 colors drawn from: #726347, #8F7356, #9E805D. NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
a single light source from the upper left. Every flat color region is at least
4x4 pixels. The result must read cleanly when scaled down to a 24x24 pixel tile.

VIEW: strict top-down orthographic. No perspective, no vanishing point, no camera
tilt, no drop shadow cast outside the tile.

BACKGROUND: no border, no frame, no label, no caption, no watermark, no grid lines.
```

### 벽 윗면 → `echo_well__wall-top.png`

```
A seamless tileable pixel-art texture of the TOP surface of a dungeon wall, seen
from directly above.

SURFACE: dark wet stone slabs with shallow standing water This is the flat top of a thick wall, in shadow — clearly
darker than the floor so that the player reads it as "cannot walk here".

TILING: seamless in both directions.

CANVAS: 512 x 512 pixels, filling the frame edge to edge.

STYLE: true pixel art. Hard-edged pixels, no anti-aliasing, no gradients, no
dithering noise, no blur, no glow, no photographic texture, no JPEG-like speckle.
Limited palette of at most 12 colors drawn from: #726347, #8F7356, #9E805D. NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
a single light source from the upper left. Every flat color region is at least
4x4 pixels. The result must read cleanly when scaled down to a 24x24 pixel tile.

VIEW: strict top-down orthographic. No perspective, no vanishing point, no camera
tilt, no drop shadow cast outside the tile.

BACKGROUND: no border, no frame, no label, no caption, no watermark, no grid lines.
```

### 물 → `echo_well__water.png`

```
A seamless tileable top-down pixel-art water surface for a 2D RPG dungeon.

SURFACE: deep still well water, very dark toward the center Gentle ripple lines in two or three tones. No foam, no
reflections of objects, no sky reflection.

TILING: seamless in both directions.

CANVAS: 512 x 512 pixels, filling the frame edge to edge.

STYLE: true pixel art. Hard-edged pixels, no anti-aliasing, no gradients, no
dithering noise, no blur, no glow, no photographic texture, no JPEG-like speckle.
Limited palette of at most 10 colors: #16516E, #054D73, plus lighter and darker tints of those blues for the ripple bands. NO sand, stone, or brown tones anywhere in the frame — this tile is water only. Flat cel shading with
a single light source from the upper left. Every flat color region is at least
4x4 pixels. The result must read cleanly when scaled down to a 24x24 pixel tile.

VIEW: strict top-down orthographic. No perspective, no vanishing point, no camera
tilt, no drop shadow cast outside the tile.

BACKGROUND: no border, no frame, no label, no caption, no watermark, no grid lines.
```

### 물건 6종 → `echo_well__objects.png`

```
Six separate top-down pixel-art dungeon objects for a 2D RPG, arranged in one row
of six evenly spaced cells, each object centered in its own cell with generous
empty space around it. The objects do NOT touch or overlap.

OBJECTS, left to right:
1. a short flight of stone stairs descending away from the viewer
2. a dark doorway arch with deep shadow inside, set into a wall
3. a stone pillar seen from a high angle, base and capital both visible
4. the corner of a woven floor rug, showing two straight edges and a braided trim
5. a small pile of rubble and broken stones
6. a clump of tall grass or ferns

All six objects are wet dark stone and waterlogged wood, with algae.

CANVAS: 1536 x 1024 pixels. Six cells of 256 x 1024 side by side, each object
centered in its cell.

BACKGROUND: fully transparent. No ground, no shadow blob painted into the
background, no cell borders, no labels.

STYLE: true pixel art. Hard-edged pixels, no anti-aliasing, no gradients, no
dithering noise, no blur, no glow, no photographic texture, no JPEG-like speckle.
Limited palette of at most 12 colors drawn from: #726347, #8F7356, #9E805D. NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
a single light source from the upper left. Every flat color region is at least
4x4 pixels. The result must read cleanly when scaled down to a 24x24 pixel tile.

VIEW: strict top-down orthographic. No perspective, no vanishing point, no camera
tilt, no drop shadow cast outside the tile.

BACKGROUND: no border, no frame, no label, no caption, no watermark, no grid lines.
```

## 별씨앗 보관고 `starlight_seed_vault`

팔레트: `#8F8C95, #A19B9F, #AEA7A5, #4A5E83, #405B84`

### 방 안 바닥 → `starlight_seed_vault__floor-room.png`

```
A seamless tileable top-down pixel-art floor texture for a 2D RPG dungeon.

SURFACE: pale grey stone hexagonal floor plates fitted tightly together, hairline frost tracing the seams

DETAIL: irregular hand-placed detail — the wear is NOT uniform. Some areas are
smoother, some carry small chips, hairline cracks, or a scatter of tiny stones.
Detail covers roughly one fifth of the surface; the rest stays calm. Avoid any
regular repeating motif that the eye can lock onto.

TILING: the texture must tile seamlessly — the left edge continues into the right
edge, and the top edge into the bottom edge, with no visible seam.

CANVAS: 512 x 512 pixels, filling the frame edge to edge.

STYLE: true pixel art. Hard-edged pixels, no anti-aliasing, no gradients, no
dithering noise, no blur, no glow, no photographic texture, no JPEG-like speckle.
Limited palette of at most 12 colors drawn from: #8F8C95, #A19B9F, #AEA7A5. NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
a single light source from the upper left. Every flat color region is at least
4x4 pixels. The result must read cleanly when scaled down to a 24x24 pixel tile.

VIEW: strict top-down orthographic. No perspective, no vanishing point, no camera
tilt, no drop shadow cast outside the tile.

BACKGROUND: no border, no frame, no label, no caption, no watermark, no grid lines.
```

### 복도 바닥 → `starlight_seed_vault__floor-path.png`

```
A seamless tileable top-down pixel-art floor texture for a 2D RPG dungeon.

SURFACE: frost-dusted stone worn pale down the middle, thin ice creeping in from the edges

DETAIL: irregular hand-placed detail — the wear is NOT uniform. Some areas are
smoother, some carry small chips, hairline cracks, or a scatter of tiny stones.
Detail covers roughly one fifth of the surface; the rest stays calm. Avoid any
regular repeating motif that the eye can lock onto.

TILING: the texture must tile seamlessly — the left edge continues into the right
edge, and the top edge into the bottom edge, with no visible seam.

CANVAS: 512 x 512 pixels, filling the frame edge to edge.

STYLE: true pixel art. Hard-edged pixels, no anti-aliasing, no gradients, no
dithering noise, no blur, no glow, no photographic texture, no JPEG-like speckle.
Limited palette of at most 12 colors drawn from: #8F8C95, #A19B9F, #AEA7A5. NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
a single light source from the upper left. Every flat color region is at least
4x4 pixels. The result must read cleanly when scaled down to a 24x24 pixel tile.

VIEW: strict top-down orthographic. No perspective, no vanishing point, no camera
tilt, no drop shadow cast outside the tile.

BACKGROUND: no border, no frame, no label, no caption, no watermark, no grid lines.
```

### 벽 앞면 → `starlight_seed_vault__wall-face.png`

```
A seamless horizontally-tiling pixel-art wall face for a 2D RPG dungeon, seen
straight from the front as if standing in front of it.

SURFACE: pale stone blocks rimmed with frost, a few thin icicles hanging from the crest

LIGHT: the top of the wall face catches light and is clearly brighter; the bottom
where it meets the floor is clearly darker. This vertical falloff is what makes
the wall read as tall.

TILING: tiles seamlessly left to right. The top and bottom edges do NOT tile —
they are the crest and the base of the wall.

CANVAS: 512 x 512 pixels, filling the frame edge to edge.

STYLE: true pixel art. Hard-edged pixels, no anti-aliasing, no gradients, no
dithering noise, no blur, no glow, no photographic texture, no JPEG-like speckle.
Limited palette of at most 12 colors drawn from: #8F8C95, #A19B9F, #AEA7A5. NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
a single light source from the upper left. Every flat color region is at least
4x4 pixels. The result must read cleanly when scaled down to a 24x24 pixel tile.

VIEW: strict top-down orthographic. No perspective, no vanishing point, no camera
tilt, no drop shadow cast outside the tile.

BACKGROUND: no border, no frame, no label, no caption, no watermark, no grid lines.
```

### 벽 윗면 → `starlight_seed_vault__wall-top.png`

```
A seamless tileable pixel-art texture of the TOP surface of a dungeon wall, seen
from directly above.

SURFACE: dark frosted stone dusted with pale ice crystals This is the flat top of a thick wall, in shadow — clearly
darker than the floor so that the player reads it as "cannot walk here".

TILING: seamless in both directions.

CANVAS: 512 x 512 pixels, filling the frame edge to edge.

STYLE: true pixel art. Hard-edged pixels, no anti-aliasing, no gradients, no
dithering noise, no blur, no glow, no photographic texture, no JPEG-like speckle.
Limited palette of at most 12 colors drawn from: #8F8C95, #A19B9F, #AEA7A5. NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
a single light source from the upper left. Every flat color region is at least
4x4 pixels. The result must read cleanly when scaled down to a 24x24 pixel tile.

VIEW: strict top-down orthographic. No perspective, no vanishing point, no camera
tilt, no drop shadow cast outside the tile.

BACKGROUND: no border, no frame, no label, no caption, no watermark, no grid lines.
```

### 물 → `starlight_seed_vault__water.png`

```
A seamless tileable top-down pixel-art water surface for a 2D RPG dungeon.

SURFACE: half-frozen water with thin plates of ice floating on it Gentle ripple lines in two or three tones. No foam, no
reflections of objects, no sky reflection.

TILING: seamless in both directions.

CANVAS: 512 x 512 pixels, filling the frame edge to edge.

STYLE: true pixel art. Hard-edged pixels, no anti-aliasing, no gradients, no
dithering noise, no blur, no glow, no photographic texture, no JPEG-like speckle.
Limited palette of at most 10 colors: #4A5E83, #405B84, plus lighter and darker tints of those blues for the ripple bands. NO sand, stone, or brown tones anywhere in the frame — this tile is water only. Flat cel shading with
a single light source from the upper left. Every flat color region is at least
4x4 pixels. The result must read cleanly when scaled down to a 24x24 pixel tile.

VIEW: strict top-down orthographic. No perspective, no vanishing point, no camera
tilt, no drop shadow cast outside the tile.

BACKGROUND: no border, no frame, no label, no caption, no watermark, no grid lines.
```

### 물건 6종 → `starlight_seed_vault__objects.png`

```
Six separate top-down pixel-art dungeon objects for a 2D RPG, arranged in one row
of six evenly spaced cells, each object centered in its own cell with generous
empty space around it. The objects do NOT touch or overlap.

OBJECTS, left to right:
1. a short flight of stone stairs descending away from the viewer
2. a dark doorway arch with deep shadow inside, set into a wall
3. a stone pillar seen from a high angle, base and capital both visible
4. the corner of a woven floor rug, showing two straight edges and a braided trim
5. a small pile of rubble and broken stones
6. a clump of tall grass or ferns

All six objects are pale frosted stone and cold metal, rimmed with ice.

CANVAS: 1536 x 1024 pixels. Six cells of 256 x 1024 side by side, each object
centered in its cell.

BACKGROUND: fully transparent. No ground, no shadow blob painted into the
background, no cell borders, no labels.

STYLE: true pixel art. Hard-edged pixels, no anti-aliasing, no gradients, no
dithering noise, no blur, no glow, no photographic texture, no JPEG-like speckle.
Limited palette of at most 12 colors drawn from: #8F8C95, #A19B9F, #AEA7A5. NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
a single light source from the upper left. Every flat color region is at least
4x4 pixels. The result must read cleanly when scaled down to a 24x24 pixel tile.

VIEW: strict top-down orthographic. No perspective, no vanishing point, no camera
tilt, no drop shadow cast outside the tile.

BACKGROUND: no border, no frame, no label, no caption, no watermark, no grid lines.
```

## 마음나무 관측실 `heartwood_observatory`

팔레트: `#6C4C30, #885E37, #A77445, #51391F, #02375B`

### 방 안 바닥 → `heartwood_observatory__floor-room.png`

```
A seamless tileable top-down pixel-art floor texture for a 2D RPG dungeon.

SURFACE: warm wooden planks laid in a neat row, visible grain and small nail heads

DETAIL: irregular hand-placed detail — the wear is NOT uniform. Some areas are
smoother, some carry small chips, hairline cracks, or a scatter of tiny stones.
Detail covers roughly one fifth of the surface; the rest stays calm. Avoid any
regular repeating motif that the eye can lock onto.

TILING: the texture must tile seamlessly — the left edge continues into the right
edge, and the top edge into the bottom edge, with no visible seam.

CANVAS: 512 x 512 pixels, filling the frame edge to edge.

STYLE: true pixel art. Hard-edged pixels, no anti-aliasing, no gradients, no
dithering noise, no blur, no glow, no photographic texture, no JPEG-like speckle.
Limited palette of at most 12 colors drawn from: #6C4C30, #885E37, #A77445, #51391F. NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
a single light source from the upper left. Every flat color region is at least
4x4 pixels. The result must read cleanly when scaled down to a 24x24 pixel tile.

VIEW: strict top-down orthographic. No perspective, no vanishing point, no camera
tilt, no drop shadow cast outside the tile.

BACKGROUND: no border, no frame, no label, no caption, no watermark, no grid lines.
```

### 복도 바닥 → `heartwood_observatory__floor-path.png`

```
A seamless tileable top-down pixel-art floor texture for a 2D RPG dungeon.

SURFACE: a worn wooden boardwalk of planks of uneven width, sawdust and bark chips caught in the gaps

DETAIL: irregular hand-placed detail — the wear is NOT uniform. Some areas are
smoother, some carry small chips, hairline cracks, or a scatter of tiny stones.
Detail covers roughly one fifth of the surface; the rest stays calm. Avoid any
regular repeating motif that the eye can lock onto.

TILING: the texture must tile seamlessly — the left edge continues into the right
edge, and the top edge into the bottom edge, with no visible seam.

CANVAS: 512 x 512 pixels, filling the frame edge to edge.

STYLE: true pixel art. Hard-edged pixels, no anti-aliasing, no gradients, no
dithering noise, no blur, no glow, no photographic texture, no JPEG-like speckle.
Limited palette of at most 12 colors drawn from: #6C4C30, #885E37, #A77445, #51391F. NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
a single light source from the upper left. Every flat color region is at least
4x4 pixels. The result must read cleanly when scaled down to a 24x24 pixel tile.

VIEW: strict top-down orthographic. No perspective, no vanishing point, no camera
tilt, no drop shadow cast outside the tile.

BACKGROUND: no border, no frame, no label, no caption, no watermark, no grid lines.
```

### 벽 앞면 → `heartwood_observatory__wall-face.png`

```
A seamless horizontally-tiling pixel-art wall face for a 2D RPG dungeon, seen
straight from the front as if standing in front of it.

SURFACE: living tree bark and root walls with deep vertical grain, small climbing vines

LIGHT: the top of the wall face catches light and is clearly brighter; the bottom
where it meets the floor is clearly darker. This vertical falloff is what makes
the wall read as tall.

TILING: tiles seamlessly left to right. The top and bottom edges do NOT tile —
they are the crest and the base of the wall.

CANVAS: 512 x 512 pixels, filling the frame edge to edge.

STYLE: true pixel art. Hard-edged pixels, no anti-aliasing, no gradients, no
dithering noise, no blur, no glow, no photographic texture, no JPEG-like speckle.
Limited palette of at most 12 colors drawn from: #6C4C30, #885E37, #A77445, #51391F. NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
a single light source from the upper left. Every flat color region is at least
4x4 pixels. The result must read cleanly when scaled down to a 24x24 pixel tile.

VIEW: strict top-down orthographic. No perspective, no vanishing point, no camera
tilt, no drop shadow cast outside the tile.

BACKGROUND: no border, no frame, no label, no caption, no watermark, no grid lines.
```

### 벽 윗면 → `heartwood_observatory__wall-top.png`

```
A seamless tileable pixel-art texture of the TOP surface of a dungeon wall, seen
from directly above.

SURFACE: dark tree canopy and thick bark seen from directly above This is the flat top of a thick wall, in shadow — clearly
darker than the floor so that the player reads it as "cannot walk here".

TILING: seamless in both directions.

CANVAS: 512 x 512 pixels, filling the frame edge to edge.

STYLE: true pixel art. Hard-edged pixels, no anti-aliasing, no gradients, no
dithering noise, no blur, no glow, no photographic texture, no JPEG-like speckle.
Limited palette of at most 12 colors drawn from: #6C4C30, #885E37, #A77445, #51391F. NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
a single light source from the upper left. Every flat color region is at least
4x4 pixels. The result must read cleanly when scaled down to a 24x24 pixel tile.

VIEW: strict top-down orthographic. No perspective, no vanishing point, no camera
tilt, no drop shadow cast outside the tile.

BACKGROUND: no border, no frame, no label, no caption, no watermark, no grid lines.
```

### 물 → `heartwood_observatory__water.png`

```
A seamless tileable top-down pixel-art water surface for a 2D RPG dungeon.

SURFACE: a dark sap-colored pool held between roots Gentle ripple lines in two or three tones. No foam, no
reflections of objects, no sky reflection.

TILING: seamless in both directions.

CANVAS: 512 x 512 pixels, filling the frame edge to edge.

STYLE: true pixel art. Hard-edged pixels, no anti-aliasing, no gradients, no
dithering noise, no blur, no glow, no photographic texture, no JPEG-like speckle.
Limited palette of at most 10 colors: #02375B, plus lighter and darker tints of those blues for the ripple bands. NO sand, stone, or brown tones anywhere in the frame — this tile is water only. Flat cel shading with
a single light source from the upper left. Every flat color region is at least
4x4 pixels. The result must read cleanly when scaled down to a 24x24 pixel tile.

VIEW: strict top-down orthographic. No perspective, no vanishing point, no camera
tilt, no drop shadow cast outside the tile.

BACKGROUND: no border, no frame, no label, no caption, no watermark, no grid lines.
```

### 물건 6종 → `heartwood_observatory__objects.png`

```
Six separate top-down pixel-art dungeon objects for a 2D RPG, arranged in one row
of six evenly spaced cells, each object centered in its own cell with generous
empty space around it. The objects do NOT touch or overlap.

OBJECTS, left to right:
1. a short flight of stone stairs descending away from the viewer
2. a dark doorway arch with deep shadow inside, set into a wall
3. a stone pillar seen from a high angle, base and capital both visible
4. the corner of a woven floor rug, showing two straight edges and a braided trim
5. a small pile of rubble and broken stones
6. a clump of tall grass or ferns

All six objects are living wood, bark, and root, warm and organic.

CANVAS: 1536 x 1024 pixels. Six cells of 256 x 1024 side by side, each object
centered in its cell.

BACKGROUND: fully transparent. No ground, no shadow blob painted into the
background, no cell borders, no labels.

STYLE: true pixel art. Hard-edged pixels, no anti-aliasing, no gradients, no
dithering noise, no blur, no glow, no photographic texture, no JPEG-like speckle.
Limited palette of at most 12 colors drawn from: #6C4C30, #885E37, #A77445, #51391F. NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
a single light source from the upper left. Every flat color region is at least
4x4 pixels. The result must read cleanly when scaled down to a 24x24 pixel tile.

VIEW: strict top-down orthographic. No perspective, no vanishing point, no camera
tilt, no drop shadow cast outside the tile.

BACKGROUND: no border, no frame, no label, no caption, no watermark, no grid lines.
```
