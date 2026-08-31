"""합동 수호전 「깊은 꿈」 콘텐츠 — 수호짐승 4마리의 꿈 3겹.

`docs/guardian_raid_design.md`가 확정한 계약을 코드로 옮긴다. 이 모듈은 수치와
문구의 **단일 원본**이고 판정은 하지 않는다.

핵심 계약 세 가지만 다시 적는다.

1. 상대는 적이 아니라 너무 깊이 잠든 수호짐승이다. 이기는 것이 아니라 깨워
   주는 것이라서 승패·처치 어휘를 쓰지 않는다(설계서 7장).
2. 경제 보상이 0이다. XP·씨앗·수집품을 지급하지 않으므로 이 카탈로그에는
   보상 수치가 아예 없다. 최초 1회의 기억만 남는다.
3. 역할은 분류 라벨이고 판정 코드가 읽지 않는다(성장 설계서 6.6 원칙 1).
   그래서 결정적 순간은 역할이 아니라 **효과**로 적는다 - 전원 방어가 있으면
   화려하게 넘고, 없으면 행동을 더 써서 우직하게 넘는다. 어느 쪽도 막히지 않는다.

겹별 상성표(설계서 4.5.1)는 여섯 결이 약점 2회·내성 2회씩 정확히 나오도록
짜여 있다. 감정의 우열이 아니라 편성·교대 판단을 만드는 수평 상성이며,
`validate_joint_guard_content`가 이 균형을 매번 다시 센다.
"""

from typing import Any

from app.content.expeditions.combat_identity import (
    CURRENT_KEL_MAP_VERSION,
    KEL_LABELS,
    element_kel_map,
)
from app.core.korean import korean_object, korean_subject


JOINT_GUARD_VERSION = "joint-guard-v1.1"

#: 겹 안에서 도는 능력치 약점. 결 상성이 이 콘텐츠의 본체이고 이쪽은
#: 엔진이 라운드마다 하나씩 집어 가는 기존 축이다.
AFFINITY_CYCLE = ("insight", "care", "courage", "focus")

# 겹별 기준 장벽과 라운드(설계서 4.1). 짐승별 수치 변주는 첫 출시에 넣지
# 않는다 - 학습 비용을 낮추고 밸런스 변수를 줄이기 위해서다.
LAYER_BARRIERS: tuple[int, int, int] = (70, 90, 110)
LAYER_ROUNDS = 4

# 난이도 두 단계(설계서 5.1). `겉꿈 산책`은 튜토리얼을 겸한다.
DIFFICULTIES: dict[str, dict[str, Any]] = {
    "outer_walk": {
        "name": "겉꿈 산책",
        "summary": "한 겹만 걸어요. 교대와 결정적 순간을 한 번씩 익혀요.",
        "layers": 1,
        "tutorial": True,
    },
    "three_layers": {
        "name": "세 겹의 꿈",
        "summary": "세 겹을 모두 얕게 만들어요. 순서와 교대가 중요해요.",
        "layers": 3,
        "tutorial": False,
    },
}

