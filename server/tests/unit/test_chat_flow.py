from app.ai.chat_flow import next_stage, stage_for_reply
from app.models.enums import ReflectionStage as S


def test_greeting_moves_to_emotion_check():
    assert next_stage(S.GREETING, 1, "안녕") == S.EMOTION_CHECK


def test_explore_needs_two_turns():
    assert next_stage(S.EXPLORE, 1, "그랬어") == S.EXPLORE
    assert next_stage(S.EXPLORE, 2, "그랬어") == S.REFRAME_OPTION


def test_reframe_skip_on_refusal():
    assert next_stage(S.REFRAME_OPTION, 0, "그건 싫어") == S.ACTION


def test_closing_is_terminal():
    assert next_stage(S.CLOSING, 5, "응") == S.CLOSING


def test_turn_limit_forces_closing():
    assert stage_for_reply(S.EXPLORE, 1, "계속 이야기", 10, 10) == S.CLOSING
    assert stage_for_reply(S.EXPLORE, 1, "계속 이야기", 3, 10) == S.EXPLORE
