"""퀘스트 콘텐츠 확장과 캐릭터 세계관 메타데이터

Revision ID: 0004_content_depth
Revises: 0003_character_catalog
Create Date: 2026-07-13
"""

from alembic import op
import sqlalchemy as sa


revision = "0004_content_depth"
down_revision = "0003_character_catalog"
branch_labels = None
depends_on = None


QUEST_ROWS = (
    (
        "QST_NAME_THE_MOMENT",
        "현재 기분 두 단어",
        "지금 상태를 설명하는 단어 두 개를 메모에 적어보세요. 서로 반대여도 됩니다.",
        "reflection",
        1,
        2,
        [],
    ),
    (
        "QST_TEXTURE_SCOUT",
        "촉감 비교: 매끈·거침",
        "안전하게 만질 수 있는 물건 두 개를 골라 어느 쪽이 더 매끈한지 비교해보세요.",
        "senses",
        1,
        2,
        [],
    ),
    (
        "QST_TEMPERATURE_NOTE",
        "공기 온도 체크",
        "손등에 닿는 공기가 따뜻한지, 서늘한지, 비슷한지 셋 중 하나로 기록하세요.",
        "senses",
        1,
        2,
        [],
    ),
    (
        "QST_PALM_SPACE",
        "우편엽서 크기 정리",
        "책상이나 선반에서 엽서 정도 넓이를 비우고 치운 물건은 가까운 자리에 모아두세요.",
        "space",
        1,
        3,
        [],
    ),
    (
        "QST_SHOULDER_DROP",
        "어깨 으쓱 한 번",
        "불편하지 않다면 어깨를 귀 쪽으로 한 번 올렸다가 숨을 내쉬며 내려놓으세요. 동작이 어렵다면 생략해도 됩니다.",
        "body",
        1,
        2,
        ["mobility_adaptable"],
    ),
    (
        "QST_COMFY_POSTURE",
        "등·팔·발 위치 바꾸기",
        "등받이에 기대기, 팔 내려놓기, 발 위치 옮기기 중 편해 보이는 하나를 선택하세요. 현재 자세가 낫다면 그대로 두세요.",
        "body",
        1,
        2,
        ["mobility_adaptable"],
    ),
    (
        "QST_ONE_MINUTE_GAP",
        "알림 끄고 1분",
        "타이머를 1분으로 맞춘 뒤 알림과 화면을 보지 않는 시간을 가져보세요.",
        "rest",
        1,
        1,
        [],
    ),
    (
        "QST_CHOOSE_NOT_TODO",
        "오늘 목록에서 하나 빼기",
        "오늘 할 일 중 내일로 미뤄도 문제가 적은 항목 하나에 ‘내일’ 표시를 해두세요.",
        "planning",
        1,
        2,
        [],
    ),
    (
        "QST_MOOD_SHAPE",
        "선 세 개로 기분 그리기",
        "종이나 메모 앱에 직선, 곡선, 점을 한 번씩 써서 오늘 상태를 표시해보세요.",
        "creativity",
        1,
        3,
        [],
    ),
    (
        "QST_MEMORY_TITLE",
        "오늘 장면에 영화 제목",
        "가장 먼저 떠오르는 장면을 고르고 다섯 단어 안으로 제목을 붙여보세요.",
        "reflection",
        1,
        3,
        [],
    ),
    (
        "QST_SMALL_BOUNDARY",
        "방해 금지 10분 예약",
        "방해받고 싶지 않은 시간대를 10분 정해 달력이나 메모에 표시하세요. 당장 지키지 못해도 표시만 하면 됩니다.",
        "self_kindness",
        1,
        3,
        [],
    ),
    (
        "QST_KIND_SELF_LINE",
        "친구에게 하듯 한 줄",
        "오늘 수고한 일을 하나 떠올리고, 친한 친구에게 말하듯 짧은 답장을 적어보세요.",
        "self_kindness",
        1,
        3,
        [],
    ),
    (
        "QST_SKY_PATCH",
        "하늘 색 확인",
        "창밖이나 저장된 사진에서 하늘을 찾아 색을 한 단어로 적어보세요. 하늘을 볼 수 없으면 천장이나 벽의 색을 골라도 됩니다.",
        "senses",
        1,
        2,
        ["outdoor_optional"],
    ),
    (
        "QST_SOUNDTRACK_PICK",
        "오늘 장면의 배경음",
        "오늘과 어울리는 노래 제목을 하나 고르세요. 소리를 재생하지 않고 제목만 떠올려도 됩니다.",
        "creativity",
        1,
        3,
        ["audio_optional"],
    ),
    (
        "QST_SLOW_HANDS",
        "손 동작 리플레이",
        "컵 들기, 문 열기, 펜 놓기 중 가능한 동작을 한 번 하고 손의 움직임을 관찰하세요. 동작이 불편하면 눈으로만 따라가도 됩니다.",
        "body",
        1,
        2,
        ["mobility_adaptable"],
    ),
    (
        "QST_OBJECT_STORY",
        "책상 물건 시점 일기",
        "가까운 물건 하나를 화자로 정해 ‘오늘 나는 ___을 봤다’ 한 줄을 완성하세요.",
        "creativity",
        1,
        3,
        [],
    ),
    (
        "QST_EASY_CHOICE",
        "2분 안에 끝낼 일 선택",
        "지금 가능한 일 중 준비가 가장 적게 필요한 항목을 하나 골라 체크 표시만 해두세요.",
        "planning",
        1,
        2,
        [],
    ),
    (
        "QST_UNSENT_HELLO",
        "전송하지 않는 안부 초안",
        "떠오르는 사람이 있다면 안부 한 줄을 메모장에 쓰고 저장하지 않아도 됩니다. 사람이 떠오르지 않으면 좋아하는 캐릭터에게 적어보세요.",
        "connection",
        1,
        3,
        ["social_optional"],
    ),
    (
        "QST_FIVE_MIN_RESET",
        "자주 쓰는 자리 5분 정리",
        "책상, 침대 옆, 가방 중 한 곳을 고르고 타이머가 울릴 때까지만 정리하세요.",
        "space",
        2,
        5,
        [],
    ),
    (
        "QST_FUTURE_NOTE",
        "주말 전에 볼 메모",
        "이번 주가 끝나기 전에 기억할 일 하나와 챙길 일 하나를 메모에 남기세요.",
        "reflection",
        2,
        5,
        [],
    ),
    (
        "QST_FRESH_AIR_OPTION",
        "방 공기 5분 바꾸기",
        "가능하면 창문이나 문을 열어 환기하세요. 여의치 않으면 익숙한 실내에서 다른 자리로 옮겨 앉아도 됩니다.",
        "movement",
        2,
        5,
        ["outdoor_optional"],
    ),
    (
        "QST_TINY_DELAYED_TASK",
        "미룬 일, 첫 화면 열기",
        "미뤄 둔 일에 필요한 앱, 문서, 가방 중 하나를 열고 5분 동안 첫 단계만 진행하세요.",
        "planning",
        2,
        5,
        [],
    ),
    (
        "QST_REST_CORNER",
        "쉬는 자리 세팅",
        "의자나 침대 주변에 물, 충전기, 쿠션 중 필요한 물건 하나를 두고 사용 후 돌려놓을 자리를 정하세요.",
        "space",
        2,
        5,
        [],
    ),
    (
        "QST_GENTLE_REACH",
        "앉은 자리 몸풀기",
        "앉거나 선 자세에서 불편하지 않은 손목 또는 발목을 세 번 돌려보세요. 어렵다면 손가락을 펴고 오므리는 동작으로 바꿔도 됩니다.",
        "movement",
        2,
        4,
        ["mobility_adaptable"],
    ),
)