# 결정적 순간 3종(설계서 4.4). `optimal`은 있으면 화려하게 넘는 길이고
# `bypass`는 아무 역할도 없을 때 라운드·HP를 더 써서 넘는 길이다. 우회가
# 없는 순간은 validate가 막는다.
DECISIVE_MOMENTS: dict[str, dict[str, Any]] = {
    "big_toss": {
        "name": "크게 뒤척이기",
        "layer_index": 0,
        "round_no": 3,
        "telegraph_rounds": 2,
        "target": "all",
        "power": 2,
        "optimal": [
            {
                "effect": "guard_all",
                "text": "전원 방어 효과가 있으면 한 사람도 다치지 않아요.",
            },
            {
                "effect": "finisher",
                "text": "이미 공개된 약점으로 결정타를 넣을 수 있어요.",
            },
        ],
        "bypass": {
            "text": "각자 마음 지키기를 골라 행동 하나씩으로 막아요.",
            "cost": "행동 1회씩",
        },
    },
    "tight_hug": {
        "name": "꼭 끌어안기",
        "layer_index": 1,
        "round_no": 3,
        "telegraph_rounds": 2,
        "target": "front",
        "power": 3,
        "follow_up": {"target": "all", "power": 1, "after_rounds": 1},
        "optimal": [
            {"effect": "soothe", "text": "위력을 낮추거나 대상을 옮길 수 있어요."},
            {"effect": "guard_reflect", "text": "받아 내고 그대로 돌려줄 수 있어요."},
            {
                "effect": "heal",
                "text": "지나간 자리를 일으키기에 가장 좋은 순간이에요.",
            },
        ],
        "bypass": {
            "text": "HP로 받아 내고 다음 라운드에 회복하거나 교대로 수습해요.",
            "cost": "HP와 다음 라운드",
        },
    },
    "deep_sleeptalk": {
        "name": "깊은 잠꼬대",
        "layer_index": 2,
        "round_no": 2,
        "telegraph_rounds": 2,
        "target": "none",
        "power": 0,
        "focus_surcharge": 1,
        "optimal": [
            {
                "effect": "focus_refund",
                "text": "환급과 선충전으로 늘어난 비용을 상쇄해요.",
            },
            {"effect": "reveal", "text": "약점을 밝혀 기본 공격의 값을 올려요."},
        ],
        "bypass": {
            "text": "한 라운드를 기본 공격과 방어로 소화하고 지나보내요.",
            "cost": "라운드 1회",
        },
    },
}

# 짐승 4마리(설계서 4.5). 수치 구조는 넷이 같고 다른 것은 겹별 고정 상성과
# 연출·서사다.
BEAST_CATALOG: dict[str, dict[str, Any]] = {
    "ledger_keeper": {
        "region_code": "moss_archive",
        "name": "돌비늘 장부지기",
        "dream_scene": "페이지가 눈처럼 내리는 서고의 꿈",
        "holding": "분류 못 한 기억 장부",
        "moment_flavor": "장부지기가 몸을 뒤척이자 장부 페이지가 회오리쳐요.",
        "intents": [
            {
                "code": "page_snow",
                "name": "페이지 눈보라",
                "telegraph": "잠결에 페이지가 눈처럼 쏟아져요.",
                "target": "all",
                "power": 2,
            },
            {
                "code": "spine_lean",
                "name": "책등 기대기",
                "telegraph": "책등이 맨 앞 대원 쪽으로 기울어요.",
                "target": "front",
                "power": 2,
            },
        ],
        "sleeptalk": {
            "code": "margin_murmur",
            "name": "여백의 잠꼬대",
            "telegraph": "여백에 적힌 말이 작게 새어 나와요.",
            "target": "lowest",
            "power": 1,
        },
        "layers": [
            {"name": "겉꿈", "weak_kel": "sunny", "resist_kel": "rainy"},
            {"name": "선잠", "weak_kel": "rainy", "resist_kel": "ember"},
            {"name": "깊은 꿈", "weak_kel": "ember", "resist_kel": "moonlit"},
        ],
    },
    "echo_keeper": {
        "region_code": "echo_well",
        "name": "물거울 메아리지기",
        "dream_scene": "소리가 물결로 보이는 우물의 꿈",
        "holding": "주인 못 찾은 메아리",
        "moment_flavor": "메아리지기가 품을 좁히자 소리가 파문으로 퍼져요.",
        "intents": [
            {
                "code": "ripple_hug",
                "name": "파문 껴안기",
                "telegraph": "물결이 둥글게 번져 모두를 감싸요.",
                "target": "all",
                "power": 2,
            },
            {
                "code": "well_lean",
                "name": "두레박 기울이기",
                "telegraph": "두레박이 맨 앞 대원 쪽으로 기울어요.",
                "target": "front",
                "power": 2,
            },
        ],
        "sleeptalk": {
            "code": "half_echo",
            "name": "반쪽 메아리",
            "telegraph": "돌아오지 못한 메아리가 가장 지친 쪽에 머물러요.",
            "target": "lowest",
            "power": 1,
        },
        "layers": [
            {"name": "겉꿈", "weak_kel": "moonlit", "resist_kel": "sparkling"},
            {"name": "선잠", "weak_kel": "sparkling", "resist_kel": "mosaic"},
            {"name": "깊은 꿈", "weak_kel": "mosaic", "resist_kel": "sunny"},
        ],
    },
    "seed_keeper": {
        "region_code": "starlight_seed_vault",
        "name": "별가루 씨앗지기",
        "dream_scene": "별빛이 모래처럼 쌓이는 보관고의 꿈",
        "holding": "때가 안 된 씨앗함",
        "moment_flavor": "씨앗지기의 잠꼬대가 별가루 소용돌이로 보여요.",
        "intents": [
            {
                "code": "stardust_drift",
                "name": "별가루 흩날림",
                "telegraph": "쌓인 별가루가 잠결에 흩날려요.",
                "target": "all",
                "power": 2,
            },
            {
                "code": "shelf_tilt",
                "name": "씨앗함 기울기",
                "telegraph": "씨앗함이 맨 앞 대원 쪽으로 기울어요.",
                "target": "front",
                "power": 2,
            },
        ],
        "sleeptalk": {
            "code": "sprout_sigh",
            "name": "새싹 한숨",
            "telegraph": "아직 못 깬 씨앗이 작게 숨을 뱉어요.",
            "target": "lowest",
            "power": 1,
        },
        "layers": [
            {"name": "겉꿈", "weak_kel": "sunny", "resist_kel": "ember"},
            {"name": "선잠", "weak_kel": "rainy", "resist_kel": "moonlit"},
            {"name": "깊은 꿈", "weak_kel": "ember", "resist_kel": "sparkling"},
        ],
    },
    "record_keeper": {
        "region_code": "heartwood_observatory",
        "name": "옹이등 기록지기",
        "dream_scene": "나이테가 물결치는 관측실의 꿈",
        "holding": "완성 못 한 기록 한 장",
        "moment_flavor": "기록지기의 뒤척임이 나이테 파동으로 번져요.",
        "intents": [
            {
                "code": "ring_wave",
                "name": "나이테 파동",
                "telegraph": "나이테가 물결처럼 번져 나가요.",
                "target": "all",
                "power": 2,
            },
            {
                "code": "lamp_lean",
                "name": "옹이등 기울기",
                "telegraph": "등불이 맨 앞 대원 쪽으로 기울어요.",
                "target": "front",
                "power": 2,
            },
        ],
        "sleeptalk": {
            "code": "unfinished_line",
            "name": "미완의 한 줄",
            "telegraph": "쓰다 만 한 줄이 가장 지친 쪽을 맴돌아요.",
            "target": "lowest",
            "power": 1,
        },
        "layers": [
            {"name": "겉꿈", "weak_kel": "moonlit", "resist_kel": "mosaic"},
            {"name": "선잠", "weak_kel": "sparkling", "resist_kel": "sunny"},
            {"name": "깊은 꿈", "weak_kel": "mosaic", "resist_kel": "rainy"},
        ],
    },
}

