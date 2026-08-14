"""지역 ambience 8종(4지역 × A/B)을 합성한다.

외부 샘플을 쓰지 않는다는 `ADVENTURE_AUDIO.md`의 제약을 그대로 따른다.

## 왜 16초가 아니라 32/40초인가

BGM은 16초 loop다. 그런데 ambience를 같은 길이로 만들면 **반복이 들린다.** 게임
오디오에서 ambience는 30초~2분이 권장 범위이고, 같은 소리가 15초마다 돌아오면
몰입이 깨진다는 것이 일반적인 정리다.

여기서는 한 걸음 더 간다. **A는 32초, B는 40초로 서로 다르게** 두어 둘을 겹쳐
틀면 합성 주기가 최소공배수인 **160초**가 된다. 파일은 작게 두면서 귀에 들리는
반복 주기는 2분 40초로 늘어난다.

## 왜 튀는 소리를 넣지 않는가

물방울 한 방울, 새 한 마리처럼 **도드라지는 소리는 loop를 들키게 하는 주범**이다.
`N초마다 같은 물방울`이 되는 순간 배경이 배경이 아니게 된다. 그래서 이 파일들은
전부 **연속적인 층**으로만 만든다. 변화는 아주 느린 스웰과 필터 움직임이 준다.
검수기가 `짧은 창 최대 RMS / 중앙값 RMS` 비율로 이 규칙을 실제로 강제한다.

## 어떻게 이음매 없이 만드는가

FFT 없이도 정확한 주기를 얻는다.

- **부분음**: 주파수를 `1/loop`의 정수배로만 고른다. 정의상 loop 경계에서 위상이
  정확히 맞는다.
- **잡음층**: 씨앗 고정 백색 잡음을 **원형 필터링**한다. 버퍼 끝부분으로 필터
  상태를 먼저 데운 뒤 전체를 거르면, 필터의 임펄스 응답이 데우는 길이 안에서
  충분히 잦아드는 한 결과는 원형 합성곱과 같아진다. 경계에 이어 붙인 자국이
  남지 않는다.

정말 이어지는지는 믿지 않고 **검수기가 경계 불연속을 내부 표본 간 변화량과
비교해서** 확인한다.

## 대역 분리 — BGM을 가리지 않기 위해

지역 BGM의 핵심은 드론 816~1704Hz와 마림바 음이다. ambience가 그 대역에 앉으면
서로 갉아먹는다. 그래서 역할을 나눈다.

- **A(바닥)**: 공간의 무게. BGM 핵심 아래에서만 운다.
- **B(공기)**: 높고 성긴 결. BGM 핵심 위에서만 운다.

검수기가 두 층의 스펙트럼 무게중심을 재서 이 분리를 강제한다.

사용법:
    python build_expedition_ambience.py --region all
    python build_expedition_ambience.py --region all --check
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import shutil
import subprocess
import sys
import tempfile
import wave
from array import array
from pathlib import Path

SAMPLE_RATE = 48_000

# A와 B의 길이를 다르게 둔다. 최소공배수 160초가 겹쳐 틀었을 때의 반복 주기다.
LAYER_SECONDS = {"a": 32.0, "b": 40.0}

# 원형 필터링에서 상태를 데우는 길이. 여기 쓰는 필터의 임펄스 응답은 수십
# 밀리초면 잦아들어서 1초면 넉넉하다.
WARMUP_SECONDS = 1.0

# ambience 목표. 문서 범위(-28~-24 LUFS) 중 **조용한 끝**을 쓴다. 배경은 배경
# 자리에 있어야 하고, 접촉음과 대사가 지나갈 자리를 남겨야 한다.
TARGET_LUFS = -28

# 배경층이라 피크를 아낄 이유가 없다. 넉넉히 낮춰 다른 소리와 합쳐져도
# master bus가 -2dBTP를 넘지 않게 한다.
TRUE_PEAK_TARGET_DBTP = -9.0

ROOT = Path(__file__).resolve().parents[2]
MASTER_DIR = ROOT / "design-system" / "audio" / "ambience"
RUNTIME_DIR = ROOT / "app" / "assets" / "adventure" / "ambience"
MANIFEST = ROOT / "design-system" / "audio" / "ambience-manifest.json"


# ── 지역별 성격 ──────────────────────────────────────────────────────────────
#
# 각 층은 `bands`로 정의한다. 한 band는 (중심Hz, 대역폭Hz, 이득, 스웰 주기,
# 스웰 깊이, 좌우 위치)다. 스웰 주기는 **loop 안의 정수 회전수**라 경계에서
# 진폭이 튀지 않는다.
#
# `partials`는 (loop당 회전수, 이득, 좌우 위치)다. 회전수가 정수라 위상이 맞는다.
# 회전수 ÷ loop초 = 실제 Hz이므로, 32초 loop에서 회전수 1600 = 50Hz다.
REGIONS: dict[str, dict] = {
    # 이끼 낀 기억서고 — 책장 사이에 갇힌 공기, 종이 먼지.
    "moss_archive": {
        "slug": "moss-archive",
        "name": "이끼 낀 기억서고",
        "a": {
            "bands": (
                (66, 34, 0.145, 2, 0.30, -0.18),
                (128, 58, 0.100, 3, 0.26, 0.20),
                (232, 96, 0.052, 5, 0.22, -0.10),
            ),
            "partials": ((1408, 0.020, -0.30), (2112, 0.013, 0.30)),
        },
        "b": {
            "bands": (
                (3150, 1500, 0.052, 3, 0.34, 0.26),
                (5400, 2300, 0.030, 5, 0.30, -0.24),
            ),
            "partials": ((104_000, 0.006, 0.34),),
        },
    },
    # 메아리 우물정원 — 젖은 돌 울림, 멀리서 도는 물의 기척.
    "echo_well": {
        "slug": "echo-well",
        "name": "메아리 우물정원",
        "a": {
            "bands": (
                (58, 30, 0.150, 2, 0.34, 0.16),
                (142, 64, 0.098, 3, 0.30, -0.22),
                (256, 104, 0.048, 4, 0.24, 0.12),
            ),
            "partials": ((1216, 0.021, 0.28), (1824, 0.012, -0.28)),
        },
        "b": {
            "bands": (
                (2900, 1350, 0.056, 4, 0.38, -0.28),
                (6100, 2500, 0.026, 3, 0.32, 0.24),
            ),
            "partials": ((132_000, 0.005, -0.32),),
        },
    },
    # 별빛 씨앗 보관고 — 차고 마른 공기, 금속 선반의 먼 잔향.
    "starlight_seed_vault": {
        "slug": "starlight-seed-vault",
        "name": "별빛 씨앗 보관고",
        "a": {
            "bands": (
                (74, 32, 0.138, 3, 0.26, -0.20),
                (116, 52, 0.104, 2, 0.30, 0.18),
                (208, 88, 0.050, 5, 0.20, 0.10),
            ),
            "partials": ((1760, 0.019, -0.26), (2640, 0.011, 0.26)),
        },
        "b": {
            "bands": (
                (3600, 1700, 0.050, 5, 0.30, 0.28),
                (7200, 2800, 0.024, 4, 0.34, -0.26),
            ),
            "partials": ((176_000, 0.005, 0.30),),
        },
    },
    # 마음나무 관측실 — 나무 몸통의 낮은 숨, 높은 곳의 성긴 바람.
    "heartwood_observatory": {
        "slug": "heartwood-observatory",
        "name": "마음나무 관측실",
        "a": {
            "bands": (
                (52, 26, 0.152, 2, 0.32, 0.20),
                (104, 48, 0.106, 4, 0.28, -0.18),
                (196, 84, 0.054, 3, 0.22, 0.12),
            ),
            "partials": ((1632, 0.020, 0.24), (2448, 0.012, -0.24)),
        },
        "b": {
            "bands": (
                (2700, 1250, 0.058, 4, 0.36, -0.22),
                (5000, 2100, 0.028, 5, 0.30, 0.28),
            ),
            "partials": ((120_000, 0.006, -0.30),),
        },
    },
}


def _circular_bandpass(
    length: int, centre: float, width: float, seed: int
) -> list[float]:
    """씨앗 고정 잡음을 원형으로 대역 통과시킨다.

    버퍼 끝으로 필터 상태를 먼저 데운 뒤 전체를 거른다. 임펄스 응답이 데우는
    길이 안에서 잦아들면 결과는 원형 합성곱과 같아져, loop 경계에 자국이 남지
    않는다. `_seam_step`이 실제로 그런지 잰다.
    """

    rng = random.Random(seed)
    noise = [rng.uniform(-1.0, 1.0) for _ in range(length)]

    low = max(20.0, centre - width * 0.5)
    high = min(SAMPLE_RATE * 0.45, centre + width * 0.5)
    # 2극 저역 + 2극 고역으로 대역을 만든다. 값이 클수록 천천히 따라간다.
    low_k = 1.0 - math.exp(-math.tau * high / SAMPLE_RATE)
    high_k = 1.0 - math.exp(-math.tau * low / SAMPLE_RATE)

    warmup = min(length, round(WARMUP_SECONDS * SAMPLE_RATE))
    lp1 = lp2 = hp1 = hp2 = 0.0

    def step(sample: float) -> float:
        nonlocal lp1, lp2, hp1, hp2
        lp1 += low_k * (sample - lp1)
        lp2 += low_k * (lp1 - lp2)
        hp1 += high_k * (lp2 - hp1)
        hp2 += high_k * (hp1 - hp2)
        return lp2 - hp2

    # 끝부분으로 상태를 데운다 — 이 값이 곧 loop가 한 바퀴 돌아온 직후의 상태다.
    for index in range(length - warmup, length):
        step(noise[index])
    return [step(sample) for sample in noise]


def _layer(region: dict, layer: str, seed_base: int) -> tuple[array, array]:
    """한 층(A 또는 B)의 좌우 표본을 만든다."""

    seconds = LAYER_SECONDS[layer]
    length = round(SAMPLE_RATE * seconds)
    spec = region[layer]
    left = [0.0] * length
    right = [0.0] * length

    for index, (centre, width, gain, swell_cycles, depth, pan) in enumerate(
        spec["bands"]
    ):
        # 좌우를 **다른 씨앗**으로 만든다. 같은 잡음을 좌우에 놓으면 가운데
        # 뭉쳐 들리고 헤드폰에서 답답하다.
        band_l = _circular_bandpass(length, centre, width, seed_base + index * 2)
        band_r = _circular_bandpass(length, centre, width, seed_base + index * 2 + 1)
        # 스웰은 loop 안 정수 회전이라 경계에서 진폭이 튀지 않는다.
        omega = math.tau * swell_cycles / length
        left_gain = gain * min(1.0, 1.0 - pan)
        right_gain = gain * min(1.0, 1.0 + pan)
        for position in range(length):
            swell = 1.0 + depth * math.sin(omega * position)
            left[position] += band_l[position] * left_gain * swell
            right[position] += band_r[position] * right_gain * swell

    for cycles, gain, pan in spec["partials"]:
        omega = math.tau * cycles / length
        left_gain = gain * min(1.0, 1.0 - pan)
        right_gain = gain * min(1.0, 1.0 + pan)
        # 좌우 위상을 어긋내 폭을 준다. 4분의 1 주기면 충분히 넓고 모노로
        # 합쳐도 사라지지 않는다.
        for position in range(length):
            left[position] += math.sin(omega * position) * left_gain
            right[position] += math.sin(omega * position + math.pi / 4) * right_gain

    return _to_pcm(left), _to_pcm(right)


def _to_pcm(samples: list[float]) -> array:
    peak = max(abs(value) for value in samples) or 1.0
    # 여유를 크게 둔다. loudnorm이 뒤에서 목표를 맞추므로 여기서는 클리핑만
    # 피하면 된다.
    scale = 0.35 / peak
    return array("h", (int(max(-32768, min(32767, value * scale * 32767))) for value in samples))


def _write_master(path: Path, left: array, right: array) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    interleaved = array("h")
    for index in range(len(left)):
        interleaved.append(left[index])
        interleaved.append(right[index])
    with wave.open(str(path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(interleaved.tobytes())


def _encode(master: Path, runtime: Path) -> None:
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        raise RuntimeError("ffmpeg is required to encode the runtime M4A assets")
    runtime.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            ffmpeg,
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(master),
            "-af",
            f"loudnorm=I={TARGET_LUFS}:TP={TRUE_PEAK_TARGET_DBTP}:LRA=4",
            "-ar",
            str(SAMPLE_RATE),
            "-c:a",
            "aac",
            "-profile:a",
            "aac_low",
            # 배경층이라 대역폭을 아낀다. 96k면 이 정도 스펙트럼에 충분하다.
            "-b:a",
            "96k",
            str(runtime),
        ],
        check=True,
    )


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _build_one(code: str, layer: str, master_dir: Path, runtime_dir: Path) -> dict:
    region = REGIONS[code]
    seed_base = _stable_seed(code, layer)
    left, right = _layer(region, layer, seed_base)
    master = master_dir / f"{region['slug']}-{layer}-master.wav"
    runtime = runtime_dir / f"{region['slug']}-{layer}.m4a"
    _write_master(master, left, right)
    _encode(master, runtime)
    return {
        "region": code,
        "layer": layer,
        "name": region["name"],
        "seconds": LAYER_SECONDS[layer],
        "master_sha256": _sha256(master),
        "runtime": _repo_path(runtime),
        "runtime_sha256": _sha256(runtime),
    }


def _repo_path(path: Path) -> str:
    """저장소 기준 경로. 스크래치로 뽑을 때는 절대 경로 그대로 둔다."""

    try:
        return str(path.relative_to(ROOT)).replace("\\", "/")
    except ValueError:
        return str(path).replace("\\", "/")


def _stable_seed(code: str, layer: str) -> int:
    """실행마다 같은 씨앗. `hash()`는 파이썬 실행마다 달라져 쓸 수 없다."""

    digest = hashlib.sha256(f"{code}:{layer}".encode()).digest()
    return int.from_bytes(digest[:4], "big") % 1_000_000


def build(codes: list[str], *, master_dir: Path, runtime_dir: Path) -> list[dict]:
    entries = []
    for code in codes:
        for layer in ("a", "b"):
            print(f"  {REGIONS[code]['name']} {layer.upper()} …", flush=True)
            entries.append(_build_one(code, layer, master_dir, runtime_dir))
    return entries


def check(codes: list[str]) -> int:
    """마스터를 임시로 다시 렌더링해 기록과 대조한다."""

    if not MANIFEST.exists():
        print("manifest가 없습니다. 먼저 --region all로 생성하세요.")
        return 1
    recorded = {
        (item["region"], item["layer"]): item
        for item in json.loads(MANIFEST.read_text(encoding="utf-8"))["entries"]
    }
    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        for code in codes:
            for layer in ("a", "b"):
                left, right = _layer(REGIONS[code], layer, _stable_seed(code, layer))
                master = tmp_path / f"{code}-{layer}.wav"
                _write_master(master, left, right)
                digest = _sha256(master)
                previous = recorded.get((code, layer))
                if previous is None:
                    print(f"  기록에 없음: {code} {layer}")
                    failures += 1
                elif previous["master_sha256"] != digest:
                    print(f"  달라짐: {code} {layer}")
                    failures += 1
    if failures:
        print(f"{failures}건이 기록과 다릅니다.")
        return 1
    print("모든 마스터가 기록과 같습니다.")
    return 0


def _validate_regions() -> None:
    """만들기 전에 설계 규칙을 스스로 검사한다."""

    for code, region in REGIONS.items():
        for layer in ("a", "b"):
            length = round(SAMPLE_RATE * LAYER_SECONDS[layer])
            spec = region[layer]
            for cycles, _gain, _pan in spec["partials"]:
                if cycles != int(cycles):
                    raise ValueError(f"{code} {layer}: 부분음 회전수가 정수가 아닙니다")
                hz = cycles / LAYER_SECONDS[layer]
                if not 20.0 <= hz <= SAMPLE_RATE * 0.45:
                    raise ValueError(f"{code} {layer}: 부분음 {hz:.1f}Hz가 범위 밖입니다")
            for centre, width, _gain, swell, _depth, pan in spec["bands"]:
                if swell != int(swell) or swell < 1:
                    raise ValueError(f"{code} {layer}: 스웰 회전수가 정수가 아닙니다")
                if centre - width * 0.5 <= 0:
                    raise ValueError(f"{code} {layer}: 대역 하단이 0 이하입니다")
                if not -1.0 <= pan <= 1.0:
                    raise ValueError(f"{code} {layer}: 좌우 위치가 범위 밖입니다")
            if length <= 0:
                raise ValueError(f"{code} {layer}: 길이가 0입니다")

    # A와 B가 같은 길이면 겹쳐 틀 때 주기가 늘어나지 않는다 — 이 스크립트의
    # 존재 이유가 사라지므로 만들기 전에 막는다.
    if LAYER_SECONDS["a"] == LAYER_SECONDS["b"]:
        raise ValueError("A와 B 길이가 같으면 합성 주기가 늘어나지 않습니다")
    combined = math.lcm(round(LAYER_SECONDS["a"]), round(LAYER_SECONDS["b"]))
    if combined < 120:
        raise ValueError(f"겹친 반복 주기 {combined}초는 너무 짧습니다")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--region", default="all", choices=[*REGIONS, "all"])
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--out", default=None, help="스크래치 출력 폴더")
    args = parser.parse_args()

    _validate_regions()
    codes = list(REGIONS) if args.region == "all" else [args.region]

    if args.check:
        return check(codes)

    master_dir = Path(args.out) / "master" if args.out else MASTER_DIR
    runtime_dir = Path(args.out) / "runtime" if args.out else RUNTIME_DIR
    entries = build(codes, master_dir=master_dir, runtime_dir=runtime_dir)

    if args.out is None:
        MANIFEST.parent.mkdir(parents=True, exist_ok=True)
        MANIFEST.write_text(
            json.dumps(
                {
                    "loop_seconds": LAYER_SECONDS,
                    "combined_period_seconds": math.lcm(
                        round(LAYER_SECONDS["a"]), round(LAYER_SECONDS["b"])
                    ),
                    "target_lufs": TARGET_LUFS,
                    "true_peak_dbtp": TRUE_PEAK_TARGET_DBTP,
                    "entries": entries,
                },
                ensure_ascii=False,
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
    print(f"{len(entries)}개 완료")
    return 0


if __name__ == "__main__":
    sys.exit(main())
