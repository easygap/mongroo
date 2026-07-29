"""Build the undressed base, the shared inner layer and outfit layers.

ImageGen sources are kept as six-form chroma sheets.  Wardrobe contract v2
splits a character into three stacked layers that share one canvas:

    base   skin, face, hair and the plant motif only - no garment at all
    inner  one minimal neutral underlayer, always composited over the base
    outfit the purchased garment, its own shoes and accessories

Every layer of one character is cropped, scaled and baselined together, so a
purchased outfit composites without per-frame offsets, and a base that carries
no garment cannot leak through an outfit that covers less than the old baked-in
tank and shorts did.

The builder also verifies the contract.  A base still wearing the v1 tank and
shorts is rejected, outfit sheets have to stay locked to the base pose, and the
inner has to stay inside the coverage envelope documented in the concept README.
Violations are reported per frame with a QA overlay so a bad sheet is visible
instead of silent.
"""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

from build_character_emotion_adults_v2 import FORMS, _empty_runs
from build_emotion_archetype_sprites_v4 import CHARACTERS, STATES
from build_growth_assets import BASELINE_Y, CANVAS
from extract_magenta_sprite import extract


BASE_DIR = "base"
INNER_DIR = "inner"
OUTFITS_DIR = "outfits"

CHARACTER_NAMES = dict(CHARACTERS)

# A child body never gets a bare-torso base.  Its plain bodysuit *is* the base,
# so no separate inner layer applies and the route scale stays smaller.
CHILD_SPECIES = frozenset({"baby-pot"})

# Characters whose base may keep the v1 tank and shorts.
#
# The envelope exists to sit inside the *least* covering outfit a character
# sells.  When every outfit covers neck to ankle, the v1 garment leaks nothing
# and undressing the base buys nothing - so these keep their original sheet.
# The claim is not taken on trust: `garment-exposed` below measures whether the
# outfit really does cover the garment, frame by frame.
#
# Move a character out of this set before selling it anything sleeveless,
# off-shoulder, high-slit or short-hemmed.
COVERED_BASE_SPECIES = frozenset({"magical-pot"})

# Fractions of the figure height, measured from the top of the head.  An adult
# inner has to stay inside this band; see the concept README for how the numbers
# were measured off the v1 sheets.
ENVELOPE = {"adult": (0.24, 0.46)}

# The band used to tell an undressed base from a dressed one.  A chibi child is
# nearly half head, so its torso starts much lower down the figure.
TORSO_BAND = {"adult": (0.22, 0.55), "child": (0.55, 0.95)}

# Measured on the v1 착의형 sheets: the charcoal tank and shorts read 0.54-0.67
# neutral across the adult torso while bare skin reads 0.000.  A contract base
# keeps its minimal cover in a warm skin-adjacent tone, which carries enough
# chroma not to count here, so the limit sits between the two with room for
# shading.  The child floor is far looser because a chibi figure is nearly half
# head and its diary pose pulls both hands into the band, dropping a correct
# bodysuit to 0.20 - but a decorated costume still lands near 0.
ADULT_GARMENT_LIMIT = 0.35
CHILD_BODYSUIT_FLOOR = 0.15

ALPHA_FLOOR = 64
# ImageGen re-frames an edited sheet by a few pixels. Anything inside this share
# of the canvas is repaired against the baseline; anything past it is a fresh
# generation that cannot be trusted to line up.
ALIGN_TOLERANCE = 0.01

# Pose lock.  How much of the outfit lands on the body is the discriminator:
# measured across the v1 sheets, pose-matched outfits keep 0.58-0.83 of their
# pixels on the body while the flat-lay mannequin sheet drops to 0.45.  Coats
# and skirts legitimately spill past the silhouette, so the floor stays
# generous.  The centroid guard only catches gross horizontal displacement,
# which is why it sits well above the 0.11 a correct sheet can reach.
CENTROID_LIMIT = 0.15
ON_BODY_FLOOR = 0.55

# Limb protrusion.  `pose-lock` asks whether the outfit sits on the body; this
# asks the opposite - whether the body pokes out of the outfit.  A sheet whose
# arms and legs are a few degrees off passes the first and fails the second,
# leaving a bare leg drawn beside the trouser.
#
# The amount of leg a design leaves bare is a per-character constant (trousers
# hide all of it, a skirt none), so the comparison is against that character's
# own median rather than an absolute number.  Only the outliers are wrong.
LIMB_BAND = (0.55, 1.0)
LIMB_OUTLIER_MARGIN = 0.10

# Pose variety.  `pose-lock` compares one outfit panel against its own base
# panel, and a full-body garment overlaps a full-body figure enough to pass even
# when the pose is wrong.  This asks a sharper question: do the six panels of
# the sheet differ from each other the way the six base panels do?
#
# A sheet drawn once and recoloured six times has near-identical silhouettes.
# Measured across the v1 sheets, a pose-locked outfit tracks its base to within
# +0.10 self-similarity, while a recoloured lineup runs +0.16 to +0.25 above it.
POSE_VARIETY_MARGIN = 0.13
SILHOUETTE_SIZE = (120, 300)

# Disconnected outfit pieces.  A two-piece outfit, separate shoes and gloves
# are legitimate, so component count or "keep only the largest" is not a valid
# rule here.  Measurements across the current wardrobe put every intended
# piece at 2% or more of the largest garment component; floating ImageGen
# crumbs are all below that share.
OUTFIT_COMPONENT_MIN_RATIO = 0.02

