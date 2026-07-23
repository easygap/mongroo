"""안전 레이어. LLM 앞뒤를 모두 통과하며 fail-closed로 동작한다 (design.md 6.3).

- 입력 검사: normal | concern | imminent 라우팅. 내부 값이며 진단·위험등급이 아니다.
- 출력 가드: 진단/처방/거짓 안심 등 금지 표현 차단.
- 일반 감정 분류 결과는 여기서 사용하지 않는다(보조 신호로도 P0에서는 미사용).
"""

import re
from dataclasses import dataclass, field

DETECTOR_VERSION = "safety-rules-2026.07.4"

_ROUTE_RANK = {"normal": 0, "concern": 1, "imminent": 2}

# 즉각적 위험: 구체적 계획·시도·수단 언급
_IMMINENT_PATTERNS = [
    (
        re.compile(
            r"(자살|스스로\s*목숨)[^.!?\n。！？]{0,20}"
            r"(하려|할\s*거|계획|준비|시도)"
        ),
        "SI_PLAN",
    ),
    (re.compile(r"(죽으려고|죽을\s*방법|목숨을\s*끊)"), "SI_METHOD"),
    (re.compile(r"(유서)[^.!?\n。！？]{0,10}(쓰|썼|남기)"), "SI_NOTE"),
    (re.compile(r"(뛰어내리|목을\s*매|약을\s*(한꺼번에|모아서)\s*먹)"), "SI_MEANS"),
]

# 우려 신호: 죽음·자해 언급, 소극적 희사(希死) 표현
_CONCERN_PATTERNS = [
    (
        re.compile(r"(죽고\s*싶|죽어\s*버리고|사라지고\s*싶|없어지고\s*싶)"),
        "SI_PASSIVE",
    ),
    (re.compile(r"(자해|손목을\s*긋|몸에\s*상처를\s*내)"), "SELF_HARM"),
    (re.compile(r"(살\s*이유가\s*없|살기\s*싫|삶을\s*포기)"), "SI_IDEATION"),
    (re.compile(r"(다\s*끝내고\s*싶|모든\s*걸\s*끝내)"), "SI_ENDING"),
]

# 분노의 강도가 아니라 실행 의도·계획·수단을 본다. 욕설이나
# "죽이고 싶다"같은 비구체적 표현만으로는 안전 경로를 열지 않는다.
_VIOLENCE_IMMINENT_PATTERNS = [
    (
        re.compile(
            r"(칼|흉기|총|망치|둔기)[^.!?\n。！？]{0,40}"
            r"(죽이|죽일|죽여\s*버리|찌르|찌를|해치|해칠|공격하|공격할|때리|때릴)"
            r"(?:[^.!?\n。！？]{0,12}(거야|거다|거라고|려고|하러|계획)|"
            r"겠(?:다|어|다고))"
        ),
        "VIOLENCE_PLAN_MEANS",
    ),
    (
        re.compile(
            r"(죽이려고|찌르려고|해치려고|공격하려고|때리려고)"
            r"[^.!?\n。！？]{0,40}(칼|흉기|총|망치|둔기)"
            r"[^.!?\n。！？]{0,16}"
            r"(챙|준비|샀|들고|갖고)"
        ),
        "VIOLENCE_PLAN_MEANS",
    ),
]

_VIOLENCE_CONCERN_PATTERNS = [
    (
        re.compile(
            r"(죽일|해칠|찌를|공격할|패\s*죽일)\s*"
            r"(거야|거다|거라고|생각이야|계획이야)"
        ),
        "VIOLENCE_INTENT",
    ),
    (
        re.compile(
            r"(죽이|죽여\s*버리|해치|찌르|공격하|때리|패\s*죽이)"
            r"겠(?:다|어|다고)"
        ),
        "VIOLENCE_INTENT",
    ),
    (
        re.compile(
            r"(죽여\s*버릴|해쳐\s*버릴|찔러\s*버릴|때려\s*버릴)\s*"
            r"(거야|거다|거라고|생각이야|계획이야)"
        ),
        "VIOLENCE_INTENT",
    ),
    (
        re.compile(
            r"(죽이|해치|찌르|공격하|패\s*죽이)[^.!?\n。！？]{0,16}"
            r"(계획했|준비했|하러\s*갈|찾아갈)"
        ),
        "VIOLENCE_INTENT",
    ),
]