# 승패 언어를 쓰지 않는 문구 계약(설계서 7장).
#
# 조사는 원문에 박아 두지 않는다. `씨앗함`처럼 받침으로 끝나는 이름에
# `{holding}를`이라고 써 두면 `씨앗함를`이 그대로 화면에 나간다. 이름 자리
# 뒤에 붙는 조사는 `beast_story`가 받침을 보고 고른다.
STORY_LINES = {
    "enter": (
        "{beast_subject} 꿈속에서 {holding_object} 너무 꼭 끌어안고 있어요. "
        "여섯이서 살며시 깨워 주세요."
    ),
    "layer_opened": "꿈이 한 겹 얕아졌어요.",
    "awake": (
        "{beast_subject} 깨어났어요. 품에 안고 있던 {holding_object} "
        "살며시 내려놓아요."
    ),
    "withdraw": (
        "꿈이 다시 깊어졌어요. {beast}도 탐험대도 다치지 않았어요. "
        "다음에 다시 와 주세요."
    ),
}

# 최초 1회만 열리는 기억(설계서 6장). 반복 보상이 없어 그라인딩 유인도 없다.
FIRST_CLEAR_MEMORIES = {
    "collection_prefix": "dream_",
    "title_suffix": "의 꿈을 지킨 친구",
    "all_beasts_title": "깊은 꿈의 친구",
    "return_photo": "joint_guard_return_v1",
}

BANNED_OUTCOME_WORDS = ("처치", "소멸", "죽", "쓰러뜨", "승리", "패배", "무찌")