# Seam and antialiasing noise around a covered garment. A real neckline gap or
# a short hem exposes far more than this.
GARMENT_LEAK_LIMIT = 0.05


@dataclass
class Violation:
    species: str
    layer: str
    state: str
    form: str
    rule: str
    detail: str


@dataclass
class BuildReport:
    species: list[str] = field(default_factory=list)
    outfits: dict[str, list[str]] = field(default_factory=dict)
    violations: list[Violation] = field(default_factory=list)
    exposure: dict[str, float] = field(default_factory=dict)
    pending: list[str] = field(default_factory=list)
    limb: dict[str, dict[str, float]] = field(default_factory=dict)
    warnings: list[Violation] = field(default_factory=list)

    def warn(
        self,
        species: str,
        layer: str,
        state: str,
        form: str,
        rule: str,
        detail: str,
    ) -> None:
        self.warnings.append(
            Violation(species, layer, state, form, rule, detail)
        )

    def fail(
        self,
        species: str,
        layer: str,
        state: str,
        form: str,
        rule: str,
        detail: str,
    ) -> None:
        self.violations.append(
            Violation(species, layer, state, form, rule, detail)
        )


def _body_type(slug: str) -> str:
    return "child" if slug in CHILD_SPECIES else "adult"


def _alpha_path(chroma_path: Path) -> Path:
    return chroma_path.with_name(chroma_path.name.replace("-chroma", "-alpha"))


def _load_alpha(chroma_path: Path) -> Image.Image:
    alpha_path = _alpha_path(chroma_path)
    if (
        not alpha_path.exists()
        or alpha_path.stat().st_mtime < chroma_path.stat().st_mtime
    ):
        extract(chroma_path, alpha_path)
    with Image.open(alpha_path) as source:
        return source.convert("RGBA")


def _six_boundaries(sheet: Image.Image) -> list[int]:
    width, _ = sheet.size
    runs = _empty_runs(sheet)
    cuts: list[int] = []
    for index in range(1, 6):
        target = width * index / 6
        candidates = [
            run
            for run in runs
            if abs(((run[0] + run[1]) / 2) - target) <= width * 0.09
        ]
        if candidates:
            left, right = max(
                candidates,
                key=lambda run: (
                    run[1] - run[0],
                    -abs(((run[0] + run[1]) / 2) - target),
                ),
            )
            cuts.append(round((left + right) / 2))
        else:
            cuts.append(round(target))
    boundaries = [0, *cuts, width]
    if boundaries != sorted(boundaries) or len(set(boundaries)) != 7:
        raise ValueError(f"Invalid six-panel boundaries: {boundaries}")
    return boundaries


def _split_with_boundaries(
    sheet: Image.Image,
    boundaries: list[int],
) -> list[Image.Image]:
    return [
        sheet.crop((boundaries[index], 0, boundaries[index + 1], sheet.height))
        for index in range(6)
    ]


def _mask(layer: Image.Image) -> Image.Image:
    return layer.getchannel("A").point(
        lambda value: 255 if value >= ALPHA_FLOOR else 0
    )


def _connected_components(
    mask: Image.Image,
) -> list[list[tuple[int, int]]]:
    """Return four-connected visible components from a binary mask."""

    pixels = mask.load()
    width, height = mask.size
    seen: set[tuple[int, int]] = set()
    components: list[list[tuple[int, int]]] = []
    for y in range(height):
        for x in range(width):
            if not pixels[x, y] or (x, y) in seen:
                continue
            stack = [(x, y)]
            seen.add((x, y))
            component: list[tuple[int, int]] = []
            while stack:
                current_x, current_y = stack.pop()
                component.append((current_x, current_y))
                for neighbor_x, neighbor_y in (
                    (current_x - 1, current_y),
                    (current_x + 1, current_y),
                    (current_x, current_y - 1),
                    (current_x, current_y + 1),
                ):
                    point = (neighbor_x, neighbor_y)
                    if (
                        0 <= neighbor_x < width
                        and 0 <= neighbor_y < height
                        and pixels[neighbor_x, neighbor_y]
                        and point not in seen
                    ):
                        seen.add(point)
                        stack.append(point)
            components.append(component)
    return components


def _remove_edge_fragments(layer: Image.Image) -> Image.Image:
    """Drop neighboring panel pieces that touch a vertical crop edge.

    The largest component is the current figure. Disconnected pieces on either
    vertical edge come from the adjacent route, while interior petals and other
    floating motifs remain part of the current panel.
    """

    components = _connected_components(_mask(layer))
    if len(components) <= 1:
        return layer
    primary = max(components, key=len)
    keep = Image.new("L", layer.size, 0)
    keep_pixels = keep.load()
    for component in components:
        if component is not primary:
            left = min(x for x, _ in component)
            right = max(x for x, _ in component)
            if left <= 1 or right >= layer.width - 2:
                continue
        for x, y in component:
            keep_pixels[x, y] = 255

    # Restore the retained components' antialiased fringe, matching the source
    # sprite builder without changing this panel's canvas or alignment.
    keep = keep.filter(ImageFilter.MaxFilter(7))
    cleaned = layer.copy()
    cleaned.putalpha(ImageChops.multiply(layer.getchannel("A"), keep))
    return cleaned


