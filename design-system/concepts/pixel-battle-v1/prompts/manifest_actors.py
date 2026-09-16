"""아군 전투 도트 2차 배치.

걷기 시트(app/assets/adventure/overworld/expedition-walker-<품종>-v1.png)를
참조로 첨부해 같은 캐릭터를 옆모습 전투 자세로 다시 그린다. 걷기 시트는
24×30 도트라 전투 무대에 세우기엔 너무 작다. 전투용은 48도트 키로 만든다.
"""

import json
import os

OUT_ROOT = "design-system/concepts/pixel-battle-v1/sources/actors"
os.makedirs(OUT_ROOT, exist_ok=True)

STYLE = (
    "True pixel art player character battle sprite for a 2D turn-based cozy JRPG, "
    "16-bit SNES-era style with modern clean pixel work. Redraw the exact character "
    "from the attached pixel sprite sheet reference: keep its identity, hair or hat, "
    "outfit, flower-pot motif and color palette, but render it larger and more "
    "detailed as a full-body three-quarter side view facing RIGHT in a ready idle "
    "stance, weight slightly forward, feet on the ground, arms relaxed. One sprite "
    "only, centered, about 72% of the canvas height, on a flat solid pure magenta "
    "(#FF00FF) background covering the entire canvas, no cast shadow, no floor, no "
    "ground line. Clean 1px darker outline, hard-edged pixels only, no "
    "anti-aliasing, no gradients, no glow, no blur, no text, no border, no frame, "
    "no alternate views. Limited palette of about 16 colors taken from the "
    "reference. Every distinct pixel block is about 14x14 canvas pixels so it reads "
    "cleanly when downscaled to a 56 pixel tall sprite."
)

SPECIES = {
    "baby-pot": "a baby sprout character with a leaf bonnet, a coral pacifier and a flower-pot romper",
    "handsome-pot": "a calm boy character with navy hair and a plant-school coat, a small flower-pot badge",
    "pretty-pot": "a confident idol girl character with a coral bob haircut and a green cape",
    "tsundere-pot": "a tsundere girl character with red hair, folded arms and cracked flower-pot armor pieces",
    "zombie-pot": "a laid-back zombie character with sage-green skin, sleepy eyes and purple suspenders",
    "gumiho-pot": "a playful nine-tailed fox spirit character in modern hanbok with asymmetric tails",
    "ninja-pot": "a small ninja scout character with leaf shuriken and a flower-pot backpack",
    "magical-pot": "a magic-school honor student character with a vine hat and a sprout wand",
    "aloof-pot": "an aloof rival character with a black bob haircut and a white research coat",
    "student-pot": "a student-council president character in a school uniform with a sprout badge and a pot-shaped satchel",
    "gal-pot": "a cheerful fashionable girl character with bright accessories and a flower-pot bag",
    "maestro-pot": "a conductor character in a tailcoat holding a sprout baton",
    "marten-pot": "a small marten animal character with a bushy tail and a flower-pot",
    "nurse-pot": "a caring nurse character with a leaf cap and a small flower-pot kit",
    "restorer-pot": "an art-restorer character with a work apron, gloves and a flower-pot toolbox",
    "cactus": "a round cactus character in a pot with a small flower on top",
    "sunflower": "a sunflower character in a pot with a big bright flower head",
}

jobs = []
for code, description in SPECIES.items():
    reference = f"app/assets/adventure/overworld/expedition-walker-{code}-v1.png"
    if not os.path.exists(reference):
        raise SystemExit(f"missing walker sheet: {reference}")
    jobs.append(
        dict(
            id=f"actor-{code}",
            mode="generate",
            prompt=f"{STYLE} The character is {description}.",
            references=[reference],
            size="1024x1024",
            quality="high",
            out=f"{OUT_ROOT}/{code}.png",
        )
    )

os.makedirs("tmp/pixel-battle", exist_ok=True)
with open("tmp/pixel-battle/batch-actors.json", "w", encoding="utf-8") as handle:
    json.dump({"version": 1, "jobs": jobs}, handle, ensure_ascii=False, indent=2)
print(len(jobs), "jobs written")