_VIOLENCE_LANGUAGE = (
    r"(?:죽이|죽일|죽여\s*버리|해치|해칠|찌르|찌를|공격하|공격할|"
    r"때리|때릴|패\s*죽이|패\s*죽일)"
)

# 제지 표현은 위해 문구 뒤에 이어질 때만 인정한다. 문장 앞의 unrelated
# "없다/참았다"가 뒤쪽의 실제 실행 의도를 가리지 않도록 범위를 묶는다.
_VIOLENCE_RESTRAINT_PATTERNS = [
    re.compile(
        rf"{_VIOLENCE_LANGUAGE}[^.!?\n。！？]{{0,80}}"
        r"(?:(실제로는|진짜로는)[^.!?\n。！？]{0,16}(그럴|할)\s*생각이\s*없|"
        r"(그러지|하지)\s*않(?:았|겠|고)|"
        r"참았(?:다|어)|참는다|참겠다|참기로\s*했|"
        r"말로만|농담|과장해서|화가\s*나서\s*한\s*말)"
    ),
]

# 부정문·인용·제3자 언급이면 한 단계 완화한다. 단, 각 완화 단서는
# 위험 표현과 같은 구절에 있어야 한다.
_HARM_LANGUAGE = (
    r"(?:죽고\s*싶|죽으려고|죽을\s*방법|목숨을\s*끊|자살|자해|"
    r"손목을\s*긋|몸에\s*상처를\s*내|사라지고\s*싶|없어지고\s*싶|"
    r"살기\s*싫|삶을\s*포기|다\s*끝내고\s*싶|모든\s*걸\s*끝내|"
    rf"{_VIOLENCE_LANGUAGE})"
)
_SOFTENER_PATTERNS = [
    (
        re.compile(
            rf"(?:{_HARM_LANGUAGE}\s*지\s*않|"
            rf"{_HARM_LANGUAGE}[^.!?\n。！？]{{0,45}}(?:들지\s*않|"
            r"생각(?:은|이)?\s*없|마음(?:은|이)?\s*없|"
            r"의도(?:는|가)?\s*없|계획(?:은|이)?\s*없|원하지\s*않))"
        ),
        "NEGATED",
    ),
    (
        re.compile(
            rf"(?:['\"“][^'\"”]{{0,100}}{_HARM_LANGUAGE}[^'\"”]{{0,100}}['\"”]|"
            rf"{_HARM_LANGUAGE}[^.!?\n。！？]{{0,30}}(?:라는\s*(?:말|글|기사|노래)|"
            r"고\s*하더라|다고\s*(?:했|들었)))"
        ),
        "QUOTED",
    ),
    (
        re.compile(
            rf"(?:친구가|동생이|엄마가|아빠가|지인이|동료가|"
            rf"그\s*사람이|주인공이)[^.!?\n。！？]{{0,35}}{_HARM_LANGUAGE}"
        ),
        "THIRD_PARTY",
    ),
]

SUPPORT_RESOURCES = [
    {"label": "자살예방 상담전화", "phone": "109"},
    {"label": "정신건강 위기상담", "phone": "1577-0199"},
    {"label": "긴급 상황", "phone": "112"},
]

_SUPPORT_MESSAGE = (
    "이야기해 줘서 고마워요. 이 안내는 감정을 판단하거나 불이익을 주기 위한 것이 아니에요. "
    "혼자 견디지 않아도 됩니다. "
    "아래 연락처에서 바로 도움을 받을 수 있어요."
)
_IMMINENT_MESSAGE = (
    "지금 위험한 상황이라면 즉시 112 또는 119에 연락해 주세요. "
    "이 안내는 감정을 판단하거나 불이익을 주기 위한 것이 아니에요."
)
_VIOLENCE_SUPPORT_MESSAGE = (
    "지금 누군가 다칠 가능성이 있다면 상대와 위험한 물건에서 거리를 두고 "
    "112 또는 119에 연락해 주세요. 분노 자체를 잘못된 감정으로 판단하지 않아요."
)
_PRIOR_SUPPORT_MESSAGE = (
    "이전 대화에서 확인한 안전 안내를 이어갈게요. 감정을 잘못됐다고 판단하는 "
    "안내가 아니에요. 지금 본인이나 다른 사람이 다칠 가능성이 있다면 "
    "112 또는 119에 연락하고, 아래 상담 창구의 도움을 받아 주세요."
)