def _remove_outfit_fragments(layer: Image.Image) -> Image.Image:
    """Remove only pieces smaller than the measured outfit component floor."""

    components = _connected_components(_mask(layer))
    if len(components) <= 1:
        return layer

    primary_area = max(len(component) for component in components)
    keep = Image.new("L", layer.size, 0)
    keep_pixels = keep.load()
    remove = Image.new("L", layer.size, 0)
    remove_pixels = remove.load()
    for component in components:
        if len(component) / primary_area < OUTFIT_COMPONENT_MIN_RATIO:
            for x, y in component:
                remove_pixels[x, y] = 255
            continue
        for x, y in component:
            keep_pixels[x, y] = 255

    # Restore the retained components' antialiased fringe without reconnecting
    # a detached crumb several pixels away.
    keep = keep.filter(ImageFilter.MaxFilter(3))
    cleaned = layer.copy()
    alpha = ImageChops.multiply(layer.getchannel("A"), keep)
    alpha.paste(0, mask=remove)
    cleaned.putalpha(alpha)
    return cleaned


def _count(mask: Image.Image) -> int:
    return mask.histogram()[255]


def _align_to_base(
    layer: Image.Image,
    base_size: tuple[int, int],
) -> Image.Image:
    """Pad or crop a layer sheet onto the base canvas, anchored bottom-center.

    ImageGen returns a canvas a few pixels off even when the same reference
    sheet is edited.  The ground line and the horizontal center are the two
    anchors the app composites against, so both are preserved here.  Anything
    past ALIGN_TOLERANCE is a differently framed generation, not a rounding
    difference, and is rejected by the caller.
    """

    canvas = Image.new("RGBA", base_size, (0, 0, 0, 0))
    offset_x = (base_size[0] - layer.width) // 2
    offset_y = base_size[1] - layer.height
    canvas.alpha_composite(
        layer.crop(
            (
                max(0, -offset_x),
                max(0, -offset_y),
                min(layer.width, layer.width - (offset_x + layer.width - base_size[0])),
                layer.height,
            )
        ),
        (max(0, offset_x), max(0, offset_y)),
    )
    return canvas


def _union_bbox(layers: list[Image.Image]) -> tuple[int, int, int, int]:
    union = _mask(layers[0])
    for layer in layers[1:]:
        union = ImageChops.lighter(union, _mask(layer))
    bbox = union.getbbox()
    if bbox is None:
        raise ValueError("Layer stack contains no visible pixels.")
    left, top, right, bottom = bbox
    width, height = layers[0].size
    return (
        max(0, left - 4),
        max(0, top - 4),
        min(width, right + 4),
        min(height, bottom + 4),
    )


def _route_scale(slug: str, union_sizes: list[tuple[int, int]]) -> float:
    max_width = max(width for width, _ in union_sizes)
    max_height = max(height for _, height in union_sizes)
    if _body_type(slug) == "child":
        return min(390 / max_width, 580 / max_height)
    return min(468 / max_width, 704 / max_height)


def _save_webp_atomic(image: Image.Image, output: Path, **options: object) -> None:
    """Replace a watched app asset only after the encoded file is complete."""

    output.parent.mkdir(parents=True, exist_ok=True)
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            dir=output.parent,
            prefix=f".{output.stem}-",
            suffix=output.suffix,
            delete=False,
        ) as handle:
            temporary = Path(handle.name)
        image.save(temporary, "WEBP", **options)
        os.replace(temporary, output)
        temporary = None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def _render_layer(
    layer: Image.Image,
    *,
    crop_box: tuple[int, int, int, int],
    scale: float,
    output: Path,
    clean_fragments: bool = False,
) -> None:
    cropped = layer.crop(crop_box)
    width = max(1, round(cropped.width * scale))
    height = max(1, round(cropped.height * scale))
    resized = (
        cropped.convert("RGBa")
        .resize((width, height), Image.Resampling.LANCZOS)
        .convert("RGBA")
    )
    if clean_fragments:
        cleaned = _remove_outfit_fragments(resized)
        if cleaned is not resized:
            resized.close()
            resized = cleaned
    canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    x = (CANVAS[0] - width) // 2
    y = BASELINE_Y - height
    if x < 0 or y < 0 or x + width > CANVAS[0] or y + height > CANVAS[1]:
        raise ValueError(f"{output.name} does not fit the 512x768 canvas.")
    canvas.alpha_composite(resized, (x, y))
    with canvas.getchannel("A") as alpha:
        transparent = alpha.point(lambda value: 255 if value == 0 else 0)
    canvas.paste((0, 0, 0, 0), mask=transparent)
    transparent.close()
    try:
        _save_webp_atomic(canvas, output, lossless=True, method=6)
    finally:
        canvas.close()
        resized.close()
        cropped.close()


