"""Extract an opaque illustrated sprite from ImageGen's varied magenta field.

The generic chroma helper works well for a uniform key, but ImageGen can add
large low-frequency variations that are still visibly magenta.  This extractor
keys on magenta dominance instead of distance from one sampled RGB value.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter


def extract(source_path: Path, output_path: Path) -> None:
    source = Image.open(source_path).convert("RGBA")
    red, green, blue, _ = source.split()
    magenta_score = ImageChops.subtract(ImageChops.darker(red, blue), green)

    # Subject colors are below 52. All generated key variations are above 116.
    # Preserve a narrow antialiasing ramp between the two values.
    alpha = magenta_score.point(
        lambda score: (
            255
            if score <= 52
            else 0
            if score >= 116
            else round(255 * (116 - score) / 64)
        )
    )
    alpha = alpha.filter(ImageFilter.MinFilter(3))

    result = source.copy()
    result.putalpha(alpha)
    transparent = alpha.point(lambda value: 255 if value == 0 else 0)
    result.paste((0, 0, 0, 0), mask=transparent)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    result.save(output_path, "PNG", optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    extract(args.input, args.out)


if __name__ == "__main__":
    main()
