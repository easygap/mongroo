"""퀘스트와 캐릭터 도감 문구 갱신

Revision ID: 0009_content_copy
Revises: 0008_character_voice
Create Date: 2026-07-14
"""

from alembic import op
import sqlalchemy as sa


revision = "0009_content_copy"
down_revision = "0008_character_voice"
branch_labels = None
depends_on = None


QUEST_COPY = {
    "QST_NOTICE_THREE": (
        "색·모양·글자 찾기",
        "지금 있는 곳에서 색, 모양, 글자를 하나씩 찾아 이름을 적어보세요.",
    ),
    "QST_TODAY_COLOR": (
        "오늘을 대표할 색",
        "색상표나 주변 물건에서 오늘 기분에 어울리는 색을 고르고 이름을 붙여보세요.",
    ),
    "QST_SIP_COMMA": (
        "음료 세 모금",
        "물이나 평소 마시는 음료를 준비해 세 모금 마신 뒤 컵을 내려놓으세요.",
    ),
    "QST_WINDOW_HELLO": (
        "창밖 30초 관찰",
        "창문 너머나 방 안 먼 곳을 30초 보고, 움직이는 것과 멈춰 있는 것을 하나씩 찾아보세요.",
    ),
    "QST_TIDY_THREE": (
        "책상 위 세 물건 정리",
        "가장 가까운 물건 세 개를 원래 자리나 사용하기 편한 곳으로 옮겨보세요.",
    ),
    "QST_ONE_TRUE_SENTENCE": (
        "오늘 상태 한 줄",
        "‘지금 나는 ___하다’ 문장을 완성해 메모에 남겨보세요.",
    ),
    "QST_BODY_WEATHER": (
        "몸 상태 빠른 점검",
        "턱, 어깨, 손 세 곳을 차례로 살펴 편한 곳과 불편한 곳을 확인하세요.",
    ),
    "QST_OWN_PACE_WALK": (
        "익숙한 길 7분",
        "가능하면 안전하고 익숙한 곳을 7분 걸어보세요. 밖이 어렵다면 실내에서 이동하거나 앉은 채 발을 번갈아 움직여도 됩니다.",
    ),
    "QST_COLLECT_SOUNDS": (
        "가까운 소리·먼 소리",
        "지금 들리는 소리 중 가까운 것 두 개와 먼 것 하나를 구분해보세요.",
    ),
    "QST_KEEP_A_SCENE": (
        "오늘의 장면 캡션",
        "오늘 기억나는 장면 하나를 고르고 사진 설명처럼 20자 안팎으로 적어보세요.",
    ),
    "QST_LIGHT_HELLO": (
        "화면 밖 시선 휴식",
        "휴대폰에서 시선을 떼고 방 안의 먼 지점이나 창밖을 30초 바라보세요.",
    ),
    "QST_TOMORROW_SEED": (
        "내일 준비물 꺼내기",
        "내일 쓸 옷, 가방, 문서 중 하나를 골라 눈에 보이는 곳에 준비해두세요.",
    ),
    "QST_NAME_THE_MOMENT": (
        "현재 기분 두 단어",
        "지금 상태를 설명하는 단어 두 개를 메모에 적어보세요. 서로 반대여도 됩니다.",
    ),
    "QST_TEXTURE_SCOUT": (
        "촉감 비교: 매끈·거침",
        "안전하게 만질 수 있는 물건 두 개를 골라 어느 쪽이 더 매끈한지 비교해보세요.",
    ),
    "QST_TEMPERATURE_NOTE": (
        "공기 온도 체크",
        "손등에 닿는 공기가 따뜻한지, 서늘한지, 비슷한지 셋 중 하나로 기록하세요.",
    ),
    "QST_PALM_SPACE": (
        "우편엽서 크기 정리",
        "책상이나 선반에서 엽서 정도 넓이를 비우고 치운 물건은 가까운 자리에 모아두세요.",
    ),
    "QST_SHOULDER_DROP": (
        "어깨 으쓱 한 번",
        "불편하지 않다면 어깨를 귀 쪽으로 한 번 올렸다가 숨을 내쉬며 내려놓으세요. 동작이 어렵다면 생략해도 됩니다.",
    ),
    "QST_COMFY_POSTURE": (
        "등·팔·발 위치 바꾸기",
        "등받이에 기대기, 팔 내려놓기, 발 위치 옮기기 중 편해 보이는 하나를 선택하세요. 현재 자세가 낫다면 그대로 두세요.",
    ),
    "QST_ONE_MINUTE_GAP": (
        "알림 끄고 1분",
        "타이머를 1분으로 맞춘 뒤 알림과 화면을 보지 않는 시간을 가져보세요.",
    ),
    "QST_CHOOSE_NOT_TODO": (
        "오늘 목록에서 하나 빼기",
        "오늘 할 일 중 내일로 미뤄도 문제가 적은 항목 하나에 ‘내일’ 표시를 해두세요.",
    ),
    "QST_MOOD_SHAPE": (
        "선 세 개로 기분 그리기",
        "종이나 메모 앱에 직선, 곡선, 점을 한 번씩 써서 오늘 상태를 표시해보세요.",
    ),
    "QST_MEMORY_TITLE": (
        "오늘 장면에 영화 제목",
        "가장 먼저 떠오르는 장면을 고르고 다섯 단어 안으로 제목을 붙여보세요.",
    ),
    "QST_SMALL_BOUNDARY": (
        "방해 금지 10분 예약",
        "방해받고 싶지 않은 시간대를 10분 정해 달력이나 메모에 표시하세요. 당장 지키지 못해도 표시만 하면 됩니다.",
    ),
    "QST_KIND_SELF_LINE": (
        "친구에게 하듯 한 줄",
        "오늘 수고한 일을 하나 떠올리고, 친한 친구에게 말하듯 짧은 답장을 적어보세요.",
    ),
    "QST_SKY_PATCH": (
        "하늘 색 확인",
        "창밖이나 저장된 사진에서 하늘을 찾아 색을 한 단어로 적어보세요. 하늘을 볼 수 없으면 천장이나 벽의 색을 골라도 됩니다.",
    ),
    "QST_SOUNDTRACK_PICK": (
        "오늘 장면의 배경음",
        "오늘과 어울리는 노래 제목을 하나 고르세요. 소리를 재생하지 않고 제목만 떠올려도 됩니다.",
    ),
    "QST_SLOW_HANDS": (
        "손 동작 리플레이",
        "컵 들기, 문 열기, 펜 놓기 중 가능한 동작을 한 번 하고 손의 움직임을 관찰하세요. 동작이 불편하면 눈으로만 따라가도 됩니다.",
    ),
    "QST_OBJECT_STORY": (
        "책상 물건 시점 일기",
        "가까운 물건 하나를 화자로 정해 ‘오늘 나는 ___을 봤다’ 한 줄을 완성하세요.",
    ),
    "QST_EASY_CHOICE": (
        "2분 안에 끝낼 일 선택",
        "지금 가능한 일 중 준비가 가장 적게 필요한 항목을 하나 골라 체크 표시만 해두세요.",
    ),
    "QST_UNSENT_HELLO": (
        "전송하지 않는 안부 초안",
        "떠오르는 사람이 있다면 안부 한 줄을 메모장에 쓰고 저장하지 않아도 됩니다. 사람이 떠오르지 않으면 좋아하는 캐릭터에게 적어보세요.",
    ),
    "QST_FIVE_MIN_RESET": (
        "자주 쓰는 자리 5분 정리",
        "책상, 침대 옆, 가방 중 한 곳을 고르고 타이머가 울릴 때까지만 정리하세요.",
    ),
    "QST_FUTURE_NOTE": (
        "주말 전에 볼 메모",
        "이번 주가 끝나기 전에 기억할 일 하나와 챙길 일 하나를 메모에 남기세요.",
    ),
    "QST_FRESH_AIR_OPTION": (
        "방 공기 5분 바꾸기",
        "가능하면 창문이나 문을 열어 환기하세요. 여의치 않으면 익숙한 실내에서 다른 자리로 옮겨 앉아도 됩니다.",
    ),
    "QST_TINY_DELAYED_TASK": (
        "미룬 일, 첫 화면 열기",
        "미뤄 둔 일에 필요한 앱, 문서, 가방 중 하나를 열고 5분 동안 첫 단계만 진행하세요.",
    ),
    "QST_REST_CORNER": (
        "쉬는 자리 세팅",
        "의자나 침대 주변에 물, 충전기, 쿠션 중 필요한 물건 하나를 두고 사용 후 돌려놓을 자리를 정하세요.",
    ),
    "QST_GENTLE_REACH": (
        "앉은 자리 몸풀기",
        "앉거나 선 자세에서 불편하지 않은 손목 또는 발목을 세 번 돌려보세요. 어렵다면 손가락을 펴고 오므리는 동작으로 바꿔도 됩니다.",
    ),
}


