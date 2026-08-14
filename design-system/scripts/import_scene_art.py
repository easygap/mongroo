"""생성한 장면 원화를 앱 규격 WebP 두 벌로 들여온다.

ImageGen이 뱉은 PNG/JPG를 그대로 앱에 넣으면 안 된다. 앱은 장면마다 **데스크톱
1600×900과 모바일 960×540 두 벌**을 쓰고(`expeditionMobileSceneWidth = 960`),
이름 규칙이 `expedition-{장면}-{지역}-v1.webp` / `…-v1-mobile.webp`다. 손으로
리사이즈하면 여덟 장 × 두 벌 = 열여섯 번 틀릴 기회가 생긴다.

이 스크립트는 원본 비율이 16:9가 아니어도 **가운데를 기준으로 잘라** 맞춘다.
늘려서 맞추면 화풍이 뭉개지기 때문이다.

사용법:
    python import_scene_art.py <원본> --scene monster_den --region echo_well
    python import_scene_art.py <폴더> --all      # 파일명으로 자동 판별

`--all`은 원본 파일명이 `{장면}__{지역}.png` 형식일 때만 쓴다.
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

# 앱이 실제로 쓰는 두 벌. `expedition_scene.dart`의 값과 같아야 한다.
DESKTOP = (1600, 900)
MOBILE = (960, 540)
QUALITY = 88

# 이 스크립트가 받아들이는 조합. 여기 없는 조합을 넣으면 오타이거나 계획에 없던
# 그림이므로 막는다 — 앱이 안 찾는 파일이 자산 폴더에 쌓이는 것을 막는다.
PLANNED = {
    ("monster_den", "echo_well"),
    ("monster_den", "starlight_seed_vault"),
    ("monster_den", "heartwood_observatory"),
    ("dungeon_gate", "echo_well"),
    ("dungeon_gate", "starlight_seed_vault"),
    ("dungeon_gate", "heartwood_observatory"),
    ("treasure_vault", "starlight_seed_vault"),
    ("moon_tower", "heartwood_observatory"),
    # v2 — 글과 그림이 다른 말을 하던 세 자리.
    ("root_tunnel", "starlight_seed_vault"),
    ("echo_well", "echo_well"),
    ("treasure_vault", "echo_well"),
}

REGION_SLUG = {
    "echo_well": "echo-well",
    "starlight_seed_vault": "starlight-seed-vault",
    "heartwood_observatory": "heartwood-observatory",
}
SCENE_SLUG = {
    "monster_den": "monster-den",
    "dungeon_gate": "dungeon-gate",
    "treasure_vault": "treasure-vault",
    "moon_tower": "moon-tower",
    "root_tunnel": "root-tunnel",
    "echo_well": "echo-well",
}


def _fit(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    """가운데를 기준으로 잘라 16:9로 맞춘 뒤 줄인다.

    늘려서 맞추지 않는다. 손으로 그린 선이 한 축으로만 늘어나면 화풍이 무너진다.
    """

    target_ratio = size[0] / size[1]
    width, height = image.size
    ratio = width / height
    if ratio > target_ratio:
        # 너무 넓다 — 좌우를 자른다.
        new_width = round(height * target_ratio)
        left = (width - new_width) // 2
        image = image.crop((left, 0, left + new_width, height))
    elif ratio < target_ratio:
        # 너무 높다 — 위아래를 자른다.
        new_height = round(width / target_ratio)
        top = (height - new_height) // 2
        image = image.crop((0, top, width, top + new_height))
    return image.resize(size, Image.LANCZOS)


def import_one(source: Path, scene: str, region: str) -> list[Path]:
    if (scene, region) not in PLANNED:
        raise SystemExit(
            f"계획에 없는 조합입니다: {scene}/{region}\n"
            f"허용: {sorted(f'{s}/{r}' for s, r in PLANNED)}"
        )
    image = Image.open(source).convert("RGB")
    if min(image.size) < MOBILE[1]:
        raise SystemExit(
            f"{source.name}: {image.size[0]}×{image.size[1]}은 너무 작습니다. "
            f"최소 {DESKTOP[0]}×{DESKTOP[1]}로 생성하세요"
        )
    stem = f"expedition-{SCENE_SLUG[scene]}-{REGION_SLUG[region]}-v1"
    written = []
    for suffix, size in (("", DESKTOP), ("-mobile", MOBILE)):
        path = OUT_DIR / f"{stem}{suffix}.webp"
        _fit(image, size).save(path, "WEBP", quality=QUALITY, method=6)
        written.append(path)
        print(f"  {path.name}  {size[0]}×{size[1]}  {path.stat().st_size // 1024}KB")
    return written


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="원본 이미지 또는 폴더")
    parser.add_argument("--scene", choices=sorted(SCENE_SLUG))
    parser.add_argument("--region", choices=sorted(REGION_SLUG))
    parser.add_argument("--all", action="store_true", help="폴더를 파일명으로 판별")
    args = parser.parse_args()

    if args.all:
        sources = sorted(
            path
            for path in args.source.iterdir()
            if path.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp"}
        )
        if not sources:
            raise SystemExit(f"{args.source}에 이미지가 없습니다")
        for path in sources:
            if "__" not in path.stem:
                print(f"[건너뜀] {path.name} — `{{장면}}__{{지역}}` 형식이 아닙니다")
                continue
            scene, region = path.stem.split("__", 1)
            print(f"{path.name} → {scene}/{region}")
            import_one(path, scene, region)
        return 0

    if not args.scene or not args.region:
        raise SystemExit("--scene과 --region이 필요합니다 (또는 --all)")
    print(f"{args.source.name} → {args.scene}/{args.region}")
    import_one(args.source, args.scene, args.region)

    print(
        "\n앱에 붙이려면 `expedition_scene.dart`의 "
        "`expeditionRegionSceneAssets`에 한 줄 더하세요:"
    )
    print(
        f"  '{args.region}/{args.scene}': "
        f"'assets/adventure/expedition-{SCENE_SLUG[args.scene]}-"
        f"{REGION_SLUG[args.region]}-v1.webp',"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