@dataclass
class SafetyResult:
    route: str  # normal | concern | imminent
    reason_codes: list[str] = field(default_factory=list)

    @property
    def flagged(self) -> bool:
        return self.route != "normal"


def _apply_prior_state(result: SafetyResult, prior_state: str) -> SafetyResult:
    """한 번 확인한 세션 안전 수준을 하한으로 유지해 다음 턴의 LLM 재진입을 막는다."""
    # 알 수 없는 저장값도 fail-closed로 concern으로 취급한다.
    prior_route = prior_state if prior_state in _ROUTE_RANK else "concern"
    if _ROUTE_RANK[prior_route] > _ROUTE_RANK[result.route]:
        return SafetyResult(prior_route, [*result.reason_codes, "PRIOR_STATE"])
    return result


def _softeners_for_signal(text: str, signal: re.Match[str]) -> list[str]:
    """해당 위험 표현을 실제로 감싸는 완화 단서만 돌려준다."""
    codes: list[str] = []
    for pattern, code in _SOFTENER_PATTERNS:
        if any(
            cue.start() <= signal.start() < cue.end() for cue in pattern.finditer(text)
        ):
            codes.append(code)
    return codes


def _restraints_for_signal(text: str, signal: re.Match[str]) -> list[str]:
    if any(
        cue.start() <= signal.start() < cue.end()
        for pattern in _VIOLENCE_RESTRAINT_PATTERNS
        for cue in pattern.finditer(text)
    ):
        return ["VIOLENCE_RESTRAINT"]
    return []


def check_text(text: str | None, prior_state: str = "normal") -> SafetyResult:
    """동기식 입력 검사. 이전 안전 신호(prior_state)가 있으면 concern 이상을 유지한다."""
    if not text:
        return _apply_prior_state(SafetyResult("normal"), prior_state)

    candidates: list[SafetyResult] = []

    for pattern, code in _IMMINENT_PATTERNS:
        for signal in pattern.finditer(text):
            softeners = _softeners_for_signal(text, signal)
            # 즉각 위험 신호는 인용/제3자라도 concern 밑으로 낮추지 않는다 (fail-closed)
            if softeners:
                candidates.append(SafetyResult("concern", [code, *softeners]))
            else:
                candidates.append(SafetyResult("imminent", [code]))

    for pattern, code in _VIOLENCE_IMMINENT_PATTERNS:
        for signal in pattern.finditer(text):
            softeners = _softeners_for_signal(text, signal)
            restraint_codes = _restraints_for_signal(text, signal)
            # 계획·수단이 있던 표현은 제지 단서가 있어도 지원 경로를 남긴다.
            if softeners or restraint_codes:
                candidates.append(
                    SafetyResult("concern", [code, *softeners, *restraint_codes]),
                )
            else:
                candidates.append(SafetyResult("imminent", [code]))

    for pattern, code in _VIOLENCE_CONCERN_PATTERNS:
        for signal in pattern.finditer(text):
            softeners = _softeners_for_signal(text, signal)
            restraint_codes = _restraints_for_signal(text, signal)
            if softeners or restraint_codes:
                candidates.append(
                    SafetyResult(
                        "normal",
                        [code, *softeners, *restraint_codes, "SOFTENED"],
                    )
                )
            else:
                candidates.append(SafetyResult("concern", [code]))

    for pattern, code in _CONCERN_PATTERNS:
        for signal in pattern.finditer(text):
            softeners = _softeners_for_signal(text, signal)
            if softeners:
                candidates.append(
                    SafetyResult("normal", [code, *softeners, "SOFTENED"]),
                )
            else:
                candidates.append(SafetyResult("concern", [code]))

    if not candidates:
        return _apply_prior_state(SafetyResult("normal"), prior_state)
    route = max(candidates, key=lambda result: _ROUTE_RANK[result.route]).route
    # 완화된 다른 구절의 이유 코드가 실제로 라우팅을 만든 신호의 지원 화면을
    # 바꾸지 않도록, 최종 라우팅과 같은 후보의 코드만 합친다.
    reason_codes = list(
        dict.fromkeys(
            code
            for result in candidates
            if result.route == route
            for code in result.reason_codes
        )
    )
    return _apply_prior_state(SafetyResult(route, reason_codes), prior_state)


