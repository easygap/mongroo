# 마음나무 관측실 타일셋 프롬프트

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
Limited palette of at most 12 colors drawn from: . NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
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
Limited palette of at most 12 colors drawn from: . NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
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
Limited palette of at most 12 colors drawn from: . NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
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
Limited palette of at most 12 colors drawn from: . NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
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
Limited palette of at most 10 colors: , plus lighter and darker tints of those blues for the ripple bands. NO sand, stone, or brown tones anywhere in the frame — this tile is water only. Flat cel shading with
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
Limited palette of at most 12 colors drawn from: . NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
a single light source from the upper left. Every flat color region is at least
4x4 pixels. The result must read cleanly when scaled down to a 24x24 pixel tile.

VIEW: strict top-down orthographic. No perspective, no vanishing point, no camera
tilt, no drop shadow cast outside the tile.

BACKGROUND: no border, no frame, no label, no caption, no watermark, no grid lines.
```
