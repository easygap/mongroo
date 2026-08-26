"""한국어 조사 선택.

앱 쪽 `core/text/korean_particles.dart`와 같은 규칙이다. 서버에서도 이름을
문장에 넣는 자리가 늘면서 `새싹몬이(가)`처럼 자리표시자가 그대로 화면에 나갔다.
`prompts.py` 안에만 있던 것을 꺼내 한 곳에서 쓴다.
"""

from __future__ import annotations

#: 한국어로 읽었을 때 받침으로 끝나는 숫자. 영·일·삼·육·칠·팔.
_DIGITS_WITH_FINAL = frozenset("013678")


def has_final_consonant(word: str) -> bool:
    """마지막 글자에 받침이 있는지."""
    trimmed = word.rstrip()
    if not trimmed:
        return False
    last = trimmed[-1]
    code_point = ord(last)
    if 0xAC00 <= code_point <= 0xD7A3:
        return (code_point - 0xAC00) % 28 != 0
    # 숫자는 한국어로 읽었을 때의 받침 유무를 따른다.
    if last.isdigit():
        return last in _DIGITS_WITH_FINAL
    return False


def korean_subject(word: str) -> str:
    """주격 조사 이/가."""
    return f"{word}{'이' if has_final_consonant(word) else '가'}"


def korean_object(word: str) -> str:
    """목적격 조사 을/를."""
    return f"{word}{'을' if has_final_consonant(word) else '를'}"


def korean_with(word: str) -> str:
    """동반격 조사 과/와."""
    return f"{word}{'과' if has_final_consonant(word) else '와'}"


def korean_topic(word: str) -> str:
    """보조사 은/는."""
    return f"{word}{'은' if has_final_consonant(word) else '는'}"
