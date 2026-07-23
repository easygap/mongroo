"""대화 단계 전이 규칙. LLM이 아니라 서버가 흐름을 결정한다 (design.md 6.2)."""
from app.models.enums import ReflectionStage as S

# 각 단계에서 사용자 발화를 몇 번 받으면 다음 단계로 넘어가는지
_TURNS_PER_STAGE = {
    S.GREETING: 1,        # 첫 사용자 발화가 오면 emotion_check로
    S.EMOTION_CHECK: 1,
    S.EXPLORE: 2,
    S.REFRAME_OPTION: 1,
    S.ACTION: 1,
}

_SKIP_REFRAME_HINTS = ("싫어", "안 할래", "넘어가", "그냥", "됐어")


def next_stage(current: str, user_turns_in_stage: int, latest_user_text: str) -> str:
    """이번 사용자 발화에 대한 응답을 생성할 단계를 결정한다."""
    if current == S.CLOSING:
        return S.CLOSING
    if current == S.REFRAME_OPTION and any(h in latest_user_text for h in _SKIP_REFRAME_HINTS):
        return S.ACTION
    required = _TURNS_PER_STAGE.get(current, 1)
    if user_turns_in_stage >= required:
        order = S.ORDER
        return order[min(order.index(current) + 1, len(order) - 1)]
    return current


def stage_for_reply(session_stage: str, user_turns_in_stage: int, latest_user_text: str,
                    total_user_turns: int, max_user_turns: int) -> str:
    """턴 한도에 도달하면 무조건 closing으로 마무리한다."""
    if total_user_turns >= max_user_turns:
        return S.CLOSING
    return next_stage(session_stage, user_turns_in_stage, latest_user_text)
