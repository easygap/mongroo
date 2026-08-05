"""민감 본문에서 기능에 필요한 최소 메타데이터만 파생한다."""

DIARY_REWARD_THRESHOLD = 50


def diary_content_marker(content: str | None) -> int:
    """본문 유무와 50자 보상 조건만 보존하고 정확한 길이는 저장하지 않는다."""

    length = len(content.strip()) if content else 0
    if length == 0:
        return 0
    if length >= DIARY_REWARD_THRESHOLD:
        return DIARY_REWARD_THRESHOLD
    return 1