OLD_QUEST_COPY = {
    "QST_NOTICE_THREE": ("지금 보이는 세 가지", "주변에서 눈에 들어오는 것 세 가지를 천천히 찾아보세요."),
    "QST_TODAY_COLOR": ("오늘의 색 한 가지", "지금 마음과 닮았다고 느끼는 색 하나를 골라보세요. 이유는 없어도 괜찮아요."),
    "QST_SIP_COMMA": ("물 한 모금의 쉼표", "물이나 따뜻한 음료를 한 모금 천천히 마시며 잠깐 쉬어보세요."),
    "QST_WINDOW_HELLO": ("창밖에 짧은 인사", "창밖이나 먼 곳을 잠시 바라보며 오늘의 바깥과 인사해 보세요."),
    "QST_TIDY_THREE": ("세 가지만 제자리로", "눈앞의 물건 세 가지만 편한 자리로 옮겨보세요."),
    "QST_ONE_TRUE_SENTENCE": ("솔직한 한 문장", "지금의 기분을 꾸미지 않고 한 문장으로 적어보세요."),
    "QST_BODY_WEATHER": ("몸의 날씨 살피기", "머리부터 발끝까지 천천히 살피며 편한 곳과 뻐근한 곳을 알아차려 보세요."),
    "QST_OWN_PACE_WALK": ("내 속도로 잠깐 걷기", "가능하다면 안전하고 익숙한 곳을 내 속도로 잠깐 걸어보세요."),
    "QST_COLLECT_SOUNDS": ("소리 세 개 모으기", "가까운 소리와 먼 소리를 포함해 들리는 소리 세 개를 찾아보세요."),
    "QST_KEEP_A_SCENE": ("간직하고 싶은 장면", "오늘 스쳐 간 장면 중 하나를 짧게 적거나 마음속에 담아보세요."),
    "QST_LIGHT_HELLO": ("빛에게 인사하기", "햇빛이나 조명처럼 곁의 빛을 잠시 바라보며 눈을 쉬게 해주세요."),
    "QST_TOMORROW_SEED": ("내일을 위한 작은 씨앗", "내일의 나를 위해 5분 안에 할 수 있는 작은 준비 하나를 해보세요."),
    "QST_NAME_THE_MOMENT": ("지금 마음에 이름 붙이기", "정답을 찾지 말고 지금 마음을 한두 단어로 불러보세요. 어떤 이름이어도 괜찮아요."),
    "QST_TEXTURE_SCOUT": ("촉감 탐험가", "손이 닿는 안전한 물건 하나의 촉감을 천천히 느껴보세요."),
    "QST_TEMPERATURE_NOTE": ("온도 한 칸 알아차리기", "손끝이나 볼에 닿는 공기가 따뜻한지 서늘한지 잠깐 알아차려 보세요."),
    "QST_PALM_SPACE": ("손바닥만 한 자리", "손바닥만 한 공간 하나를 골라 물건을 편한 자리로 옮겨보세요."),
    "QST_SHOULDER_DROP": ("어깨 힘 한 번 놓기", "불편하지 않은 범위에서 어깨를 올렸다가 천천히 내려보세요."),
    "QST_COMFY_POSTURE": ("조금 더 편한 자세", "지금 자세에서 한 군데만 편하게 바꿔보세요. 그대로가 편하면 바꾸지 않아도 돼요."),
    "QST_ONE_MINUTE_GAP": ("1분짜리 빈칸", "할 일을 잠시 멈추고 아무것도 채우지 않는 1분을 가져보세요."),
    "QST_CHOOSE_NOT_TODO": ("오늘 안 해도 될 한 가지", "오늘 목록에서 미뤄도 괜찮은 것 하나를 골라 부담을 조금 덜어보세요."),
    "QST_MOOD_SHAPE": ("마음 모양 낙서", "종이나 메모장에 지금 마음과 닮은 선이나 모양 하나를 자유롭게 그려보세요."),
    "QST_MEMORY_TITLE": ("오늘 장면의 제목", "오늘 기억에 남은 장면 하나에 영화 제목처럼 짧은 이름을 붙여보세요."),
    "QST_SMALL_BOUNDARY": ("나를 위한 작은 경계", "지금 지키고 싶은 내 시간이나 공간 한 가지를 마음속으로 정해보세요."),
    "QST_KIND_SELF_LINE": ("내 편 한 문장", "친한 사람에게 말하듯 지금의 나에게 부담 없는 한 문장을 건네보세요."),
    "QST_SKY_PATCH": ("하늘 한 조각 찾기", "창문이나 사진 속에서도 좋아요. 하늘 한 조각을 잠시 바라보세요."),
    "QST_SOUNDTRACK_PICK": ("오늘의 배경음 고르기", "소리를 듣지 않아도 괜찮아요. 오늘과 어울리는 노래나 소리 하나를 떠올려 보세요."),
    "QST_SLOW_HANDS": ("손끝 속도 낮추기", "컵을 들거나 문을 여는 평범한 동작 하나를 평소보다 천천히 해보세요."),
    "QST_OBJECT_STORY": ("물건 하나의 한 줄 이야기", "곁의 물건 하나를 골라 오늘 그 물건이 본 장면을 한 줄로 상상해 보세요."),
    "QST_EASY_CHOICE": ("가장 쉬운 선택 먼저", "지금 할 수 있는 선택 중 가장 부담이 작은 것 하나만 골라보세요."),
    "QST_UNSENT_HELLO": ("보내지 않아도 되는 안부", "누군가 떠오른다면 보내지 않아도 되는 짧은 안부 한 줄을 적어보세요."),
    "QST_FIVE_MIN_RESET": ("5분 정원 리셋", "자주 머무는 자리 한 곳을 5분 동안만 편하게 정돈해 보세요."),
    "QST_FUTURE_NOTE": ("미래의 나에게 쪽지", "오늘을 지나온 나에게 기억해 주고 싶은 말을 짧게 남겨보세요."),
    "QST_FRESH_AIR_OPTION": ("공기 바꾸기 선택지", "가능하다면 안전한 곳에서 창문을 잠깐 열거나 익숙한 바깥 공기를 느껴보세요."),
    "QST_TINY_DELAYED_TASK": ("미뤄 둔 일의 첫 조각", "미뤄 둔 일 하나에서 5분 안에 끝낼 수 있는 첫 조각만 해보세요."),
    "QST_REST_CORNER": ("쉬는 자리 한 칸 만들기", "쿠션이나 컵처럼 편안함을 더하는 물건 하나로 작은 휴식 자리를 만들어 보세요."),
    "QST_GENTLE_REACH": ("내 방식의 가벼운 움직임", "앉거나 선 자세 모두 좋아요. 불편하지 않은 범위에서 몸 한 곳을 천천히 움직여 보세요."),
}