def discover(source_root: Path) -> tuple[dict[str, list[str]], list[str]]:
    """Split the roster into buildable characters and ones still missing a base.

    Only a few of the ten characters have wardrobe sources, so the builder walks
    what exists.  A character that has outfit sheets but no undressed base is
    reported rather than skipped in silence - it is mid-regeneration, and the
    difference matters to whoever is reading the build output.
    """

    found: dict[str, list[str]] = {}
    pending: list[str] = []
    for slug, _ in CHARACTERS:
        character_root = source_root / slug
        if not character_root.is_dir():
            continue
        base_dir = character_root / BASE_DIR
        outfits_root = character_root / OUTFITS_DIR
        keys = sorted(
            path.name
            for path in outfits_root.glob("*")
            if path.is_dir()
            and all((path / f"{state}-chroma.png").exists() for state in STATES)
        )
        if all((base_dir / f"{state}-chroma.png").exists() for state in STATES):
            found[slug] = keys
        elif (
            keys
            or (character_root / "legacy-body").is_dir()
            # v1 초판이 쓰던 이름. 계약이 바뀌었으니 읽지 않는다.
            or (character_root / "body").is_dir()
        ):
            pending.append(slug)
    return found, pending


def _load_layers(
    source_root: Path,
    slug: str,
    outfit_keys: list[str],
) -> tuple[
    dict[str, dict[str, list[Image.Image]]],
    list[str],
    dict[str, dict[str, list[Image.Image]]],
]:
    """Split every sheet of one character with the boundaries of its base."""

    names = ["base"]
    inner_dir = source_root / slug / INNER_DIR
    has_inner = all(
        (inner_dir / f"{state}-chroma.png").exists() for state in STATES
    )
    if has_inner:
        names.append("inner")
    names.extend(outfit_keys)

    def _sheet_path(name: str, state: str) -> Path:
        root = source_root / slug
        if name == "base":
            return root / BASE_DIR / f"{state}-chroma.png"
        if name == "inner":
            return root / INNER_DIR / f"{state}-chroma.png"
        return root / OUTFITS_DIR / name / f"{state}-chroma.png"

    panels: dict[str, dict[str, list[Image.Image]]] = {}
    source_outfits: dict[str, dict[str, list[Image.Image]]] = {}
    repairs: list[str] = []
    for state in STATES:
        base_sheet = _load_alpha(_sheet_path("base", state))
        boundaries = _six_boundaries(base_sheet)
        panels[state] = {}
        source_outfits[state] = {}
        for name in names:
            sheet = (
                base_sheet
                if name == "base"
                else _load_alpha(_sheet_path(name, state))
            )
            if sheet.size != base_sheet.size:
                drift_x = abs(sheet.width - base_sheet.width) / base_sheet.width
                drift_y = abs(sheet.height - base_sheet.height) / base_sheet.height
                if max(drift_x, drift_y) > ALIGN_TOLERANCE:
                    raise ValueError(
                        f"{slug}/{name}/{state} 캔버스가 {sheet.size} 로 "
                        f"베이스 {base_sheet.size} 와 크게 다르다. 의상 시트는 "
                        "베이스 시트를 image-to-image 로 편집해 같은 캔버스로 "
                        "다시 만들어야 한다."
                    )
                sheet = _align_to_base(sheet, base_sheet.size)
                repairs.append(f"{name}/{state} {drift_x:.3%}x{drift_y:.3%}")
            split = _split_with_boundaries(sheet, boundaries)
            if name not in ("base", "inner"):
                # Pose variety describes the authored sheet. Fragment cleanup
                # is a derived render step and must not change that source
                # validation result.
                source_outfits[state][name] = split
            split = [
                _remove_edge_fragments(panel)
                for panel in split
            ]
            if name not in ("base", "inner"):
                split = [
                    _remove_outfit_fragments(panel)
                    for panel in split
                ]
            panels[state][name] = split
    if repairs:
        print(f"  {slug}: 캔버스 정렬 보정 {len(repairs)}건 - {', '.join(repairs)}")
    return panels, names, source_outfits


def _check_inner_envelope(
    report: BuildReport,
    slug: str,
    state: str,
    form: str,
    base: Image.Image,
    inner: Image.Image,
) -> None:
    envelope = ENVELOPE.get(_body_type(slug))
    if envelope is None:
        # A child body carries its bodysuit on the base, so there is nothing
        # to keep inside an envelope.
        return
    base_box = _mask(base).getbbox()
    inner_box = _mask(inner).getbbox()
    if base_box is None or inner_box is None:
        return
    top, bottom = envelope
    figure_top, figure_height = base_box[1], base_box[3] - base_box[1]
    limit_top = figure_top + figure_height * top
    limit_bottom = figure_top + figure_height * bottom
    if inner_box[1] < limit_top - 1 or inner_box[3] > limit_bottom + 1:
        report.fail(
            slug,
            "inner",
            state,
            form,
            "envelope",
            f"이너 y {(inner_box[1] - figure_top) / figure_height:.3f}"
            f"-{(inner_box[3] - figure_top) / figure_height:.3f}"
            f" 이 허용 범위 {top:.2f}-{bottom:.2f} 를 벗어났다",
        )


def _centroid_x(mask: Image.Image) -> float:
    box = mask.getbbox()
    if box is None:
        return 0.0
    pixels = mask.load()
    total = 0
    weighted = 0
    for x in range(box[0], box[2]):
        column = sum(1 for y in range(box[1], box[3]) if pixels[x, y])
        total += column
        weighted += column * x
    return weighted / max(1, total)


