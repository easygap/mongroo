import pytest

from app.ai import classifier as classifier_module
from app.ai.classifier import (
    FakeClassifier,
    LocalClassifier,
    RulesClassifier,
    UNCERTAIN,
)
from app.core.config import get_settings


def test_fake_classifier_abstains_on_exact_top_tie():
    label, scores = FakeClassifier().classify("행복했지만 동시에 불안했다")
    assert scores["기쁨"] == scores["불안"] == 0.5
    assert label == UNCERTAIN


def test_fake_classifier_reads_colloquial_profanity_as_anger():
    label, scores = FakeClassifier().classify(
        "회사 동기 진짜 개빡치네 ㅅㅂ 오늘도 일을 나한테 개같이 맡겼어."
    )

    assert label == "분노"
    assert scores["분노"] == 1.0


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("오늘 자판기 밑에 500원 빠뜨렸는데 결국 못찾음ㅜㅜ", "슬픔"),
        ("지갑을 잃어버렸어. 너무 아깝고 속상하다 ㅠㅠ", "슬픔"),
        ("면접에서 떨어져서 눈물이 났다", "슬픔"),
        ("프로젝트를 끝냈다. 진짜 뿌듯해ㅋㅋ", "기쁨"),
        ("오늘 시험에 합격했어! 너무 행복하다", "기쁨"),
        ("발표 망칠까 봐 걱정돼서 잠도 안 와", "불안"),
        ("친구가 내 진심을 무시해서 너무 서운했다", "상처"),
        ("갑자기 발표하라고 해서 완전 멘붕이었다", "당황"),
        ("일을 나한테 떠넘겨서 개빡치네ㅋㅋ", "분노"),
        ("존나 행복하다 오늘 진짜 최고야", "기쁨"),
        ("헐 면접에 합격했어", "기쁨"),
    ],
)
def test_fake_classifier_combines_colloquial_and_event_cues(text, expected):
    label, scores = FakeClassifier().classify(text)

    assert label == expected
    assert scores[expected] == max(scores.values())


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("오늘은 전혀 슬프지 않았고 오히려 후련했다", "기쁨"),
        ("걱정했지만 결국 문제는 잘 해결됐다", "기쁨"),
        ("화난 게 아니라 너무 당황했다", "당황"),
        ("기쁘지 않고 불안했다", "불안"),
        ("실패하지 않았다. 오히려 성공했다", "기쁨"),
        ("걱정할 필요 없다. 오늘은 좋았다", "기쁨"),
    ],
)
def test_fake_classifier_handles_negation_and_reversal(text, expected):
    label, scores = FakeClassifier().classify(text)

    assert label == expected
    assert scores[expected] == max(scores.values())


@pytest.mark.parametrize(
    "text",
    [
        "분노의 질주 영화를 봤다",
        "화난 캐릭터가 나오는 웹툰을 읽었다",
        "무서운 영화 예고편을 봤다",
        "안 무서웠고 슬프지도 않았다",
        "좋지 않았다",
        "ㅋㅋ 오늘 회의만 세 번 했다",
        "그 문서에는 불안이라는 단어가 적혀 있었다",
        "새치기 장면이 나오는 영화를 봤다",
        "공연 취소라는 제목의 소설을 읽었다",
    ],
)
def test_fake_classifier_abstains_on_negated_or_referential_cues(text):
    label, _ = FakeClassifier().classify(text)

    assert label == UNCERTAIN


