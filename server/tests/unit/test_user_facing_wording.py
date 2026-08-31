"""화면에 나가는 서버 문구가 옛 어휘를 쓰지 않는지 본다.

앱 쪽에는 같은 검사가 있는데(`app/test/user_facing_vocabulary_test.dart`)
서버가 내려보내는 라벨은 그 그물에 안 걸린다. 실제로 탐험 탭의 `오늘의 성장
효율`이 같은 기능을 `일일 미션`이라고 부르고 있었다 - 같은 파일의 다른 문구는
전부 `작은 행동`인데 이 한 줄만 남아 있었다.

주석과 docstring은 보지 않는다. 화면에 나가는 것은 payload의 값이다.

콘텐츠 JSON도 같이 본다. 파이썬만 훑었을 때 `moss_archive.json`의
`scene_label`이 `몬스터 소굴`인 채로 남아 있었다 - 화면 머리글과 스크린리더가
그대로 읽는 자리인데, 나머지 세 지역은 전부 세계관 이름을 쓰고 있었고 하필
새 사용자가 처음 밟는 지역만 옛 이름이었다. JSON은 키를 고르지 않고 **한글이
들어간 문자열 전부**를 본다. 콘텐츠 fixture의 한글은 정의상 화면에 나가는 말이고,
코드값은 전부 ASCII다.
"""

from __future__ import annotations

import ast
import json
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


CONTENT = pathlib.Path(__file__).resolve().parents[2] / "app" / "content"


def _has_hangul(text: str) -> bool:
    return any(0xAC00 <= ord(ch) <= 0xD7A3 for ch in text)


def _json_offenders() -> list[str]:
    found: list[str] = []

    def walk(node: object, path: str, source: pathlib.Path) -> None:
        if isinstance(node, dict):
            for key, value in node.items():
                walk(value, f"{path}.{key}", source)
        elif isinstance(node, list):
            for index, value in enumerate(node):
                walk(value, f"{path}[{index}]", source)
        elif isinstance(node, str) and _has_hangul(node):
            for word, instead in BANNED.items():
                if word in node:
                    found.append(
                        f"{source.name}:{path} {node!r} → {word} 대신 {instead}"
                    )

    for path in sorted(CONTENT.rglob("*.json")):
        walk(json.loads(path.read_text(encoding="utf-8")), "", path)
    return found


def test_server_labels_use_the_current_wording():
    offenders = _offenders()
    assert not offenders, "옛 어휘가 남아 있습니다:\n" + "\n".join(offenders)


def test_content_json_uses_the_current_wording():
    offenders = _json_offenders()
    assert not offenders, "콘텐츠에 옛 어휘가 남아 있습니다:\n" + "\n".join(offenders)
