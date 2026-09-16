"""도트 전투 자산 1차 배치 매니페스트.

전투 배경 8장(지역 4 × 세로/가로), 엉킴 12종, 수호짐승 4종. 결과는
design-system/concepts/pixel-battle-v1/sources/ 아래에 떨어지고,
build_pixel_battle_assets.py가 런타임 도트로 굽는다.
"""

import json
import os

OUT_ROOT = "design-system/concepts/pixel-battle-v1/sources"
for sub in ("backdrops", "tangles", "keepers"):
    os.makedirs(f"{OUT_ROOT}/{sub}", exist_ok=True)

STYLE_BG = (
    "True pixel art, 16-bit SNES-era JRPG battle background drawn with modern clean "
    "pixel work in the spirit of contemporary indie pixel RPGs, hand-placed pixel "
    "clusters, hard-edged pixels only, no anti-aliasing, no gradients, no blur, no "
    "glow halos, no photographic texture, no painterly brushwork, no text, no "
    "characters, no creatures, no UI, no border, no frame."
)

REGIONS = {
    "moss_archive": dict(
        scene=(
            "an underground memory archive overgrown with soft moss: tall sandstone "
            "bookshelves stacked with old ledgers and pressed-flower folios, hanging "
            "ferns, a round wooden vault door in the back wall, small bronze lanterns "
            "with amber glass, a few teal memory crystals growing at the floor edge"
        ),
        light="warm amber lantern light from the upper left, cool deep-teal shadows toward the lower right",
        palette="about 24 colors: warm sand stone, olive moss green, walnut brown, deep teal shadow, amber highlight, cream",
    ),
    "echo_well": dict(
        scene=(
            "a sunken well garden at dusk: a round stone well with a wooden bell frame "
            "in the back, shallow water channels with lily pads along the sides, hanging "
            "wind bells, wet moss on the stone walls, a few softly glowing blue droplets"
        ),
        light="cool blue moonlight from above, pale cyan reflections on the wet stone, deep slate shadows",
        palette="about 24 colors: slate blue, deep teal, wet stone gray, pale cyan highlight, a little moss green, bronze",
    ),
    "starlight_seed_vault": dict(
        scene=(
            "a frosty seed vault at night: tall shelves of glass jars holding glowing "
            "seeds, frost on the metal shelf edges, a domed ceiling with a round window "
            "showing a starry sky, a large brass seed-clock on the back wall, faint "
            "violet and gold sparkles"
        ),
        light="cold indigo ambient light with warm gold pinpoints from the glowing seeds",
        palette="about 24 colors: indigo, violet, frost white, brass gold, pale mint, midnight blue",
    ),
    "heartwood_observatory": dict(
        scene=(
            "an observatory built inside a giant living tree: curved heartwood walls "
            "with visible growth rings, a spiral wooden staircase in the back, a brass "
            "telescope pointing at a knot-hole window, hanging leaf lanterns"
        ),
        light="warm amber-orange lantern light from the upper right, deep umber shadows",
        palette="about 24 colors: warm oak, amber, umber brown, leaf green, cream highlight, dark bark",
    ),
}