# 짐승의 예고는 위협이 아니라 몸짓 묘사다(설계서 7장) - `장부지기가 몸을 크게
# 뒤척이려 해요`이지 `공격해요`가 아니다.
#
# 이 목록은 **짐승이 하는 일을 적는 자리에만** 적용한다. 우리 편 행동은 게임이
# 실제로 `공명 공격`이라고 부르므로, 전부에 걸면 정상 어휘까지 막힌다.
BANNED_THREAT_WORDS = ("공격", "위협", "덮쳐", "노려", "짓밟")

#: 의도 대상은 기존 세 가지뿐이다.
ALLOWED_INTENT_TARGETS = {"front", "lowest", "all"}


def beast_story(beast_code: str, key: str) -> str:
    """짐승 이름과 끌어안은 것을 채운 문구를 돌려준다.

    이름 뒤 조사는 받침을 보고 고른다 - `씨앗함을`, `장부를`.
    """
    beast = BEAST_CATALOG[beast_code]
    name = str(beast["name"])
    holding = str(beast["holding"])
    return STORY_LINES[key].format(
        beast=name,
        holding=holding,
        beast_subject=korean_subject(name),
        holding_object=korean_object(holding),
    )


def moment_code_for_layer(index: int) -> str:
    """겹 번호가 만나는 결정적 순간 코드."""
    for code, moment in DECISIVE_MOMENTS.items():
        if int(moment["layer_index"]) == index:
            return code
    raise KeyError(f"{index}겹의 결정적 순간이 없습니다")


def layers_for(beast_code: str, difficulty: str) -> list[dict[str, Any]]:
    """난이도가 정한 겹 수만큼, 장벽과 상성을 채운 겹 목록을 만든다."""
    beast = BEAST_CATALOG[beast_code]
    count = int(DIFFICULTIES[difficulty]["layers"])
    layers: list[dict[str, Any]] = []
    for index in range(count):
        layer = beast["layers"][index]
        layers.append(
            {
                "index": index,
                "name": layer["name"],
                "barrier": LAYER_BARRIERS[index],
                "max_barrier": LAYER_BARRIERS[index],
                "rounds": LAYER_ROUNDS,
                "weak_kel": layer["weak_kel"],
                "resist_kel": layer["resist_kel"],
                "weak_kel_label": KEL_LABELS[layer["weak_kel"]],
                "resist_kel_label": KEL_LABELS[layer["resist_kel"]],
                "moment_code": moment_code_for_layer(index),
            }
        )
    return layers


def layer_warning(beast_code: str, layer_index: int) -> dict[str, Any] | None:
    """겹에 들어설 때 미리 알려야 하는 결정적 순간.

    `깊은 잠꼬대`는 2라운드에 오는데 예고는 2라운드 전이다. 라운드 0은 없으므로
    이 예고는 **겹에 들어서는 순간** 나가야 한다. 라운드 안에 자리가 있는
    순간은 여기서 None이고 `round_schedule`이 대신 들고 있다.

    둘 중 어느 쪽으로도 알리지 못하는 순간이 생기면 예고 없는 큰 패턴이 되므로
    `validate_joint_guard_content`가 막는다.
    """
    moment = DECISIVE_MOMENTS[moment_code_for_layer(layer_index)]
    warn_round = int(moment["round_no"]) - int(moment["telegraph_rounds"])
    if warn_round >= 1:
        return None
    beast = BEAST_CATALOG[beast_code]
    return {
        "code": moment_code_for_layer(layer_index),
        "name": moment["name"],
        "in_rounds": int(moment["round_no"]),
        "text": beast["moment_flavor"],
        "bypass": moment["bypass"]["text"],
    }


