"""감정 분류기. local=파인튜닝 모델(CPU), fake=결정적 키워드 규칙 (design.md 6.1)."""

import math
import re
from functools import lru_cache
from typing import Protocol

from app.core.config import get_settings

EMOTION_LABELS = ("기쁨", "슬픔", "분노", "불안", "상처", "당황")
UNCERTAIN = "uncertain"


class ClassifierError(Exception):
    pass


class EmotionClassifier(Protocol):
    model_version: str

    def classify(self, text: str) -> tuple[str, dict[str, float]]: ...


class FakeClassifier:
    """한국어 구어체를 포함한 결정적 감정 분류기.

    단순 부분 문자열 개수만 세면 ``못 찾음`` 같은 사건 단서나 ``안 슬펐다``의
    부정을 놓치고, ``무서운 영화``처럼 감정의 *대상*을 사용자의 감정으로
    오인하기 쉽다. 이 구현은 문장 속 사건/표현 단서를 가중 합산한 뒤 부정,
    반전, 강도 표현을 반영한다. 외부 모델이 없는 demo·CI에서도 같은 문장은
    항상 같은 결과를 내면서 여러 감정의 비율을 성장 로직에 전달한다.

    이 규칙은 진단 도구가 아니다. 뚜렷한 근거가 없거나 두 감정이 동률이면
    기존 계약대로 ``uncertain``을 반환한다.
    """

    model_version = "fake-clf-3"

    # 사건의 결과를 나타내는 긴 표현부터 적용한다. 같은 감정 안에서 더 짧은
    # 어휘 단서와 겹치는 구간은 한 번만 세어 과도한 확신을 막는다.
    _EVENT_CUES: dict[str, tuple[tuple[str, float], ...]] = {
        "기쁨": (
            (r"(?:웃겨서|웃다가|웃느라).{0,8}?(?:눈물|울었|울음)", 2.6),
            (r"(?:자판기|기계).{0,18}?(?:두\s*개|하나\s*더).{0,8}?(?:나왔|받았)", 1.8),
            (r"(?:목표|일|과제|프로젝트)(?:를|을)?\s*(?:끝냈|마쳤|해냈|완료)", 2.4),
            (r"(?:문제|일|상황)(?:가|이|는|은)?\s*(?:잘\s*)?(?:해결|풀렸)", 2.3),
            (r"(?:시험|면접|오디션)(?:에|을|를)?\s*(?:합격|붙었)", 2.4),
            (r"(?:성공|성취|당첨|우승|승진|합격|해냈|이겼)", 2.0),
            (r"(?:잃어버린|잃었던|놓친)\s*.+?(?:찾았|되찾)", 2.2),
            (r"(?:칭찬|선물|상을)\s*(?:받았|받음)", 1.9),
        ),
        "슬픔": (
            (
                r"(?:떨어|빠)뜨렸(?:는데|지만|고)?.{0,24}?"
                r"(?:결국\s*)?못\s*찾(?:았|음|겠|겠어|겠다|았다)?",
                3.0,
            ),
            (r"(?:잃어버렸|분실했|도난당|사라졌)(?:어|다|음)?", 2.3),
            (r"(?:결국\s*)?못\s*(?:찾|구했|해냈|갔|만났)(?:다|어|음|았다)?", 2.1),
            (r"(?:시험|면접|오디션)(?:에서|에)?\s*(?:떨어졌|탈락|불합격)", 2.4),
            (r"(?:실패했|실패함|망했|놓쳤|헤어졌|이별했)", 2.1),
            (r"(?:돈|지갑|휴대폰|물건)(?:을|를)?\s*(?:잃었|잃어버)", 2.2),
            (r"(?:아끼던|소중한).{0,12}?(?:깨뜨|깨졌|망가|고장)", 2.2),
            (
                r"(?:공연|약속|여행|행사|경기).{0,10}?(?:취소|무산).{0,10}?(?:허무|아쉽|속상)?",
                2.0,
            ),
            (
                r"(?:자판기|기계).{0,18}?(?:안\s*나오|먹통).{0,18}?(?:못\s*(?:돌려받|환불)|돈도)",
                2.4,
            ),
            (r"(?:버스|지하철|기차|비행기).{0,12}?(?:놓쳤|놓침)", 1.9),
            (r"(?:옷|신발|운동화|가방).{0,10}?(?:다\s*)?젖", 1.7),
            (r"(?:반려|친구|가족).{0,10}?(?:세상을\s*떠났|죽었)", 2.5),
        ),
        "분노": (
            (r"(?:죽여|죽이고)\s*싶", 2.5),
            (r"(?:일|책임|잘못)(?:을|를)?\s*(?:떠넘|미뤘|뒤집어씌)", 2.2),
            (r"(?:무시|막말|욕설|갑질)(?:했|당했|하네|함)", 2.0),
            (r"(?:대놓고\s*)?새치기", 2.2),
            (
                r"(?:택배|배송|물건).{0,16}?(?:파손|찌그러|깨져서\s*왔|망가져서\s*왔)",
                2.0,
            ),
            (r"(?:허락|동의)도?\s*없이.{0,18}?(?:가져|사용|건드)", 2.2),
            (
                r"(?:약속|예약).{0,18}?(?:일방적으로\s*)?취소.{0,10}?(?:통보|한다고)",
                2.0,
            ),
            (r"(?:내가|제가)\s*한\s*일.{0,18}?(?:자기|본인)\s*(?:공|성과)", 2.4),
        ),
        "불안": (
            (r"(?:어쩌|어떡)지", 2.0),
            (r"(?:망할|늦을|떨어질|실패할|잘못될|안\s*될)까", 2.0),
            (r"(?:쫓기|위협받|위험하|불안정하)", 2.0),
            (r"(?:잠이|잠도)\s*안\s*(?:와|왔|오|온|옴|들|든)", 1.7),
            (
                r"(?:결과|합격|당락).{0,12}?(?:발표|나오).{0,18}?(?:신경\s*쓰|기다리|잠이?\s*안)",
                2.1,
            ),
            (
                r"(?:늦는데|늦었는데|한참인데).{0,18}?연락(?:이|도)?\s*안\s*(?:와|오|됨)",
                2.2,
            ),
            (
                r"(?:발표|면접|시험).{0,18}?(?:다가오|직전).{0,12}?(?:심장|가슴).{0,6}?(?:두근|뛰)",
                2.1,
            ),
            (
                r"(?:내일|곧|다가오는).{0,10}?(?:발표|면접|시험).{0,18}?"
                r"(?:생각|상상).{0,10}?(?:심장|가슴).{0,6}?(?:두근|뛰)",
                2.1,
            ),
            (r"혹시.{0,20}?(?:잘못|실수).{0,18}?(?:계속\s*)?(?:생각|떠올)", 2.0),
        ),
        "상처": (
            (r"(?:믿었|좋아했|친한).{0,18}?(?:배신|뒷담|험담)", 2.5),
            (r"(?:무시|거절|따돌림|모욕|버림)(?:을|를)?\s*당", 2.3),
            (r"(?:내\s*마음|진심)(?:을|를)?\s*(?:몰라|무시)", 2.1),
            (
                r"(?:내\s*말|메시지|카톡)(?:만|을|를)?.{0,10}?(?:읽씹|안\s*읽|답이\s*없)",
                2.2,
            ),
            (r"(?:나|저)(?:만|를)\s*빼고", 2.2),
            (r"(?:나|저)(?:를|만)?\s*(?:비웃|조롱)", 2.2),
            (r"(?:믿었던|친한).{0,12}?(?:뒤에서|몰래).{0,10}?(?:내\s*)?욕", 2.3),
        ),
        "당황": (
            (r"(?:예상|생각)도?\s*못\s*(?:했|한)", 2.0),
            (r"(?:갑자기|난데없이).{0,18}?(?:나타|벌어|말했|연락)", 1.9),
            (r"(?:말문이|머릿속이)\s*(?:막혔|하얘|새하얘)", 2.2),
            (
                r"(?:자판기|기계).{0,12}?갑자기.{0,10}?(?:두\s*개|하나\s*더).{0,8}?나",
                2.1,
            ),
            (r"모르는\s*사람.{0,16}?갑자기.{0,12}?(?:이름|나를|저를).{0,6}?불", 2.1),
            (r"(?:회의|수업).{0,12}?갑자기.{0,12}?(?:발표|말해\s*보|시켰)", 2.1),
            (r"(?:주문|시킨).{0,18}?(?:전혀|완전히)\s*다른\s*(?:물건|메뉴)", 2.2),
            (r"갑자기.{0,12}?고백.{0,18}?(?:뭐라|어떻게|모르겠)", 2.3),
        ),
    }

    _LEXICAL_CUES: dict[str, tuple[tuple[str, float], ...]] = {
        "기쁨": (
            (r"행복", 1.2),
            (r"즐거|즐거운", 1.1),
            (r"기쁘|기쁜", 1.1),
            (r"좋|개좋", 1.0),
            (r"뿌듯|설레|신나|반갑|후련", 1.2),
            (r"재밌|맛있|웃었|웃음|괜찮|안심", 1.0),
            (r"개이득|득템|횡재|웃겨|웃기", 1.2),
        ),
        "슬픔": (
            (r"슬프|슬픈|서글프", 1.2),
            (r"눈물|울었|울컥|펑펑\s*울", 1.3),
            (r"우울|허전|공허", 1.2),
            (r"그립|속상|아쉽|아깝|쓸쓸|외롭|외로운|허무", 1.1),
        ),
        "분노": (
            (r"개빡|빡치|빡쳤", 1.5),
            (r"화가|화나|화났", 1.2),
            (r"짜증|분노|억울|열받|성질나", 1.2),
            (r"개같|엿같|좆같", 1.5),
            (r"(?:ㅅㅂ|시발|씨발)", 1.4),
        ),
        "불안": (
            (r"불안|걱정|초조|긴장", 1.2),
            (r"무섭|무서운|무서웠|두렵|겁나(?:네|다|서)|떨려|떨렸", 1.2),
            (r"조마조마|안절부절|마음이\s*놓이질|신경\s*쓰여|두근거", 1.4),
        ),
        "상처": (
            (r"상처|서운|배신|실망", 1.2),
            (r"섭섭|모욕|비참|존중받지", 1.2),
        ),
        "당황": (
            (r"당황|황당|어이없|혼란|멘붕", 1.2),
            (r"놀랐|깜짝|얼떨떨|벙쪘|헉|헐", 1.0),
        ),
    }

    _CONTENT_NOUNS = re.compile(
        r"^(?:의|ㄴ|는|은|한|했던|운)?\s*(?:영화|드라마|애니|노래|책|소설|웹툰|"
        r"이야기|장면|캐릭터|제목|단어|표현|밈)"
    )
    _NEGATION_BEFORE = re.compile(r"(?:안|전혀|별로|하나도|그다지|절대)$")
    _NEGATION_AFTER = re.compile(
        r"^(?:(?:하|되)?지(?:는|도)?(?:않|못)|(?:ㄴ|는)?(?:건|게|것은)?아니|"
        r"(?:할)?필요(?:는)?없|않|못했)"
    )
    _INTENSIFIERS = re.compile(r"(?:너무|정말|진짜|완전|엄청|존나|겁나|몹시|되게)$")
    _DIMINISHERS = re.compile(r"(?:조금|살짝|약간|조금은)$")
    _CONTRAST = re.compile(r"지만|그러나|그런데|그래도|반면(?:에)?|오히려")
    _COEQUAL_MIX = re.compile(r"기도\s*하고.{0,40}?기도\s*(?:했|하|한|해)")
    _POSITIVE_TEARS = re.compile(
        r"(?:웃겨서|웃다가|웃느라|기뻐서|감동(?:해서|받아서)).{0,10}?(?:눈물|울)"
    )
    _MIN_EVIDENCE = 1.0

    @staticmethod
    def _compact(fragment: str) -> str:
        return re.sub(r"[\s,.;!?~]+", "", fragment)

    @classmethod
    def _is_negated(cls, text: str, start: int, end: int) -> bool:
        before = cls._compact(text[max(0, start - 12) : start])
        after = cls._compact(text[end : min(len(text), end + 16)])
        return bool(
            cls._NEGATION_BEFORE.search(before) or cls._NEGATION_AFTER.match(after)
        )

    @classmethod
    def _describes_content(cls, text: str, end: int) -> bool:
        """``무서운 영화``처럼 작품 수식어로 쓰인 감정 단서는 제외한다."""
        after = text[end : min(len(text), end + 12)].lstrip()
        # ``분노의 질주``처럼 감정어가 작품명 일부인 경우도 사용자 상태가 아니다.
        return (
            after.startswith("의")
            or bool(re.match(r"^(?:이?라는)\s*(?:단어|표현|제목)", after))
            or bool(cls._CONTENT_NOUNS.match(after))
        )

    @classmethod
    def _contrast_factor(cls, text: str, cue_start: int) -> float:
        matches = tuple(cls._CONTRAST.finditer(text))
        if not matches:
            return 1.0
        pivot = matches[-1]
        # ``행복했지만 동시에 불안했다``는 반전이 아니라 감정의 공존이다.
        if "동시에" in text[pivot.end() : pivot.end() + 12]:
            return 1.0
        return 0.8 if cue_start < pivot.start() else 1.25

    @classmethod
    def _intensity_factor(cls, text: str, cue_start: int) -> float:
        before = cls._compact(text[max(0, cue_start - 10) : cue_start])
        if cls._INTENSIFIERS.search(before):
            return 1.25
        if cls._DIMINISHERS.search(before):
            return 0.8
        return 1.0

    @staticmethod
    def _overlaps(span: tuple[int, int], occupied: list[tuple[int, int]]) -> bool:
        return any(span[0] < other[1] and other[0] < span[1] for other in occupied)

    @classmethod
    def _score_cues(cls, text: str) -> dict[str, float]:
        raw_scores = dict.fromkeys(EMOTION_LABELS, 0.0)
        occupied: dict[str, list[tuple[int, int]]] = {
            label: [] for label in EMOTION_LABELS
        }

        for cue_table in (cls._EVENT_CUES, cls._LEXICAL_CUES):
            for label, cues in cue_table.items():
                for pattern, weight in cues:
                    for match in re.finditer(pattern, text, flags=re.IGNORECASE):
                        span = match.span()
                        if cls._overlaps(span, occupied[label]):
                            continue
                        if cls._is_negated(text, *span):
                            continue
                        if cls._describes_content(text, span[1]):
                            continue
                        factor = cls._contrast_factor(text, span[0])
                        factor *= cls._intensity_factor(text, span[0])
                        raw_scores[label] += weight * factor
                        occupied[label].append(span)

        # ㅠ/ㅜ는 손실·속상함을 놓치지 않게 하는 강한 보조 단서다. 반면 ㅋㅋ/ㅎㅎ는
        # 부정적 문장 끝의 헛웃음으로도 자주 쓰이므로 다른 부정 단서가 없을 때만
        # 기쁨으로 센다.
        tear_matches = list(re.finditer(r"[ㅠㅜ]{1,}", text))
        if tear_matches:
            positive_tears = bool(cls._POSITIVE_TEARS.search(text))
            negative_without_sadness = sum(
                raw_scores[label]
                for label in EMOTION_LABELS
                if label not in {"기쁨", "슬픔"}
            )
            if positive_tears:
                # ``웃겨서 눈물남ㅠㅠ``의 눈물 어휘가 만든 슬픔 점수를 제거한다.
                raw_scores["슬픔"] = max(0.0, raw_scores["슬픔"] - 1.3)
                raw_scores["기쁨"] += min(1.2, 0.8 + 0.1 * len(tear_matches))
            elif raw_scores["기쁨"] >= 1.8 and negative_without_sadness == 0:
                # 합격·감동 뒤의 ㅠㅠ는 슬픔을 새로 만들지 않고 감정 강도로만 쓴다.
                raw_scores["기쁨"] += min(0.7, 0.4 + 0.1 * len(tear_matches))
            else:
                raw_scores["슬픔"] += min(2.0, 1.2 + 0.2 * len(tear_matches))

        negative_total = sum(
            raw_scores[label] for label in EMOTION_LABELS if label != "기쁨"
        )
        if negative_total == 0 and re.search(r"(?:ㅋ{2,}|ㅎ{2,})", text):
            raw_scores["기쁨"] += 0.8

        if re.search(r"(?:ㄷㄷ+|;;+)", text):
            raw_scores["당황"] += 0.8
        if cls._COEQUAL_MIX.search(text):
            present = [label for label, score in raw_scores.items() if score > 0]
            if len(present) >= 2:
                shared = max(raw_scores[label] for label in present)
                for label in present:
                    raw_scores[label] = shared
        return raw_scores

    def classify(self, text: str) -> tuple[str, dict[str, float]]:
        normalized_text = " ".join(text.strip().split())
        raw_scores = self._score_cues(normalized_text)
        total = sum(raw_scores.values())
        if total == 0:
            scores = {
                label: round(1 / len(EMOTION_LABELS), 3) for label in EMOTION_LABELS
            }
            return UNCERTAIN, scores
        scores = {
            label: round(raw_score / total, 3)
            for label, raw_score in raw_scores.items()
        }
        highest = max(scores.values())
        leaders = [label for label, score in scores.items() if score == highest]
        if len(leaders) != 1:
            return UNCERTAIN, scores
        top = leaders[0]
        if (
            raw_scores[top] < self._MIN_EVIDENCE
            or scores[top] < get_settings().classifier_abstain_threshold
        ):
            return UNCERTAIN, scores
        return top, scores