jobs = []
for code, r in REGIONS.items():
    portrait = (
        f"{STYLE_BG} Portrait composition 1024x1536 for a vertical phone battle screen. "
        f"The lower 58% of the image is an open, empty, flat ground plane seen from a "
        f"slightly raised three-quarter view where two combatants will stand later, kept "
        f"clear of objects and with only subtle floor detail. The upper 42% shows the "
        f"environment: {r['scene']}. Lighting: {r['light']}. Limited palette, "
        f"{r['palette']}. Every distinct pixel block is about 6x6 canvas pixels so the "
        f"picture reads cleanly when downscaled to 160 pixels wide."
    )
    landscape = (
        f"{STYLE_BG} Landscape composition 1536x1024 for a wide battle screen. The lower "
        f"52% of the image is an open, empty, flat ground plane seen from a slightly "
        f"raised three-quarter view where two combatants will stand later, kept clear of "
        f"objects and with only subtle floor detail. The upper 48% shows the environment: "
        f"{r['scene']}. Lighting: {r['light']}. Limited palette, {r['palette']}. Every "
        f"distinct pixel block is about 5x5 canvas pixels so the picture reads cleanly "
        f"when downscaled to 320 pixels wide."
    )
    jobs.append(
        dict(
            id=f"bg-{code}-portrait",
            mode="generate",
            prompt=portrait,
            size="1024x1536",
            quality="high",
            out=f"{OUT_ROOT}/backdrops/{code}-portrait.png",
        )
    )
    jobs.append(
        dict(
            id=f"bg-{code}-landscape",
            mode="generate",
            prompt=landscape,
            size="1536x1024",
            quality="high",
            out=f"{OUT_ROOT}/backdrops/{code}-landscape.png",
        )
    )

STYLE_SPR = (
    "True pixel art enemy sprite for a 2D turn-based cozy JRPG, 16-bit SNES-era style "
    "with modern clean pixel work. It faces left in a neutral idle pose, centered, "
    "filling about 70% of a 1024x1024 canvas. Flat solid pure magenta (#FF00FF) "
    "background covering the entire canvas with nothing else on it, no cast shadow, no "
    "floor, no ground line. Clean 1px darker outline around the silhouette, hard-edged "
    "pixels only, no anti-aliasing, no gradients, no glow, no blur, no soft shading, no "
    "text, no border, no frame, exactly one sprite, no alternate views."
)

TANGLES = {
    "tangled_ledger": (
        "a gentle tangle creature that is a round bundle of old ledger books and loose pages bound up in green thread like a ball of yarn, two small round eyes peeking out between the pages, a brass clasp dangling",
        "about 14 colors: parchment cream, walnut brown, moss green thread, brass, dark umber outline",
        64,
    ),
    "drifting_pressings": (
        "a gentle tangle creature that is a small floating swarm of dried pressed flowers and leaves gathered into one loose rounded shape, a faint leaf face in the middle, a few petals trailing off the sides",
        "about 14 colors: dusty rose, faded gold, olive green, cream, dark olive outline",
        64,
    ),
    "shelf_snarl": (
        "a big knotted bookshelf tangle creature: three tilted wooden shelves tangled together with catalogue cards and rope, books spilling out like teeth, two lantern-like amber eyes glowing in the dark gap between shelves",
        "about 16 colors: dark walnut, parchment, moss green, amber, rope beige, dark umber outline",
        80,
    ),
    "knotted_echo": (
        "a gentle tangle creature made of translucent sound rings and ripples tied together into a knot like a bow, with two small bright dots for eyes, a few loose ring fragments floating around it",
        "about 12 colors: pale cyan, teal, slate blue, white, deep blue outline",
        64,
    ),
    "splashing_droplets": (
        "a lively cluster of chubby round water droplets stacked together into one creature, the biggest droplet in front with a cheeky face, small splash dots around the edges",
        "about 12 colors: deep blue, cyan, white highlight, teal, navy outline",
        64,
    ),
    "bell_knot_swirl": (
        "a large spiral swirl of bell ropes with three bronze bells caught inside the whirl, the swirl forming a wide sleepy face with heavy-lidded eyes",
        "about 16 colors: bronze, teal, deep blue, cream rope, gold highlight, navy outline",
        80,
    ),
    "snarled_stardust": (
        "a gentle tangle creature that is a tangled ball of glittering star-dust thread with a few small four-pointed stars caught inside it, two star-shaped eyes",
        "about 12 colors: violet, gold, indigo, white, deep purple outline",
        64,
    ),
    "rolling_seedbox": (
        "a wooden seed box creature with a brass latch that is half asleep, tilted as if it is rolling, sleepy half-closed eyes on the lid, a few glowing mint seeds spilling out of the open corner",
        "about 14 colors: warm wood brown, brass, indigo, mint glow, cream, dark brown outline",
        64,
    ),
    "backwound_clockspring": (
        "a large brass clock spring uncoiled and standing upright like a curious snake, with small gears and a clock face embedded in the coil, one gear as its eye, the coil tip curling at the top",
        "about 16 colors: brass, copper, indigo, cream, dark bronze outline",
        80,
    ),
    "ring_shard_tangle": (
        "a creature made of several curved wooden tree-ring shards locked together into a rolling wheel shape, growth-ring lines visible on the wood, two knot-hole eyes",
        "about 14 colors: oak, amber, umber, leaf green, dark bark outline",
        64,
    ),
    "scattered_records": (
        "a fluttering stack of loose observation record sheets flying in formation like a small bird, ink diagrams on the pages, a small inked face on the front sheet",
        "about 12 colors: cream paper, ink blue, amber, umber, dark ink outline",
        64,
    ),
    "matted_observatory": (
        "a big tangled bundle made of a brass telescope lens, measuring tapes and red record ribbons all knotted into one creature, the round glass lens serving as its single big eye",
        "about 16 colors: brass, dark umber, ribbon red, cream, glass blue, dark bronze outline",
        80,
    ),
}
for code, (design, palette, native) in TANGLES.items():
    block = 1024 // native
    prompt = (
        f"{STYLE_SPR} The sprite is {design}. It is a soft, harmless, slightly sleepy "
        f"archive object that got knotted up, not a scary monster. Limited palette, "
        f"{palette}. Every distinct pixel block is about {block}x{block} canvas pixels so "
        f"it reads cleanly when downscaled to a {native} pixel sprite."
    )
    jobs.append(
        dict(
            id=f"tangle-{code}",
            mode="generate",
            prompt=prompt,
            size="1024x1024",
            quality="high",
            out=f"{OUT_ROOT}/tangles/{code}.png",
        )
    )