def round_schedule(beast_code: str, layer_index: int) -> list[dict[str, Any]]:
    """한 겹의 라운드별 의도를 미리 펼쳐 둔다.

    기존 전투 엔진은 `intents[round_index % len(intents)]`로 이번 라운드의
    의도를 고른다. 그래서 겹의 라운드 수만큼 목록을 만들어 두면 결정적 순간을
    **정해진 라운드에 그대로 얹을 수 있다** - 엔진을 고치지 않고도 순간의
    시점이 콘텐츠가 정한 대로 온다.

    돌아오는 각 항목은 그 라운드의 주 의도이고, 결정적 순간인 라운드에는
    `moment_code`와 예고 문구가 함께 붙는다. 선잠부터는 `sleeptalk`이 함께
    실려 앱이 예고를 두 줄로 읽는다(설계서 4.3).
    """
    beast = BEAST_CATALOG[beast_code]
    mains = list(beast["intents"])
    moment_code = moment_code_for_layer(layer_index)
    moment = DECISIVE_MOMENTS[moment_code]
    moment_round = int(moment["round_no"])
    # 선잠(1겹)부터 잠꼬대가 붙는다. 겉꿈은 기본 루프만 익히는 자리다.
    with_sleeptalk = layer_index >= 1

    schedule: list[dict[str, Any]] = []
    for round_no in range(1, LAYER_ROUNDS + 1):
        if round_no == moment_round and moment["target"] != "none":
            entry: dict[str, Any] = {
                "code": moment_code,
                "name": moment["name"],
                "telegraph": beast["moment_flavor"],
                "target": moment["target"],
                "power": int(moment["power"]),
            }
        elif round_no == moment_round:
            # 위력이 없는 순간(깊은 잠꼬대)은 때리지 않고 다음 라운드의 비용을
            # 올린다. 그 라운드의 주 의도는 그대로 오되 순간이 함께 걸린다.
            entry = dict(mains[(round_no - 1) % len(mains)])
            entry["focus_surcharge_next_round"] = int(
                moment.get("focus_surcharge", 0)
            )
        else:
            entry = dict(mains[(round_no - 1) % len(mains)])

        entry["round_no"] = round_no
        # `꼭 끌어안기`는 다음 라운드에 여운이 한 번 더 온다. 순간을 넘긴 뒤
        # 바로 숨을 돌릴 수 없다는 것이 이 순간의 설계다 - 빠뜨리면 선잠이
        # 겉꿈과 같은 무게가 된다.
        follow_up = moment.get("follow_up")
        if follow_up and round_no == moment_round + int(follow_up["after_rounds"]):
            entry["follow_up_from"] = {
                "code": moment_code,
                "name": moment["name"],
                "target": follow_up["target"],
                "power": int(follow_up["power"]),
            }
        if round_no == moment_round:
            entry["moment_code"] = moment_code
            entry["moment_name"] = moment["name"]
        # 순간은 2라운드 전에 예고된다. 예고 없이 오는 큰 패턴은 없다.
        if round_no == moment_round - int(moment["telegraph_rounds"]):
            entry["moment_warning"] = {
                "code": moment_code,
                "name": moment["name"],
                "in_rounds": int(moment["telegraph_rounds"]),
                "text": beast["moment_flavor"],
                "bypass": moment["bypass"]["text"],
            }
        if with_sleeptalk:
            entry["sleeptalk"] = dict(beast["sleeptalk"])
        schedule.append(entry)
    return schedule


def _element_for_kel(kel: str) -> str:
    """결 하나를 대표하는 속성 코드.

    전투 엔진은 약점·내성을 속성으로 들고 다니고 결은 거기서 파생한다. 속성
    여럿이 같은 결로 모이므로 대표 하나를 **정렬해서** 고른다 - 사전순 첫
    번째면 매핑이 늘어나도 같은 값이 나온다.
    """
    mapping = element_kel_map(CURRENT_KEL_MAP_VERSION)
    candidates = sorted(
        element for element, mapped in mapping.items() if mapped == kel
    )
    if not candidates:
        raise KeyError(f"{kel} 결에 해당하는 속성이 없습니다")
    return candidates[0]


def layer_encounter(
    beast_code: str,
    difficulty: str,
    layer_index: int,
) -> dict[str, Any]:
    """겹 하나를 기존 전투 엔진이 읽는 encounter로 편다.

    합동 수호전은 별도 전투 엔진을 두지 않는다. 겹마다 수호자 전투를 하나
    세우고, 라운드별 의도를 미리 펼쳐 넘긴다. 그래서 방어·빈틈·피해 상한처럼
    이미 검증된 규칙이 그대로 적용된다.
    """
    beast = BEAST_CATALOG[beast_code]
    layer = layers_for(beast_code, difficulty)[layer_index]
    return {
        "enemy_name": beast["name"],
        "enemy_max_guard": int(layer["barrier"]),
        "max_rounds": int(layer["rounds"]),
        "starting_focus": 3,
        "max_focus": 5,
        "weakness_cycle": list(AFFINITY_CYCLE),
        "weak_element": _element_for_kel(str(layer["weak_kel"])),
        "resist_element": _element_for_kel(str(layer["resist_kel"])),
        "contact_material": "paper",
        "intents": round_schedule(beast_code, layer_index),
    }


