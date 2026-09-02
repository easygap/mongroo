#!/usr/bin/env python3
"""설계서 4.7이 요구하는 납품 묶음에서 빠져 있던 것을 만든다.

## 4.7이 뭐라고 적어 뒀나

> 최종 납품은 RGBA master, 프레임 contact sheet, 0.25× onion-skin 영상,
> 실제 배경 합성 영상, atlas/WebP, manifest, 프롬프트·참조 hash를 한 묶음으로
> 가진다. 어느 하나가 없으면 `art_complete=false`다.

일곱 가지 중 **셋이 없었다.** onion-skin 영상, 실제 배경 합성 영상,
프롬프트·참조 hash. 그러니까 규칙대로면 지금 실려 있는 90종 전부
`art_complete=false`인데, 그 필드가 아예 없어서 아무도 그렇게 세지 않았다.
`production_ready`가 이름값으로만 붙어 있던 것과 같은 종류의 일이다.

## 이 스크립트가 만드는 것

- **onion-skin 영상** — `0.25×`는 **속도**로 읽었다. 프레임 길이를 4배로 늘리고,
  앞 두 프레임을 옅게 깔아 in-between이 어디서 끊기는지 보이게 한다. 애니메이터가
  이걸 보려고 요구하는 물건이다.
- **실제 배경 합성 영상** — 그 연출이 실제로 나가는 **지역 전투 배경** 위에
  얹어 돌린다. 게이트가 재는 정적 대비와 달리, 움직이는 동안 배경에 묻히는
  구간이 있는지는 이것으로만 보인다.
- **프롬프트·참조 hash** — 어느 프롬프트와 어느 참조 시트에서 나온 그림인지
  되짚을 수 있게 `jobs*.json`에서 찾아 해시로 박는다.

## 안 되는 것은 안 된다고 적는다

프롬프트 기록(`jobs*.json`)이 있는 것은 39종뿐이다. 나머지는 이 파이프라인이
생기기 전에 다른 경로로 만들어졌고, 그 프롬프트는 남아 있지 않다. 그것들은
`art_complete=false`로 두고 `delivery.missing`에 이유를 적는다 — 없는 것을
있다고 세면 이 필드도 `production_ready`처럼 뜻을 잃는다.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[2]
MANIFEST = REPO / "app/assets/adventure/effects/manifest.json"
RUNTIME_ROOT = REPO / "app/assets/adventure/effects"
CONCEPT_ROOT = REPO / "design-system/concepts"
BACKDROP_ROOT = REPO / "app/assets/adventure"

#: 납품물을 한곳에 모은다. concept 디렉터리가 있는 연출은 46종뿐이라, 있는
#: 것만 concept 밑에 넣으면 나머지 44종은 갈 곳이 없고 검사도 두 갈래가 된다.
DELIVERY_ROOT = REPO / "design-system/deliveries"

#: 실제 전투 배경. `verify_effect_production_gate.py`와 같은 표를 쓴다.
BACKDROPS = {
    "moss_archive": "expedition-monster-den-battle-v1.webp",
    "echo_well": "expedition-monster-den-echo-well-v1.webp",
    "starlight_seed_vault": "expedition-monster-den-starlight-seed-vault-v1.webp",
    "heartwood_observatory": "expedition-monster-den-heartwood-observatory-v1.webp",
}
DEFAULT_BACKDROP = "expedition-monster-den-battle-v1.webp"

#: onion-skin에서 앞 프레임을 몇 장이나, 얼마나 옅게 깔 것인가.
ONION_TRAIL = 2
ONION_ALPHA = (0.22, 0.11)

#: `0.25×`는 속도다. 프레임 길이를 네 배로 늘린다.
ONION_SPEED = 4


def _region_of(family: str) -> str | None:
    """이 연출이 어느 지역 것인가. 엉킴·짐승 카탈로그가 원본이다."""

    sys.path.insert(0, str(REPO / "server"))
    from app.content.expeditions.joint_guard import BEAST_CATALOG  # noqa: PLC0415
    from app.content.expeditions.tangles import TANGLE_CATALOG  # noqa: PLC0415

    for tangle in TANGLE_CATALOG.values():
        for intent in tangle["intents"]:
            if intent["vfx_family"] == family:
                return str(tangle["region_code"])
    for beast in BEAST_CATALOG.values():
        for intent in list(beast["intents"]) + [beast["sleeptalk"]]:
            if intent["vfx_family"] == family:
                return str(beast["region_code"])
    return None


def _frames(directory: Path, count: int) -> list[Image.Image]:
    return [
        Image.open(directory / f"frame-{index:02d}.webp").convert("RGBA")
        for index in range(count)
    ]


def _onion(frames: list[Image.Image], durations: list[int], out: Path) -> None:
    """앞 프레임을 옅게 깔아 in-between을 보이게 한다."""

    plate = Image.new("RGBA", frames[0].size, (24, 26, 30, 255))
    composed = []
    for index, frame in enumerate(frames):
        canvas = plate.copy()
        for back, weight in enumerate(ONION_ALPHA[:ONION_TRAIL], start=1):
            if index - back < 0:
                continue
            ghost = frames[index - back].copy()
            alpha = ghost.getchannel("A").point(lambda value: int(value * weight))
            ghost.putalpha(alpha)
            canvas = Image.alpha_composite(canvas, ghost)
        composed.append(Image.alpha_composite(canvas, frame).convert("RGB"))
    composed[0].save(
        out,
        format="WEBP",
        save_all=True,
        append_images=composed[1:],
        duration=[duration * ONION_SPEED for duration in durations],
        loop=0,
        quality=82,
        method=4,
    )


def _on_backdrop(
    frames: list[Image.Image], durations: list[int], backdrop: str, out: Path
) -> None:
    """실제 지역 전투 배경 위에 얹어 돌린다.

    게이트는 정지 프레임의 대비만 잰다. 움직이는 동안 어느 구간에서 배경에
    묻히는지는 이렇게 돌려 봐야 보인다.
    """

    size = frames[0].size
    with Image.open(BACKDROP_ROOT / backdrop) as opened:
        plate = opened.convert("RGBA").resize(size, Image.LANCZOS)
    composed = [Image.alpha_composite(plate, frame).convert("RGB") for frame in frames]
    composed[0].save(
        out,
        format="WEBP",
        save_all=True,
        append_images=composed[1:],
        duration=durations,
        loop=0,
        quality=78,
        method=4,
    )


def _prompt_record(
    effect_keys: list[str], family: str
) -> dict[str, str] | None:
    """`jobs*.json`에서 이 연출의 프롬프트와 참조를 찾아 해시로 만든다.

    job의 `id`는 대시, 이펙트 키는 밑줄이라 둘 다 맞춰 본다.

    **키가 없는 연출도 있다.** 성장결 폴백은 서버가 키로 지목하지 않고
    family로만 닿아서 `effect_keys`가 비어 있다. 그래서 family 이름으로도
    찾는데, 이때는 job의 `out`이 `<키>-sheet.png`인 것만 본다. 같은 이름의
    벨트 아이콘 job(`kel-mosaic`)이 있어서, 이름만 맞춰 보면 **연출 프롬프트
    자리에 아이콘 프롬프트가 들어앉는다.** 시트를 굽는 job만 `-sheet`로
    끝나므로 그 하나로 갈린다.
    """

    wanted = {key for key in effect_keys}
    wanted |= {key.replace("_", "-") for key in effect_keys}
    # family로만 닿는 것. 시트를 굽는 job에서만 찾는다.
    tail = family.split(".", 1)[-1].replace("-", "_")
    sheet_only = {tail, f"{family.split('.', 1)[0]}_{tail}"}

    for jobs_path in sorted(CONCEPT_ROOT.glob("*/jobs*.json")):
        payload = json.loads(jobs_path.read_text(encoding="utf-8"))
        for job in payload.get("jobs", []):
            out_stem = Path(str(job.get("out", ""))).stem
            sheet_key = (
                out_stem[: -len("-sheet")] if out_stem.endswith("-sheet") else None
            )
            names = {str(job.get("id"))}
            if sheet_key is not None:
                names.add(sheet_key)
            if not (names & wanted) and not (
                sheet_key is not None and sheet_key in sheet_only
            ):
                continue
            prompt = str(job.get("prompt", ""))
            references = [
                hashlib.sha256((REPO / reference).read_bytes()).hexdigest().upper()
                for reference in job.get("references", [])
                if (REPO / reference).exists()
            ]
            return {
                "jobs_file": str(jobs_path.relative_to(REPO)).replace("\\", "/"),
                "prompt_sha256": hashlib.sha256(
                    prompt.encode("utf-8")
                ).hexdigest().upper(),
                "reference_sha256": references,
            }
    return None


def _check() -> int:
    """적어 둔 묶음이 실제로 있는지 본다.

    `art_complete:true`인데 파일이 없으면 그 필드는 `production_ready`가 그랬듯
    이름값만 남는다. 지우거나 옮기면 여기서 걸린다.
    """

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    problems: list[str] = []
    complete = 0
    for effect in manifest["effects"]:
        family = str(effect["family"])
        delivery = effect.get("delivery")
        if delivery is None:
            problems.append(f"{family}: delivery 기록 없음")
            continue
        for field in ("onion_025x", "on_backdrop"):
            path = REPO / str(delivery[field])
            if not path.is_file() or path.stat().st_size < 2_000:
                problems.append(f"{family}: {field} 없음")
        if effect.get("art_complete"):
            complete += 1
            if delivery.get("missing"):
                problems.append(f"{family}: art_complete인데 {delivery['missing']}")
            if not delivery.get("prompt_sha256"):
                problems.append(f"{family}: art_complete인데 프롬프트 해시 없음")
            if not effect.get("production_ready"):
                problems.append(f"{family}: art_complete인데 production_ready가 아님")

    print(f"art_complete {complete} / 전체 {len(manifest['effects'])}")
    for problem in problems:
        print("  ", problem)
    return 1 if problems else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--only",
        nargs="*",
        default=None,
        help="이 family만 만든다. 안 주면 manifest 전체.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="만들지 않고, 적어 둔 묶음이 실제로 있는지만 본다.",
    )
    args = parser.parse_args()

    if args.check:
        return _check()

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    complete = 0
    seen = 0
    short: list[tuple[str, list[str]]] = []

    for effect in manifest["effects"]:
        family = str(effect["family"])
        if args.only and family not in args.only:
            continue
        seen += 1
        directory = str(effect["directory"])
        runtime = RUNTIME_ROOT / directory
        frames = _frames(runtime, int(effect["frame_count"]))
        durations = [int(value) for value in effect["frame_durations_ms"]]

        out_dir = DELIVERY_ROOT / directory
        out_dir.mkdir(parents=True, exist_ok=True)
        _onion(frames, durations, out_dir / "onion-025x.webp")
        backdrop = BACKDROPS.get(_region_of(family) or "", DEFAULT_BACKDROP)
        _on_backdrop(frames, durations, backdrop, out_dir / "on-backdrop.webp")

        # 성장결 폴백은 자기 키가 없다. family 이름으로 찾는다.
        keys = [str(key) for key in effect.get("effect_keys", [])]
        record = _prompt_record(keys, str(family))
        missing: list[str] = []
        if record is None:
            missing.append("prompt_hash")

        delivery = {
            "onion_025x": f"design-system/deliveries/{directory}/onion-025x.webp",
            "on_backdrop": f"design-system/deliveries/{directory}/on-backdrop.webp",
            "backdrop": backdrop,
            **(record or {}),
            "missing": missing,
        }
        effect["delivery"] = delivery
        # 4.7: 일곱 중 하나라도 없으면 art_complete는 false다.
        effect["art_complete"] = not missing and bool(effect.get("production_ready"))
        if effect["art_complete"]:
            complete += 1
        else:
            short.append((family, missing or ["production_ready"]))

    MANIFEST.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"art_complete {complete} / 이번에 만든 것 {seen} (manifest 전체 {len(manifest['effects'])})")
    if short:
        print()
        print("아직 묶음이 덜 찬 것:")
        for family, reasons in short:
            print(f"  {family}: {', '.join(reasons)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