CHARACTER_STORY_META = {
    "character_baby_pot": {
        "story_role": "마음정원의 새싹 안내자",
        "lore_hook": "박물관 창고에서 쪽쪽이와 함께 발견된 첫 번째 꼬마 화분.",
        "quest_affinities": ["senses", "reflection"],
        "collection_quote": "뽀또! 새싹 스티커는 내가 붙일래!",
    },
    "character_handsome_pot": {
        "story_role": "비밀 온실의 수호자",
        "lore_hook": "식물 학교 수석 배지를 달고 비밀 온실의 열쇠를 관리한다.",
        "quest_affinities": ["rest", "self_kindness"],
        "collection_quote": "온실 점검 끝. 다음 구역으로 가지.",
    },
    "character_pretty_pot": {
        "story_role": "정원 스테이지의 센터",
        "lore_hook": "정원 축제 메인 스테이지의 순서표와 조명을 직접 챙기는 새싹 아이돌.",
        "quest_affinities": ["creativity", "connection"],
        "collection_quote": "조명 켜! 이번 무대 센터는 나야.",
    },
    "character_tsundere_pot": {
        "story_role": "가시 울타리의 단짝",
        "lore_hook": "가시 울타리 경비대 소속으로, 분실한 씨앗 주머니를 몰래 주인에게 돌려놓는다.",
        "quest_affinities": ["space", "self_kindness"],
        "collection_quote": "예비 씨앗은 남아서 주는 거야.",
    },
    "character_zombie_pot": {
        "story_role": "새벽 정원의 생존왕",
        "lore_hook": "해가 지면 묘목 창고에서 깨어나 야간 출석 도장을 찍는다.",
        "quest_affinities": ["rest", "body"],
        "collection_quote": "으으… 해 뜨기 전에 한 바퀴 더.",
    },
    "character_gumiho_pot": {
        "story_role": "달빛 온실의 장난꾼",
        "lore_hook": "달빛 신사의 봉인이 풀린 밤, 아홉 꼬리불을 훔쳐 달아난 여우 화분.",
        "quest_affinities": ["reflection", "creativity"],
        "collection_quote": "후후, 마지막 꼬리불은 어디 있게?",
    },
    "character_ninja_pot": {
        "story_role": "그림자 임무의 동료",
        "lore_hook": "잎 수리검과 연막 씨앗으로 정원 외곽을 정찰하는 그림자 대원.",
        "quest_affinities": ["planning", "movement"],
        "collection_quote": "연막 씨앗 장전. 셋에 이동한다.",
    },
    "character_magical_pot": {
        "story_role": "별잎 마법학원의 문제아",
        "lore_hook": "별잎 마법학원에서 금지된 잡초 변환식을 시험해 온실 지붕을 덩굴로 덮었다.",
        "quest_affinities": ["creativity", "reflection"],
        "collection_quote": "별자리 세 번째 줄, 주문 개시!",
    },
    "character_aloof_pot": {
        "story_role": "서리동백 정원의 주인",
        "lore_hook": "서리동백 연구소에서 희귀 꽃의 개화 시간을 초 단위로 기록하는 책임자.",
        "quest_affinities": ["self_kindness", "rest"],
        "collection_quote": "표본은 손대지 마. 기록부터 확인해.",
    },
    "character_student_pot": {
        "story_role": "마음정원 학생회장",
        "lore_hook": "식물 학교 학생회장으로 축제 당번표와 씨앗 창고 장부를 동시에 관리한다.",
        "quest_affinities": ["planning", "space"],
        "collection_quote": "수첩 펴. 오늘 순서는 내가 정리할게.",
    },
}

