#!/usr/bin/env python3
"""전투 VFX manifest v2를 검증하고 Dart 상수 카탈로그를 만든다."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

try:
    from PIL import Image
except ImportError as exc:  # pragma: no cover - 실행 환경 오류를 바로 설명한다.
    raise SystemExit(
        "Pillow가 필요합니다. python -m pip install -r design-system/requirements.txt"
    ) from exc


MANIFEST = Path("app/assets/adventure/effects/manifest.json")
OUTPUT = Path(
    "app/lib/features/expedition/presentation/expedition_combat_effect_catalog.g.dart"
)
RUNTIME_ROOT = Path("app/assets/adventure/effects")
SHA256_PATTERN = re.compile(r"^[0-9A-F]{64}$")
KELS = {"sunny", "rainy", "ember", "moonlit", "sparkling", "mosaic"}


def _aggregate_sha256(paths: list[Path]) -> str:
    frame_hashes = "".join(
        hashlib.sha256(path.read_bytes()).hexdigest().upper() for path in paths
    )
    return hashlib.sha256(frame_hashes.encode("ascii")).hexdigest().upper()


def _dart_string(value: str) -> str:
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"


def _string_list(values: list[str]) -> str:
    return "[" + ", ".join(_dart_string(value) for value in values) + "]"


def _int_list(values: list[int]) -> str:
    return "[" + ", ".join(str(value) for value in values) + "]"


def _validate(manifest: dict[str, Any], *, check_assets: bool) -> None:
    if manifest.get("version") != 2:
        raise ValueError("effect manifest version must be 2")
    manifest_frame_size = manifest.get("frame_size")
    if (
        not isinstance(manifest_frame_size, list)
        or len(manifest_frame_size) != 2
        or any(
            not isinstance(value, int) or value <= 0 for value in manifest_frame_size
        )
    ):
        raise ValueError("effect manifest needs a positive [width, height] frame_size")
    effects = manifest.get("effects")
    if not isinstance(effects, list) or not effects:
        raise ValueError("effect manifest needs a non-empty effects list")
    families: set[str] = set()
    effect_keys: set[str] = set()
    for effect in effects:
        if not isinstance(effect, dict):
            raise TypeError("every effect entry must be an object")
        family = str(effect.get("family", ""))
        if not family or family in families:
            raise ValueError(f"duplicate or empty VFX family: {family}")
        families.add(family)
        frame_count = int(effect.get("frame_count", 0))
        frame_size = effect.get("frame_size") or []
        durations = effect.get("frame_durations_ms") or []
        if (
            frame_count <= 0
            or len(durations) != frame_count
            or any(not isinstance(value, int) or value <= 0 for value in durations)
        ):
            raise ValueError(f"frame duration mismatch: {family}")
        if frame_size != manifest_frame_size:
            raise ValueError(f"frame size mismatch: {family}")
        contact_frame = int(effect.get("contact_frame", -1))
        if not 0 <= contact_frame < frame_count:
            raise ValueError(f"contact frame out of range: {family}")
        pivot = effect.get("pivot") or []
        if len(pivot) != 2 or not all(0 <= float(value) <= 1 for value in pivot):
            raise ValueError(f"invalid normalized pivot: {family}")
        kel = effect.get("kel")
        if kel is not None and kel not in KELS:
            raise ValueError(f"invalid growth texture: {family}.{kel}")
        for field in ("directory", "anchor"):
            if not isinstance(effect.get(field), str) or not effect[field].strip():
                raise ValueError(f"missing {field}: {family}")
        if not isinstance(effect.get("production_ready"), bool):
            raise TypeError(f"production_ready must be boolean: {family}")
        for field in ("source_hash", "runtime_hash"):
            value = str(effect.get(field, ""))
            if not SHA256_PATTERN.fullmatch(value):
                raise ValueError(f"{field} must be uppercase SHA-256: {family}")
        raw_effect_keys = effect.get("effect_keys") or []
        if not isinstance(raw_effect_keys, list) or any(
            not isinstance(value, str) or not value for value in raw_effect_keys
        ):
            raise ValueError(f"effect_keys must be non-empty strings: {family}")
        for effect_key in raw_effect_keys:
            if effect_key in effect_keys:
                raise ValueError(f"duplicate legacy effect key: {effect_key}")
            effect_keys.add(effect_key)
        if check_assets:
            directory = RUNTIME_ROOT / str(effect["directory"])
            frames = sorted(directory.glob("frame-*.webp"))
            expected_names = [f"frame-{index:02d}.webp" for index in range(frame_count)]
            if [path.name for path in frames] != expected_names:
                raise ValueError(
                    f"runtime frame mismatch: {family} ({len(frames)}/{frame_count})"
                )
            for frame in frames:
                with Image.open(frame) as image:
                    if image.size != tuple(frame_size):
                        raise ValueError(
                            f"runtime frame size mismatch: {family}.{frame.name}"
                        )
                    if "A" not in image.getbands() or image.getextrema()[-1][0] >= 255:
                        raise ValueError(
                            f"runtime frame needs transparency: {family}.{frame.name}"
                        )
            if _aggregate_sha256(frames) != effect["runtime_hash"]:
                raise ValueError(f"runtime aggregate SHA-256 mismatch: {family}")
    fallback = str(manifest.get("fallback_family", ""))
    if fallback not in families:
        raise ValueError("fallback family must exist in effects")
    for kel in KELS:
        family = f"kel.{kel}"
        if family not in families:
            raise ValueError(f"missing growth texture fallback: {family}")


def _render(manifest: dict[str, Any]) -> str:
    lines = [
        "// GENERATED FILE. 수정하지 말고 manifest와 생성 스크립트를 고쳐 주세요.",
        "part of 'expedition_combat_effect_catalog.dart';",
        "",
        (
            "const expeditionCombatEffectFallbackFamily = "
            f"{_dart_string(str(manifest['fallback_family']))};"
        ),
        "",
        "const Map<String, ExpeditionCombatEffectSpec> expeditionCombatEffectsByFamily =",
        "    {",
    ]
    for effect in manifest["effects"]:
        family = str(effect["family"])
        kel = effect.get("kel")
        pivot = effect["pivot"]
        lines.extend(
            [
                f"  {_dart_string(family)}: ExpeditionCombatEffectSpec(",
                f"    family: {_dart_string(family)},",
                f"    effectKeys: {_string_list(list(effect.get('effect_keys') or []))},",
                f"    kel: {('null' if kel is None else _dart_string(str(kel)))},",
                f"    directory: {_dart_string(str(effect['directory']))},",
                f"    frameCount: {int(effect['frame_count'])},",
                f"    frameWidth: {int(effect['frame_size'][0])},",
                f"    frameHeight: {int(effect['frame_size'][1])},",
                (
                    "    frameDurationsMs: "
                    f"{_int_list([int(value) for value in effect['frame_durations_ms']])},"
                ),
                f"    contactFrame: {int(effect['contact_frame'])},",
                f"    pivotX: {float(pivot[0])},",
                f"    pivotY: {float(pivot[1])},",
                f"    anchor: {_dart_string(str(effect['anchor']))},",
                f"    productionReady: {str(bool(effect['production_ready'])).lower()},",
                "    sourceHash:",
                f"        {_dart_string(str(effect['source_hash']))},",
                "    runtimeHash:",
                f"        {_dart_string(str(effect['runtime_hash']))},",
                "  ),",
            ]
        )
    lines.extend(
        ["};", "", "const Map<String, String> expeditionCombatFamilyByEffectKey = {"]
    )
    for effect in manifest["effects"]:
        for effect_key in effect.get("effect_keys") or []:
            lines.append(
                f"  {_dart_string(str(effect_key))}: "
                f"{_dart_string(str(effect['family']))},"
            )
    lines.extend(["};", ""])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--skip-assets",
        action="store_true",
        help="에셋 제작 전 스키마와 Dart 출력만 검증합니다.",
    )
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    _validate(manifest, check_assets=not args.skip_assets)
    OUTPUT.write_text(_render(manifest), encoding="utf-8")
    print(f"generated {OUTPUT} from {MANIFEST}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
