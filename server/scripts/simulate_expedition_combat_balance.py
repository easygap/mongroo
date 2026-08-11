"""탐험 전투 전수 시뮬레이션 결과를 JSON 리포트로 저장한다."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


SERVER_ROOT = Path(__file__).resolve().parents[1]
if str(SERVER_ROOT) not in sys.path:
    sys.path.insert(0, str(SERVER_ROOT))

from app.content.expeditions.combat_simulator import run_balance_matrix  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=SERVER_ROOT.parent / "docs" / "expedition_combat_balance_report.json",
        help="저장할 JSON 리포트 경로",
    )
    args = parser.parse_args()

    report = run_balance_matrix()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        f"{report['dimensions']['total_battles']:,}전투 전수 계산 완료: "
        f"{args.output.resolve()}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
