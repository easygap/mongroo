from app.services.keywords import extract_keywords


def test_extract_keywords_basic():
    docs = [
        (1, "오늘 산책을 했다 산책은 즐거웠다"),
        (2, "산책하고 나서 커피를 마셨다"),
        (3, "회사 일이 많아서 야근을 했다"),
    ]
    keywords = extract_keywords(docs, top_n=5)
    assert keywords, "키워드가 추출되어야 한다"
    terms = [k["keyword"] for k in keywords]
    assert any("산책" in t for t in terms)
    top = next(k for k in keywords if "산책" in k["keyword"])
    assert 1 in top["entry_ids"]


def test_extract_keywords_empty():
    assert extract_keywords([]) == []
