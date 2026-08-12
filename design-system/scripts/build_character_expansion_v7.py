#!/usr/bin/env python3
"""신규 캐릭터 3종의 성장·전투 래스터를 앱 규격으로 빌드한다.

검수한 투명 원화를 단계별로 분리하고 6개 감정 성장결을 낮은 농도로 합성한다.
검수한 스킬 시트는 7개 포즈로 나눠 고정 캔버스 프레임과 아이콘을 만든다.
화면에 보이는 캐릭터나 이펙트 본체를 코드로 새로 그리지 않는다.
"""

from __future__ import annotations

import hashlib
import json
from collections import deque
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image, ImageChops, ImageColor, ImageDraw, ImageFilter, ImageFont


CONCEPT_ROOT = Path("design-system/concepts/character-expansion-v7")
ALPHA_ROOT = CONCEPT_ROOT / "alpha"
SKILL_ALPHA_ROOT = CONCEPT_ROOT / "skill-sheets" / "alpha"
SKILL_FRAME_ROOT = CONCEPT_ROOT / "skill-sheets" / "frames"
QA_ROOT = CONCEPT_ROOT / "qa"

PLANT_ROOT = Path("app/assets/plants")
CHARACTER_ROOT = Path("app/assets/characters")
WARDROBE_PREVIEW_ROOT = Path("app/assets/wardrobe/previews")
EFFECT_ROOT = Path("app/assets/adventure/effects")
SKILL_ICON_ROOT = Path("app/assets/adventure/skill-icons")
EFFECT_MANIFEST = EFFECT_ROOT / "manifest.json"

GROWTH_CANVAS = (512, 768)
GROWTH_BASELINE_Y = 718
EFFECT_CANVAS = (576, 288)

FORMS: dict[str, tuple[str, str]] = {
    "sunny": ("#FFD48A", "#FF8FA8"),
    "rainy": ("#8FD8F2", "#B7C8FF"),
    "ember": ("#FF7B61", "#FFC05C"),
    "moonlit": ("#9DA7E8", "#71C6C8"),
    "sparkling": ("#C6A8FF", "#FFE37A"),
    "mosaic": ("#A8C5BE", "#D8C9B7"),
}

LINEAGES: dict[str, dict[str, str]] = {
    "restorer-pot": {
        "name": "에단",
        "outfit_key": "bluegray-restorer-workwear",
        "outfit_name": "블루그레이 복원 워크웨어",
    },
    "marten-pot": {
        "name": "모루",
        "outfit_key": "leaf-trail-harness",
        "outfit_name": "잎길 탐험 하네스",
    },
    "gal-pot": {
        "name": "리아",
        "outfit_key": "coral-lingerie-work",
        "outfit_name": "코랄 란제리 워크 스트리트",
    },
}

SKILLS: dict[str, dict[str, Any]] = {
    "patina-parry": {
        "species": "restorer-pot",
        "family": "restorer-pot.patina-parry",
        "effect_key": "patina_parry",
        "directory": "patina-parry-v1",
        "kel": "mosaic",
        "anchor": "actor_center",
        "durations": (120, 100, 100, 80, 130, 80, 90),
    },
    "golden-seam": {
        "species": "restorer-pot",
        "family": "restorer-pot.golden-seam",
        "effect_key": "golden_seam",
        "directory": "golden-seam-v1",
        "kel": "sunny",
        "anchor": "stage_center",
        "durations": (170, 100, 65, 65, 80, 120, 160),
    },
    "softpaw-rush": {
        "species": "marten-pot",
        "family": "marten-pot.softpaw-rush",
        "effect_key": "softpaw_rush",
        "directory": "softpaw-rush-v1",
        "kel": "moonlit",
        "anchor": "actor_center",
        "durations": (100, 90, 110, 110, 70, 180, 200),
    },
    "den-guardian-roar": {
        "species": "marten-pot",
        "family": "marten-pot.den-guardian-roar",
        "effect_key": "den_guardian_roar",
        "directory": "den-guardian-roar-v1",
        "kel": "sunny",
        "anchor": "stage_center",
        "durations": (170, 100, 65, 65, 80, 120, 160),
    },
    "patchwork-relay": {
        "species": "gal-pot",
        "family": "gal-pot.patchwork-relay",
        "effect_key": "patchwork_relay",
        "directory": "patchwork-relay-v1",
        "kel": "sparkling",
        "anchor": "actor_center",
        "durations": (150, 110, 90, 90, 80, 100, 160),
    },
    "runway-reversal": {
        "species": "gal-pot",
        "family": "gal-pot.runway-reversal",
        "effect_key": "runway_reversal",
        "directory": "runway-reversal-v1",
        "kel": "sparkling",
        "anchor": "stage_center",
        "durations": (170, 100, 65, 65, 80, 120, 160),
    },
}

