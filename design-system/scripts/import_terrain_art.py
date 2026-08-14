"""생성한 지역 지형 지도를 앱 규격 WebP 두 벌로 들여온다.

장면 배경(`import_scene_art.py`)과 규격이 다르다. 지형은 **캐릭터가 그 위를 걸어
다니는 지도**라 데스크톱 1600×900과 모바일 960×540 두 벌을 쓰고, 이름 규칙도
`expedition-{지역}-terrain-v1.webp`다.

품질을 장면보다 높게 잡는다(95). 픽셀아트라 압축을 세게 걸면 같은 색 덩어리
경계가 뭉개져 자글자글해 보이는데, 그건 원본이 아니라 우리가 만든 잡티다.

사용법:
    python import_terrain_art.py <폴더> --all     # terrain__{지역}.png
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    print("Pillow가 필요합니다: pip install Pillow")
    raise SystemExit(1)

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "app" / "assets" / "adventure"

DESKTOP = (1600, 900)
MOBILE = (960, 540)
# 픽셀아트는 압축에 약하다. 장면(88)보다 높게 잡아 덩어리 경계를 지킨다.
QUALITY = 95

REGION_SLUG = {
    "echo_well": "echo-well",
    "starlight_seed_vault": "starlight-seed-vault",
    "heartwood_observatory": "heartwood-observatory",
}


def _fit(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    """16:9로 맞춘 뒤 줄인다. 축소는 최근접 이웃이 아니라 LANCZOS다.

    픽셀아트를 정수배가 아닌 비율로 줄일 때 최근접 이웃을 쓰면 픽셀이 들쭉날쭉
    사라져 오히려 지저분해진다. 1600→960은 0.6배라 정수배가 아니다.
    """

    target = size[0] / size[1]
    width, height = image.size
    ratio = width / height
    if ratio > target:
        new_width = round(height * target)
        left = (width - new_width) // 2
        image = image.crop((left, 0, left + new_width, height))
    elif ratio < target:
        new_height = round(width / target)
        top = (height - new_height) // 2
        image = image.crop((0, top, width, top + new_height))
    return image.resize(size, Image.LANCZOS)


def import_one(source: Path, region: str) -> None:
    if region not in REGION_SLUG:
        raise SystemExit(
            f"계획에 없는 지역입니다: {region}\n허용: {sorted(REGION_SLUG)}"
        )
    image = Image.open(source).convert("RGB")
    if image.size[0] < DESKTOP[0]:
        raise SystemExit(
            f"{source.name}: {image.size[0]}×{image.size[1]}은 너무 작습니다. "
            f"최소 {DESKTOP[0]}×{DESKTOP[1]}로 생성하세요"
        )
    stem = f"expedition-{REGION_SLUG[region]}-terrain-v1"
    for suffix, size in (("", DESKTOP), ("-mobile", MOBILE)):
        path = OUT_DIR / f"{stem}{suffix}.webp"
        _fit(image, size).save(path, "WEBP", quality=QUALITY, method=6)
        print(f"  {path.name}  {size[0]}×{size[1]}  {path.stat().st_size // 1024}KB")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--region", choices=sorted(REGION_SLUG))
    parser.add_argument("--all", action="store_true")
    args = parser.parse_args()

    if args.all:
        found = 0
        for path in sorted(args.source.iterdir()):
            if not path.stem.startswith("terrain__"):
                continue
            region = path.stem.removeprefix("terrain__")
            print(f"{path.name} → {region}")
            import_one(path, region)
            found += 1
        if not found:
            raise SystemExit(f"{args.source}에 terrain__*.png가 없습니다")
        print("\n`expedition_scene.dart`의 `expeditionRegionTerrain`에 등록하세요.")
        return 0

    if not args.region:
        raise SystemExit("--region이 필요합니다 (또는 --all)")
    print(f"{args.source.name} → {args.region}")
    import_one(args.source, args.region)
    return 0


if __name__ == "__main__":
    sys.exit(main())
