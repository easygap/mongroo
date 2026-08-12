#!/usr/bin/env python3
"""누락된 18개 고유 스킬 시트를 런타임 프레임과 아이콘으로 빌드한다.

Imagegen으로 만든 3행×7열 투명 시트는 원본 그대로 보존한다. 이 스크립트는
행과 열을 안전하게 나누고, 공통 캔버스에 맞춘 뒤 manifest와 검수 시트를 만든다.
화면에 보이는 효과의 형태를 코드로 새로 그리지는 않는다.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont

CONCEPT_ROOT = Path("design-system/concepts/signature-skill-completion-v8")
SOURCE_ROOT = CONCEPT_ROOT / "sources"
ALPHA_ROOT = CONCEPT_ROOT / "alpha"
FRAME_ROOT = CONCEPT_ROOT / "frames"
QA_ROOT = CONCEPT_ROOT / "qa"
EFFECT_ROOT = Path("app/assets/adventure/effects")
ICON_ROOT = Path("app/assets/adventure/skill-icons")
EFFECT_MANIFEST = EFFECT_ROOT / "manifest.json"
EFFECT_CANVAS = (576, 288)
FRAME_PHASES = (
    "anticipation",
    "release",
    "travel",
    "precontact",
    "contact",
    "reaction",
    "recovery",
)

EXISTING_SIGNATURE_KEYS = {
    "baby-pot.care-vines": "sprout_cheer",
    "ninja-pot.venom-seam": "venom_seam",
    "nurse-pot.triage-bloom": "triage_bloom",
    "nurse-pot.white-garden-oath": "white_garden_oath",
    "maestro-pot.golden-downbeat": "golden_downbeat",
    "maestro-pot.silent-coda": "silent_coda",
    "restorer-pot.patina-parry": "patina_parry",
    "restorer-pot.golden-seam": "golden_seam",
    "marten-pot.softpaw-rush": "softpaw_rush",
    "marten-pot.den-guardian-roar": "den_guardian_roar",
    "gal-pot.patchwork-relay": "patchwork_relay",
    "gal-pot.runway-reversal": "runway_reversal",
}


GROUPS: dict[str, tuple[dict[str, Any], ...]] = {
    "support": (
        {
            "code": "root_embrace",
            "species": "baby-pot",
            "family": "baby-pot.root-embrace",
            "kel": "sunny",
            "anchor": "stage_center",
        },
        {
            "code": "heart_spotlight",
            "species": "pretty-pot",
            "family": "pretty-pot.heart-spotlight",
            "kel": "sunny",
            "anchor": "stage_center",
        },
        {
            "code": "ribbon_encore",
            "species": "pretty-pot",
            "family": "pretty-pot.ribbon-encore",
            "kel": "sunny",
            "anchor": "stage_center",
        },
    ),
    "martial": (
        {
            "code": "command_blade",
            "species": "handsome-pot",
            "family": "handsome-pot.command-blade",
            "kel": "mosaic",
            "anchor": "actor_center",
        },
        {
            "code": "command_crescendo",
            "species": "handsome-pot",
            "family": "handsome-pot.command-crescendo",
            "kel": "sparkling",
            "anchor": "stage_center",
        },
        {
            "code": "iron_uppercut",
            "species": "tsundere-pot",
            "family": "tsundere-pot.iron-uppercut",
            "kel": "ember",
            "anchor": "actor_center",
        },
    ),
    "dark": (
        {
            "code": "grave_gravity",
            "species": "zombie-pot",
            "family": "zombie-pot.grave-gravity",
            "kel": "mosaic",
            "anchor": "stage_center",
        },
        {
            "code": "undying_chain",
            "species": "zombie-pot",
            "family": "zombie-pot.undying-chain",
            "kel": "ember",
            "anchor": "stage_center",
        },
        {
            "code": "shadow_execution",
            "species": "ninja-pot",
            "family": "ninja-pot.shadow-execution",
            "kel": "moonlit",
            "anchor": "actor_center",
        },
    ),
    "mystic": (
        {
            "code": "heart_moon_charm",
            "species": "gumiho-pot",
            "family": "gumiho-pot.heart-moon-charm",
            "kel": "sunny",
            "anchor": "stage_center",
        },
        {
            "code": "nine_tail_eclipse",
            "species": "gumiho-pot",
            "family": "gumiho-pot.nine-tail-eclipse",
            "kel": "moonlit",
            "anchor": "stage_center",
        },
        {
            "code": "prism_meteor",
            "species": "magical-pot",
            "family": "magical-pot.prism-meteor",
            "kel": "sparkling",
            "anchor": "stage_center",
        },
    ),
    "arcane": (
        {
            "code": "timefold_comet",
            "species": "magical-pot",
            "family": "magical-pot.timefold-comet",
            "kel": "sparkling",
            "anchor": "stage_center",
        },
        {
            "code": "ink_formula_burst",
            "species": "student-pot",
            "family": "student-pot.ink-formula",
            "kel": "mosaic",
            "anchor": "stage_center",
        },
        {
            "code": "seal_rewrite",
            "species": "student-pot",
            "family": "student-pot.seal-rewrite",
            "kel": "mosaic",
            "anchor": "stage_center",
        },
    ),
    "control": (
        {
            "code": "absolute_zero_read",
            "species": "aloof-pot",
            "family": "aloof-pot.absolute-zero",
            "kel": "rainy",
            "anchor": "stage_center",
        },
        {
            "code": "steel_verdict",
            "species": "aloof-pot",
            "family": "aloof-pot.steel-verdict",
            "kel": "mosaic",
            "anchor": "stage_center",
        },
        {
            "code": "blazing_counter",
            "species": "tsundere-pot",
            "family": "tsundere-pot.blazing-counter",
            "kel": "ember",
            "anchor": "actor_center",
        },
    ),
}


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def _aggregate_sha256(paths: list[Path]) -> str:
    values = "".join(_sha256(path) for path in paths)
    return hashlib.sha256(values.encode("ascii")).hexdigest().upper()


def _visible_bbox(image: Image.Image, threshold: int = 28) -> tuple[int, int, int, int]:
    alpha = image.getchannel("A").point(lambda value: 255 if value >= threshold else 0)
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError("투명 패널에 표시할 픽셀이 없습니다.")
    return bbox


def _premultiplied_resize(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    return image.convert("RGBa").resize(size, Image.Resampling.LANCZOS).convert("RGBA")


def _panel(sheet: Image.Image, row: int, column: int) -> Image.Image:
    width, height = sheet.size
    left = round(width * column / 7)
    right = round(width * (column + 1) / 7)
    top = round(height * row / 3)
    bottom = round(height * (row + 1) / 3)
    panel = sheet.crop((left, top, right, bottom))
    bbox = _visible_bbox(panel)
    padding = 6
    return panel.crop(
        (
            max(0, bbox[0] - padding),
            max(0, bbox[1] - padding),
            min(panel.width, bbox[2] + padding),
            min(panel.height, bbox[3] + padding),
        )
    )


def _frame(source: Image.Image, scale: float) -> Image.Image:
    resized = _premultiplied_resize(
        source,
        (max(1, round(source.width * scale)), max(1, round(source.height * scale))),
    )
    frame = Image.new("RGBA", EFFECT_CANVAS)
    frame.alpha_composite(
        resized,
        (
            (EFFECT_CANVAS[0] - resized.width) // 2,
            (EFFECT_CANVAS[1] - resized.height) // 2,
        ),
    )
    bbox = frame.getchannel("A").getbbox()
    if bbox is None or bbox[0] < 4 or bbox[1] < 4 or bbox[2] > 572 or bbox[3] > 284:
        raise ValueError(f"전투 프레임 여백이 잘못되었습니다: {bbox}")
    return frame


def _save_webp(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "WEBP", lossless=True, method=6)


def _qa(frames: list[Image.Image], path: Path) -> None:
    cell = (288, 144)
    canvas = Image.new("RGB", (cell[0] * 4, cell[1] * 4), "#12181A")
    draw = ImageDraw.Draw(canvas)
    for background_row, background in enumerate(("#12181A", "#F4EFDA")):
        for index, frame in enumerate(frames):
            staged = Image.new("RGBA", EFFECT_CANVAS, background)
            staged.alpha_composite(frame)
            thumb = staged.convert("RGB").resize(cell, Image.Resampling.LANCZOS)
            x = index % 4 * cell[0]
            y = (background_row * 2 + index // 4) * cell[1]
            canvas.paste(thumb, (x, y))
            draw.rectangle((x, y, x + cell[0] - 1, y + cell[1] - 1), outline="#71806E")
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(path, "WEBP", quality=92, method=6)


def _preview(frames: list[Image.Image], durations: tuple[int, ...], path: Path) -> None:
    pages: list[Image.Image] = []
    for frame in frames:
        staged = Image.new("RGBA", EFFECT_CANVAS, "#12181A")
        staged.alpha_composite(frame)
        pages.append(staged.convert("RGB"))
    pages[0].save(
        path,
        "WEBP",
        save_all=True,
        append_images=pages[1:],
        duration=list(durations),
        loop=0,
        quality=92,
        method=6,
    )


def _build_skill(
    group: str,
    row: int,
    spec: dict[str, Any],
    sheet: Image.Image,
) -> tuple[dict[str, Any], dict[str, Any]]:
    panels = [_panel(sheet, row, column) for column in range(7)]
    common_scale = min(
        540 / max(panel.width for panel in panels),
        252 / max(panel.height for panel in panels),
    )
    frames = [_frame(panel, common_scale) for panel in panels]
    slug = str(spec["code"]).replace("_", "-")
    directory = f"{slug}-v1"
    frame_root = FRAME_ROOT / str(spec["code"])
    runtime_root = EFFECT_ROOT / directory
    runtime_paths: list[Path] = []
    for index, (frame, phase) in enumerate(zip(frames, FRAME_PHASES, strict=True)):
        frame_root.mkdir(parents=True, exist_ok=True)
        frame.save(frame_root / f"pose-{index:02d}-{phase}.png", "PNG", optimize=True)
        runtime_path = runtime_root / f"frame-{index:02d}.webp"
        _save_webp(frame, runtime_path)
        runtime_paths.append(runtime_path)

    durations = (120, 90, 95, 75, 135, 100, 145)
    _qa(frames, QA_ROOT / f"{directory}-light-dark.webp")
    _preview(frames, durations, QA_ROOT / f"{directory}-preview.webp")

    contact = frames[4].crop(_visible_bbox(frames[4]))
    contact.thumbnail((224, 224), Image.Resampling.LANCZOS)
    icon = Image.new("RGBA", (256, 256))
    icon.alpha_composite(
        contact, ((256 - contact.width) // 2, (256 - contact.height) // 2)
    )
    icon_path = ICON_ROOT / str(spec["species"]) / f"{slug}-v1.webp"
    _save_webp(icon, icon_path)

    source_path = SOURCE_ROOT / f"{group}-chroma.png"
    alpha_path = ALPHA_ROOT / f"{group}-alpha.png"
    manifest_entry = {
        "family": spec["family"],
        "effect_keys": [spec["code"]],
        "kel": spec["kel"],
        "directory": directory,
        "frame_count": 7,
        "frame_size": list(EFFECT_CANVAS),
        "frame_durations_ms": list(durations),
        "contact_frame": 4,
        "pivot": [0.5, 0.5],
        "anchor": spec["anchor"],
        "production_ready": True,
        "source_hash": _sha256(source_path),
        "runtime_hash": _aggregate_sha256(runtime_paths),
    }
    return manifest_entry, {
        "code": spec["code"],
        "species": spec["species"],
        "family": spec["family"],
        "source": str(source_path),
        "alpha": str(alpha_path),
        "frames": [str(path) for path in runtime_paths],
        "icon": str(icon_path),
        "source_sha256": _sha256(source_path),
        "runtime_sha256": manifest_entry["runtime_hash"],
        "production_ready": True,
    }


def _build_boss_phase() -> tuple[dict[str, Any], dict[str, Any]]:
    source_path = SOURCE_ROOT / "boss-phase-break-chroma.png"
    alpha_path = ALPHA_ROOT / "boss-phase-break-alpha.png"
    sheet = Image.open(alpha_path).convert("RGBA")
    panels = []
    for column in range(7):
        left = round(sheet.width * column / 7)
        right = round(sheet.width * (column + 1) / 7)
        panel = sheet.crop((left, 0, right, sheet.height))
        bbox = _visible_bbox(panel)
        panels.append(
            panel.crop(
                (
                    max(0, bbox[0] - 6),
                    max(0, bbox[1] - 6),
                    min(panel.width, bbox[2] + 6),
                    min(panel.height, bbox[3] + 6),
                )
            )
        )
    common_scale = min(
        540 / max(panel.width for panel in panels),
        252 / max(panel.height for panel in panels),
    )
    frames = [_frame(panel, common_scale) for panel in panels]
    durations = (150, 100, 90, 80, 150, 120, 180)
    directory = "boss-phase-break-v1"
    runtime_paths: list[Path] = []
    for index, (frame, phase) in enumerate(zip(frames, FRAME_PHASES, strict=True)):
        frame_root = FRAME_ROOT / "boss_phase_break"
        frame_root.mkdir(parents=True, exist_ok=True)
        frame.save(frame_root / f"pose-{index:02d}-{phase}.png", "PNG", optimize=True)
        runtime_path = EFFECT_ROOT / directory / f"frame-{index:02d}.webp"
        _save_webp(frame, runtime_path)
        runtime_paths.append(runtime_path)
    _qa(frames, QA_ROOT / f"{directory}-light-dark.webp")
    _preview(frames, durations, QA_ROOT / f"{directory}-preview.webp")
    entry = {
        "family": "guardian.phase-break",
        "effect_keys": ["boss_phase_break"],
        "kel": "mosaic",
        "directory": directory,
        "frame_count": 7,
        "frame_size": list(EFFECT_CANVAS),
        "frame_durations_ms": list(durations),
        "contact_frame": 4,
        "pivot": [0.5, 0.5],
        "anchor": "stage_center",
        "production_ready": True,
        "source_hash": _sha256(source_path),
        "runtime_hash": _aggregate_sha256(runtime_paths),
    }
    return entry, {
        "code": "boss_phase_break",
        "species": "guardian",
        "family": "guardian.phase-break",
        "source": str(source_path),
        "alpha": str(alpha_path),
        "frames": [str(path) for path in runtime_paths],
        "icon": None,
        "source_sha256": _sha256(source_path),
        "runtime_sha256": entry["runtime_hash"],
        "production_ready": True,
    }


def _update_manifest(entries: list[dict[str, Any]]) -> None:
    manifest = json.loads(EFFECT_MANIFEST.read_text(encoding="utf-8"))
    families = {str(entry["family"]) for entry in entries}
    keys = {str(key) for entry in entries for key in entry["effect_keys"]}
    manifest["effects"] = [
        entry
        for entry in manifest["effects"]
        if entry["family"] not in families
        and not keys.intersection(entry.get("effect_keys") or [])
    ]
    manifest["effects"].extend(entries)
    for entry in manifest["effects"]:
        code = EXISTING_SIGNATURE_KEYS.get(str(entry["family"]))
        if code is not None:
            entry["effect_keys"] = [code]
            entry["production_ready"] = True
        if str(entry["family"]).startswith("kel."):
            entry["production_ready"] = True
    EFFECT_MANIFEST.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def _overview(entries: list[dict[str, Any]]) -> None:
    columns = 6
    cell = (288, 180)
    rows = (len(entries) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * cell[0], rows * cell[1]), "#12181A")
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=15)
    for index, entry in enumerate(entries):
        frame = Image.open(entry["frames"][4]).convert("RGBA")
        thumb = Image.new("RGBA", EFFECT_CANVAS, "#12181A")
        thumb.alpha_composite(frame)
        thumb.thumbnail((cell[0] - 12, cell[1] - 30), Image.Resampling.LANCZOS)
        x = index % columns * cell[0]
        y = index // columns * cell[1]
        sheet.paste(thumb.convert("RGB"), (x + (cell[0] - thumb.width) // 2, y + 24))
        draw.text((x + 8, y + 6), str(entry["code"]), fill="#F4EFDA", font=font)
        draw.rectangle((x, y, x + cell[0] - 1, y + cell[1] - 1), outline="#71806E")
    QA_ROOT.mkdir(parents=True, exist_ok=True)
    sheet.save(
        QA_ROOT / "signature-skill-completion-v8-overview.webp",
        "WEBP",
        quality=92,
        method=6,
    )


def main() -> None:
    entries: list[dict[str, Any]] = []
    concepts: list[dict[str, Any]] = []
    for group, specs in GROUPS.items():
        sheet = Image.open(ALPHA_ROOT / f"{group}-alpha.png").convert("RGBA")
        for row, spec in enumerate(specs):
            entry, concept = _build_skill(group, row, spec, sheet)
            entries.append(entry)
            concepts.append(concept)
    boss_entry, boss_concept = _build_boss_phase()
    entries.append(boss_entry)
    concepts.append(boss_concept)
    _update_manifest(entries)
    _overview(concepts)
    manifest = {
        "version": "signature-skill-completion-v8",
        "source": "Imagegen built-in with existing Mood Pot VFX references",
        "frame_phases": list(FRAME_PHASES),
        "skills": concepts,
    }
    (CONCEPT_ROOT / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"built {len(entries) - 1} signature skills and one boss phase effect")


if __name__ == "__main__":
    main()