FRAME_PHASES = (
    "anticipation",
    "release",
    "travel",
    "precontact",
    "contact",
    "reaction",
    "recovery",
)


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def _aggregate_sha256(paths: list[Path]) -> str:
    frame_hashes = "".join(
        hashlib.sha256(path.read_bytes()).hexdigest().upper() for path in paths
    )
    return hashlib.sha256(frame_hashes.encode("ascii")).hexdigest().upper()


def _visible_bbox(image: Image.Image, threshold: int = 16) -> tuple[int, int, int, int]:
    alpha = image.getchannel("A").point(lambda value: 255 if value >= threshold else 0)
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError("투명 원본에 표시할 픽셀이 없습니다.")
    return bbox


def _premultiplied_resize(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    return image.convert("RGBa").resize(size, Image.Resampling.LANCZOS).convert("RGBA")


def _major_component_boxes(image: Image.Image) -> list[tuple[int, int, int, int]]:
    """성장 시트의 네 주 피사체를 연결요소로 찾아 왼쪽부터 돌려준다."""

    mask = np.asarray(image.getchannel("A"), dtype=np.uint8) >= 48
    height, width = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    components: list[tuple[int, tuple[int, int, int, int]]] = []
    for y in range(height):
        for x in range(width):
            if not mask[y, x] or seen[y, x]:
                continue
            queue: deque[tuple[int, int]] = deque([(x, y)])
            seen[y, x] = True
            count = 0
            min_x = max_x = x
            min_y = max_y = y
            while queue:
                current_x, current_y = queue.popleft()
                count += 1
                min_x = min(min_x, current_x)
                max_x = max(max_x, current_x)
                min_y = min(min_y, current_y)
                max_y = max(max_y, current_y)
                for next_x, next_y in (
                    (current_x - 1, current_y),
                    (current_x + 1, current_y),
                    (current_x, current_y - 1),
                    (current_x, current_y + 1),
                ):
                    if (
                        0 <= next_x < width
                        and 0 <= next_y < height
                        and mask[next_y, next_x]
                        and not seen[next_y, next_x]
                    ):
                        seen[next_y, next_x] = True
                        queue.append((next_x, next_y))
            if count >= 1_000:
                components.append((count, (min_x, min_y, max_x + 1, max_y + 1)))
    if len(components) != 4:
        raise ValueError(f"성장 시트의 주 피사체가 4개가 아닙니다: {len(components)}")
    return [box for _, box in sorted(components, key=lambda item: item[1][0])]


def _split_growth_sheet(image: Image.Image) -> list[Image.Image]:
    boxes = _major_component_boxes(image)
    width, height = image.size
    boundaries = [0]
    boundaries.extend(
        round((left_box[2] + right_box[0]) / 2)
        for left_box, right_box in zip(boxes, boxes[1:])
    )
    boundaries.append(width)
    panels: list[Image.Image] = []
    for index in range(4):
        panel = image.crop((boundaries[index], 0, boundaries[index + 1], height))
        bbox = _visible_bbox(panel)
        padding = 10
        crop = (
            max(0, bbox[0] - padding),
            max(0, bbox[1] - padding),
            min(panel.width, bbox[2] + padding),
            min(panel.height, bbox[3] + padding),
        )
        panels.append(panel.crop(crop))
    return panels


def _render_growth(source: Image.Image, *, scale: float) -> Image.Image:
    width = max(1, round(source.width * scale))
    height = max(1, round(source.height * scale))
    if width > 468 or height > 704:
        raise ValueError(f"성장 에셋이 캔버스를 벗어납니다: {width}x{height}")
    resized = _premultiplied_resize(source, (width, height))
    canvas = Image.new("RGBA", GROWTH_CANVAS)
    x = (GROWTH_CANVAS[0] - width) // 2
    y = GROWTH_BASELINE_Y - height
    canvas.alpha_composite(resized, (x, y))
    return canvas


def _emotion_blend(
    source: Image.Image,
    primary_hex: str,
    secondary_hex: str,
) -> Image.Image:
    """피부와 본색을 보존하면서 채도 영역과 외곽에만 감정색을 얹는다."""

    rgba = np.asarray(source.convert("RGBA"), dtype=np.float32)
    rgb = rgba[..., :3]
    saturation = (rgb.max(axis=2, keepdims=True) - rgb.min(axis=2, keepdims=True)) / 255
    weight = 0.025 + saturation * 0.055
    primary = np.array(ImageColor.getrgb(primary_hex), dtype=np.float32)
    blended_rgb = rgb * (1 - weight) + primary * weight
    blended = np.dstack((np.clip(blended_rgb, 0, 255), rgba[..., 3])).astype(np.uint8)
    character = Image.fromarray(blended, "RGBA")

    alpha_image = source.getchannel("A")
    expanded = alpha_image.filter(ImageFilter.MaxFilter(5))
    outline_alpha = ImageChops.subtract(expanded, alpha_image).point(
        lambda value: round(value * 0.34)
    )
    secondary = Image.new("RGBA", source.size, ImageColor.getrgb(secondary_hex) + (0,))
    secondary.putalpha(outline_alpha)
    result = Image.new("RGBA", source.size)
    result.alpha_composite(secondary)
    result.alpha_composite(character)
    result.putalpha(ImageChops.lighter(alpha_image, outline_alpha))
    return result


def _save_lossless_webp(image: Image.Image, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination, "WEBP", lossless=True, method=6)


def _build_growth_lineage(slug: str, meta: dict[str, str]) -> dict[str, Any]:
    growth_path = ALPHA_ROOT / f"{slug}-growth.png"
    full_path = ALPHA_ROOT / f"{slug}-full-bloom.png"
    growth_sheet = Image.open(growth_path).convert("RGBA")
    panels = _split_growth_sheet(growth_sheet)
    common_scale = min(
        448 / max(panel.width for panel in panels),
        704 / max(panel.height for panel in panels),
    )
    stages = {
        "seed": _render_growth(panels[0], scale=common_scale),
        "sprout": _render_growth(panels[1], scale=common_scale),
        "branching": _render_growth(panels[2], scale=common_scale),
        "bloom": _render_growth(panels[3], scale=common_scale),
    }
    full_master = Image.open(full_path).convert("RGBA")
    full_master = full_master.crop(_visible_bbox(full_master))
    full_scale = min(448 / full_master.width, 704 / full_master.height)
    stages["full-bloom"] = _render_growth(full_master, scale=full_scale)

    outputs: list[Path] = []
    for phase, stage in stages.items():
        canonical = PLANT_ROOT / f"{slug}-25d-{phase}.webp"
        _save_lossless_webp(stage, canonical)
        outputs.append(canonical)
        if phase != "seed":
            for form, (primary, secondary) in FORMS.items():
                destination = PLANT_ROOT / f"{slug}-25d-{phase}-{form}.webp"
                _save_lossless_webp(
                    _emotion_blend(stage, primary, secondary), destination
                )
                outputs.append(destination)

    character_path = CHARACTER_ROOT / f"{slug}-v7.webp"
    _save_lossless_webp(stages["full-bloom"], character_path)
    outputs.append(character_path)

    wardrobe_preview = Image.new("RGBA", (512, 512), "#FFF8EA")
    adult = stages["full-bloom"].crop(_visible_bbox(stages["full-bloom"]))
    adult.thumbnail((390, 450), Image.Resampling.LANCZOS)
    wardrobe_preview.alpha_composite(
        adult,
        ((512 - adult.width) // 2, 486 - adult.height),
    )
    draw = ImageDraw.Draw(wardrobe_preview)
    draw.rounded_rectangle((12, 12, 500, 500), 28, outline="#D7C4A8", width=3)
    preview_path = WARDROBE_PREVIEW_ROOT / f"{meta['outfit_key']}.webp"
    preview_path.parent.mkdir(parents=True, exist_ok=True)
    wardrobe_preview.convert("RGB").save(preview_path, "WEBP", quality=92, method=6)
    outputs.append(preview_path)

    _build_growth_preview(slug, stages)
    return {
        "slug": slug,
        "name": meta["name"],
        "outfit_key": meta["outfit_key"],
        "asset_count": len(outputs),
        "source_sha256": {
            growth_path.name: _sha256(growth_path),
            full_path.name: _sha256(full_path),
        },
        "runtime_sha256": {path.name: _sha256(path) for path in outputs},
    }


def _build_growth_preview(slug: str, stages: dict[str, Image.Image]) -> None:
    phases = ("seed", "sprout", "branching", "bloom", "full-bloom")
    cell = (180, 270)
    sheet = Image.new("RGB", (cell[0] * 5 + 80, cell[1] * 6 + 100), "#FFF8EA")
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=17)
    for row, form in enumerate(FORMS):
        draw.text((12, 50 + row * cell[1] + 8), form.upper(), fill="#654C3A", font=font)
        for column, phase in enumerate(phases):
            image = (
                stages[phase]
                if phase == "seed"
                else _emotion_blend(stages[phase], *FORMS[form])
            )
            thumb = image.copy()
            thumb.thumbnail((150, 230), Image.Resampling.LANCZOS)
            x = 80 + column * cell[0] + (cell[0] - thumb.width) // 2
            y = 50 + row * cell[1] + (240 - thumb.height)
            sheet.paste(thumb, (x, y), thumb)
            draw.rectangle(
                (
                    80 + column * cell[0],
                    50 + row * cell[1],
                    80 + (column + 1) * cell[0] - 1,
                    50 + (row + 1) * cell[1] - 1,
                ),
                outline="#E0CEB3",
            )
    for column, phase in enumerate(phases):
        draw.text((92 + column * cell[0], 20), phase.upper(), fill="#654C3A", font=font)
    QA_ROOT.mkdir(parents=True, exist_ok=True)
    sheet.save(QA_ROOT / f"{slug}-growth-preview.webp", "WEBP", quality=92, method=6)


def _split_skill_sheet(sheet: Image.Image) -> list[Image.Image]:
    width, height = sheet.size
    alpha = np.asarray(sheet.getchannel("A"), dtype=np.uint8)
    occupied = (alpha >= 48).sum(axis=0).astype(np.float32)
    kernel_width = max(5, round(width * 0.004))
    if kernel_width % 2 == 0:
        kernel_width += 1
    smoothed = np.convolve(
        occupied,
        np.ones(kernel_width, dtype=np.float32),
        mode="same",
    )

    # 생성 모델이 일곱 포즈의 폭을 완전히 같게 두지는 않는다. 각 균등 경계
    # 주변 7.5% 범위에서 실제 알파가 가장 적은 골짜기를 찾아 본체를 자르지 않는다.
    cuts: list[int] = []
    search_radius = round(width * 0.075)
    minimum_gap = round(width * 0.045)
    for index in range(1, 7):
        expected = round(width * index / 7)
        left = max(cuts[-1] + minimum_gap if cuts else 1, expected - search_radius)
        right = min(width - 1, expected + search_radius)
        cut = min(
            range(left, right + 1),
            key=lambda x: (float(smoothed[x]), abs(x - expected)),
        )
        cuts.append(cut)

    boundaries = [0, *cuts, width]
    panels: list[Image.Image] = []
    for index in range(7):
        left = boundaries[index]
        right = boundaries[index + 1]
        panel = sheet.crop((left, 0, right, height))
        bbox = _visible_bbox(panel)
        padding = 8
        crop = (
            max(0, bbox[0] - padding),
            max(0, bbox[1] - padding),
            min(panel.width, bbox[2] + padding),
            min(panel.height, bbox[3] + padding),
        )
        panels.append(panel.crop(crop))
    return panels


def _effect_frame(source: Image.Image, *, scale: float) -> Image.Image:
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


def _effect_qa(frames: list[Image.Image], destination: Path) -> None:
    cell = (288, 144)
    sheet = Image.new("RGB", (cell[0] * 4, cell[1] * 4), "#12181A")
    draw = ImageDraw.Draw(sheet)
    for background_row, background in enumerate(("#12181A", "#F4EFDA")):
        for index, frame in enumerate(frames):
            canvas = Image.new("RGBA", EFFECT_CANVAS, background)
            canvas.alpha_composite(frame)
            thumb = canvas.convert("RGB").resize(cell, Image.Resampling.LANCZOS)
            x = (index % 4) * cell[0]
            y = (background_row * 2 + index // 4) * cell[1]
            sheet.paste(thumb, (x, y))
            draw.rectangle((x, y, x + cell[0] - 1, y + cell[1] - 1), outline="#71806E")
    destination.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(destination, "WEBP", quality=92, method=6)


def _effect_preview(
    frames: list[Image.Image], durations: tuple[int, ...], destination: Path
) -> None:
    previews = []
    for frame in frames:
        canvas = Image.new("RGBA", EFFECT_CANVAS, "#12181A")
        canvas.alpha_composite(frame)
        previews.append(canvas.convert("RGB"))
    previews[0].save(
        destination,
        "WEBP",
        save_all=True,
        append_images=previews[1:],
        duration=list(durations),
        loop=0,
        quality=92,
        method=6,
    )


def _build_skill(
    name: str, spec: dict[str, Any]
) -> tuple[dict[str, Any], dict[str, Any]]:
    alpha_path = SKILL_ALPHA_ROOT / f"{name}.png"
    source_path = CONCEPT_ROOT / "skill-sheets" / "sources" / f"{name}-chroma.png"
    sheet = Image.open(alpha_path).convert("RGBA")
    panels = _split_skill_sheet(sheet)
    common_scale = min(
        540 / max(panel.width for panel in panels),
        252 / max(panel.height for panel in panels),
    )
    frames = [_effect_frame(panel, scale=common_scale) for panel in panels]

    frame_source_root = SKILL_FRAME_ROOT / name
    runtime_root = EFFECT_ROOT / str(spec["directory"])
    frame_source_root.mkdir(parents=True, exist_ok=True)
    runtime_root.mkdir(parents=True, exist_ok=True)
    runtime_paths: list[Path] = []
    for index, (frame, phase) in enumerate(zip(frames, FRAME_PHASES, strict=True)):
        frame.save(
            frame_source_root / f"pose-{index:02d}-{phase}.png", "PNG", optimize=True
        )
        runtime_path = runtime_root / f"frame-{index:02d}.webp"
        _save_lossless_webp(frame, runtime_path)
        runtime_paths.append(runtime_path)

    qa_root = CONCEPT_ROOT / "skill-sheets" / "qa"
    _effect_qa(frames, qa_root / f"{spec['directory']}-light-dark.webp")
    _effect_preview(
        frames,
        tuple(spec["durations"]),
        qa_root / f"{spec['directory']}-preview.webp",
    )

    contact = frames[4].crop(_visible_bbox(frames[4]))
    contact.thumbnail((224, 224), Image.Resampling.LANCZOS)
    icon = Image.new("RGBA", (256, 256))
    icon.alpha_composite(
        contact, ((256 - contact.width) // 2, (256 - contact.height) // 2)
    )
    icon_path = SKILL_ICON_ROOT / str(spec["species"]) / f"{spec['directory']}.webp"
    _save_lossless_webp(icon, icon_path)

    manifest_entry = {
        "family": spec["family"],
        "effect_keys": [spec["effect_key"]],
        "kel": spec["kel"],
        "directory": spec["directory"],
        "frame_count": 7,
        "frame_size": list(EFFECT_CANVAS),
        "frame_durations_ms": list(spec["durations"]),
        "contact_frame": 4,
        "pivot": [0.5, 0.5],
        "anchor": spec["anchor"],
        "production_ready": True,
        "source_hash": _sha256(source_path),
        "runtime_hash": _aggregate_sha256(runtime_paths),
    }
    concept_entry = {
        "effect_key": spec["effect_key"],
        "source": str(source_path),
        "alpha": str(alpha_path),
        "frames": [str(path) for path in runtime_paths],
        "icon": str(icon_path),
        "source_sha256": _sha256(source_path),
        "runtime_sha256": manifest_entry["runtime_hash"],
        "frame_phases": list(FRAME_PHASES),
        "frame_durations_ms": list(spec["durations"]),
        "production_ready": True,
    }
    return manifest_entry, concept_entry


def _update_effect_manifest(entries: list[dict[str, Any]]) -> None:
    manifest = json.loads(EFFECT_MANIFEST.read_text(encoding="utf-8"))
    families = {entry["family"] for entry in entries}
    effect_keys = {key for entry in entries for key in entry["effect_keys"]}
    manifest["effects"] = [
        entry
        for entry in manifest["effects"]
        if entry["family"] not in families
        and not effect_keys.intersection(entry.get("effect_keys") or [])
    ]
    manifest["effects"].extend(entries)
    EFFECT_MANIFEST.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def _build_overview() -> None:
    sheet = Image.new("RGB", (1536, 820), "#FFF8EA")
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=22)
    for index, (slug, meta) in enumerate(LINEAGES.items()):
        asset = Image.open(CHARACTER_ROOT / f"{slug}-v7.webp").convert("RGBA")
        asset.thumbnail((430, 700), Image.Resampling.LANCZOS)
        x = index * 512 + (512 - asset.width) // 2
        y = 760 - asset.height
        sheet.paste(asset, (x, y), asset)
        draw.text((index * 512 + 24, 24), slug, fill="#594536", font=font)
    draw.line((512, 0, 512, 820), fill="#E0CEB3", width=2)
    draw.line((1024, 0, 1024, 820), fill="#E0CEB3", width=2)
    QA_ROOT.mkdir(parents=True, exist_ok=True)
    sheet.save(
        QA_ROOT / "character-expansion-v7-overview.webp", "WEBP", quality=92, method=6
    )


def _build_style_consistency_preview() -> None:
    """기존 출시 캐릭터와 신규 3종을 같은 축척으로 나란히 검수한다."""

    references = (
        ("EXISTING / BYEOLSOL", CHARACTER_ROOT / "magical-pot-v2.webp"),
        ("EXISTING / BAEKHWA", CHARACTER_ROOT / "nurse-pot-v6.webp"),
        ("EXISTING / MONGLE", CHARACTER_ROOT / "mongle.webp"),
        ("NEW / ETHAN", CHARACTER_ROOT / "restorer-pot-v7.webp"),
        ("NEW / RIA", CHARACTER_ROOT / "gal-pot-v7.webp"),
        ("NEW / MORU", CHARACTER_ROOT / "marten-pot-v7.webp"),
    )
    cell_width = 320
    sheet = Image.new("RGB", (cell_width * 3, 1_260), "#FFF8EA")
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=16)
    for index, (label, path) in enumerate(references):
        row, column = divmod(index, 3)
        asset = Image.open(path).convert("RGBA")
        bbox = _visible_bbox(asset)
        asset = asset.crop(bbox)
        asset.thumbnail((250, 500), Image.Resampling.LANCZOS)
        x = column * cell_width + (cell_width - asset.width) // 2
        y = row * 610 + 560 - asset.height
        sheet.paste(asset, (x, y), asset)
        draw.text(
            (column * cell_width + 20, row * 610 + 18), label, fill="#594536", font=font
        )
        draw.rounded_rectangle(
            (
                column * cell_width + 8,
                row * 610 + 8,
                (column + 1) * cell_width - 8,
                row * 610 + 598,
            ),
            18,
            outline="#D7C4A8",
            width=2,
        )
    QA_ROOT.mkdir(parents=True, exist_ok=True)
    sheet.save(
        QA_ROOT / "character-expansion-v7-style-consistency.webp",
        "WEBP",
        quality=94,
        method=6,
    )


def main() -> None:
    growth_reports = [
        _build_growth_lineage(slug, meta) for slug, meta in LINEAGES.items()
    ]
    effect_entries: list[dict[str, Any]] = []
    concept_effects: dict[str, Any] = {}
    for name, spec in SKILLS.items():
        manifest_entry, concept_entry = _build_skill(name, spec)
        effect_entries.append(manifest_entry)
        concept_effects[name] = concept_entry
    _update_effect_manifest(effect_entries)
    _build_overview()
    _build_style_consistency_preview()

    concept_manifest = {
        "version": 7,
        "source_policy": "one reviewed generated master per character stage sheet and skill strip",
        "code_generated_character_pixels": False,
        "code_generated_effect_pixels": False,
        "style_reference_assets": [
            "app/assets/characters/handsome-pot-v2.webp",
            "app/assets/characters/magical-pot-v2.webp",
            "app/assets/characters/student-pot-v2.webp",
            "app/assets/characters/nurse-pot-v6.webp",
            "app/assets/characters/aloof-pot-v2.webp",
            "design-system/concepts/character-redesign-v6/character-style-identity-v6.webp",
        ],
        "visual_qa": {
            "overview": str(QA_ROOT / "character-expansion-v7-overview.webp"),
            "style_consistency": str(
                QA_ROOT / "character-expansion-v7-style-consistency.webp"
            ),
        },
        "emotion_blend": {
            "forms": list(FORMS),
            "inside_weight_range": [0.025, 0.08],
            "edge_width_px": 2,
        },
        "growth": growth_reports,
        "effects": concept_effects,
    }
    (CONCEPT_ROOT / "manifest.json").write_text(
        json.dumps(concept_manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        f"신규 계보 {len(growth_reports)}종과 전용 VFX {len(effect_entries)}종을 빌드했습니다."
    )


if __name__ == "__main__":
    main()
