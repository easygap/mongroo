"""3차 배치 — 장면 원화 21장과 허브 배너 1장을 도트로.

전투 배경은 2차까지 끝났지만 준비 화면·사건 장면·깊은 조사 현장은 아직 뿌연
장면 원화(`expedition-*.webp`)를 쓴다. 같은 화풍으로 바꿔야 탐험 전체가 한
그림이 된다. 장면 키 7 × 공용(기억서고) + 지역 전용 14 = 21.
"""

import json
import os

OUT_ROOT = "design-system/concepts/pixel-battle-v1/sources"
os.makedirs(f"{OUT_ROOT}/scenes", exist_ok=True)
os.makedirs(f"{OUT_ROOT}/banners", exist_ok=True)

STYLE = (
    "True pixel art, 16-bit SNES-era JRPG location illustration drawn with modern "
    "clean pixel work in the spirit of contemporary indie pixel RPGs, hand-placed "
    "pixel clusters, hard-edged pixels only, no anti-aliasing, no gradients, no blur, "
    "no glow halos, no photographic texture, no painterly brushwork, no text, no "
    "characters, no creatures, no UI, no border, no frame. Landscape composition "
    "1536x1024. Every distinct pixel block is about 4x4 canvas pixels so the picture "
    "reads cleanly when downscaled to 384 pixels wide."
)

REGION_FLAVOR = {
    "moss_archive": (
        "inside an underground memory archive overgrown with soft moss; sandstone, "
        "walnut shelves, ferns, bronze lanterns; warm amber lantern light from the "
        "upper left with cool deep-teal shadows; palette of warm sand, olive moss, "
        "walnut brown, deep teal, amber, cream"
    ),
    "echo_well": (
        "in a sunken well garden at dusk; wet slate stone, water channels, lily pads, "
        "hanging wind bells; cool blue moonlight with pale cyan reflections; palette of "
        "slate blue, deep teal, wet stone gray, pale cyan, a little moss green, bronze"
    ),
    "starlight_seed_vault": (
        "in a frosty seed vault at night; frosted metal shelves of glowing seed jars, "
        "a starry domed ceiling, brass fittings; cold indigo ambient light with warm "
        "gold pinpoints; palette of indigo, violet, frost white, brass gold, pale mint"
    ),
    "heartwood_observatory": (
        "inside a giant living tree turned observatory; curved heartwood walls with "
        "growth rings, brass instruments, hanging leaf lanterns; warm amber-orange "
        "lantern light with deep umber shadows; palette of warm oak, amber, umber, "
        "leaf green, cream"
    ),
}

SCENES = {
    "dungeon_gate": "the entrance gate: a large round doorway with a heavy wooden door and a bronze ring, a few steps leading down, a lantern on each side",
    "flooded_cave": "a flooded cavern room where shallow water covers most of the floor, stepping stones cross it, small glowing crystals light the water from below",
    "root_tunnel": "a tunnel woven from giant tree roots arching overhead, soft light coming through cracks between the roots, hanging moss",
    "echo_well": "a round stone well in the middle of a small chamber, a bell hanging from a wooden frame above it, water rings on the floor",
    "treasure_vault": "a small vault with a few closed wooden chests, a stone pedestal holding a glowing memory crystal, a rune seal on the back wall",
    "monster_den": "a round open den, the floor ringed by thick old roots like a nest, empty in the middle, a raised stone step at the back",
    "moon_tower": "the base of a tall spiral staircase winding upward, a round window high up showing the moon, a railing of carved wood",
}

REGION_SCENES = {
    "moss_archive": list(SCENES),
    "echo_well": ["monster_den", "dungeon_gate", "treasure_vault", "flooded_cave", "root_tunnel", "echo_well"],
    "starlight_seed_vault": ["monster_den", "dungeon_gate", "treasure_vault", "root_tunnel"],
    "heartwood_observatory": ["monster_den", "dungeon_gate", "moon_tower", "root_tunnel"],
}

jobs = []
for region, keys in REGION_SCENES.items():
    for key in keys:
        prompt = (
            f"{STYLE} The location is {SCENES[key]}, {REGION_FLAVOR[region]}. "
            f"A clear open floor area in the lower third where characters could stand."
        )
        jobs.append(
            dict(
                id=f"scene-{region}-{key}",
                mode="generate",
                prompt=prompt,
                size="1536x1024",
                quality="high",
                out=f"{OUT_ROOT}/scenes/{region}__{key}.png",
            )
        )

jobs.append(
    dict(
        id="banner-patrol-garden-path",
        mode="generate",
        prompt=(
            f"{STYLE} The location is a quiet garden path leading out through the open "
            f"glass door of a small greenhouse at dawn, seen from inside looking out; "
            f"flower pots and sprouting seedlings along the path, a small wooden "
            f"signpost, dew on the grass, soft pink and gold morning light, gentle "
            f"warm palette of sage green, terracotta, cream and dawn pink."
        ),
        size="1536x1024",
        quality="high",
        out=f"{OUT_ROOT}/banners/patrol-garden-path.png",
    )
)

os.makedirs("tmp/pixel-battle", exist_ok=True)
with open("tmp/pixel-battle/batch-scenes.json", "w", encoding="utf-8") as handle:
    json.dump({"version": 1, "jobs": jobs}, handle, ensure_ascii=False, indent=2)
print(len(jobs), "jobs written")
