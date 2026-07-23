"""리포트 키워드 추출 (design.md 6.4).

kiwipiepy가 있으면 형태소 분석 + TF-IDF, 없으면 단순 토큰 빈도로 동작한다.
"""
import math
import re
from collections import Counter

STOPWORDS_VERSION = "ko-stopwords-2026.07.1"
_STOPWORDS = {
    "오늘", "어제", "내일", "그리고", "그래서", "하지만", "그냥", "정말", "진짜", "너무",
    "조금", "많이", "계속", "요즘", "이번", "지난", "하루", "생각", "기분", "마음",
    "사람", "시간", "때문", "우리", "저는", "나는", "내가", "제가", "같다", "있다", "없다",
    "하다", "되다", "이다", "것", "수", "등", "및", "더",
}

try:
    from kiwipiepy import Kiwi

    _kiwi = Kiwi()
except ImportError:
    _kiwi = None


def _tokenize(text: str) -> list[str]:
    if _kiwi is not None:
        return [
            token.form
            for token in _kiwi.tokenize(text)
            if token.tag in ("NNG", "NNP") and len(token.form) >= 2
        ]
    # 폴백: 한글 2자 이상 토큰
    return [t for t in re.findall(r"[가-힣]{2,}", text)]


def extract_keywords(docs: list[tuple[int, str]], top_n: int = 8) -> list[dict]:
    """(entry_id, text) 목록에서 TF-IDF 상위 키워드를 뽑는다."""
    if not docs:
        return []
    doc_tokens: dict[int, list[str]] = {}
    df: Counter = Counter()
    for entry_id, text in docs:
        tokens = [t for t in _tokenize(text) if t not in _STOPWORDS]
        doc_tokens[entry_id] = tokens
        df.update(set(tokens))

    n_docs = len(docs)
    tf: Counter = Counter()
    for tokens in doc_tokens.values():
        tf.update(tokens)

    scored = {
        term: (count / sum(tf.values())) * (math.log((1 + n_docs) / (1 + df[term])) + 1)
        for term, count in tf.items()
    }
    top = sorted(scored.items(), key=lambda kv: kv[1], reverse=True)[:top_n]
    return [
        {
            "keyword": term,
            "score": round(score, 4),
            "entry_ids": [eid for eid, tokens in doc_tokens.items() if term in tokens],
        }
        for term, score in top
    ]


def analyzer_version() -> str:
    engine = "kiwi" if _kiwi is not None else "simple"
    return f"keywords-{engine}-{STOPWORDS_VERSION}"