CHARACTER_STORY_COPY = {
    "character_baby_pot": ("박물관 창고에서 쪽쪽이와 함께 발견된 첫 번째 꼬마 화분.", "뽀또! 새싹 스티커는 내가 붙일래!"),
    "character_handsome_pot": ("식물 학교 수석 배지를 달고 비밀 온실의 열쇠를 관리한다.", "온실 점검 끝. 다음 구역으로 가지."),
    "character_pretty_pot": ("정원 축제 메인 스테이지의 순서표와 조명을 직접 챙기는 새싹 아이돌.", "조명 켜! 이번 무대 센터는 나야."),
    "character_tsundere_pot": ("가시 울타리 경비대 소속으로, 분실한 씨앗 주머니를 몰래 주인에게 돌려놓는다.", "예비 씨앗은 남아서 주는 거야."),
    "character_zombie_pot": ("해가 지면 묘목 창고에서 깨어나 야간 출석 도장을 찍는다.", "으으… 해 뜨기 전에 한 바퀴 더."),
    "character_gumiho_pot": ("달빛 신사의 봉인이 풀린 밤, 아홉 꼬리불을 훔쳐 달아난 여우 화분.", "후후, 마지막 꼬리불은 어디 있게?"),
    "character_ninja_pot": ("잎 수리검과 연막 씨앗으로 정원 외곽을 정찰하는 그림자 대원.", "연막 씨앗 장전. 셋에 이동한다."),
    "character_magical_pot": ("별잎 마법학원에서 금지된 잡초 변환식을 시험해 온실 지붕을 덩굴로 덮었다.", "별자리 세 번째 줄, 주문 개시!"),
    "character_aloof_pot": ("서리동백 연구소에서 희귀 꽃의 개화 시간을 초 단위로 기록하는 책임자.", "표본은 손대지 마. 기록부터 확인해."),
    "character_student_pot": ("식물 학교 학생회장으로 축제 당번표와 씨앗 창고 장부를 동시에 관리한다.", "수첩 펴. 오늘 순서는 내가 정리할게."),
}


