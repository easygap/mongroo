"""도트 전투 자산을 굽는다 — 생성 원본을 진짜 도트로 되돌린다.

이미지 생성기가 내놓는 "픽셀 아트"는 1024px 판에 큰 네모를 그린 그림이다. 격자가
정확하지도 않고(블록 크기와 정렬이 그림 안에서 흔들린다) 알파도 없다. 이 스크립트가
그것을 출시 도트로 만든다.

1. 스프라이트는 마젠타(#FF00FF) 바탕을 **마젠타 우세도**로 키잉한다. 생성기는
   바탕에 저주파 얼룩을 넣으므로 한 색과의 거리로는 못 지운다. 몸 안쪽의
   마젠타도 지운다 — 고리 사이로 바탕이 비치는 진짜 구멍이다.
2. 목표 키에 맞는 **정수 배수로 한 번에 면적 평균**을 낸다. 격자를 추정해
   표본화하는 방식은 버렸다 — 같은 색 연속 길이의 분포가 봉우리 없이 단조롭게
   떨어져서, 어느 블록을 골라도 절반은 틀렸다.
3. 미디언컷으로 색을 줄여 경계를 다시 단단하게 만든다. 디더는 쓰지 않는다.
   빈도순 팔레트도 쓰지 않는다 — 외곽선과 눈처럼 화소는 적어도 그림을 결정하는
   색이 탈락해 단색 실루엣이 됐다.
4. 급별 목표 키가 있다. 무대는 정수 배율 하나로 그리므로 여기서 키를 맞춰야
   화면에서 엉킴·큰 엉킴·수호짐승·아군의 크기가 층이 진다. 결과 키는 정수
   배수 때문에 목표와 조금 다를 수 있고, 그 크기는 manifest가 앱에 알린다.

출력은 `app/assets/adventure/pixel/`와 그 manifest, 그리고 앱이 크기를 읽는
`expedition_pixel_assets.g.dart`다. 원본은 `design-system/concepts/pixel-battle-v1/
sources/`에 두고 앱은 구운 것만 읽는다. 같은 원본이면 결과도 같다.

사용법:
    python build_pixel_battle_assets.py            # 전부 굽고 manifest 갱신
    python build_pixel_battle_assets.py --check    # 구운 것이 원본과 맞는지 대조
    python build_pixel_battle_assets.py --contact  # 검수용 콘택트 시트만
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from collections import Counter, deque
from io import BytesIO
from pathlib import Path

try:
    from PIL import Image, ImageChops, ImageOps
except ImportError:  # pragma: no cover
    print("Pillow가 필요합니다: pip install Pillow")
    raise SystemExit(1)

ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "design-system" / "concepts" / "pixel-battle-v1" / "sources"
RUNTIME_DIR = ROOT / "app" / "assets" / "adventure" / "pixel"
MANIFEST_PATH = RUNTIME_DIR / "manifest.json"
DART_PATH = (
    ROOT
    / "app"
    / "lib"
    / "features"
    / "expedition"
    / "presentation"
    / "expedition_pixel_assets.g.dart"
)
CONTACT_DIR = ROOT / "design-system" / "concepts" / "pixel-battle-v1"

#: 급별 목표 키(도트). 무대는 이 값 × 정수 배율(폰에서 2)로 그린다.
#: 생성기가 그린 도트(대략 110~130도트 키)의 절반 언저리라 세부가 살아남는다.
TARGET_HEIGHT = {
    "tangles": 56,
    "tangles_elite": 72,
    # 96으로 구웠더니 폰(390px)에서 2배 배율로 화면 폭의 4분의 3을 차지해
    # 예고판을 덮었다. 큰 엉킴과 아군보다는 크되 무대를 넘지 않는 값이다.
    "keepers": 76,
    "actors": 58,
}
ELITE_TANGLES = {
    "shelf_snarl",
    "bell_knot_swirl",
    "backwound_clockspring",
    "matted_observatory",
}
#: 오른쪽을 보라고 했는데 왼쪽을 보고 나온 아군. 무대에서 적은 오른쪽에 있으니
#: 굽는 단계에서 뒤집는다. 어느 쪽인지는 `--contact` 시트로 눈으로 확정했다.
FLIP_ACTORS = {
    "aloof-pot",
    "gal-pot",
    "handsome-pot",
    "marten-pot",
    "nurse-pot",
    "restorer-pot",
    "student-pot",
    "tsundere-pot",
    "zombie-pot",
}
#: 배경 native 상한. 이 안에 들어오는 정수 배수로 줄인다. 세로 256×384는 폰
#: 무대(390×600)를 2배로 덮고, 가로 384×256은 넓은 무대를 2~3배로 덮는다.
#: 장면·배너(`scene`)는 무대가 아니라 카드 안의 그림이라 한 단계 촘촘하게
#: (1536/3 = 512) 굽는다. 폰 폭에서 1배로 덮여 구도가 살아남는다.
BACKDROP_MAX = {
    "portrait": (256, 384),
    "landscape": (384, 256),
    "scene": (512, 342),
}
BACKDROP_COLORS = 40
SPRITE_COLORS = 24


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


# ── 키잉 ──────────────────────────────────────────────────────────


def key_magenta(image: Image.Image) -> Image.Image:
    """마젠타 우세도로 바탕을 지운다. 알파는 0/255 둘뿐이다."""
    image = image.convert("RGBA")
    red, green, blue, _ = image.split()
    score = ImageChops.subtract(ImageChops.darker(red, blue), green)
    alpha = score.point(lambda v: 0 if v >= 84 else 255)
    result = image.copy()
    result.putalpha(alpha)
    return result


def _drop_small_islands(image: Image.Image, min_pixels: int) -> Image.Image:
    """본체와 떨어진 작은 조각을 지운다. 생성기가 흘린 부스러기다."""
    width, height = image.size
    pixels = image.load()
    seen = [[False] * width for _ in range(height)]
    components: list[list[tuple[int, int]]] = []
    for sy in range(height):
        for sx in range(width):
            if seen[sy][sx] or pixels[sx, sy][3] == 0:
                continue
            component = []
            queue = deque([(sx, sy)])
            seen[sy][sx] = True
            while queue:
                x, y = queue.popleft()
                component.append((x, y))
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if (
                        0 <= nx < width
                        and 0 <= ny < height
                        and not seen[ny][nx]
                        and pixels[nx, ny][3] != 0
                    ):
                        seen[ny][nx] = True
                        queue.append((nx, ny))
            components.append(component)
    if not components:
        return image
    largest = max(len(c) for c in components)
    for component in components:
        if len(component) < min_pixels and len(component) < largest:
            for x, y in component:
                pixels[x, y] = (0, 0, 0, 0)
    return image


def _crop_alpha(image: Image.Image, pad: int) -> Image.Image:
    box = image.getchannel("A").point(lambda v: 255 if v > 0 else 0).getbbox()
    if box is None:
        raise SystemExit("키잉 뒤 아무것도 남지 않았습니다")
    left, top, right, bottom = box
    return image.crop(
        (
            max(0, left - pad),
            max(0, top - pad),
            min(image.width, right + pad),
            min(image.height, bottom + pad),
        )
    )


# ── 축소와 양자화 ─────────────────────────────────────────────────


def _downsample(image: Image.Image, factor: int) -> Image.Image:
    """정수 배수로 면적 평균 축소. 알파를 곱해 줄이고 문턱으로 되돌린다.

    알파를 곱하지 않고 줄이면 투명한 자리의 검정이 가장자리로 번져 후광이 생긴다.
    """
    width = max(1, image.width // factor)
    height = max(1, image.height // factor)
    r, g, b, a = image.split()
    pre = Image.merge(
        "RGBA",
        (ImageChops.multiply(r, a), ImageChops.multiply(g, a), ImageChops.multiply(b, a), a),
    )
    small = pre.crop((0, 0, width * factor, height * factor)).resize(
        (width, height), Image.Resampling.BOX
    )
    pixels = small.load()
    for y in range(height):
        for x in range(width):
            rr, gg, bb, aa = pixels[x, y]
            if aa < 128:
                pixels[x, y] = (0, 0, 0, 0)
            else:
                pixels[x, y] = (
                    min(255, rr * 255 // aa),
                    min(255, gg * 255 // aa),
                    min(255, bb * 255 // aa),
                    255,
                )
    return small


def quantize(image: Image.Image, colors: int) -> Image.Image:
    """디더 없이 색을 줄인다. 알파는 따로 들고 있다가 되돌린다."""
    image = image.convert("RGBA")
    alpha = image.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
    rgb = image.convert("RGB")
    # 투명한 자리의 색은 팔레트를 오염시키므로 가장 흔한 불투명 색으로 채운다.
    opaque = [
        rgb.getpixel((x, y))
        for y in range(image.height)
        for x in range(image.width)
        if alpha.getpixel((x, y))
    ]
    if opaque:
        fill = Counter(opaque).most_common(1)[0][0]
        filler = Image.new("RGB", image.size, fill)
        rgb = Image.composite(rgb, filler, alpha)
    palette = rgb.quantize(
        colors=colors,
        method=Image.Quantize.MEDIANCUT,
        dither=Image.Dither.NONE,
    )
    out = palette.convert("RGBA")
    out.putalpha(alpha)
    pixels = out.load()
    for y in range(out.height):
        for x in range(out.width):
            if pixels[x, y][3] == 0:
                pixels[x, y] = (0, 0, 0, 0)
    return out


# ── 급별 굽기 ─────────────────────────────────────────────────────


def build_sprite(source: Path, kind: str) -> tuple[Image.Image, dict]:
    with Image.open(source) as raw:
        image = raw.convert("RGBA")
    keyed = _crop_alpha(key_magenta(image), pad=0)
    target = TARGET_HEIGHT[
        "tangles_elite" if kind == "tangles" and source.stem in ELITE_TANGLES else kind
    ]
    factor = max(1, round(keyed.height / target))
    # 여백을 배수에 맞춰 한 칸 두른다. 그래야 축소 뒤 가장자리 도트가 잘리지 않는다.
    padded = Image.new("RGBA", (keyed.width + factor * 2, keyed.height + factor * 2))
    padded.alpha_composite(keyed, (factor, factor))
    native = _downsample(padded, factor)
    native = _drop_small_islands(native, min_pixels=max(4, native.width * native.height // 400))
    native = _crop_alpha(native, pad=1)
    final = quantize(native, SPRITE_COLORS)
    flipped = kind == "actors" and source.stem in FLIP_ACTORS
    if flipped:
        final = ImageOps.mirror(final)
    return final, {
        "factor": factor,
        "source_size": [image.width, image.height],
        "flipped": flipped,
    }


def build_backdrop(source: Path, orientation: str) -> tuple[Image.Image, dict]:
    with Image.open(source) as raw:
        image = raw.convert("RGBA")
    max_w, max_h = BACKDROP_MAX[orientation]
    factor = max(1, math.ceil(max(image.width / max_w, image.height / max_h)))
    native = _downsample(image, factor)
    final = quantize(native, BACKDROP_COLORS)
    return final, {
        "factor": factor,
        "source_size": [image.width, image.height],
        "flipped": False,
    }


def _iter_sources() -> list[tuple[str, Path]]:
    found: list[tuple[str, Path]] = []
    for kind in ("backdrops", "scenes", "banners", "tangles", "keepers", "actors"):
        directory = SOURCE_DIR / kind
        if not directory.exists():
            continue
        for path in sorted(directory.glob("*.png")):
            found.append((kind, path))
    return found


def _png_bytes(image: Image.Image) -> bytes:
    buffer = BytesIO()
    image.save(buffer, "PNG", optimize=True)
    return buffer.getvalue()


def build_all(check: bool) -> int:
    entries: dict[str, dict] = {}
    failures = 0
    for kind, source in _iter_sources():
        if kind == "backdrops":
            orientation = "portrait" if source.stem.endswith("-portrait") else "landscape"
            image, info = build_backdrop(source, orientation)
        elif kind in ("scenes", "banners"):
            image, info = build_backdrop(source, "scene")
        else:
            image, info = build_sprite(source, kind)
        data = _png_bytes(image)
        relative = f"assets/adventure/pixel/{kind}/{source.name}"
        target = RUNTIME_DIR / kind / source.name
        entry = {
            "asset": relative,
            "kind": kind,
            "width": image.width,
            "height": image.height,
            "sha256": _sha256(data),
            "source": str(source.relative_to(ROOT)).replace("\\", "/"),
            "source_sha256": _sha256(source.read_bytes()),
            **info,
        }
        entries[relative] = entry
        if check:
            if not target.exists() or _sha256(target.read_bytes()) != entry["sha256"]:
                print(f"MISMATCH {relative}")
                failures += 1
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        print(
            f"{relative}: {image.width}x{image.height} "
            f"(1/{info['factor']} of {info['source_size'][0]}x{info['source_size'][1]}"
            f"{', flipped' if info['flipped'] else ''})"
        )
    manifest = {"version": 1, "assets": entries}
    if check:
        if not MANIFEST_PATH.exists():
            print("MISSING manifest")
            return 1
        recorded = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        if recorded != manifest:
            print("MISMATCH manifest")
            failures += 1
        if DART_PATH.read_text(encoding="utf-8") != _dart_source(manifest):
            print("MISMATCH expedition_pixel_assets.g.dart")
            failures += 1
        print("OK" if failures == 0 else f"{failures} mismatch(es)")
        return 1 if failures else 0
    MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST_PATH.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    DART_PATH.write_text(_dart_source(manifest), encoding="utf-8")
    print(f"{len(entries)} assets → {RUNTIME_DIR}")
    return 0


def _dart_source(manifest: dict) -> str:
    lines = [
        "// GENERATED — design-system/scripts/build_pixel_battle_assets.py가 만든다.",
        "// 손으로 고치지 말 것. 원본이 바뀌면 스크립트를 다시 돌린다.",
        "",
        "import 'dart:ui' show Size;",
        "",
        "/// 구운 도트 자산의 native 크기. 무대는 이 값에 정수 배율을 곱해 그린다.",
        "const expeditionPixelAssetSizes = <String, Size>{",
    ]
    for asset, entry in sorted(manifest["assets"].items()):
        lines.append(f"  '{asset}': Size({entry['width']}, {entry['height']}),")
    lines.append("};")
    lines.append("")
    return "\n".join(lines)


def contact_sheets() -> None:
    """검수용. 급별로 구운 도트를 키워 한 장에 늘어놓는다."""
    for kind in ("backdrops", "scenes", "banners", "tangles", "keepers", "actors"):
        directory = RUNTIME_DIR / kind
        if not directory.exists():
            continue
        images = [Image.open(p).convert("RGBA") for p in sorted(directory.glob("*.png"))]
        if not images:
            continue
        wide = kind in ("backdrops", "scenes", "banners")
        zoom = 1 if kind in ("scenes", "banners") else 2 if wide else 4
        cell_w = max(i.width for i in images) * zoom + 12
        cell_h = max(i.height for i in images) * zoom + 12
        columns = 4 if wide else 6
        rows = (len(images) + columns - 1) // columns
        sheet = Image.new("RGBA", (cell_w * columns, cell_h * rows), (40, 36, 32, 255))
        for index, image in enumerate(images):
            big = image.resize((image.width * zoom, image.height * zoom), Image.Resampling.NEAREST)
            x = (index % columns) * cell_w + 6
            y = (index // columns) * cell_h + cell_h - 6 - big.height
            sheet.alpha_composite(big, (x, y))
        out = CONTACT_DIR / f"contact-{kind}.png"
        sheet.save(out, "PNG", optimize=True)
        print(out)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--contact", action="store_true")
    args = parser.parse_args()
    if args.contact:
        contact_sheets()
        return 0
    return build_all(check=args.check)


if __name__ == "__main__":
    sys.exit(main())
