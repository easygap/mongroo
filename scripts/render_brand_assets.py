"""Render Mongroo launcher, PWA, splash, and favicon assets.

Every raster is derived from the approved transparent symbol master so the
material, camera angle, and silhouette stay identical across platforms.
"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / "design-system" / "brand" / "mongroo-symbol-master.png"
PAPER = (239, 239, 239, 255)


@lru_cache(maxsize=1)
def _symbol() -> Image.Image:
    image = Image.open(MASTER).convert("RGBA")
    bounds = image.getbbox()
    if bounds is None:
        raise ValueError(f"The symbol master is empty: {MASTER}")
    return image.crop(bounds)


def _render(
    size: int,
    *,
    ratio: float,
    background: tuple[int, int, int, int] | None,
) -> Image.Image:
    canvas = Image.new(
        "RGBA",
        (size, size),
        (0, 0, 0, 0) if background is None else background,
    )
    symbol = _symbol()
    limit = round(size * ratio)
    scale = min(limit / symbol.width, limit / symbol.height)
    width = max(1, round(symbol.width * scale))
    height = max(1, round(symbol.height * scale))
    resized = symbol.resize((width, height), Image.Resampling.LANCZOS)

    # The dimensional mark carries slightly more visual weight on the right.
    # A small optical shift keeps it centered after platform masks are applied.
    x = round((size - width) / 2 - size * 0.008)
    y = round((size - height) / 2)
    canvas.alpha_composite(resized, (x, y))
    return canvas


def _render_monochrome(size: int, *, ratio: float) -> Image.Image:
    colored = _render(size, ratio=ratio, background=None)
    result = Image.new("RGBA", colored.size, (0, 0, 0, 255))
    result.putalpha(colored.getchannel("A"))
    return result


def _save_png(
    path: Path,
    size: int,
    *,
    ratio: float,
    background: tuple[int, int, int, int] | None = PAPER,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    _render(size, ratio=ratio, background=background).save(path, optimize=True)


def main() -> None:
    if not MASTER.exists():
        raise FileNotFoundError(f"Approved Mongroo symbol not found: {MASTER}")

    web = ROOT / "app" / "web"
    for name, size in (
        ("favicon-16.png", 16),
        ("favicon-32.png", 32),
        ("favicon-48.png", 48),
        ("favicon.png", 64),
    ):
        _save_png(path=web / name, size=size, ratio=0.92, background=None)

    favicon = _render(64, ratio=0.92, background=None)
    favicon.save(
        web / "favicon.ico",
        format="ICO",
        sizes=[(16, 16), (32, 32), (48, 48)],
    )

    _save_png(web / "icons" / "apple-touch-icon.png", 180, ratio=0.78)
    _save_png(web / "icons" / "Icon-192.png", 192, ratio=0.80)
    _save_png(web / "icons" / "Icon-512.png", 512, ratio=0.80)
    _save_png(web / "icons" / "Icon-maskable-192.png", 192, ratio=0.62)
    _save_png(web / "icons" / "Icon-maskable-512.png", 512, ratio=0.62)

    brand = ROOT / "app" / "assets" / "brand"
    brand.mkdir(parents=True, exist_ok=True)
    # 512px covers the largest in-app use at 3x without shipping the full
    # working master in every Flutter bundle.
    _render(512, ratio=0.90, background=None).save(
        brand / "mongroo-symbol.webp",
        format="WEBP",
        quality=92,
        method=6,
    )
    _render(1024, ratio=0.80, background=PAPER).save(
        ROOT / "design-system" / "brand" / "mongroo-app-icon.png",
        optimize=True,
    )

    android = ROOT / "app" / "android" / "app" / "src" / "main" / "res"
    densities = {
        "mdpi": 48,
        "hdpi": 72,
        "xhdpi": 96,
        "xxhdpi": 144,
        "xxxhdpi": 192,
    }
    for density, size in densities.items():
        folder = android / f"mipmap-{density}"
        _save_png(folder / "ic_launcher.png", size, ratio=0.78)
        _save_png(folder / "ic_launcher_round.png", size, ratio=0.74)

    drawable = android / "drawable-nodpi"
    drawable.mkdir(parents=True, exist_ok=True)
    _render(432, ratio=0.62, background=None).save(
        drawable / "mongroo_launcher_foreground.png",
        optimize=True,
    )
    _render_monochrome(432, ratio=0.62).save(
        drawable / "mongroo_launcher_monochrome.png",
        optimize=True,
    )
    _render(512, ratio=0.72, background=None).save(
        drawable / "mongroo_splash_icon.png",
        optimize=True,
    )


if __name__ == "__main__":
    main()