def _neutral_share(panel: Image.Image, band: tuple[float, float]) -> float:
    """Share of torso pixels that read as flat neutral fabric instead of skin.

    Skin keeps a warm red-over-blue bias at every shading step, so its chroma
    stays well above a garment's.  Pure black outlines and white highlights are
    excluded because every layer has them.
    """

    mask = _mask(panel)
    box = mask.getbbox()
    if box is None:
        return 0.0
    figure_height = box[3] - box[1]
    top = int(box[1] + figure_height * band[0])
    bottom = int(box[1] + figure_height * band[1])
    pixels = panel.load()
    visible = mask.load()
    total = 0
    neutral = 0
    for y in range(top, bottom):
        for x in range(box[0], box[2]):
            if not visible[x, y]:
                continue
            red, green, blue, _ = pixels[x, y]
            high, low = max(red, green, blue), min(red, green, blue)
            total += 1
            if high - low <= 30 and 40 <= high <= 225:
                neutral += 1
    return neutral / max(1, total)


def _garment_mask(panel: Image.Image, body_type: str) -> Image.Image:
    """Where the base still carries flat neutral fabric.

    Restricted to the torso band so dark hair and shadow do not register.  On a
    regenerated skin-toned base this comes back empty, which makes the
    `garment-exposed` check below a no-op rather than a false alarm.
    """

    mask = _mask(panel)
    box = mask.getbbox()
    result = Image.new("L", panel.size, 0)
    if box is None:
        return result
    top, bottom = TORSO_BAND[body_type]
    figure_height = box[3] - box[1]
    pixels = panel.load()
    visible = mask.load()
    target = result.load()
    for y in range(
        int(box[1] + figure_height * top),
        int(box[1] + figure_height * bottom),
    ):
        for x in range(box[0], box[2]):
            if not visible[x, y]:
                continue
            red, green, blue, _ = pixels[x, y]
            high, low = max(red, green, blue), min(red, green, blue)
            if high - low <= 30 and 40 <= high <= 225:
                target[x, y] = 255
    return result


def _check_garment_hidden(
    report: BuildReport,
    slug: str,
    outfit: str,
    state: str,
    form: str,
    base: Image.Image,
    layer: Image.Image,
    qa_root: Path,
) -> None:
    """Any garment left on the base has to disappear under the outfit.

    Scoped to COVERED_BASE_SPECIES on purpose.  Colour is the only signal for
    "this is fabric, not body", and it stops working elsewhere: a zombie's
    desaturated skin and a child's plain bodysuit both read as neutral, so
    running this on every character produced far more false alarms than
    findings.  On a declared covered base the fabric really is the charcoal v1
    garment, which the measurement separates cleanly.

    The minimal cover on a regenerated base has no automatic guard - it is
    skin-adjacent by contract, which is exactly what makes it undetectable.
    The composited preview is the check for that.
    """

    if slug not in COVERED_BASE_SPECIES:
        return
    garment = _garment_mask(base, _body_type(slug))
    area = _count(garment)
    if area < 200:
        return
    layer_mask = _mask(layer)
    exposed = _count(ImageChops.subtract(garment, layer_mask))
    ratio = exposed / area
    report.exposure[f"{slug}/{outfit}/{state}/{form}"] = round(ratio, 4)
    if ratio > GARMENT_LEAK_LIMIT:
        report.fail(
            slug,
            outfit,
            state,
            form,
            "garment-exposed",
            f"베이스에 남은 의류의 {ratio:.1%} 가 의상 밖으로 보인다"
            f"(허용 {GARMENT_LEAK_LIMIT:.0%}). 베이스를 무착의형으로 다시 "
            "만들거나, 이 의상의 목선·밑단을 더 덮게 고쳐야 한다",
        )
        _write_overlay(
            base,
            garment,
            layer_mask,
            qa_root / slug / outfit / state / f"{form}.webp",
        )


def _silhouette(panel: Image.Image) -> Image.Image | None:
    """The panel's shape, normalized to a fixed box so poses can be compared."""

    mask = _mask(panel)
    box = mask.getbbox()
    if box is None:
        return None
    return (
        mask.crop(box)
        .resize(SILHOUETTE_SIZE, Image.Resampling.NEAREST)
        .point(lambda value: 255 if value > 127 else 0)
    )


def _self_similarity(panels: list[Image.Image]) -> float | None:
    """Mean pairwise IoU across the six panels of one sheet."""

    shapes = [_silhouette(panel) for panel in panels]
    if any(shape is None for shape in shapes):
        return None
    scores = []
    for first in range(len(shapes)):
        for second in range(first + 1, len(shapes)):
            overlap = _count(ImageChops.multiply(shapes[first], shapes[second]))
            union = _count(ImageChops.lighter(shapes[first], shapes[second]))
            scores.append(overlap / max(1, union))
    return sum(scores) / len(scores)


def _check_pose_variety(
    report: BuildReport,
    slug: str,
    outfit: str,
    state: str,
    base_panels: list[Image.Image],
    layer_panels: list[Image.Image],
) -> None:
    """Reject a sheet whose six panels are one pose recoloured six times."""

    base_score = _self_similarity(base_panels)
    layer_score = _self_similarity(layer_panels)
    if base_score is None or layer_score is None:
        return
    if layer_score > base_score + POSE_VARIETY_MARGIN:
        report.fail(
            slug,
            outfit,
            state,
            "-",
            "pose-variety",
            f"의상 여섯 칸이 서로 {layer_score:.2f} 로 닮았는데 바디는 "
            f"{base_score:.2f} 다. 한 자세를 그려 색만 여섯 번 바꾼 시트이므로 "
            "각 칸을 그 칸의 베이스 자세에 맞춰 다시 만들어야 한다",
        )