KEEPERS = {
    "ledger_keeper": "a big dreaming guardian beast: a mossy stone-scaled tortoise whose shell is made of stacked stone ledger slabs and moss pads, a crest of leaf-shaped pages on its head, eyes closed in sleep, lying down peacefully",
    "echo_keeper": "a big dreaming guardian beast: a plump round otter-like creature made of water-mirror, its body reflecting like a still pond, a small wooden well bucket resting on its back, ripple rings around its paws, eyes closed in sleep",
    "seed_keeper": "a big dreaming guardian beast: a fluffy dozing owl-like creature whose feathers are made of drifting star-dust, a wooden seed box held under one wing, tiny glowing seeds in its fur, eyes closed in sleep",
    "record_keeper": "a big dreaming guardian beast: a tall wooden stag-like creature made of heartwood with visible growth rings, a knot-hole lamp glowing softly on its chest, an unfinished record page tucked in its antlers, eyes closed in sleep",
}
for code, design in KEEPERS.items():
    prompt = (
        f"{STYLE_SPR} The sprite is {design}. It is calm and gentle, never menacing. "
        f"Limited palette, about 18 colors matching its material, with a dark outline. "
        f"Every distinct pixel block is about 8x8 canvas pixels so it reads cleanly when "
        f"downscaled to a 128 pixel sprite."
    )
    jobs.append(
        dict(
            id=f"keeper-{code}",
            mode="generate",
            prompt=prompt,
            size="1024x1024",
            quality="high",
            out=f"{OUT_ROOT}/keepers/{code}.png",
        )
    )

os.makedirs("tmp/pixel-battle", exist_ok=True)
with open("tmp/pixel-battle/batch-backdrops-enemies.json", "w", encoding="utf-8") as handle:
    json.dump({"version": 1, "jobs": jobs}, handle, ensure_ascii=False, indent=2)
print(len(jobs), "jobs written")