class LocalClassifier:
    """MONGROO_MODEL_ROOT의 파인튜닝 모델을 CPU에서 lazy load한다."""

    def __init__(self, model_dir: str) -> None:
        if not model_dir:
            raise ClassifierError("classifier_model_dir 미설정")
        self._model_dir = model_dir
        self._pipeline = None
        self.model_version = model_dir.replace("\\", "/").rstrip("/").split("/")[-1]

    def _load(self):
        if self._pipeline is None:
            try:
                from transformers import (
                    AutoModelForSequenceClassification,
                    AutoTokenizer,
                    pipeline,
                )
            except ImportError as exc:
                raise ClassifierError(
                    "transformers 미설치 (local-ai extra 필요)"
                ) from exc
            tokenizer = AutoTokenizer.from_pretrained(self._model_dir)
            model = AutoModelForSequenceClassification.from_pretrained(self._model_dir)
            self._pipeline = pipeline(
                "text-classification",
                model=model,
                tokenizer=tokenizer,
                device=-1,
                top_k=None,
                truncation=True,
                max_length=256,
            )
        return self._pipeline

    def classify(self, text: str) -> tuple[str, dict[str, float]]:
        results = self._load()(text)[0]
        scores = {r["label"]: round(float(r["score"]), 4) for r in results}
        highest = max(scores.values())
        leaders = [label for label, score in scores.items() if score == highest]
        if len(leaders) != 1:
            return UNCERTAIN, scores
        top = leaders[0]
        threshold = get_settings().classifier_abstain_threshold
        entropy = -sum(p * math.log(p + 1e-9) for p in scores.values())
        max_entropy = math.log(len(scores)) if scores else 1.0
        if scores[top] < threshold or entropy > 0.9 * max_entropy:
            return UNCERTAIN, scores
        return top, scores


@lru_cache(maxsize=1)
def _classifier_for(mode: str, model_dir: str) -> EmotionClassifier | None:
    """worker 프로세스에서 현재 AI 설정의 분류기 하나만 유지한다.

    local pipeline은 ``LocalClassifier`` 내부에서 lazy load되고 이후 job이 같은
    인스턴스를 재사용한다. 설정 값을 cache key로 받아 테스트/개발 중 mode 전환도
    ``get_settings.cache_clear()``만으로 오래된 분류기를 잘못 돌려주지 않는다.
    """
    if mode == "local":
        return LocalClassifier(model_dir)
    if mode == "fake":
        return FakeClassifier()
    return None


def get_classifier() -> EmotionClassifier | None:
    settings = get_settings()
    return _classifier_for(settings.ai_mode, settings.classifier_model_dir)