def _measure_limb_leak(
    base: Image.Image,
    layer: Image.Image,
) -> float | None:
    """Share of the lower body left outside the outfit."""

    base_mask = _mask(base)
    box = base_mask.getbbox()
    if box is None:
        return None
    figure_height = box[3] - box[1]
    zone = Image.new("L", base.size, 0)
    ImageDraw.Draw(zone).rectangle(
        (
            box[0],
            box[1] + figure_height * LIMB_BAND[0],
            box[2],
            box[1] + figure_height * LIMB_BAND[1],
        ),
        fill=255,
    )
    lower = ImageChops.multiply(base_mask, zone)
    area = _count(lower)
    if area < 200:
        return None
    return _count(ImageChops.subtract(lower, _mask(layer))) / area


def _check_limb_outliers(report: BuildReport, qa_root: Path) -> None:
    """Flag frames whose bare lower body is far above the character's own norm.

    Trousers hide every leg pixel and a skirt hides none, so the absolute
    number says nothing on its own.  Within one character and one outfit the
    number is near-constant, and a frame whose garment was drawn a few degrees
    off spikes well clear of it - that spike is a leg drawn beside the trouser.
    """

    for key, frames in report.limb.items():
        if len(frames) < 6:
            continue
        values = sorted(frames.values())
        median = values[len(values) // 2]
        slug, outfit = key.split("/", 1)
        for frame, value in sorted(frames.items()):
            if value <= median + LIMB_OUTLIER_MARGIN:
                continue
            state, form = frame.split("/", 1)
            report.warn(
                slug,
                outfit,
                state,
                form,
                "limb-exposed",
                f"하반신의 {value:.0%} 가 의상 밖으로 나왔다"
                f"(이 캐릭터 기준값 {median:.0%}). 맨다리나 맨발이 옷 옆에 "
                "따로 그려진 것이므로 이 자세의 의상을 다시 만들어야 한다",
            )


def _check_base_undressed(
    report: BuildReport,
    slug: str,
    state: str,
    form: str,
    base: Image.Image,
) -> None:
    """Reject a 착의형 sheet dropped into base/.

    This is the mistake the contract exists to prevent: the v1 bases baked a
    charcoal tank and shorts into the body, so every outfit that covered less
    than they did leaked grey at the neckline, the armhole and the hem.
    """

    if slug in COVERED_BASE_SPECIES:
        # Declared as fully covered by its own outfits; `garment-exposed`
        # verifies that claim instead.
        return
    body_type = _body_type(slug)
    share = _neutral_share(base, TORSO_BAND[body_type])
    if body_type == "adult":
        if share > ADULT_GARMENT_LIMIT:
            report.fail(
                slug,
                "base",
                state,
                form,
                "base-dressed",
                f"몸통의 {share:.1%} 가 무채색 의류다. 베이스는 맨살이어야 "
                f"한다(허용 {ADULT_GARMENT_LIMIT:.0%}). legacy-body/ 시트를 "
                "그대로 넣지 않았는지 확인한다",
            )
    elif share < CHILD_BODYSUIT_FLOOR:
        report.fail(
            slug,
            "base",
            state,
            form,
            "base-dressed",
            f"플레인 바디수트 비율이 {share:.1%} 로 낮다. 아동 베이스는 무늬 "
            f"없는 단색 바디수트여야 한다(최소 {CHILD_BODYSUIT_FLOOR:.0%})",
        )


def _check_outfit(
    report: BuildReport,
    slug: str,
    outfit: str,
    state: str,
    form: str,
    base: Image.Image,
    inner: Image.Image | None,
    layer: Image.Image,
    qa_root: Path,
) -> None:
    base_mask = _mask(base)
    layer_mask = _mask(layer)
    base_box = base_mask.getbbox()
    layer_box = layer_mask.getbbox()
    if base_box is None or layer_box is None:
        report.fail(slug, outfit, state, form, "empty", "레이어가 비어 있다")
        return

    figure_width = base_box[2] - base_box[0]

    # Pose lock.  A flat-lay mannequin sheet reads fine on its own but sits in a
    # different place than the body, so it can never composite.  Bbox
    # containment would punish coats and skirts instead, which legitimately
    # spill past the silhouette, so compare where the mass actually sits.
    drift = abs(_centroid_x(base_mask) - _centroid_x(layer_mask)) / figure_width
    on_body = _count(ImageChops.multiply(base_mask, layer_mask)) / max(
        1, _count(layer_mask)
    )
    off_body = _count(ImageChops.subtract(layer_mask, base_mask))
    if on_body < ON_BODY_FLOOR or (
        drift > CENTROID_LIMIT and off_body
    ):
        report.fail(
            slug,
            outfit,
            state,
            form,
            "pose-lock",
            f"의상 중심이 바디에서 {drift:.1%} 어긋나고 {on_body:.1%} 만 "
            f"바디 위에 있다(허용 {CENTROID_LIMIT:.0%} / "
            f"최소 {ON_BODY_FLOOR:.0%}). 의상 시트를 바디와 같은 여섯 자세로 "
            "다시 만들어야 한다",
        )

    # Inner exposure.  Reported, not failed: a visible child undershirt is a
    # design choice, a visible adult bandeau usually means the outfit is short.
    if inner is not None:
        inner_mask = _mask(inner)
        inner_area = _count(inner_mask)
        if inner_area:
            exposed = _count(
                ImageChops.subtract(inner_mask, layer_mask)
            )
            ratio = exposed / inner_area
            report.exposure[f"{slug}/{outfit}/{state}/{form}"] = round(ratio, 4)
            if _body_type(slug) == "adult" and ratio > 0.25:
                report.fail(
                    slug,
                    outfit,
                    state,
                    form,
                    "inner-exposed",
                    f"이너의 {ratio:.1%} 가 의상 밖으로 보인다",
                )
                _write_overlay(
                    base,
                    inner_mask,
                    layer_mask,
                    qa_root / slug / outfit / state / f"{form}.webp",
                )


def _write_overlay(
    base: Image.Image,
    inner_mask: Image.Image,
    layer_mask: Image.Image,
    output: Path,
) -> None:
    """Paint the uncovered inner pixels over the base so a hole is visible."""

    overlay = base.copy()
    leak = ImageChops.subtract(inner_mask, layer_mask)
    tint = Image.new("RGBA", base.size, (255, 0, 128, 255))
    overlay.paste(tint, mask=leak)
    output.parent.mkdir(parents=True, exist_ok=True)
    overlay.save(output, "WEBP", quality=88, method=6)


def _output_path(
    output_root: Path,
    name: str,
    slug: str,
    state: str,
    form: str,
) -> Path:
    """Flat file names inside one directory per layer role.

    Flutter's asset entries are not recursive, so a nested tree would need a
    pubspec line per leaf directory and would silently ship nothing when a new
    character lands.  The growth sprites in assets/plants use the same flat
    convention.
    """

    if name == "base":
        return output_root / "bodies" / f"{slug}-{state}-{form}.webp"
    if name == "inner":
        return output_root / "inners" / f"{slug}-{state}-{form}.webp"
    return output_root / "outfits" / f"{name}-{slug}-{state}-{form}.webp"


def build(
    source_root: Path,
    output_root: Path,
    qa_root: Path,
    manifest_path: Path,
) -> BuildReport:
    report = BuildReport()
    catalog, report.pending = discover(source_root)
    if not catalog:
        raise ValueError(
            f"{source_root} 아래에 base/ 시트를 가진 캐릭터가 없다. "
            "착의형 legacy-body/ 시트는 빌드 대상이 아니다."
        )

    manifest_layers: dict[str, dict] = {}
    for slug, outfit_keys in catalog.items():
        try:
            panels, names, source_outfits = _load_layers(
                source_root, slug, outfit_keys
            )
        except ValueError as error:
            # One unusable sheet must not hide the state of every other
            # character; the roster is built one character at a time.
            report.fail(slug, "-", "-", "-", "source", str(error))
            continue
        report.species.append(slug)
        for key in outfit_keys:
            report.outfits.setdefault(key, []).append(slug)

        # One crop and one scale per emotion route across every state and every
        # layer, so adding an outfit never shifts the body it sits on.
        boxes: dict[str, list[tuple[int, int, int, int]]] = {
            state: [
                _union_bbox([panels[state][name][index] for name in names])
                for index in range(6)
            ]
            for state in STATES
        }

        # Sheet-level check: the six panels must vary the way the base does.
        for name in names:
            if name in ("base", "inner"):
                continue
            for state in STATES:
                _check_pose_variety(
                    report,
                    slug,
                    name,
                    state,
                    panels[state]["base"],
                    source_outfits[state][name],
                )

        scales: dict[str, float] = {}
        for form_index, form in enumerate(FORMS):
            sizes = [
                (
                    boxes[state][form_index][2] - boxes[state][form_index][0],
                    boxes[state][form_index][3] - boxes[state][form_index][1],
                )
                for state in STATES
            ]
            scale = _route_scale(slug, sizes)
            scales[form] = round(scale, 6)
            for state in STATES:
                crop_box = boxes[state][form_index]
                base = panels[state]["base"][form_index]
                inner = (
                    panels[state]["inner"][form_index]
                    if "inner" in names
                    else None
                )
                _check_base_undressed(report, slug, state, form, base)
                if inner is not None:
                    _check_inner_envelope(
                        report, slug, state, form, base, inner
                    )
                for name in names:
                    if name not in ("base", "inner"):
                        _check_outfit(
                            report,
                            slug,
                            name,
                            state,
                            form,
                            base,
                            inner,
                            panels[state][name][form_index],
                            qa_root,
                        )
                        _check_garment_hidden(
                            report,
                            slug,
                            name,
                            state,
                            form,
                            base,
                            panels[state][name][form_index],
                            qa_root,
                        )
                        leak = _measure_limb_leak(
                            base, panels[state][name][form_index]
                        )
                        if leak is not None:
                            report.limb.setdefault(f"{slug}/{name}", {})[
                                f"{state}/{form}"
                            ] = round(leak, 4)
                    _render_layer(
                        panels[state][name][form_index],
                        crop_box=crop_box,
                        scale=scale,
                        output=_output_path(
                            output_root, name, slug, state, form
                        ),
                        clean_fragments=name not in ("base", "inner"),
                    )

        manifest_layers[slug] = {
            "name": CHARACTER_NAMES.get(slug, slug),
            "body_type": _body_type(slug),
            "has_inner": "inner" in names,
            "outfits": outfit_keys,
            "route_scale": scales,
        }

    _check_limb_outliers(report, qa_root)
    _write_manifest(manifest_path, manifest_layers, report)
    return report


def _write_manifest(
    manifest_path: Path,
    layers: dict[str, dict],
    report: BuildReport,
) -> None:
    manifest = {
        "schema_version": 1,
        "layer_contract": 2,
        "rule": (
            "The base layer carries no garment. Render order is "
            "base -> inner -> outfit, and every layer of one character shares "
            "one crop, scale and baseline."
        ),
        "canvas": {"width": CANVAS[0], "height": CANVAS[1], "baseline_y": BASELINE_Y},
        "states": list(STATES),
        "forms": list(FORMS),
        "envelope": {
            body_type: {"top": top, "bottom": bottom}
            for body_type, (top, bottom) in ENVELOPE.items()
        },
        "characters": layers,
        "pending_base": report.pending,
        "violations": [
            {
                "species": item.species,
                "layer": item.layer,
                "state": item.state,
                "form": item.form,
                "rule": item.rule,
                "detail": item.detail,
            }
            for item in report.violations
        ],
        "inner_exposure": report.exposure,
        "limb_leak": report.limb,
        "warnings": [
            {
                "species": item.species,
                "state": item.state,
                "form": item.form,
                "rule": item.rule,
                "detail": item.detail,
            }
            for item in report.warnings
        ],
    }
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def build_preview(output_root: Path, outfit_key: str, species: list[str]) -> None:
    """Contact sheet of the three-layer stack for one outfit."""

    cell_width = 164
    cell_height = 250
    label_width = 190
    header_height = 70
    width = label_width + cell_width * len(FORMS) + 32
    height = header_height + cell_height * len(species) + 24
    canvas = Image.new("RGB", (width, height), "#f4eee5")
    draw = ImageDraw.Draw(canvas)
    title_font = ImageFont.load_default(size=28)
    label_font = ImageFont.load_default(size=18)
    form_font = ImageFont.load_default(size=14)
    draw.text(
        (24, 20),
        f"MONGROO WARDROBE / {outfit_key.upper()} / BASE + INNER + OUTFIT",
        fill="#543f34",
        font=title_font,
    )
    for row, slug in enumerate(species):
        top = header_height + row * cell_height
        draw.text(
            (22, top + 96),
            f"{CHARACTER_NAMES.get(slug, slug)}\n{slug}",
            fill="#624a39",
            font=label_font,
            spacing=6,
        )
        for form_index, form in enumerate(FORMS):
            stack = None
            for name in ("base", "inner", outfit_key):
                path = _output_path(output_root, name, slug, "idle", form)
                if not path.exists():
                    continue
                layer = Image.open(path).convert("RGBA")
                if stack is None:
                    stack = layer
                else:
                    stack.alpha_composite(layer)
            if stack is None:
                continue
            stack.thumbnail(
                (cell_width - 12, cell_height - 34),
                Image.Resampling.LANCZOS,
            )
            left = label_width + form_index * cell_width
            canvas.paste(
                stack,
                (
                    left + (cell_width - stack.width) // 2,
                    top + cell_height - 28 - stack.height,
                ),
                stack,
            )
            draw.text(
                (left + 8, top + cell_height - 24),
                form.upper(),
                fill="#806855",
                font=form_font,
            )

    preview_dir = output_root / "previews"
    preview_dir.mkdir(parents=True, exist_ok=True)
    _save_webp_atomic(
        canvas,
        preview_dir / f"{outfit_key}.webp",
        quality=94,
        method=6,
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--qa-root", type=Path)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument(
        "--report-only",
        action="store_true",
        help="Print contract violations instead of failing the build.",
    )
    args = parser.parse_args()
    qa_root = args.qa_root or args.source_root / "qa"
    manifest_path = args.manifest or args.source_root / "wardrobe-layers.json"
    report = build(args.source_root, args.output_root, qa_root, manifest_path)

    for outfit_key, species in sorted(report.outfits.items()):
        build_preview(args.output_root, outfit_key, species)

    print(f"built {len(report.species)} characters: {', '.join(report.species)}")
    for outfit_key, species in sorted(report.outfits.items()):
        print(f"  outfit {outfit_key}: {len(species)} characters")

    if report.pending:
        print(
            f"\n무착의형 base/ 시트를 아직 만들지 않아 건너뛴 캐릭터 "
            f"{len(report.pending)}개: {', '.join(report.pending)}"
        )
        print("  PROMPTS.md 의 재생성 프롬프트로 base/ 를 채워야 한다.")

    if report.warnings:
        print(f"\n확인 필요 {len(report.warnings)}건 (빌드는 통과):")
        for item in report.warnings:
            print(
                f"  [{item.rule}] {item.species}/{item.state}/{item.form}: "
                f"{item.detail}"
            )
        print(
            "  감정별로 의상이 다른 캐릭터(맨다리 ↔ 타이츠)는 여기 함께 걸린다. "
            "합성 프리뷰로 실제 어긋남인지 확인한다."
        )

    if not report.violations:
        print("\nwardrobe contract v2: OK")
        return

    print(f"\n{len(report.violations)} contract violations:")
    for item in report.violations:
        print(
            f"  [{item.rule}] {item.species}/{item.layer}"
            f"/{item.state}/{item.form}: {item.detail}"
        )
    print(f"\nQA overlays: {qa_root}")
    if not args.report_only:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
