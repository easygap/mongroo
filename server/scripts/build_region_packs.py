"""지역 콘텐츠 팩 3종을 생성한다 — 우물정원·보관고·관측실.

기억서고 팩과 **같은 뼈대**를 쓴다. 8노드 그래프·8스테이지 구성(전투 4·이벤트
2·쉼터 1·보스 1)·지도 템플릿 2종은 이미 검증된 구조라 지역마다 새로 짤 이유가
없다. 지역이 다른 것은 **이야기와 재료**다. 그래서 뼈대는 여기 한 번 적고,
지역별로는 이름·문장·엉킴·수호자만 표로 준다.

수호자 셋은 기록서 이름이 이미 정해 두었다.

- `bellringer_chime` 물결 종지기의 종 → 우물정원의 **물결 종지기**
- `germination_gear` 발아 시계의 태엽 → 보관고의 **발아 시계**
- `ringcount_record` 나이테 관측 기록 → 관측실의 **나이테 관측자**

각 지역의 마지막 이야기는 다음 지역을 가리킨다. 기억서고가 우물정원을 가리키며
끝나는 것과 같은 방식이고, 관측실은 온실로 돌아간다.

사용법:
    python scripts/build_region_packs.py            # 실제 경로에 씀
    python scripts/build_region_packs.py --check    # 쓰지 않고 검증만
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from app.content.expeditions.tangles import TANGLE_CATALOG  # noqa: E402
from app.content.expeditions.validator import validate_content  # noqa: E402

OUT_DIR = ROOT / "app" / "content" / "expeditions" / "v1"

SCHEMA_VERSION = 1
CONTENT_VERSION = "expedition-content-v2"

# 여덟 노드의 자리와 성격. 기억서고에서 검증된 배치를 그대로 쓴다.
NODE_LAYOUT = (
    ("entrance", "entrance", 0.08, 0.50, 0, 1),
    ("first_event", "event", 0.27, 0.30, 1, 1),
    ("second_event", "event", 0.27, 0.70, 1, 1),
    ("camp", "camp", 0.48, 0.50, 1, 1),
    ("discovery", "discovery", 0.50, 0.20, 1, 2),
    ("guardian", "guardian", 0.69, 0.50, 1, 3),
    ("objective", "objective", 0.86, 0.32, 1, 2),
    ("exit", "exit", 0.94, 0.62, 0, 1),
)

BASE_EDGES = (
    ("entrance", "first_event"),
    ("entrance", "second_event"),
    ("first_event", "camp"),
    ("second_event", "camp"),
    ("camp", "discovery"),
    ("camp", "guardian"),
    ("guardian", "objective"),
    ("objective", "exit"),
)

# 갈래가 다른 두 번째 지도. 쉼터를 거치지 않고도 수호자에 닿는 길이 열린다.
CROSSROAD_EDGES = (
    ("entrance", "first_event"),
    ("entrance", "second_event"),
    ("first_event", "camp"),
    ("first_event", "discovery"),
    ("second_event", "camp"),
    ("second_event", "discovery"),
    ("camp", "guardian"),
    ("discovery", "guardian"),
    ("guardian", "objective"),
    ("objective", "exit"),
)

# 고리 모양. 두 사건을 서로 잇고 발견을 지나 돌아 나온다.
RING_EDGES = (
    ("entrance", "first_event"),
    ("entrance", "second_event"),
    ("first_event", "second_event"),
    ("first_event", "discovery"),
    ("second_event", "camp"),
    ("camp", "discovery"),
    ("discovery", "guardian"),
    ("camp", "guardian"),
    ("guardian", "objective"),
    ("objective", "exit"),
)

# 여덟 스테이지의 뼈대. (번호, 종류, 장, 이야기 단계)
STAGE_SHAPE = (
    (1, "battle", 1, "setup"),
    (2, "event", 2, "setup"),
    (3, "battle", 3, "rising"),
    (4, "battle", 4, "turn"),
    (5, "camp", 5, "rising"),
    (6, "event", 6, "truth"),
    (7, "battle", 7, "climax"),
    (8, "boss", 8, "resolution"),
)


REGIONS: dict[str, dict] = {
    # ── 메아리 우물정원 ────────────────────────────────────────────────────
    #
    # 기억서고에서 되찾은 우편의 길이 처음 닿는 곳. 이 정원은 모든 소리를
    # 돌려주는데, 그래서 답장도 돌아와 버린다. `보낸다`는 것이 무엇인지 묻는다.
    "echo_well": {
        "name": "메아리 우물정원",
        "short_name": "우물정원",
        "description": "물이 소리를 되돌려주는 정원이에요. 보낸 답장이 자꾸 돌아와, 어떻게 해야 말이 바깥으로 나가는지 배우게 돼요.",
        "recommended_stage": 3,
        "stat_cap": 8,
        "reward": {"exp": 7, "seeds": 2, "item_code": "echo_key"},
        "map_name": "메아리 우물 물길",
        "next_region": "별빛 씨앗 보관고",
        "battle_copy": (
            ("물목의 첫 매듭", "주인을 못 찾은 메아리들이 문턱에서 서로 엉켜 웅웅거려요."),
            ("튀는 물방울 떼", "매듭 사이에서 물방울이 튀어 올라 발밑을 자꾸 흐트러뜨려요."),
            ("소용돌이 종매듭", "물살이 한자리를 맴돌다 종매듭 하나로 단단히 뭉쳤어요."),
            ("고요한 방 앞", "물방울과 종매듭이 마지막 물목에 함께 모여 길을 막아요."),
        ),
        "tangles": ("knotted_echo", "splashing_droplets", "bell_knot_swirl"),
        "scenes": {
            "entrance": ("dungeon_gate", "젖은 석문", "이끼 계단이 끝나고 물소리가 시작돼요. 문턱을 넘자 발소리가 두 번씩 들려요."),
            "first_event": ("flooded_cave", "잠긴 우편함", "물에 반쯤 잠긴 우편함이 기울어 있어요. 안의 편지가 젖지 않게 꺼내야 해요."),
            "second_event": ("echo_well", "되돌아온 목소리", "우물 입구에서 누군가의 인사가 되돌아와요. 처음 낸 목소리가 누구 것인지 헷갈려요."),
            "camp": ("root_tunnel", "물뿌리 쉼터", "젖은 뿌리 사이에 마른 자리가 있어요. 여기서는 메아리가 잠깐 쉬어요."),
            "discovery": ("echo_well", "가라앉은 종", "우물 바닥에 작은 종이 가라앉아 있어요. 물결이 지날 때만 아주 옅게 울려요."),
            "guardian": ("monster_den", "종지기의 물목", "물이 한 방향으로만 흐르는 좁은 목이에요. 그 끝에 종지기가 앉아 있어요."),
            "objective": ("treasure_vault", "메아리 없는 방", "이 방에서는 소리가 돌아오지 않아요. 처음으로 말이 바깥으로 나가요."),
            "exit": ("dungeon_gate", "물길 바깥", "물소리가 등 뒤로 멀어져요. 답장이 정말 떠났어요."),
            "depths": ("지하 1층 · 물목", "지하 2층 · 잠긴 우편", "지하 2층 · 울림터", "지하 3층 · 쉼터", "지하 3층 · 우물 바닥", "지하 4층 · 종지기의 목", "지하 5층 · 고요한 방", "지상 · 물길 밖"),
        },
        "guardian": {
            "code": "bell_ringer",
            "name": "물결 종지기",
            "title": "물결 종지기",
            "text": "물목 끝에서 종지기가 몸을 일으켜요. 종이 울리기 전에 물결의 결을 읽어야 해요.",
            "attack_name": "되울림 물결",
            "telegraph": "종의 테두리가 젖어 번들거리면 되울림이 밀려와요.",
            "weak_element": "steel",
            "resist_element": "sound",
            "weakness_cycle": ["focus", "insight", "care", "courage"],
            "phases": (
                ("still_water", "잔물 수호", "물결이 멎으면 종은 자기 소리를 되감아요.", "약점을 맞히지 못한 라운드에는 수호 장벽이 2 회복돼요.", "종 아래 물이 거울처럼 잔잔해졌어요.", "rainy"),
                ("ring_tide", "울림 밀물", "울림이 겹쳐 파도가 돼요.", "전체 공격의 위력이 한 단계 높아져요.", "종소리가 물을 밀어 올리기 시작했어요.", "moonlit"),
                ("last_toll", "마지막 타종", "종지기가 마지막 한 번을 아껴 둬요.", "장벽이 얇아질수록 예고가 짧아져요.", "종지기가 손잡이를 두 손으로 붙잡았어요.", "sparkling"),
            ),
            # 되울림은 막지 못한 순간을 표식으로 남기고, 약점을 못 맞히면
            # 종이 스스로 장벽을 되감는다.
            "mechanics": (("expose", 2), ("repairing_index", 1), ("focus_leak", 3)),
            "intents": (
                ("toll_sweep", "종 돌리기", "종이 천천히 돌아요. 맨 앞 대원을 노려요.", "front", 2, "wood"),
                ("drown_peal", "깊은 타종", "낮은 울림이 물 전체로 번져요. 탐험대 전체를 덮쳐요.", "all", 1, "stone"),
                ("undertow", "되감는 물살", "물이 발목을 잡아끌어요. 가장 지친 대원을 노려요.", "lowest", 2, "water"),
            ),
            "choices": (
                ("read_ripples", "물결의 결을 읽어 종의 박자를 어긋낸다", "insight", "insight_arc"),
                ("hold_together", "손을 맞잡아 되울림을 함께 버틴다", "care", "care_vines"),
                ("step_back", "안전한 자리까지 물러난다", None, None),
            ),
        },
        "events": (
            {
                "code": "flooded_post",
                "title": "잠긴 우편함",
                "text": "우편함이 기울어 물이 차오르고 있어요. 편지를 어떻게 꺼낼까요?",
                "choices": (
                    ("tilt_slowly", "기울기를 천천히 되돌려 물을 흘려보낸다", "focus"),
                    ("read_first", "젖기 전에 겉면부터 읽어 둔다", "insight"),
                    ("leave_mark", "표식만 남기고 물러선다", None),
                ),
                "stage_title": "잠긴 우편함",
                "stage_summary": "물이 차오르는 우편함에서 편지를 어떻게 꺼낼지 골라요.",
            },
            {
                "code": "returning_voice",
                "title": "되돌아온 목소리",
                "text": "우물이 방금 낸 목소리를 그대로 돌려줘요. 어느 쪽이 진짜인지 어떻게 가릴까요?",
                "choices": (
                    ("count_beats", "돌아오는 박자를 세어 거리를 잰다", "focus"),
                    ("call_name", "서로의 이름을 불러 답을 맞춰 본다", "care"),
                    ("stay_quiet", "아무 말도 하지 않고 지나간다", None),
                ),
                "stage_title": "되돌아온 목소리",
                "stage_summary": "메아리와 진짜 목소리를 가르는 방법을 골라요.",
            },
        ),
        "discovery": {
            "code": "sunken_bell",
            "title": "가라앉은 종",
            "text": "우물 바닥의 작은 종은 물결이 지날 때만 울려요. 탐험대는 그 박자를 손등으로 따라 두드려 봐요.",
        },
        "thread": {
            "code": "echo_returning_letter",
            "seed": "보낸 인사가 한 박자 늦게 돌아와요. 아직 아무 데도 가지 못한 소리예요.",
            "echo": "우편함과 우물에서 같은 늦음이 반복돼요. 이 정원은 무엇도 내보내지 않아요.",
            "payoff": "메아리 없는 방에서 처음으로 목소리가 돌아오지 않아요. 답장이 정말 떠났어요.",
        },
        "stories": (
            ("echo_first_delay", "한 박자 늦은 인사", "물목을 넘자 인사가 한 박자 늦게 돌아와요. 이 정원은 소리를 돌려주기만 해요."),
            ("echo_wet_address", "젖어도 남은 주소", "젖은 편지에서 글자는 번졌는데 주소만 또렷해요. 받는 이는 여전히 마음정원의 친구들이에요."),
            ("echo_two_voices", "겹친 두 목소리", "메아리와 진짜 목소리가 겹쳐 들려요. 누구의 말인지 가리는 법을 배워요."),
            ("echo_bell_under", "물 아래의 박자", "가라앉은 종이 물결마다 한 번씩 울려요. 정원 전체가 같은 박자로 숨 쉬고 있었어요."),
            ("echo_quiet_rest", "잠깐 멎은 물", "쉼터에서는 메아리가 쉬어요. 돌아오지 않는 잠깐 동안 서로의 말이 또렷해져요."),
            ("echo_why_returns", "돌아오는 이유", "이 정원은 답장을 붙잡는 게 아니라, 받는 이를 못 찾아 되돌려보내고 있었어요."),
            ("echo_open_the_throat", "물목을 여는 법", "종지기의 박자를 어긋내면 물이 한 방향으로 흘러요. 길이 열리기 시작해요."),
            ("echo_letter_leaves", "떠난 답장", "메아리 없는 방에서 목소리가 처음으로 돌아오지 않아요. 다음 편지는 별빛 씨앗 보관고로 향해요."),
        ),
    },
    # ── 별빛 씨앗 보관고 ───────────────────────────────────────────────────
    #
    # 차고 마른 곳. 모든 것이 `언젠가를 위해` 멈춰 있고, 그래서 아무것도
    # 시작되지 않는다. 기다림과 미루기를 가르는 이야기다.
    "starlight_seed_vault": {
        "name": "별빛 씨앗 보관고",
        "short_name": "보관고",
        "description": "언젠가를 위해 모든 씨앗을 재워 둔 곳이에요. 기다리는 것과 미루는 것이 어떻게 다른지 묻게 돼요.",
        "recommended_stage": 4,
        "stat_cap": 9,
        "reward": {"exp": 8, "seeds": 3, "item_code": "vault_key"},
        "map_name": "보관고 선반길",
        "next_region": "마음나무 관측실",
        "battle_copy": (
            ("문턱의 별가루", "쓸리지 않은 별가루가 성에와 엉겨 문턱을 덮고 있어요."),
            ("구르는 씨앗함", "별가루에 밀린 씨앗함들이 선반 사이를 제멋대로 굴러다녀요."),
            ("거꾸로 선 태엽", "되감긴 태엽 하나가 곧게 서서 통로를 가로막아요."),
            ("발아실 앞", "씨앗함과 태엽이 마지막 문 앞에 뒤엉켜 쌓였어요."),
        ),
        "tangles": ("snarled_stardust", "rolling_seedbox", "backwound_clockspring"),
        "scenes": {
            "entrance": ("dungeon_gate", "성에 낀 문", "문고리에 성에가 앉았어요. 안쪽 공기는 숨을 오래 참은 것처럼 말라 있어요."),
            "first_event": ("treasure_vault", "잠들지 못한 씨앗", "한 칸만 성에가 녹아 있어요. 그 안의 씨앗이 혼자 깨어 있었어요."),
            "second_event": ("root_tunnel", "거꾸로 도는 태엽", "벽시계가 거꾸로 돌아요. 보관고의 시간이 되감기고 있어요."),
            "camp": ("root_tunnel", "온기 남은 선반", "누군가 오래 앉았던 자리에 아직 온기가 남아 있어요."),
            "discovery": ("treasure_vault", "이름표 없는 칸", "비어 있는 칸 하나에 이름표만 없어요. 무엇을 재워 뒀는지 아무도 안 적었어요."),
            "guardian": ("monster_den", "발아실", "가장 안쪽 방의 공기만 따뜻해요. 시계 소리가 여기서 나요."),
            "objective": ("treasure_vault", "첫 싹의 칸", "성에가 녹은 자리에서 아주 작은 싹이 하나 올라와 있어요."),
            "exit": ("dungeon_gate", "녹기 시작한 문", "돌아 나오는 길의 성에가 물방울이 되어 떨어져요."),
            "depths": ("지하 1층 · 성에문", "지하 2층 · 깨어난 칸", "지하 2층 · 태엽실", "지하 3층 · 온기 선반", "지하 3층 · 빈 칸", "지하 4층 · 발아실", "지하 5층 · 첫 싹", "지상 · 녹는 문"),
        },
        "guardian": {
            "code": "germination_clock",
            "name": "발아 시계",
            "title": "발아 시계",
            "text": "방 한가운데의 큰 시계가 태엽을 감기 시작해요. 다 감기기 전에 멈출 자리를 찾아야 해요.",
            "attack_name": "되감는 태엽",
            "telegraph": "태엽이 반대로 돌면 시간이 되감겨요.",
            "weak_element": "nature",
            "resist_element": "gravity",
            "weakness_cycle": ["courage", "focus", "insight", "care"],
            "phases": (
                ("winding", "태엽 감기", "감을수록 다음 한 방이 무거워져요.", "감긴 만큼 다음 전체 공격의 위력이 올라가요.", "태엽이 한 칸씩 되감기기 시작했어요.", "sparkling"),
                ("frost_hold", "성에 붙듦", "성에가 톱니를 붙잡아요.", "약점을 맞히지 못한 라운드에는 수호 장벽이 2 회복돼요.", "톱니 사이에 성에가 하얗게 앉았어요.", "moonlit"),
                ("first_sprout", "첫 싹 틔우기", "시계가 마침내 앞으로 돌아요.", "장벽이 얇아질수록 예고가 짧아져요.", "태엽이 처음으로 앞으로 한 칸 움직였어요.", "sunny"),
            ),
            # 태엽은 약점을 못 맞힌 라운드를 되감아 다음 한 방을 무겁게 한다.
            "mechanics": (("reverse_winding", 1), ("repairing_index", 2), ("expose", 3)),
            "intents": (
                ("mainspring_lash", "튕기는 태엽", "태엽 하나가 팽팽해요. 맨 앞 대원을 노려요.", "front", 3, "stone"),
                ("escapement_grind", "톱니 갈림", "톱니가 서로 갈리며 방 전체가 흔들려요.", "all", 1, "stone"),
                ("frost_bite", "성에 물기", "성에가 발끝을 물어요. 가장 지친 대원을 노려요.", "lowest", 2, "water"),
            ),
            "choices": (
                ("find_the_stop", "톱니 사이의 멈출 자리를 찾아낸다", "insight", "insight_arc"),
                ("warm_the_frost", "손으로 성에를 녹여 톱니를 풀어 준다", "care", "care_vines"),
                ("step_back", "안전한 자리까지 물러난다", None, None),
            ),
        },
        "events": (
            {
                "code": "awake_seed",
                "title": "잠들지 못한 씨앗",
                "text": "혼자 깨어 있는 씨앗이 아주 작게 떨고 있어요. 어떻게 할까요?",
                "choices": (
                    ("let_it_wake", "깨어 있기로 한 선택을 존중한다", "courage"),
                    ("warm_gently", "손으로 감싸 온도를 맞춰 준다", "care"),
                    ("close_again", "칸을 다시 닫고 지나간다", None),
                ),
                "stage_title": "잠들지 못한 씨앗",
                "stage_summary": "혼자 깨어 있는 씨앗을 어떻게 대할지 골라요.",
            },
            {
                "code": "backward_spring",
                "title": "거꾸로 도는 태엽",
                "text": "벽시계가 되감기고 있어요. 이 방의 시간을 어떻게 다룰까요?",
                "choices": (
                    ("count_teeth", "톱니 수를 세어 되감긴 만큼을 잰다", "focus"),
                    ("hold_the_hand", "바늘을 붙잡아 지금에 멈춰 둔다", "courage"),
                    ("let_it_turn", "건드리지 않고 지나간다", None),
                ),
                "stage_title": "거꾸로 도는 태엽",
                "stage_summary": "되감기는 시계를 어떻게 다룰지 골라요.",
            },
        ),
        "discovery": {
            "code": "nameless_slot",
            "title": "이름표 없는 칸",
            "text": "비어 있는 칸 하나에만 이름표가 없어요. 탐험대는 대신 오늘 날짜를 적어 두기로 해요.",
        },
        "thread": {
            "code": "vault_someday",
            "seed": "모든 칸에 `언젠가`라고만 적혀 있어요. 그 언젠가가 며칠인지는 아무 데도 없어요.",
            "echo": "깨어 있는 씨앗과 되감기는 시계가 같은 말을 해요. 여기서는 시작이 계속 미뤄져요.",
            "payoff": "첫 싹이 올라온 칸에는 `오늘`이라고 적혀 있어요. 언젠가가 날짜를 가졌어요.",
        },
        "stories": (
            ("vault_someday_shelves", "언젠가라는 이름표", "모든 칸이 `언젠가`라고만 적혀 있어요. 그게 며칠인지는 아무 데도 없어요."),
            ("vault_one_awake", "혼자 깨어 있던 씨앗", "다 자는 칸에서 하나만 깨어 있었어요. 기다리는 것과 미루는 것은 다른 일이었어요."),
            ("vault_dust_of_stars", "쓸리지 않은 별가루", "선반 사이에 별가루가 쌓여 있어요. 아무도 지나가지 않은 시간만큼 두꺼워요."),
            ("vault_time_rewinds", "되감기는 방", "시계가 거꾸로 돌 때마다 방이 조금씩 더 차가워져요. 시간이 아니라 마음이 되감기고 있었어요."),
            ("vault_warm_shelf", "남은 온기", "누군가 오래 앉았던 자리가 아직 따뜻해요. 여기 있었던 사람도 시작을 망설였던 것 같아요."),
            ("vault_who_locked_it", "잠근 사람", "칸을 잠근 것은 바깥의 누군가가 아니라 이 보관고 자신이었어요. 깨우면 잃을까 봐요."),
            ("vault_wind_it_forward", "앞으로 감는 법", "태엽은 멈추는 게 아니라 앞으로 감는 것이었어요. 방이 조금 따뜻해져요."),
            ("vault_today_written", "오늘이라고 적힌 칸", "첫 싹이 오른 칸에 `오늘`이 적혀요. 다음 편지는 마음나무 관측실로 향해요."),
        ),
    },
    # ── 마음나무 관측실 ────────────────────────────────────────────────────
    #
    # 가장 높은 곳. 여기서는 모든 것이 기록으로만 남아 있고, 정작 그 기록을
    # 읽어 줄 사람이 없다. 마지막 답장이 어디로 가야 하는지 알게 된다.
    "heartwood_observatory": {
        "name": "마음나무 관측실",
        "short_name": "관측실",
        "description": "마음나무의 나이테를 오래 지켜본 곳이에요. 기록은 가득한데 읽어 줄 사람이 없어, 마지막 답장이 어디로 가야 할지 알게 돼요.",
        "recommended_stage": 5,
        "stat_cap": 10,
        "reward": {"exp": 9, "seeds": 3, "item_code": "heartwood_key"},
        "map_name": "관측실 나선길",
        "next_region": "마음정원 온실",
        "battle_copy": (
            ("계단의 나이테 조각", "떨어져 나온 나이테 조각들이 나선 계단에 얽혀 있어요."),
            ("흩어진 낱장", "나이테 조각 사이로 관측 기록 낱장이 순서 없이 날려요."),
            ("헝클어진 관측기", "렌즈와 실이 서로 감겨 관측기가 통째로 헝클어졌어요."),
            ("관측대 아래", "낱장과 관측기가 마지막 층계에 함께 뭉쳐 길을 막아요."),
        ),
        "tangles": ("ring_shard_tangle", "scattered_records", "matted_observatory"),
        "scenes": {
            "entrance": ("dungeon_gate", "나선 계단 아래", "위로 감기는 계단이 나무 속을 지나 올라가요. 밟을 때마다 나이테가 한 겹씩 지나가요."),
            "first_event": ("moon_tower", "겹친 낱장", "떨어진 관측 기록이 순서 없이 겹쳐 있어요. 어느 해의 것인지 섞여 버렸어요."),
            "second_event": ("root_tunnel", "어긋난 나이테", "한 해의 나이테만 방향이 달라요. 그해에 무슨 일이 있었어요."),
            "camp": ("moon_tower", "창가 쉼터", "창턱에 앉으면 온실 쪽 불빛이 아주 작게 보여요."),
            "discovery": ("moon_tower", "마지막 관측 일지", "일지의 마지막 장이 펼쳐진 채 멈춰 있어요. 문장이 중간에서 끊겼어요."),
            "guardian": ("monster_den", "관측대", "가장 높은 자리에 관측자가 눈을 감은 채 앉아 있어요."),
            "objective": ("moon_tower", "온실이 보이는 창", "여기서는 마음정원 온실이 또렷하게 보여요. 답장이 갈 곳이 정해졌어요."),
            "exit": ("dungeon_gate", "내려가는 계단", "내려가는 길에서는 나이테가 반대로 지나가요. 돌아가는 중이에요."),
            "depths": ("지상 1층 · 나선 아래", "2층 · 기록실", "3층 · 나이테 벽", "4층 · 창가", "5층 · 일지실", "6층 · 관측대", "7층 · 전망창", "지상 · 내려가는 길"),
        },
        "guardian": {
            "code": "ring_watcher",
            "name": "나이테 관측자",
            "title": "나이테 관측자",
            "text": "관측자가 눈을 떠요. 오래 본 사람만 아는 방식으로 길을 막고 있어요.",
            "attack_name": "나이테 읽기",
            "telegraph": "관측자의 눈이 한 바퀴 돌면 나이테가 읽혀요.",
            "weak_element": "fire",
            "resist_element": "seal",
            "weakness_cycle": ["care", "courage", "focus", "insight"],
            "phases": (
                ("long_watch", "긴 관측", "오래 본 만큼 다음 수를 읽어요.", "약점을 맞히지 못한 라운드에는 수호 장벽이 2 회복돼요.", "관측자의 눈이 천천히 초점을 맞췄어요.", "moonlit"),
                ("record_storm", "기록 폭풍", "읽은 것을 전부 한 번에 펼쳐요.", "전체 공격의 위력이 한 단계 높아져요.", "낱장이 방 전체로 날아올랐어요.", "sparkling"),
                ("closing_ring", "닫히는 나이테", "마지막 한 겹을 스스로 닫으려 해요.", "장벽이 얇아질수록 예고가 짧아져요.", "관측자가 두 손을 가슴 앞으로 모았어요.", "ember"),
            ),
            # 오래 본 만큼 읽어 낸다. `no_guard_action`은 **하나만** 둔다 —
            # 방아쇠 셋 중 유일하게 행동 하나를 통째로 내놓아야 꺼지는 것이라,
            # 둘을 달면 매 라운드 방어만 하다가 장벽을 못 깬다.
            "mechanics": (("double_exposure", 2), ("resonant_pressure", 1), ("focus_leak", 3)),
            "intents": (
                ("ringread_turn", "나이테 돌리기", "나이테 하나가 돌아요. 맨 앞 대원을 노려요.", "front", 2, "wood"),
                ("record_gale", "낱장 폭풍", "기록이 방 전체로 날아요. 탐험대 전체를 덮쳐요.", "all", 1, "paper"),
                ("lens_focus", "렌즈 반사", "렌즈가 빛을 모아요. 가장 지친 대원을 노려요.", "lowest", 2, "stone"),
            ),
            "choices": (
                ("read_the_gap", "나이테가 어긋난 해를 짚어 낸다", "insight", "insight_arc"),
                ("read_it_aloud", "기록을 소리 내어 읽어 준다", "care", "care_vines"),
                ("step_back", "안전한 자리까지 물러난다", None, None),
            ),
        },
        "events": (
            {
                "code": "scattered_pages",
                "title": "겹친 낱장",
                "text": "관측 기록이 순서 없이 겹쳐 있어요. 어떻게 되돌릴까요?",
                "choices": (
                    ("match_edges", "종이 가장자리의 닳은 결을 맞춘다", "insight"),
                    ("read_each", "한 장씩 읽으며 이야기 순서를 찾는다", "focus"),
                    ("stack_neatly", "읽지 않고 가지런히 쌓아 둔다", None),
                ),
                "stage_title": "겹친 낱장",
                "stage_summary": "섞인 관측 기록을 어떻게 되돌릴지 골라요.",
            },
            {
                "code": "crooked_ring",
                "title": "어긋난 나이테",
                "text": "한 해의 나이테만 방향이 달라요. 그해를 어떻게 읽을까요?",
                "choices": (
                    ("measure_twice", "앞뒤 해와 견주어 두 번 잰다", "focus"),
                    ("ask_the_tree", "나무에 손을 대고 그해를 물어본다", "care"),
                    ("note_and_pass", "표시만 남기고 지나간다", None),
                ),
                "stage_title": "어긋난 나이테",
                "stage_summary": "방향이 다른 한 해를 어떻게 읽을지 골라요.",
            },
        ),
        "discovery": {
            "code": "last_logbook",
            "title": "마지막 관측 일지",
            "text": "마지막 문장이 중간에서 끊겨 있어요. 쓰던 사람이 급히 자리를 떴거나, 답을 기다리고 있었던 것 같아요.",
        },
        "thread": {
            "code": "heartwood_unread",
            "seed": "관측 기록이 벽을 가득 채웠는데, 펼쳐 본 자국이 하나도 없어요.",
            "echo": "낱장도 나이테도 읽히기를 기다리고 있었어요. 기록은 남기는 것으로 끝나지 않아요.",
            "payoff": "관측자에게 기록을 소리 내어 읽어 주자, 창밖으로 온실 불빛이 또렷해져요.",
        },
        "stories": (
            ("heartwood_unopened", "펼친 자국 없는 벽", "기록이 벽을 가득 채웠는데 펼쳐 본 자국이 없어요. 남기기만 하고 아무도 읽지 않았어요."),
            ("heartwood_mixed_years", "섞여 버린 해", "낱장이 순서를 잃었어요. 순서가 없으면 기록은 이야기가 되지 못해요."),
            ("heartwood_one_off_year", "방향이 다른 한 해", "그해의 나이테만 반대로 감겨 있어요. 무언가를 견디던 해였어요."),
            ("heartwood_far_light", "창밖의 작은 불빛", "창턱에서 보면 온실 불빛이 아주 작게 켜져 있어요. 아직 누가 기다리고 있어요."),
            ("heartwood_someone_sat", "오래 앉았던 자리", "창가 자리만 반들반들해요. 여기서 오래 바깥을 본 사람이 있었어요."),
            ("heartwood_cut_sentence", "끊긴 마지막 문장", "일지의 마지막 문장이 중간에서 멈춰요. 답을 기다리다 멈춘 문장이에요."),
            ("heartwood_read_aloud", "소리 내어 읽기", "기록은 남기는 것으로 끝나지 않아요. 읽어 주는 사람이 있어야 이야기가 돼요."),
            ("heartwood_way_home", "돌아가는 길", "창밖 온실이 또렷해져요. 마지막 답장은 처음 떠나온 곳으로 돌아가요."),
        ),
    },
}


def _edges(region: dict, edges: tuple) -> list[list[str]]:
    """자리 이름으로 적은 간선을 실제 노드 코드로 옮긴다.

    발견 노드만 코드가 지역마다 다르다 — `discoveries`의 열쇠와 같아야 문장이
    붙기 때문이다. 상수는 자리 이름(`discovery`)으로 두고 여기서 한 번만 바꾼다.
    """

    real = region["discovery"]["code"]
    return [
        [real if end == "discovery" else end for end in edge] for edge in edges
    ]


def _nodes(region: dict) -> list[dict]:
    scenes = region["scenes"]
    depths = scenes["depths"]
    nodes = []
    for index, (code, kind, x, y, cost, threat) in enumerate(NODE_LAYOUT):
        scene_key, label, description = scenes[code]
        node = {
            "code": code,
            "name": label,
            "type": kind,
            "x": x,
            "y": y,
            "cost": cost,
            "scene_key": scene_key,
            "scene_label": label,
            "scene_description": description,
            "depth_label": depths[index],
            "threat_level": threat,
        }
        if kind == "event":
            node["event_code"] = region["events"][
                0 if code == "first_event" else 1
            ]["code"]
        if kind == "guardian":
            node["event_code"] = region["guardian"]["code"]
        if kind == "discovery":
            node["code"] = region["discovery"]["code"]
        nodes.append(node)
    return nodes


def _stages(region: dict) -> list[dict]:
    tangles = region["tangles"]
    events = region["events"]
    scenes = region["scenes"]
    stories = region["stories"]
    stages = []
    # 전투는 한 종류 → 두 종류 → 다른 한 종류 → 두 종류로 무게가 올라간다.
    battle_sets = (
        (tangles[0],),
        (tangles[0], tangles[1]),
        (tangles[2],),
        (tangles[1], tangles[2]),
    )
    battle_index = 0
    for no, kind, chapter, phase in STAGE_SHAPE:
        code, title, caption = stories[no - 1]
        scene_key = {
            1: scenes["entrance"][0],
            2: scenes["first_event"][0],
            3: scenes["discovery"][0],
            4: scenes["second_event"][0],
            5: scenes["camp"][0],
            6: scenes["second_event"][0],
            7: scenes["objective"][0],
            8: scenes["guardian"][0],
        }[no]
        stage: dict = {
            "no": no,
            "kind": kind,
            "estimated_seconds": {"battle": 75, "event": 45, "camp": 30, "boss": 150}[kind],
            "story": {
                "code": code,
                "chapter": chapter,
                "phase": phase,
                "title": title,
                "caption": caption,
                "scene_key": scene_key,
                # 회상은 서고 항목으로 남는다. 지역·장으로 주소를 만들어 겹치지 않게 한다.
                "codex_entry": f"{region['short_name']}.chapter.{chapter}",
            },
        }
        if kind == "battle":
            title, summary = region["battle_copy"][battle_index]
            stage["title"] = title
            stage["summary"] = summary
            wave = battle_sets[battle_index]
            stage["tangles"] = list(wave)
            # 스테이지가 예고하는 약점은 첫 웨이브의 첫 약점이다. 카탈로그에서
            # 읽어야 엉킴을 바꿔도 둘이 어긋나지 않는다.
            stage["weakness"] = TANGLE_CATALOG[wave[0]]["weakness_cycle"][0]
            battle_index += 1
        elif kind == "event":
            event = events[0 if no == 2 else 1]
            stage["title"] = event["stage_title"]
            stage["summary"] = event["stage_summary"]
            stage["event_code"] = event["code"]
        elif kind == "camp":
            stage["title"] = scenes["camp"][1]
            stage["summary"] = "숨을 고르고 오늘 본 것을 이야기해요."
        else:
            stage["title"] = region["guardian"]["name"]
            stage["summary"] = region["guardian"]["text"]
            stage["event_code"] = region["guardian"]["code"]
            stage["weakness"] = region["guardian"]["weakness_cycle"][0]
        stages.append(stage)
    return stages


def _guardian_event(region: dict) -> dict:
    guardian = region["guardian"]
    intents = [
        {
            "code": code,
            "name": name,
            "telegraph": telegraph,
            "target": target,
            "power": power,
        }
        for code, name, telegraph, target, power, _material in guardian["intents"]
    ]
    # 단계 전용 예고에는 기믹이 붙는다. `mechanic_unlock`은 그 기믹이 몇 번째
    # 위협도부터 실제로 열리는지다 — 낮은 난이도에서는 이름만 보이고 안 걸린다.
    rich_intents = [
        {
            **intent,
            "contact_material": material,
            "mechanic_code": mechanic,
            "mechanic_unlock": unlock,
        }
        for intent, (_c, _n, _t, _tg, _p, material), (mechanic, unlock) in zip(
            intents, guardian["intents"], guardian["mechanics"]
        )
    ]
    phases = []
    for index, (code, name, _flavour, rule, intro, tone) in enumerate(guardian["phases"]):
        phases.append(
            {
                "code": code,
                "name": name,
                "threshold_bp": (10_000, 6_600, 3_300)[index],
                "weak_element": guardian["weak_element"],
                "resist_element": guardian["resist_element"],
                "weakness_cycle": list(guardian["weakness_cycle"]),
                "intent_power_bonus": (0, 0, 1)[index],
                "focus_reward": (0, 1, 1)[index],
                "tone": tone,
                "rule_name": name,
                "rule_summary": rule,
                "phase_gate": "resolve_intent",
                "intro_caption": intro,
                # 단계마다 두 수를 보여 준다. 셋을 다 쓰면 읽을 것이 너무 많다.
                # 단계마다 두 수를 보여 준다. 셋을 다 쓰면 읽을 것이 너무 많고,
                # 끝에서 잘려 하나만 남으면 예고를 읽고 고를 것이 사라진다.
                "intents": [
                    rich_intents[index % len(rich_intents)],
                    rich_intents[(index + 1) % len(rich_intents)],
                ],
            }
        )
    choices = []
    for code, label, stat, effect_key in guardian["choices"]:
        choice: dict = {
            "code": code,
            "label": label,
            "stat": stat,
            "difficulty": 10 if stat else 0,
            "resolve_cost": 1 if stat else 0,
        }
        if stat is None:
            choice["safe"] = True
            # 물러나는 선택도 연출과 피해를 **명시**한다. 비워 두면 `안 정한 것`과
            # `0으로 정한 것`이 구분되지 않는다.
            choice["effect_key"] = "safe_guard"
            choice["guard_damage"] = 0
        else:
            choice["effect_key"] = effect_key
            choice["guard_damage"] = 68
        choices.append(choice)
    return {
        "title": guardian["title"],
        "text": guardian["text"],
        "tags": ["guardian", "social"],
        "encounter": {
            "kind": "guardian",
            "enemy_name": guardian["name"],
            "enemy_max_guard": 100,
            "attack_name": guardian["attack_name"],
            "telegraph": guardian["telegraph"],
            "damage_target": "탐험대",
            "max_rounds": 8,
            "starting_focus": 3,
            "max_focus": 5,
            "difficulty_code": "stage_8",
            "weak_element": guardian["weak_element"],
            "resist_element": guardian["resist_element"],
            "weakness_cycle": list(guardian["weakness_cycle"]),
            "boss_phases": phases,
            "intents": intents,
        },
        "choices": choices,
    }


def _events(region: dict) -> dict:
    events = {}
    for entry in region["events"]:
        choices = []
        for code, label, stat in entry["choices"]:
            choice: dict = {
                "code": code,
                "label": label,
                "stat": stat,
                "difficulty": 8 if stat else 0,
                "resolve_cost": 1 if stat else 0,
            }
            if stat is None:
                choice["safe"] = True
            choices.append(choice)
        events[entry["code"]] = {
            "title": entry["title"],
            "text": entry["text"],
            "tags": ["puzzle", "mystery"],
            "choices": choices,
        }
    events[region["guardian"]["code"]] = _guardian_event(region)
    return events


def build(code: str) -> dict:
    region = REGIONS[code]
    nodes = _nodes(region)
    return {
        "schema_version": SCHEMA_VERSION,
        "content_version": CONTENT_VERSION,
        "region": {
            "code": code,
            "name": region["name"],
            "short_name": region["short_name"],
            "description": region["description"],
            "recommended_stage": region["recommended_stage"],
            "stat_cap": region["stat_cap"],
            "reward": dict(region["reward"]),
        },
        "stages": _stages(region),
        "map": {
            "code": f"{code}_main",
            "name": region["map_name"],
            "entrance": "entrance",
            "nodes": nodes,
            "edges": _edges(region, BASE_EDGES),
            "initial_revealed": ["entrance", "first_event", "second_event"],
        },
        "map_templates": [
            {
                "code": f"{code}_crossroads_b",
                "name": f"{region['short_name']} 갈래길",
                "edges": _edges(region, CROSSROAD_EDGES),
                "coordinate_overrides": {"discovery": {"x": 0.50, "y": 0.78}},
            },
            {
                "code": f"{code}_ring_c",
                "name": f"{region['short_name']} 고리길",
                "edges": _edges(region, RING_EDGES),
                "coordinate_overrides": {"camp": {"x": 0.44, "y": 0.66}},
            },
        ],
        "events": _events(region),
        "discoveries": {
            region["discovery"]["code"]: {
                "title": region["discovery"]["title"],
                "text": region["discovery"]["text"],
            }
        },
        "run_threads": [dict(region["thread"])],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="쓰지 않고 검증만")
    args = parser.parse_args()

    # 수호자 공격 코드가 엉킴 것과 겹치면 소리·연출·기록이 뒤섞인다. 코드는
    # 신원이라 겹치는 순간 둘이 같은 것이 된다.
    tangle_attacks = {
        intent["code"]
        for definition in TANGLE_CATALOG.values()
        for intent in (definition.get("intents") or [])
    }
    guardian_attacks: dict[str, str] = {}
    for code, region in REGIONS.items():
        for attack in region["guardian"]["intents"]:
            name = attack[0]
            if name in tangle_attacks:
                print(f"[실패] {code}: 수호자 공격 {name}이 엉킴 공격과 겹칩니다")
                return 1
            if name in guardian_attacks:
                print(
                    f"[실패] {code}: 수호자 공격 {name}이 "
                    f"{guardian_attacks[name]}과 겹칩니다"
                )
                return 1
            guardian_attacks[name] = code

    # 원고가 뼈대 문장으로 되돌아가는 것을 막는다. 생성기는 구조를 찍어 내지만
    # **문장은 사람이 쓴 것**이어야 한다. 아래 셋은 자동으로 만든 티가 나는
    # 모양들이고, 하나라도 나오면 그 지역은 아직 원고가 없는 것이다.
    for code, region in REGIONS.items():
        titles = [title for title, _summary in region["battle_copy"]]
        summaries = [summary for _title, summary in region["battle_copy"]]
        if len(region["battle_copy"]) != sum(
            1 for _n, kind, _c, _p in STAGE_SHAPE if kind == "battle"
        ):
            print(f"[실패] {code}: 전투 원고 수가 전투 스테이지 수와 다릅니다")
            return 1
        if len(set(titles)) != len(titles) or len(set(summaries)) != len(summaries):
            print(f"[실패] {code}: 전투 원고가 서로 겹칩니다")
            return 1
        for title in titles:
            if "걸음" in title and any(ch.isdigit() for ch in title):
                print(f"[실패] {code}: `{title}`은 번호를 읽어 주는 뼈대 제목입니다")
                return 1
        for summary in summaries:
            if summary == "엉킨 것을 풀어 길을 넓혀요.":
                print(f"[실패] {code}: 전투 요약이 뼈대 문장 그대로입니다")
                return 1
            if not summary.endswith("요."):
                print(f"[실패] {code}: `{summary}`의 말투가 다릅니다")
                return 1

    # 전체 공격 위력은 **1까지**다. 실제로 걸어 보니 2만 돼도 보관고·관측실
    # 수호전에서 파티가 진다 — 장벽은 난이도 계수가 붙어 156이라 여러 라운드가
    # 필요한데, 전체 공격을 막으려면 그 라운드의 행동을 방어에 써야 해서 장벽을
    # 못 깬다. 기억서고 수호자도 1이다.
    #
    # 난이도는 **앞 대원 공격**으로 올린다 — 누가 앞에 설지는 행동 순서로 고를 수
    # 있어서 사용자가 읽고 대응할 수 있는 위험이다.
    for code, region in REGIONS.items():
        for name, _label, _tele, target, power, _material in region["guardian"]["intents"]:
            if target == "all" and power > 1:
                print(
                    f"[실패] {code}: 전체 공격 {name}의 위력 {power}는 너무 큽니다(상한 1). "
                    f"파티는 HP 5~6짜리 두셋이고 전체 공격을 피할 수단은 마음 지키기뿐인데, "
                    f"그 방어는 장벽을 깨는 데 쓸 행동을 잡아먹는다. 기억서고 수호자도 1이다"
                )
                return 1
            if target == "lowest" and power > 2:
                print(
                    f"[실패] {code}: 최약체 공격 {name}의 위력 {power}는 "
                    f"이미 지친 대원에게 너무 큽니다(상한 2)"
                )
                return 1

    # `no_guard_action` 기믹은 한 수호자에 하나까지다. 이 방아쇠만 **행동 하나를
    # 통째로 내놓아야** 꺼지므로(다른 둘은 어떻게 싸우든 충족할 수 있다), 둘을
    # 달면 매 라운드 방어만 하다가 장벽을 못 깬다. 관측실 수호자가 실제로 그랬다.
    from app.content.expeditions.combat_difficulty import ENEMY_MECHANICS

    for code, region in REGIONS.items():
        # 방어 강요 기믹은 그 자체로 **행동 하나를 세금으로 걷는다.** 거기에 앞
        # 대원 공격까지 최대치면 방어하느라 못 때리고, 안 하면 위력이 올라 맞아
        # 죽는다. 관측실 수호자가 실제로 그래서 졌다. 둘 중 하나만 센다.
        heavy_front = max(
            (power for _n, _l, _t, target, power, _m in region["guardian"]["intents"]
             if target == "front"),
            default=0,
        )
        guards = [
            name
            for name, _unlock in region["guardian"]["mechanics"]
            if ENEMY_MECHANICS[name]["trigger"] == "no_guard_action"
        ]
        # 위력을 올리는 기믹은 하나까지다. 둘이 켜지면 매 라운드 +2가 되는데,
        # 켜지는지 아닌지가 **파티의 성장결이 그 약점과 맞느냐**에 달려 있어
        # 어떤 파티에는 순하고 어떤 파티에는 못 이기는 전투가 된다. 보관고
        # 수호자는 기본 파티의 결이 마침 약점과 같아 `운으로` 통과하고 있었다.
        bonuses = [
            name
            for name, _unlock in region["guardian"]["mechanics"]
            if ENEMY_MECHANICS[name]["effect"] == "power_bonus"
        ]
        if len(bonuses) > 1:
            print(
                f"[실패] {code}: 위력 상승 기믹이 {len(bonuses)}개입니다({bonuses}). "
                f"둘이 함께 켜지면 매 라운드 +2라 파티에 따라 못 이기는 전투가 됩니다"
            )
            return 1
        if guards and heavy_front >= 3:
            print(
                f"[실패] {code}: 방어 강요 기믹({guards[0]})과 앞 대원 위력 "
                f"{heavy_front}가 겹칩니다. 방어하면 못 때리고 안 하면 죽습니다"
            )
            return 1
        if len(guards) > 1:
            print(
                f"[실패] {code}: 방어 강요 기믹이 {len(guards)}개입니다({guards}). "
                f"매 라운드 방어만 하다 장벽을 못 깹니다(상한 1)"
            )
            return 1

    failures = 0
    for code in REGIONS:
        pack = build(code)
        try:
            validate_content(pack)
        except Exception as error:  # noqa: BLE001 — 그대로 보여 주는 것이 목적이다
            failures += 1
            print(f"[실패] {code}")
            print(f"  {error}")
            continue
        print(f"[통과] {code} — 스테이지 {len(pack['stages'])}, 노드 {len(pack['map']['nodes'])}, 사건 {len(pack['events'])}")
        if not args.check:
            path = OUT_DIR / f"{code}.json"
            path.write_text(
                json.dumps(pack, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
    if failures:
        print(f"\n{failures}개 지역이 검증을 통과하지 못했습니다.")
        return 1
    print("\n모든 지역이 검증을 통과했습니다.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
