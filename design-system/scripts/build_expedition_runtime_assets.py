"""탐험 원화에서 작은 화면용 런타임 파생본을 결정적으로 생성한다."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path

from PIL import Image


@dataclass(frozen=True)
class RuntimeAssetSpec:
    filename: str
    width: int


SCENE_WIDTH = 960
GUARDIAN_WIDTH = 768

ASSETS = (
    RuntimeAssetSpec("expedition-dungeon-gate-v3.webp", SCENE_WIDTH),
    RuntimeAssetSpec("expedition-flooded-cave-v3.webp", SCENE_WIDTH),
    RuntimeAssetSpec("expedition-root-tunnel-v3.webp", SCENE_WIDTH),
    RuntimeAssetSpec("expedition-echo-well-v3.webp", SCENE_WIDTH),
    RuntimeAssetSpec("expedition-treasure-vault-v3.webp", SCENE_WIDTH),
    RuntimeAssetSpec("expedition-monster-den-v3.webp", SCENE_WIDTH),
    RuntimeAssetSpec("expedition-monster-den-battle-v1.webp", SCENE_WIDTH),
    RuntimeAssetSpec("expedition-moon-tower-v3.webp", SCENE_WIDTH),
    RuntimeAssetSpec("expedition-moss-archive-terrain-v3.webp", SCENE_WIDTH),
    RuntimeAssetSpec("ledger-keeper-idle-v1.webp", GUARDIAN_WIDTH),
    RuntimeAssetSpec("ledger-keeper-attack-v1.webp", GUARDIAN_WIDTH),
    RuntimeAssetSpec("ledger-keeper-hit-v1.webp", GUARDIAN_WIDTH),
    RuntimeAssetSpec("ledger-keeper-defeated-v1.webp", GUARDIAN_WIDTH),
)


def _mobile_path(source: Path) -> Path:
    return source.with_name(f"{source.stem}-mobile{source.suffix}")


def build_asset(source: Path, target_width: int) -> Path:
    if not source.is_file():
        raise FileNotFoundError(f"원본 에셋이 없습니다: {source}")

    with Image.open(source) as opened:
        has_alpha = "A" in opened.getbands()
        image = opened.convert("RGBA" if has_alpha else "RGB")
        if image.width < target_width:
            raise ValueError(
                f"{source.name}: 원본 너비 {image.width}px가 "
                f"파생본 {target_width}px보다 작습니다."
            )
        target_height = round(image.height * target_width / image.width)
        resized = image.resize(
            (target_width, target_height),
            Image.Resampling.LANCZOS,
        )

    output = _mobile_path(source)
    resized.save(output, "WEBP", quality=90, method=6, exact=has_alpha)

    with Image.open(output) as verified:
        if verified.width != target_width:
            raise RuntimeError(f"{output.name}: 잘못된 출력 너비 {verified.width}px")
        if has_alpha and "A" not in verified.getbands():
            raise RuntimeError(f"{output.name}: 알파 채널이 사라졌습니다.")
    return output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--asset-root",
        type=Path,
        default=Path("app/assets/adventure"),
    )
    args = parser.parse_args()

    for spec in ASSETS:
        source = args.asset_root / spec.filename
        output = build_asset(source, spec.width)
        print(f"{output}: {spec.width}px, {output.stat().st_size} bytes")


if __name__ == "__main__":
    main()
