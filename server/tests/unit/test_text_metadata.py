from app.core.text_metadata import diary_content_marker


def test_diary_content_marker_only_preserves_reward_boundaries():
    assert diary_content_marker(None) == 0
    assert diary_content_marker("  ") == 0
    assert diary_content_marker("마음") == 1
    assert diary_content_marker("가" * 49) == 1
    assert diary_content_marker("가" * 50) == 50
    assert diary_content_marker("가" * 5000) == 50