def test_fake_classifier_does_not_read_ironic_laughter_as_joy():
    label, scores = FakeClassifier().classify("진짜 개빡치네ㅋㅋ 어이가 없다")

    assert label == "분노"
    assert scores["기쁨"] == 0


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("오늘 자판기에서 음료가 두 개 나와서 개이득이었다", "기쁨"),
        ("퇴근길에 오백원을 주워서 주인 찾아줬다. 뿌듯함", "기쁨"),
        ("친구가 갑자기 선물을 줘서 기분이 좋았다", "기쁨"),
        ("별 기대 안 했는데 공연 표에 당첨됐다", "기쁨"),
        ("너무 웃겨서 눈물남ㅠㅠ", "기쁨"),
        ("버스 바로 앞에서 놓쳐서 집에 늦게 왔다 ㅜ", "슬픔"),
        ("아끼던 컵을 깨뜨려서 하루 종일 마음이 안 좋았다", "슬픔"),
        ("비 와서 새 운동화 다 젖음ㅠ", "슬픔"),
        ("기대했던 공연이 취소돼서 허무하다", "슬픔"),
        ("자판기에 돈 넣었는데 음료도 안 나오고 돈도 못 돌려받음", "슬픔"),
        ("줄 서 있는데 누가 대놓고 새치기했다", "분노"),
        ("택배 상자가 완전히 찌그러져서 왔다 진짜", "분노"),
        ("내 허락도 없이 내 물건을 가져갔다", "분노"),
        ("약속 시간 한 시간 지나서 취소한다고 통보함", "분노"),
        ("내가 한 일을 자기 공으로 돌렸다", "분노"),
        ("내일 결과 발표인데 계속 신경 쓰여 잠이 안 온다", "불안"),
        ("엄마가 늦는데 연락이 안 와서 계속 휴대폰만 보고 있다", "불안"),
        ("발표 순서가 다가오니까 심장이 두근거린다", "불안"),
        ("혹시 내가 뭔가 잘못 말했나 계속 생각난다", "불안"),
        ("내일 발표 생각만 하면 심장이 뛰고 잠이 안 온다", "불안"),
        ("비행기 시간이 촉박해서 놓칠까 봐 초조하다", "불안"),
        ("단톡방에서 내 말만 계속 읽씹했다", "상처"),
        ("친구들이 나만 빼고 여행을 갔다는 걸 알았다", "상처"),
        ("사람들 앞에서 나를 비웃었다", "상처"),
        ("내 노력을 다른 사람과 비교해서 너무 서운했다", "상처"),
        ("믿었던 친구가 뒤에서 내 욕을 했다", "상처"),
        ("자판기에서 음료가 갑자기 두 개나 나왔다", "당황"),
        ("모르는 사람이 갑자기 내 이름을 불렀다", "당황"),
        ("회의 중에 갑자기 발표해 보라고 했다", "당황"),
        ("열어 보니 주문한 것과 전혀 다른 물건이 들어 있었다", "당황"),
        ("친구가 갑자기 고백해서 뭐라 말해야 할지 모르겠다", "당황"),
        ("오늘 회의는 세 번 있었고 점심은 김밥이었다", UNCERTAIN),
        ("슬픔이라는 단어를 노트에 적었다", UNCERTAIN),
        ("무서운 영화를 봤지만 별 생각 없었다", UNCERTAIN),
        ("오늘은 그냥 평범한 하루였다", UNCERTAIN),
        ("기쁘기도 하고 불안하기도 했다", UNCERTAIN),
    ],
)
def test_fake_classifier_product_regression_pack(text, expected):
    label, scores = FakeClassifier().classify(text)

    assert label == expected
    if expected != UNCERTAIN:
        assert scores[expected] == max(scores.values())


def test_get_classifier_reuses_one_local_instance_per_worker(monkeypatch):
    monkeypatch.setenv("AI_MODE", "local")
    monkeypatch.setenv("CLASSIFIER_MODEL_DIR", "C:/models/emotion-v1")
    get_settings.cache_clear()
    classifier_module._classifier_for.cache_clear()
    try:
        first = classifier_module.get_classifier()
        second = classifier_module.get_classifier()
        assert isinstance(first, LocalClassifier)
        assert first is second
        # 실제 pipeline은 첫 classify 때 한 번만 lazy load된다.
        assert first._pipeline is None
    finally:
        classifier_module._classifier_for.cache_clear()
        get_settings.cache_clear()


def test_classifier_cache_isolated_across_fake_disabled_transitions(monkeypatch):
    classifier_module._classifier_for.cache_clear()
    try:
        monkeypatch.setenv("AI_MODE", "fake")
        get_settings.cache_clear()
        assert isinstance(classifier_module.get_classifier(), FakeClassifier)

        monkeypatch.setenv("AI_MODE", "disabled")
        get_settings.cache_clear()
        assert classifier_module.get_classifier() is None

        monkeypatch.setenv("AI_MODE", "rules")
        get_settings.cache_clear()
        rules = classifier_module.get_classifier()
        assert isinstance(rules, RulesClassifier)
        assert rules.model_version == "rules-clf-1"

        monkeypatch.setenv("AI_MODE", "fake")
        get_settings.cache_clear()
        assert isinstance(classifier_module.get_classifier(), FakeClassifier)
    finally:
        classifier_module._classifier_for.cache_clear()
        get_settings.cache_clear()