OLD_CHARACTER_STORY_COPY = {
    "character_baby_pot": ("처음 깨어난 날부터 작은 마음의 소리를 누구보다 먼저 알아듣는다.", "작은 마음도 여기 잘 심어 둘게!"),
    "character_handsome_pot": ("말없이 온실 문을 지키지만 비 오는 날이면 우산을 먼저 내민다.", "네 속도는 내가 지켜 줄게."),
    "character_pretty_pot": ("감춰 둔 마음까지 각자의 빛으로 무대에 올리는 아이돌이다.", "오늘의 하이라이트는 솔직한 너야!"),
    "character_tsundere_pot": ("기다린 적 없다고 말하면서도 늘 가장 포근한 자리를 비워 둔다.", "네 자리라서 비워 둔 건 아니거든."),
    "character_zombie_pot": ("조금 시들어도 다음 날 다시 고개를 드는 정원의 오래된 비밀이다.", "천천히 가도 다시 싹은 나."),
    "character_gumiho_pot": ("아홉 꼬리마다 서로 다른 마음의 비밀을 하나씩 숨겨 두었다.", "숨긴 마음도 꽤 귀엽네?"),
    "character_ninja_pot": ("큰 결심보다 오늘 할 수 있는 작은 임무 하나를 정확히 찾아낸다.", "작은 임무 하나면 충분하다."),
    "character_magical_pot": ("정답 없는 마음을 만날 때마다 새로운 주문을 발명한다.", "정답 대신 네 주문을 만들자!"),
    "character_aloof_pot": ("차가운 표정 뒤에서 흔들리는 잎을 가장 조용히 받쳐 준다.", "흔들려도 품위는 잃지 않는 법이야."),
    "character_student_pot": ("복잡한 하루를 가장 작은 한 칸부터 정리하는 데 누구보다 능숙하다.", "오늘은 한 칸만 채워도 합격이야."),
}