def validate_joint_guard_content() -> list[str]:
    """설계서 10장의 콘텐츠 검사를 코드로 지킨다."""
    errors: list[str] = []

    if len(BEAST_CATALOG) != 4:
        errors.append(
            f"joint_guard.beasts: 4마리여야 합니다 (현재 {len(BEAST_CATALOG)})"
        )

    regions = [beast["region_code"] for beast in BEAST_CATALOG.values()]
    if len(set(regions)) != len(regions):
        errors.append("joint_guard.beasts: 지역이 겹치면 안 됩니다")

    weak_counts: dict[str, int] = {kel: 0 for kel in KEL_LABELS}
    resist_counts: dict[str, int] = {kel: 0 for kel in KEL_LABELS}

    for code, beast in BEAST_CATALOG.items():
        layers = beast.get("layers") or []
        if len(layers) != 3:
            errors.append(f"joint_guard.{code}.layers: 3겹이어야 합니다")
            continue
        for index, layer in enumerate(layers):
            where = f"joint_guard.{code}.layers[{index}]"
            weak = layer.get("weak_kel")
            resist = layer.get("resist_kel")
            if weak not in KEL_LABELS:
                errors.append(f"{where}.weak_kel: 여섯 성장결 중 하나여야 합니다")
                continue
            if resist not in KEL_LABELS:
                errors.append(f"{where}.resist_kel: 여섯 성장결 중 하나여야 합니다")
                continue
            if weak == resist:
                errors.append(f"{where}: 약점과 내성이 같을 수 없습니다")
            weak_counts[weak] += 1
            resist_counts[resist] += 1

    # 여섯 결이 약점 2회·내성 2회씩 정확히 나온다. 어느 결도 유리하거나
    # 불리하지 않아야 편성이 취향의 문제로 남는다.
    for kel, label in KEL_LABELS.items():
        if weak_counts[kel] != 2:
            errors.append(
                f"joint_guard.balance: {korean_subject(label)} 약점으로 2번 "
                f"나와야 합니다 (현재 {weak_counts[kel]}번)"
            )
        if resist_counts[kel] != 2:
            errors.append(
                f"joint_guard.balance: {korean_subject(label)} 내성으로 2번 "
                f"나와야 합니다 (현재 {resist_counts[kel]}번)"
            )

    # 겹마다 결정적 순간이 정확히 하나씩 있고, 우회 경로가 반드시 있다.
    covered = sorted(int(m["layer_index"]) for m in DECISIVE_MOMENTS.values())
    if covered != [0, 1, 2]:
        errors.append("joint_guard.moments: 겹마다 결정적 순간이 하나씩 있어야 합니다")
    for code, moment in DECISIVE_MOMENTS.items():
        where = f"joint_guard.moments.{code}"
        if not moment.get("optimal"):
            errors.append(f"{where}.optimal: 역할별 최적 대응이 필요합니다")
        bypass = moment.get("bypass") or {}
        if not bypass.get("text"):
            errors.append(f"{where}.bypass: 역할이 없어도 통하는 우회가 필요합니다")
        if int(moment.get("round_no", 0)) > LAYER_ROUNDS:
            errors.append(f"{where}.round_no: 겹의 라운드 수를 넘을 수 없습니다")
        if int(moment.get("telegraph_rounds", 0)) < 1:
            errors.append(f"{where}.telegraph_rounds: 미리 알려 주어야 합니다")
        # 라운드 안에서 예고할 자리가 없으면 겹 입장에서 알려야 한다. 둘 다
        # 안 되면 예고 없이 오는 큰 패턴이 된다.
        layer_index = int(moment["layer_index"])
        warn_round = int(moment["round_no"]) - int(moment["telegraph_rounds"])
        if warn_round < 1:
            announced = all(
                layer_warning(beast_code, layer_index) is not None
                for beast_code in BEAST_CATALOG
            )
            if not announced:
                errors.append(f"{where}: 예고할 자리가 없습니다")

    # 의도는 기존 어휘(front|lowest|all)만 쓴다. 새 종류를 만들면 구버전
    # 사용자가 다시 배워야 하고, 앱의 예고 표시도 갈라진다(설계서 4.3).
    seen_intent_codes: set[str] = set()
    for code, beast in BEAST_CATALOG.items():
        intents = beast.get("intents") or []
        sleeptalk = beast.get("sleeptalk") or {}
        if len(intents) < 2:
            errors.append(f"joint_guard.{code}.intents: 주 의도가 둘 이상이어야 합니다")
        if not sleeptalk:
            errors.append(f"joint_guard.{code}.sleeptalk: 잠꼬대 의도가 필요합니다")
        for intent in [*intents, sleeptalk]:
            if not intent:
                continue
            where = f"joint_guard.{code}.intents.{intent.get('code')}"
            if intent.get("target") not in ALLOWED_INTENT_TARGETS:
                errors.append(
                    f"{where}.target: "
                    f"{'|'.join(sorted(ALLOWED_INTENT_TARGETS))} 중 하나여야 합니다"
                )
            power = int(intent.get("power", 0))
            if not 1 <= power <= 3:
                errors.append(f"{where}.power: 1~3 사이여야 합니다 (현재 {power})")
            intent_code = str(intent.get("code", ""))
            if intent_code in seen_intent_codes:
                errors.append(f"{where}.code: 의도 코드가 겹칩니다")
            seen_intent_codes.add(intent_code)
        # 잠꼬대는 주 의도보다 약하다. 더 세면 예고 두 줄의 우선순위가 뒤집힌다.
        if intents and sleeptalk:
            weakest_main = min(int(i.get("power", 0)) for i in intents)
            if int(sleeptalk.get("power", 0)) > weakest_main:
                errors.append(
                    f"joint_guard.{code}.sleeptalk.power: "
                    "주 의도보다 약해야 합니다"
                )

    if list(LAYER_BARRIERS) != sorted(LAYER_BARRIERS):
        errors.append("joint_guard.barriers: 겹이 깊어질수록 두꺼워야 합니다")

    if not any(spec["tutorial"] for spec in DIFFICULTIES.values()):
        errors.append("joint_guard.difficulties: 연습용 난이도가 하나 필요합니다")

    # 승패·처치 어휘 금지. 짐승은 적이 아니라 깨워 주는 상대다.
    texts: list[tuple[str, str]] = [
        (f"story.{key}", value) for key, value in STORY_LINES.items()
    ]
    beast_texts: list[tuple[str, str]] = []
    for code, beast in BEAST_CATALOG.items():
        for key in ("dream_scene", "holding", "moment_flavor", "name"):
            texts.append((f"{code}.{key}", str(beast.get(key, ""))))
        beast_texts.append((f"{code}.moment_flavor", str(beast.get("moment_flavor", ""))))
        for intent in [*(beast.get("intents") or []), beast.get("sleeptalk") or {}]:
            if not intent:
                continue
            texts.append((f"{code}.intent.name", str(intent.get("name", ""))))
            texts.append(
                (f"{code}.intent.telegraph", str(intent.get("telegraph", "")))
            )
            beast_texts.append((f"{code}.intent.name", str(intent.get("name", ""))))
            beast_texts.append(
                (f"{code}.intent.telegraph", str(intent.get("telegraph", "")))
            )
    for code, moment in DECISIVE_MOMENTS.items():
        texts.append((f"moments.{code}.name", str(moment["name"])))
        texts.append((f"moments.{code}.bypass", str(moment["bypass"]["text"])))
        for entry in moment["optimal"]:
            texts.append((f"moments.{code}.optimal", str(entry["text"])))
    for difficulty, spec in DIFFICULTIES.items():
        texts.append((f"difficulty.{difficulty}", str(spec["summary"])))
    for where, text in texts:
        for banned in BANNED_OUTCOME_WORDS:
            if banned in text:
                errors.append(f"joint_guard.{where}: 금지 표현 '{banned}'")
    for where, text in beast_texts:
        for banned in BANNED_THREAT_WORDS:
            if banned in text:
                errors.append(f"joint_guard.{where}: 위협 어휘 '{banned}'")

    return errors
