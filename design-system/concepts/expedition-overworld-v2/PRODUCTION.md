# Expedition Overworld v2 — production record

## Status

- Generation mode: built-in ImageGen
- Runtime output: `app/assets/adventure/overworld/expedition-tile-atlas-v2.png`
- Runtime manifest: `app/assets/adventure/overworld/expedition-tile-atlas-v2.json`
- Deterministic builder: `design-system/scripts/build_expedition_tile_atlas_v2.py`
- Source masters: `design-system/concepts/expedition-overworld-v2/sources/`
- Cell / gutter / stride: 96 / 2 / 100 px
- Atlas layout: 8 columns, 64 padded cells per region, 4 regions

The generator outputs are source masters, not runtime-ready sprites. The build
step removes neutral backdrops, decontaminates pale edge pixels, bottom-anchors
props, creates continuous 4x4 terrain macro phases, applies the four region grades, extrudes
gutters, and rejects seam, alpha, stipple, or isolated-speck regressions.

## Reference art

- `app/assets/adventure/expedition-moss-archive-terrain-v3.webp`
- `app/assets/adventure/expedition-monster-den-battle-v1.webp`
- Character pass additionally used
  `app/assets/adventure/ledger-keeper-idle-v1.webp`

These references are used for palette, material language, edge handling, and
upper-left warm / lower-right cool lighting. They are not copied into the new
sprites.

## Shared final prompt contract

Use case: production game sprite or seamless ground asset for a shipped 2.5D
cozy JRPG overworld. Treat the supplied project images as strict style, palette,
material, and lighting references. Handcrafted painterly game art with broad,
controlled material planes; warm amber key light from upper-left; cool deep-teal
occlusion toward lower-right; clean anti-aliased silhouettes readable at 48–96
px. No baked cast shadow because runtime adds it. Avoid stippling, pointillism,
dithering, grain, noise, random dots, glitter, tiny cracks, pebble clutter,
microtexture, watercolor bloom, photorealism, painterly mush, excessive outline,
over-sharpening, and high-frequency AI artifacts. Exactly one requested asset;
no scene, text, multiple variants, or sprite sheet unless requested.

## Asset-specific final prompt set

### Terrain

- `terrain-floor.png`: exact orthographic square seamless warm gray-brown archive
  stone ground; five to seven large slab planes; only floor, no props.
- `terrain-moss.png`: exact orthographic square seamless archive ground with four
  to six broad moss cushions over restrained warm stone; no individual grass
  blades or tiny leaves.
- `terrain-water.png`: exact orthographic square seamless shallow water; deep teal
  and muted cyan; three to five broad curved ripples; no foam, bubbles, glitter,
  or micro-caustics.

### Props and actors

Each isolated prop requested a plain neutral backdrop for deterministic alpha
matting after ImageGen returned opaque PNGs despite transparent-alpha wording.

- `prop-wall.png`: one low modular moss-archive masonry wall, straight horizontal
  footprint, broad warm stone blocks, large moss pads, clean connectable ends.
- `prop-shelf.png`: one compact dark teal-brown two-shelf bookcase, restrained
  large book spines and one scroll, gently moss-aged edges.
- `prop-lantern.png`: one short wrought-bronze pedestal lantern with oval amber
  glass and simple arched guard; glow contained close to the lamp; no particles.
- `prop-chest.png`: one closed rounded dark-walnut treasure chest, broad bronze
  bands, and one teal memory-rune latch.
- `prop-item.png`: one softened vertical diamond memory crystal with three large
  facets, cyan core, and small bronze base collar; no sparks or particles.
- `prop-npc.png`: one full-body friendly forest archivist named Moa, about three
  heads tall, moss hood, teal archive coat, tan satchel, and one rolled map;
  neutral three-quarter top-down idle pose with visible feet.
- `prop-altar.png`: one waist-high rounded stone memory altar, stepped base, open
  dark-teal book with one large cyan rune, and a recessed amber lens.
- `prop-root.png`: one low sideways arch formed by two intertwined old roots,
  thick broad curves, three large moss patches, and one subtle teal sap vein.
- `monster`: reuses the already-approved transparent project master
  `tangle-tangled-ledger-idle-v1.webp`; it is normalized and graded by the same
  v2 pipeline rather than regenerated into a conflicting character style.

## Release QA gates

- Continuous macro-cell edge deltas below the broad-brush limit, with an exact
  mirrored wrap boundary across both axes.
- Fully opaque terrain; genuinely transparent prop backgrounds.
- Two-pixel extruded gutters to prevent filtered atlas bleed.
- No-dither median cleanup before 96px normalization.
- Automated high-frequency edge and isolated-speck thresholds.
- SHA-256 pinning of every source master and the output atlas.
- Runtime only paints camera-visible tiles and camera-visible chunk objects.