def _apply_quest_copy(copy: dict[str, tuple[str, str]]) -> None:
    quests = sa.table(
        "quests",
        sa.column("code", sa.String),
        sa.column("title", sa.String),
        sa.column("description", sa.String),
    )
    bind = op.get_bind()
    for code, (title, description) in copy.items():
        bind.execute(
            sa.update(quests)
            .where(quests.c.code == code)
            .values(title=title, description=description)
        )


def _apply_character_story(copy: dict[str, tuple[str, str]]) -> None:
    items = sa.table(
        "items",
        sa.column("code", sa.String),
        sa.column("asset_manifest", sa.JSON),
    )
    bind = op.get_bind()
    rows = bind.execute(
        sa.select(items.c.code, items.c.asset_manifest).where(
            items.c.code.in_(tuple(copy))
        )
    ).mappings()
    for row in rows:
        lore_hook, collection_quote = copy[row["code"]]
        manifest = dict(row["asset_manifest"] or {})
        manifest["lore_hook"] = lore_hook
        manifest["collection_quote"] = collection_quote
        bind.execute(
            sa.update(items)
            .where(items.c.code == row["code"])
            .values(asset_manifest=manifest)
        )


def upgrade() -> None:
    _apply_quest_copy(QUEST_COPY)
    _apply_character_story(CHARACTER_STORY_COPY)


def downgrade() -> None:
    _apply_quest_copy(OLD_QUEST_COPY)
    _apply_character_story(OLD_CHARACTER_STORY_COPY)
