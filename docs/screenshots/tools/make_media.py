"""캡처 결과를 README 규격으로 굽는다.

  hub.png(390 DPR2)          → docs/screenshots/web/readme-current/adventure-hub.webp (480px 폭)
  battle.png(360x732 DPR2)   → docs/screenshots/mobile/20-integrated-battle.webp (원본 폭 720)
  walk-frames/*.png + walk.json → docs/screenshots/web/readme-current/dungeon-walk.gif (10fps)

움짤은 메모리 규칙대로 **프레임 간 변화량을 재서 연속 이동 구간만** 굽는다.
벽에 막혀 멈춘 구간이 섞이면 걷는 장면이 아니라 멈춘 장면이 된다.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageStat

ROOT = Path(__file__).resolve().parents[3]
CAPTURES = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "tmp" / "pixel-overhaul" / "captures"
README_DIR = ROOT / "docs" / "screenshots" / "web" / "readme-current"
MOBILE_DIR = ROOT / "docs" / "screenshots" / "mobile"


def webp(source: Path, target: Path, width: int | None) -> None:
    image = Image.open(source).convert("RGB")
    if width and image.width != width:
        image = image.resize((width, round(image.height * width / image.width)), Image.Resampling.LANCZOS)
    target.parent.mkdir(parents=True, exist_ok=True)
    image.save(target, "WEBP", quality=88, method=6)
    print(target, image.size)


#: 520×1126 프레임에서 필드 판(글상자·미니맵·발치 안내 포함)만 남기는 상자.
FIELD_CROP = (12, 148, 508, 880)


def gif(frame_dir: Path, timestamps_path: Path, target: Path, fps: int = 8, max_seconds: float = 5.5) -> None:
    frames = sorted(frame_dir.glob("f*.png"))
    timestamps = json.loads(timestamps_path.read_text())
    if not frames:
        print("no frames")
        return
    images = [Image.open(p).convert("RGB").crop(FIELD_CROP) for p in frames]
    # 일정 fps로 리샘플.
    start, end = timestamps[0], timestamps[-1]
    step = 1 / fps
    sampled: list[Image.Image] = []
    cursor = start
    index = 0
    while cursor <= end:
        while index + 1 < len(timestamps) and timestamps[index + 1] <= cursor:
            index += 1
        sampled.append(images[index])
        cursor += step
    # 움직임이 있는 구간만 남긴다. 변화량이 작은 프레임이 연속 6장(0.6초) 넘게
    # 이어지면 멈춘 것으로 보고 자른다.
    kept: list[Image.Image] = []
    still_run = 0
    for previous, current in zip(sampled, sampled[1:]):
        diff = ImageStat.Stat(ImageChops.difference(previous, current).convert("L")).mean[0]
        if diff < .35:
            still_run += 1
            if still_run > 6:
                continue
        else:
            still_run = 0
        kept.append(current)
    if len(kept) < 8:
        kept = sampled
    kept = kept[: round(max_seconds * fps)]
    # 지도 카드 440px 급으로 줄인다.
    scaled = [
        im.resize((440, round(im.height * 440 / im.width)), Image.Resampling.LANCZOS).quantize(
            colors=96, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE
        )
        for im in kept
    ]
    target.parent.mkdir(parents=True, exist_ok=True)
    scaled[0].save(
        target,
        save_all=True,
        append_images=scaled[1:],
        duration=round(1000 / fps),
        loop=0,
        optimize=True,
    )
    print(target, len(scaled), "frames", scaled[0].size)


if __name__ == "__main__":
    if (CAPTURES / "hub.png").exists():
        webp(CAPTURES / "hub.png", README_DIR / "adventure-hub.webp", 480)
    if (CAPTURES / "battle.png").exists():
        webp(CAPTURES / "battle.png", MOBILE_DIR / "20-integrated-battle.webp", None)
    if (CAPTURES / "walk-frames").exists():
        gif(CAPTURES / "walk-frames", CAPTURES / "walk.json", README_DIR / "dungeon-walk.gif")
