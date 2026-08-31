"""화면에 나가는 서버 문구가 옛 어휘를 쓰지 않는지 본다.

앱 쪽에는 같은 검사가 있는데(`app/test/user_facing_vocabulary_test.dart`)
서버가 내려보내는 라벨은 그 그물에 안 걸린다. 실제로 탐험 탭의 `오늘의 성장
효율`이 같은 기능을 `일일 미션`이라고 부르고 있었다 - 같은 파일의 다른 문구는
전부 `작은 행동`인데 이 한 줄만 남아 있었다.

주석과 docstring은 보지 않는다. 화면에 나가는 것은 payload의 값이다.
"""

from __future__ import annotations

import ast
import pathlib

# 쓰면 안 되는 말과 대신 쓰는 말. 세계관이 정한 어휘다.
BANNED = {
    "미션": "작은 행동",
    "퀘스트": "작은 행동",
    "몬스터": "엉킴 또는 수호자",
    "스킬북": "기록서",
    "레벨업": "성장",
}

# 화면에 그대로 실려 나가는 키. 코드·상태값은 보지 않는다.
USER_FACING_KEYS = {
    "label",
    "name",
    "message",
    "description",
    "caption",
    "title",
    "hint",
    "summary",
    "telegraph",
    "effect_summary",
    "unlock_hint",
    "lock_reason",
    "retired_reason",
}

ROOT = pathlib.Path(__file__).resolve().parents[2] / "app"


def _offenders() -> list[str]:
    found: list[str] = []
    for path in sorted(ROOT.rglob("*.py")):
        if "__pycache__" in path.parts:
            continue
        tree = ast.parse(path.read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            if not isinstance(node, ast.Dict):
                continue
            for key, value in zip(node.keys, node.values):
                if not (isinstance(key, ast.Constant) and key.value in USER_FACING_KEYS):
                    continue
                if not (isinstance(value, ast.Constant) and isinstance(value.value, str)):
                    continue
                for word, instead in BANNED.items():
                    if word in value.value:
                        found.append(
                            f"{path.name}:{value.lineno} {value.value!r} "
                            f"→ {word} 대신 {instead}"
                        )
    return found


def test_server_labels_use_the_current_wording():
    offenders = _offenders()
    assert not offenders, "옛 어휘가 남아 있습니다:\n" + "\n".join(offenders)