def safety_action_payload(severity: str, reason_codes: list[str] | None = None) -> dict:
    codes = reason_codes or []
    # PRIOR_STATE는 현재 문장이 아니라 이전 턴이 상태 하한을 만든 경우에만 붙는다.
    # 당시 신호 종류를 추정하지 않고 양쪽 긴급·상담 자원을 모두 제공한다.
    if "PRIOR_STATE" in codes:
        return {
            "action": "show_support_screen",
            "severity": severity,
            "message": _PRIOR_SUPPORT_MESSAGE,
            "resources": [
                {"label": "경찰 긴급 신고", "phone": "112"},
                {"label": "구급·구조", "phone": "119"},
                {"label": "자살예방 상담전화", "phone": "109"},
                {"label": "정신건강 위기상담", "phone": "1577-0199"},
            ],
        }
    has_self_harm_signal = any(
        code.startswith("SI_") or code == "SELF_HARM" for code in codes
    )
    # 타해 표현이 같은 문장에 섞여도 자해·자살 신호가 함께 있으면 109를
    # 빼지 않는다. 타해 전용 문구는 타해 신호만 확인된 경우에 사용한다.
    if not has_self_harm_signal and any(code.startswith("VIOLENCE_") for code in codes):
        return {
            "action": "show_support_screen",
            "severity": severity,
            "message": _VIOLENCE_SUPPORT_MESSAGE,
            "resources": [
                {"label": "경찰 긴급 신고", "phone": "112"},
                {"label": "구급·구조", "phone": "119"},
                {"label": "정신건강 위기상담", "phone": "1577-0199"},
            ],
        }
    resources = list(SUPPORT_RESOURCES)
    if severity == "imminent":
        resources = [
            {"label": "긴급 상황", "phone": "112"},
            {"label": "구급·구조", "phone": "119"},
            {"label": "자살예방 상담전화", "phone": "109"},
            {"label": "정신건강 위기상담", "phone": "1577-0199"},
        ]
        message = _IMMINENT_MESSAGE
    else:
        message = _SUPPORT_MESSAGE
    return {
        "action": "show_support_screen",
        "severity": severity,
        "message": message,
        "resources": resources,
    }


# --- 출력 가드 -------------------------------------------------------------

GUARD_VERSION = "output-guard-2026.07.1"

_OUTPUT_BANNED = [
    (re.compile(r"(당신은|너는).{0,12}(우울증|공황장애|조울증|불안장애)"), "DIAGNOSIS"),
    (re.compile(r"(진단|처방)(을|을\s*내|해\s*드)"), "PRESCRIPTIVE"),
    (re.compile(r"약(을|은)\s*(먹|드시|끊|줄이)"), "MEDICATION"),
    (re.compile(r"(반드시|분명히|금방)\s*(낫|좋아질|괜찮아질)"), "FALSE_REASSURANCE"),
    (re.compile(r"(병원|상담|전문가).{0,10}(갈\s*필요\s*없|안\s*가도)"), "AVOID_HELP"),
    (
        re.compile(r"(우리만의\s*비밀|나한테만\s*말|아무에게도\s*말하지\s*마)"),
        "SECRECY",
    ),
    (re.compile(r"(나만\s*믿|내가\s*다\s*해결)"), "DEPENDENCY"),
    (re.compile(r"(자해|자살).{0,15}(방법|하는\s*법)"), "HARM_CONTENT"),
]


def guard_output(text: str) -> tuple[bool, list[str]]:
    """LLM 응답 검사. 실패 시 원문을 사용자에게 전달하지 않는다."""
    if not text or not text.strip():
        return False, ["EMPTY_OUTPUT"]
    codes = [code for pattern, code in _OUTPUT_BANNED if pattern.search(text)]
    return (len(codes) == 0), codes


GENERATION_FALLBACK_MESSAGE = (
    "지금은 답변을 만들지 못했어요. 잠시 후 다시 시도해 주세요. "
    "작성하신 이야기는 안전하게 저장되어 있어요."
)