_STORY_KEYS = frozenset(
    {"story_role", "lore_hook", "quest_affinities", "collection_quote"}
)


def _update_character_story_meta(*, remove: bool = False) -> None:
    bind = op.get_bind()
    items = sa.table(
        "items",
        sa.column("code", sa.String),
        sa.column("asset_manifest", sa.JSON),
    )
    rows = bind.execute(
        sa.select(items.c.code, items.c.asset_manifest).where(
            items.c.code.in_(tuple(CHARACTER_STORY_META))
        )
    ).mappings()
    for row in rows:
        manifest = dict(row["asset_manifest"] or {})
        if remove:
            for key in _STORY_KEYS:
                manifest.pop(key, None)
        else:
            manifest.update(CHARACTER_STORY_META[row["code"]])
        bind.execute(
            sa.update(items)
            .where(items.c.code == row["code"])
            .values(asset_manifest=manifest)
        )


def upgrade() -> None:
    quests = sa.table(
        "quests",
        sa.column("code", sa.String),
        sa.column("title", sa.String),
        sa.column("description", sa.String),
        sa.column("trigger_rule", sa.String),
        sa.column("category", sa.String),
        sa.column("burden_level", sa.SmallInteger),
        sa.column("estimated_minutes", sa.Integer),
        sa.column("safety_tags", sa.JSON),
        sa.column("reward_exp", sa.Integer),
        sa.column("reward_seeds", sa.Integer),
        sa.column("is_active", sa.Boolean),
    )
    op.bulk_insert(
        quests,
        [
            {
                "code": code,
                "title": title,
                "description": description,
                "trigger_rule": "daily_neutral",
                "category": category,
                "burden_level": burden,
                "estimated_minutes": minutes,
                "safety_tags": tags,
                # 모든 감정과 모든 난이도에 같은 보상을 적용해 가치 판단을 만들지 않는다.
                "reward_exp": 20,
                "reward_seeds": 5,
                "is_active": True,
            }
            for code, title, description, category, burden, minutes, tags in QUEST_ROWS
        ],
    )
    _update_character_story_meta()


def downgrade() -> None:
    _update_character_story_meta(remove=True)
    quests = sa.table("quests", sa.column("id", sa.BigInteger), sa.column("code", sa.String))
    user_quests = sa.table("user_quests", sa.column("quest_id", sa.BigInteger))
    quest_ids = sa.select(quests.c.id).where(
        quests.c.code.in_(tuple(row[0] for row in QUEST_ROWS))
    )
    op.execute(sa.delete(user_quests).where(user_quests.c.quest_id.in_(quest_ids)))
    op.execute(
        sa.delete(quests).where(quests.c.code.in_(tuple(row[0] for row in QUEST_ROWS)))
    )
