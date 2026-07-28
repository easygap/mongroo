"""Nudge selected outfit panels onto the matching wardrobe base pose.

Image-to-image edits can keep the pose but re-center one slot by a few pixels.
This utility moves only the already-rendered outfit pixels inside that slot; it
does not redraw the garment or modify the base.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

from build_character_emotion_adults_v2 import FORMS
from build_wardrobe_layers import _centroid_x, _load_alpha, _mask, _six_boundaries


MAGENTA = (255, 0, 255, 255)


def align(base_path: Path, outfit_path: Path, forms: list[str]) -> None:
    base = _load_alpha(base_path)
    outfit = _load_alpha(outfit_path)
    if base.size != outfit.size:
        raise ValueError(f"canvas mismatch: {base.size} != {outfit.size}")

    boundaries = _six_boundaries(base)
    source = Image.open(outfit_path).convert("RGBA")
    result = source.copy()
    for form in forms:
        index = FORMS.index(form)
        left, right = boundaries[index], boundaries[index + 1]
        base_panel = base.crop((left, 0, right, base.height))
        outfit_panel = outfit.crop((left, 0, right, outfit.height))
        base_mask = _mask(base_panel)
        outfit_mask = _mask(outfit_panel)
        dx = round(_centroid_x(base_mask) - _centroid_x(outfit_mask))

        source_panel = source.crop((left, 0, right, source.height))
        source_alpha = outfit_panel.getchannel("A")
        shifted = Image.new("RGBA", source_panel.size, MAGENTA)
        shifted.alpha_composite(source_panel, (dx, 0))
        shifted_alpha = Image.new("L", source_alpha.size, 0)
        shifted_alpha.paste(source_alpha, (dx, 0))
        background = Image.new("RGBA", source_panel.size, MAGENTA)
        background.paste(shifted, mask=shifted_alpha)
        result.paste(background, (left, 0))
        print(f"{form}: dx={dx}px")

    result.save(outfit_path, "PNG", optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--outfit", type=Path, required=True)
    parser.add_argument("--forms", nargs="+", choices=FORMS, required=True)
    args = parser.parse_args()
    align(args.base, args.outfit, args.forms)


if __name__ == "__main__":
    main()
