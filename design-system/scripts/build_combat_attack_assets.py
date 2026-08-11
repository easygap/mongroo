#!/usr/bin/env python3
"""검수한 공격 포즈를 고정 캔버스 런타임 프레임으로 변환한다.

화면에 보이는 공격 본체는 포즈별로 검수된 원본 이미지 하나를 사용한다.
이 스크립트는 크로마 키 제거, 캔버스와 중심점 정규화, 런타임 WebP 내보내기,
QA 증거 생성만 담당한다. 공격 본체와 이동 경로, 접촉 불꽃, 충돌 및 회복 동작을
코드로 새로 그리지 않는다.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from dataclasses import dataclass
from pathlib import Path

try:
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter
except ImportError as exc:  # pragma: no cover - dependency failure is actionable.
    raise SystemExit("Pillow and NumPy are required to build combat attack assets.") from exc


VFX_V2_ROOT = Path("design-system/concepts/adventure-combat-vfx-v2")
VFX_V3_ROOT = Path("design-system/concepts/adventure-combat-vfx-v3")
VFX_V4_ROOT = Path("design-system/concepts/adventure-combat-vfx-v4")
VFX_V5_ROOT = Path("design-system/concepts/adventure-combat-vfx-v5")
VFX_V6_ROOT = Path("design-system/concepts/adventure-combat-vfx-v6")
RUNTIME_ROOT = Path("app/assets/adventure/effects")
RUNTIME_SIZE = (576, 288)
QA_CELL_SIZE = (288, 144)
CHROMA_TRANSPARENT_SCORE = 92
CHROMA_FOREGROUND_SCORE = 34


@dataclass(frozen=True)
class EffectSpec:
    effect_key: str
    runtime_directory: str
    source_directory: str
    concept_root: Path
    frame_sources: tuple[str, ...]
    frame_phases: tuple[str, ...]
    frame_durations_ms: tuple[int, ...]
    origin: str
    target: str
    release_frame: int
    travel_frames: tuple[int, ...]
    contact_frames: tuple[int, ...]
    reaction_frame: int
    recovery_frames: tuple[int, ...]
    origin_edge: str | None
    origin_tolerance_px: int
    min_coverage: float
    max_coverage: float
    align_right_edge_px: int | None = None
    preprocessed_alpha: bool = False
    fit_full_source: bool = False
    validate_magenta_residue: bool = True
    frame_center_x: tuple[int, ...] | None = None

    @property
    def chroma_root(self) -> Path:
        return self.concept_root / "sources" / self.source_directory

    @property
    def alpha_root(self) -> Path:
        return self.concept_root / "alpha" / self.source_directory

    @property
    def output_root(self) -> Path:
        return RUNTIME_ROOT / self.runtime_directory


EFFECT_SPECS = {
    "care_vines": EffectSpec(
        effect_key="care_vines",
        runtime_directory="care-vines-v2",
        source_directory="care-vines",
        concept_root=VFX_V2_ROOT,
        frame_sources=(
            "pose-00-anticipation.png",
            "pose-00a-uncoil.png",
            "pose-01-release.png",
            "pose-01a-extension.png",
            "pose-02-travel.png",
            "pose-03-contact.png",
            "pose-03a-entangle.png",
            "pose-04-impact.png",
            "pose-04a-recoil.png",
            "pose-05-recovery.png",
        ),
        frame_phases=(
            "anticipation",
            "anticipation",
            "release",
            "travel",
            "travel",
            "contact",
            "contact",
            "reaction",
            "recovery",
            "recovery",
        ),
        frame_durations_ms=(90, 70, 70, 65, 65, 70, 75, 105, 80, 110),
        origin="hand_r",
        target="guardian_center",
        release_frame=2,
        travel_frames=(3, 4),
        contact_frames=(5, 6),
        reaction_frame=7,
        recovery_frames=(8, 9),
        origin_edge="left",
        origin_tolerance_px=12,
        min_coverage=0.008,
        max_coverage=0.38,
    ),
    "ledger_claw": EffectSpec(
        effect_key="ledger_claw",
        runtime_directory="ledger-claw-v2",
        source_directory="ledger-claw",
        concept_root=VFX_V2_ROOT,
        frame_sources=(
            "pose-00-anticipation.png",
            "pose-01-release.png",
            "pose-02-uncoil.png",
            "pose-03-travel.png",
            "pose-04-contact.png",
            "pose-05-impact.png",
            "pose-06-recoil.png",
            "pose-07-retract.png",
            "pose-08-fold.png",
            "pose-09-recovery.png",
        ),
        frame_phases=(
            "anticipation",
            "release",
            "travel",
            "travel",
            "contact",
            "reaction",
            "reaction",
            "recovery",
            "recovery",
            "recovery",
        ),
        frame_durations_ms=(100, 75, 65, 65, 70, 95, 75, 70, 80, 105),
        origin="guardian_foreleg_r",
        target="front_actor",
        release_frame=1,
        travel_frames=(2, 3),
        contact_frames=(4, 5),
        reaction_frame=6,
        recovery_frames=(7, 8, 9),
        origin_edge="right",
        origin_tolerance_px=2,
        min_coverage=0.008,
        max_coverage=0.55,
        align_right_edge_px=556,
    ),
    "venom_seam": EffectSpec(
        effect_key="venom_seam",
        runtime_directory="venom-seam-v1",
        source_directory="venom-seam",
        concept_root=VFX_V3_ROOT,
        frame_sources=(
            "pose-00-anticipation.png",
            "pose-01-release.png",
            "pose-02-travel.png",
            "pose-03-precontact.png",
            "pose-04-contact.png",
            "pose-05-reaction.png",
            "pose-06-recovery.png",
        ),
        frame_phases=(
            "anticipation",
            "release",
            "travel",
            "travel",
            "contact",
            "reaction",
            "recovery",
        ),
        frame_durations_ms=(90, 70, 65, 65, 85, 105, 125),
        origin="actor_hand_r",
        target="guardian_center",
        release_frame=1,
        travel_frames=(2, 3),
        contact_frames=(4,),
        reaction_frame=5,
        recovery_frames=(6,),
        origin_edge=None,
        origin_tolerance_px=0,
        min_coverage=0.004,
        max_coverage=0.42,
        preprocessed_alpha=True,
        fit_full_source=True,
        validate_magenta_residue=False,
        frame_center_x=(120, 205, 300, 385, 450, 450, 450),
    ),
    "paper_flurry": EffectSpec(
        effect_key="paper_flurry",
        runtime_directory="paper-flurry-v1",
        source_directory="paper-flurry",
        concept_root=VFX_V4_ROOT,
        frame_sources=(
            "pose-00-anticipation.png",
            "pose-01-release.png",
            "pose-02-travel.png",
            "pose-03-precontact.png",
            "pose-04-contact.png",
            "pose-05-reaction.png",
            "pose-06-recovery.png",
        ),
        frame_phases=(
            "anticipation",
            "release",
            "travel",
            "travel",
            "contact",
            "reaction",
            "recovery",
        ),
        frame_durations_ms=(100, 85, 75, 75, 90, 115, 140),
        origin="tangle_center",
        target="front_actor",
        release_frame=1,
        travel_frames=(2, 3),
        contact_frames=(4,),
        reaction_frame=5,
        recovery_frames=(6,),
        origin_edge=None,
        origin_tolerance_px=0,
        min_coverage=0.004,
        max_coverage=0.32,
        preprocessed_alpha=True,
        fit_full_source=True,
        validate_magenta_residue=False,
        frame_center_x=(440, 390, 350, 270, 165, 175, 255),
    ),
    "ink_mist": EffectSpec(
        effect_key="ink_mist",
        runtime_directory="ink-mist-v1",
        source_directory="ink-mist",
        concept_root=VFX_V5_ROOT,
        frame_sources=(
            "pose-00-anticipation.png",
            "pose-01-release.png",
            "pose-02-travel.png",
            "pose-03-precontact.png",
            "pose-04-contact.png",
            "pose-05-reaction.png",
            "pose-06-recovery.png",
        ),
        frame_phases=(
            "anticipation",
            "release",
            "travel",
            "travel",
            "contact",
            "reaction",
            "recovery",
        ),
        # channel 모션의 760ms를 프레임 합과 정확히 맞춘다.
        frame_durations_ms=(170, 100, 65, 65, 80, 120, 160),
        origin="tangle_center",
        target="party_all",
        release_frame=1,
        travel_frames=(2, 3),
        contact_frames=(4,),
        reaction_frame=5,
        recovery_frames=(6,),
        origin_edge=None,
        origin_tolerance_px=0,
        min_coverage=0.004,
        max_coverage=0.38,
        preprocessed_alpha=True,
        fit_full_source=True,
        validate_magenta_residue=False,
        frame_center_x=(440, 350, 330, 255, 170, 180, 255),
    ),
    "petal_dart": EffectSpec(
        effect_key="petal_dart",
        runtime_directory="petal-dart-v1",
        source_directory="petal-dart",
        concept_root=VFX_V6_ROOT,
        frame_sources=(
            "pose-00-anticipation.png",
            "pose-01-release.png",
            "pose-02-travel.png",
            "pose-03-precontact.png",
            "pose-04-contact.png",
            "pose-05-reaction.png",
            "pose-06-recovery.png",
        ),
        frame_phases=(
            "anticipation",
            "release",
            "travel",
            "travel",
            "contact",
            "reaction",
            "recovery",
        ),
        # draw 모션의 720ms를 프레임 합과 정확히 맞춘다.
        frame_durations_ms=(140, 100, 75, 75, 70, 100, 160),
        origin="tangle_center",
        target="lowest_actor",
        release_frame=1,
        travel_frames=(2, 3),
        contact_frames=(4,),
        reaction_frame=5,
        recovery_frames=(6,),
        origin_edge=None,
        origin_tolerance_px=0,
        min_coverage=0.004,
        max_coverage=0.40,
        preprocessed_alpha=True,
        fit_full_source=True,
        validate_magenta_residue=False,
        frame_center_x=(440, 400, 335, 260, 165, 180, 255),
    ),
}


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build reviewed per-pose combat attack runtime frames."
    )
    parser.add_argument(
        "--effect",
        choices=("all", *EFFECT_SPECS),
        default="all",
        help="Build one family or every reviewed family.",
    )
    parser.add_argument("--report-only", action="store_true")
    return parser.parse_args()


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def _dilate_edge_colors(
    rgb: np.ndarray,
    core_mask: np.ndarray,
    *,
    iterations: int = 4,
) -> np.ndarray:
    """키 색상 테두리를 막기 위해 전경 RGB를 가장자리 페더 영역에 확장한다."""

    filled = rgb.astype(np.float32).copy()
    known = core_mask.copy()
    height, width = known.shape
    for _ in range(iterations):
        color_sum = np.zeros_like(filled)
        count = np.zeros((height, width), dtype=np.float32)
        for delta_y in (-1, 0, 1):
            for delta_x in (-1, 0, 1):
                if delta_x == 0 and delta_y == 0:
                    continue
                source_y = slice(max(0, -delta_y), min(height, height - delta_y))
                source_x = slice(max(0, -delta_x), min(width, width - delta_x))
                target_y = slice(max(0, delta_y), min(height, height + delta_y))
                target_x = slice(max(0, delta_x), min(width, width + delta_x))
                neighbor_known = known[source_y, source_x]
                color_sum[target_y, target_x] += (
                    filled[source_y, source_x] * neighbor_known[..., None]
                )
                count[target_y, target_x] += neighbor_known
        new_pixels = (~known) & (count > 0)
        if not np.any(new_pixels):
            break
        filled[new_pixels] = color_sum[new_pixels] / count[new_pixels][:, None]
        known |= new_pixels
    return np.clip(filled, 0, 255).astype(np.uint8)


def _extract_chroma(source: Path) -> Image.Image:
    """일정하지 않은 자홍색 키에서 선명한 직선 알파 스프라이트를 추출한다."""

    with Image.open(source) as opened:
        rgb_image = opened.convert("RGB")
    if min(rgb_image.size) < 512:
        raise ValueError(f"{source}: source is unexpectedly small: {rgb_image.size}")

    rgb = np.asarray(rgb_image, dtype=np.int16)
    red = rgb[..., 0]
    green = rgb[..., 1]
    blue = rgb[..., 2]
    chroma_score = np.minimum(red - green, blue - green)
    likely_magenta = (red > 105) & (blue > 88)
    foreground = (~likely_magenta) | (chroma_score <= CHROMA_FOREGROUND_SCORE)
    core = Image.fromarray((foreground * 255).astype(np.uint8)).filter(
        ImageFilter.MinFilter(3)
    )
    core_array = np.asarray(core) > 0
    feather = core.filter(ImageFilter.GaussianBlur(radius=0.75))
    feather_array = np.asarray(feather, dtype=np.uint8)

    hard_background = likely_magenta & (chroma_score >= CHROMA_TRANSPARENT_SCORE)
    feather_array = feather_array.copy()
    feather_array[hard_background & ~core_array] = 0

    edge_rgb = _dilate_edge_colors(rgb.astype(np.uint8), core_array)
    rgba = np.dstack((edge_rgb, feather_array))
    return Image.fromarray(rgba)


def _center_crop_2_to_1(image: Image.Image) -> tuple[Image.Image, list[int]]:
    width, height = image.size
    crop_height = min(height, round(width / 2))
    top = max(0, round((height - crop_height) / 2))
    crop = (0, top, width, top + crop_height)
    return image.crop(crop), list(crop)


def _translate_x(image: Image.Image, delta_x: int) -> Image.Image:
    if delta_x == 0:
        return image
    translated = Image.new("RGBA", image.size)
    translated.alpha_composite(image, (delta_x, 0))
    return translated


def _normalize(
    image: Image.Image,
    spec: EffectSpec,
    frame_index: int,
) -> tuple[Image.Image, list[int]]:
    if spec.fit_full_source:
        padding = 10
        scale = min(
            (RUNTIME_SIZE[0] - padding * 2) / image.width,
            (RUNTIME_SIZE[1] - padding * 2) / image.height,
        )
        resized_size = (
            max(1, round(image.width * scale)),
            max(1, round(image.height * scale)),
        )
        resized = image.resize(resized_size, Image.Resampling.LANCZOS)
        frame = Image.new("RGBA", RUNTIME_SIZE)
        frame.alpha_composite(
            resized,
            (
                (RUNTIME_SIZE[0] - resized.width) // 2,
                (RUNTIME_SIZE[1] - resized.height) // 2,
            ),
        )
        if spec.frame_center_x is not None:
            bbox = frame.getchannel("A").getbbox()
            if bbox is None:
                raise ValueError(f"{spec.effect_key}: empty alpha before frame placement")
            current_center_x = round((bbox[0] + bbox[2]) / 2)
            frame = _translate_x(
                frame,
                spec.frame_center_x[frame_index] - current_center_x,
            )
        return frame, [0, 0, image.width, image.height]
    cropped, crop = _center_crop_2_to_1(image)
    frame = cropped.resize(RUNTIME_SIZE, Image.Resampling.LANCZOS)
    if spec.align_right_edge_px is not None:
        bbox = frame.getchannel("A").getbbox()
        if bbox is None:
            raise ValueError(f"{spec.effect_key}: empty alpha before pivot alignment")
        frame = _translate_x(frame, spec.align_right_edge_px - bbox[2])
    return frame, crop


def _alpha_metrics(
    frame: Image.Image,
    spec: EffectSpec,
    frame_index: int,
    source_size: tuple[int, int],
    source_crop: list[int],
) -> dict[str, object]:
    alpha = frame.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError(f"{spec.effect_key} frame {frame_index}: empty alpha matte")
    if bbox[0] < 4 or bbox[1] < 4 or bbox[2] > frame.width - 4 or bbox[3] > frame.height - 4:
        raise ValueError(
            f"{spec.effect_key} frame {frame_index}: sprite violates 4px padding {bbox}"
        )

    alpha_values = list(
        alpha.get_flattened_data()
        if hasattr(alpha, "get_flattened_data")
        else alpha.getdata()
    )
    visible = sum(value > 16 for value in alpha_values)
    coverage = visible / (frame.width * frame.height)
    if not spec.min_coverage <= coverage <= spec.max_coverage:
        raise ValueError(
            f"{spec.effect_key} frame {frame_index}: suspicious alpha coverage {coverage:.4f}"
        )

    rgba_values = (
        frame.get_flattened_data()
        if hasattr(frame, "get_flattened_data")
        else frame.getdata()
    )
    magenta_residue = sum(
        1
        for red, green, blue, opacity in rgba_values
        if opacity > 32
        and red > 145
        and blue > 120
        and green < 92
        and abs(red - blue) < 105
    )
    if spec.validate_magenta_residue and magenta_residue > max(
        12, round(visible * 0.0003)
    ):
        raise ValueError(
            f"{spec.effect_key} frame {frame_index}: possible chroma residue "
            f"{magenta_residue} pixels"
        )
    return {
        "index": frame_index,
        "phase": spec.frame_phases[frame_index],
        "duration_ms": spec.frame_durations_ms[frame_index],
        "source_size": list(source_size),
        "source_crop": source_crop,
        "bbox": list(bbox),
        "coverage": round(coverage, 4),
        "magenta_residue": magenta_residue,
    }


def _write_alpha_master(image: Image.Image, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination, format="PNG", optimize=True)


def _composite(frame: Image.Image, background: tuple[int, int, int, int]) -> Image.Image:
    canvas = Image.new("RGBA", frame.size, background)
    canvas.alpha_composite(frame)
    return canvas.convert("RGB")


def _build_qa_sheet(frames: list[Image.Image], destination: Path) -> None:
    columns = 5
    rows_per_background = 2
    sheet = Image.new(
        "RGB",
        (columns * QA_CELL_SIZE[0], rows_per_background * 2 * QA_CELL_SIZE[1]),
        (18, 24, 26),
    )
    draw = ImageDraw.Draw(sheet)
    backgrounds = ((18, 24, 26, 255), (244, 239, 218, 255))
    for background_index, background in enumerate(backgrounds):
        for frame_index, frame in enumerate(frames):
            row = background_index * rows_per_background + frame_index // columns
            column = frame_index % columns
            preview = _composite(frame, background).resize(
                QA_CELL_SIZE, Image.Resampling.LANCZOS
            )
            x = column * QA_CELL_SIZE[0]
            y = row * QA_CELL_SIZE[1]
            sheet.paste(preview, (x, y))
            draw.rectangle(
                (x, y, x + QA_CELL_SIZE[0] - 1, y + QA_CELL_SIZE[1] - 1),
                outline=(112, 122, 104),
                width=1,
            )
    destination.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(destination, format="WEBP", quality=92, method=6)


def _build_animation(
    frames: list[Image.Image],
    durations_ms: tuple[int, ...],
    destination: Path,
) -> None:
    previews = [_composite(frame, (18, 24, 26, 255)) for frame in frames]
    previews[0].save(
        destination,
        format="WEBP",
        save_all=True,
        append_images=previews[1:],
        duration=list(durations_ms),
        loop=0,
        quality=92,
        method=6,
    )


def _validate_origin(spec: EffectSpec, reports: list[dict[str, object]]) -> None:
    if spec.origin_edge is None:
        return
    if spec.origin_edge == "left":
        anchors = [int(report["bbox"][0]) for report in reports]
    else:
        anchors = [RUNTIME_SIZE[0] - int(report["bbox"][2]) for report in reports]
    if max(anchors) - min(anchors) > spec.origin_tolerance_px:
        raise ValueError(
            f"{spec.effect_key}: origin drift exceeds {spec.origin_tolerance_px}px: {anchors}"
        )


def _build_effect(spec: EffectSpec, *, report_only: bool) -> dict[str, object]:
    chroma_sources = [
        spec.chroma_root / name.replace(".png", "-chroma.png")
        for name in spec.frame_sources
    ]
    alpha_sources = [spec.alpha_root / name for name in spec.frame_sources]
    required_paths = [
        *chroma_sources,
        *(alpha_sources if spec.preprocessed_alpha else ()),
    ]
    missing = [str(path) for path in required_paths if not path.exists()]
    if missing:
        raise FileNotFoundError("missing reviewed source masters: " + ", ".join(missing))

    if spec.preprocessed_alpha:
        alpha_masters = []
        for source in alpha_sources:
            with Image.open(source) as opened:
                alpha_masters.append(opened.convert("RGBA").copy())
    else:
        alpha_masters = [_extract_chroma(source) for source in chroma_sources]
    if not report_only and not spec.preprocessed_alpha:
        for master, destination in zip(alpha_masters, alpha_sources, strict=True):
            _write_alpha_master(master, destination)

    normalized = [
        _normalize(master, spec, frame_index)
        for frame_index, master in enumerate(alpha_masters)
    ]
    frames = [item[0] for item in normalized]
    source_crops = [item[1] for item in normalized]
    reports = [
        _alpha_metrics(frame, spec, index, master.size, source_crops[index])
        for index, (frame, master) in enumerate(zip(frames, alpha_masters, strict=True))
    ]
    _validate_origin(spec, reports)

    if not report_only:
        spec.output_root.mkdir(parents=True, exist_ok=True)
        for frame_index, frame in enumerate(frames):
            destination = spec.output_root / f"frame-{frame_index:02d}.webp"
            frame.save(destination, format="WEBP", quality=92, method=6)
        qa_root = spec.concept_root / "qa"
        _build_qa_sheet(frames, qa_root / f"{spec.runtime_directory}-light-dark.webp")
        _build_animation(
            frames,
            spec.frame_durations_ms,
            qa_root / f"{spec.runtime_directory}-preview.webp",
        )

    runtime_paths = [
        spec.output_root / f"frame-{frame_index:02d}.webp"
        for frame_index in range(len(frames))
    ]
    return {
        "effect_key": spec.effect_key,
        "runtime_directory": spec.runtime_directory,
        "frame_count": len(frames),
        "frame_size": list(RUNTIME_SIZE),
        "origin": spec.origin,
        "target": spec.target,
        "release_frame": spec.release_frame,
        "travel_frames": list(spec.travel_frames),
        "contact_frames": list(spec.contact_frames),
        "reaction_frame": spec.reaction_frame,
        "recovery_frames": list(spec.recovery_frames),
        "production_candidate": True,
        "production_ready": False,
        "alpha_source": (
            "imagegen_skill_remove_chroma_key"
            if spec.preprocessed_alpha
            else "builder"
        ),
        "source_sha256": {source.name: _sha256(source) for source in chroma_sources},
        "alpha_sha256": {
            source.name: _sha256(source) for source in alpha_sources if source.exists()
        },
        "runtime_sha256": {
            path.name: _sha256(path) for path in runtime_paths if path.exists()
        },
        "frames": reports,
    }


def main() -> int:
    args = _parse_args()
    selected = (
        list(EFFECT_SPECS.values())
        if args.effect == "all"
        else [EFFECT_SPECS[args.effect]]
    )
    try:
        reports = {
            spec.effect_key: _build_effect(spec, report_only=args.report_only)
            for spec in selected
        }
        if not args.report_only:
            for concept_root in {spec.concept_root for spec in selected}:
                manifest_path = concept_root / "manifest.json"
                existing_effects: dict[str, object] = {}
                if manifest_path.exists():
                    try:
                        existing = json.loads(manifest_path.read_text(encoding="utf-8"))
                        existing_effects = dict(existing.get("effects", {}))
                    except (OSError, ValueError, TypeError):
                        existing_effects = {}
                existing_effects.update(
                    {
                        spec.effect_key: reports[spec.effect_key]
                        for spec in selected
                        if spec.concept_root == concept_root
                    }
                )
                manifest = {
                    "version": (
                        6
                        if concept_root == VFX_V6_ROOT
                        else 5
                        if concept_root == VFX_V5_ROOT
                        else 4
                        if concept_root == VFX_V4_ROOT
                        else 3
                        if concept_root == VFX_V2_ROOT
                        else 1
                    ),
                    "source_policy": "one reviewed ImageGen source per visible pose",
                    "code_generated_attack_pixels": False,
                    "effects": existing_effects,
                }
                concept_root.mkdir(parents=True, exist_ok=True)
                manifest_path.write_text(
                    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                    encoding="utf-8",
                )
        mode = "validated" if args.report_only else "built"
        for spec in selected:
            print(f"{spec.runtime_directory} {mode}: {len(spec.frame_sources)} reviewed frames")
        return 0
    except (OSError, ValueError) as exc:
        print(f"combat attack asset build failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
