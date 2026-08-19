# 메아리 우물정원 타일셋 프롬프트

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
Limited palette of at most 12 colors drawn from: . NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
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
Limited palette of at most 12 colors drawn from: . NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
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
Limited palette of at most 12 colors drawn from: . NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
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
Limited palette of at most 12 colors drawn from: . NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
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
Limited palette of at most 10 colors: , plus lighter and darker tints of those blues for the ripple bands. NO sand, stone, or brown tones anywhere in the frame — this tile is water only. Flat cel shading with
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
Limited palette of at most 12 colors drawn from: . NO blue or teal water tones — those belong to the water tile only. Flat cel shading with
a single light source from the upper left. Every flat color region is at least
4x4 pixels. The result must read cleanly when scaled down to a 24x24 pixel tile.

VIEW: strict top-down orthographic. No perspective, no vanishing point, no camera
tilt, no drop shadow cast outside the tile.

BACKGROUND: no border, no frame, no label, no caption, no watermark, no grid lines.
```
