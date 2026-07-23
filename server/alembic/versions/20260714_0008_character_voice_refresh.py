"""캐릭터 설명과 대사 정리

Revision ID: 0008_character_voice
Revises: 0007_plant_museum
Create Date: 2026-07-14
"""

from alembic import op
import sqlalchemy as sa


revision = "0008_character_voice"
down_revision = "0007_plant_museum"
branch_labels = None
depends_on = None


CHARACTER_COPY = {
    "character_baby_pot": {
        "description": "쪽쪽이를 문 채 새 화분을 구경하는 정원의 막내",
        "personality": "궁금한 건 손부터 뻗는 정원 막내",
        "catchphrase": "쪽쪽! 오늘 얘기 들려줘.",
        "lore_hook": "박물관 창고에서 쪽쪽이와 함께 발견된 첫 번째 꼬마 화분.",
        "collection_quote": "뽀또! 새싹 스티커는 내가 붙일래!",
    },
    "character_handsome_pot": {
        "description": "식물 학교 코트를 단정히 입은 온실 수호자",
        "personality": "말보다 행동이 빠른 냉정한 우등생",
        "catchphrase": "말하고 싶을 때만 해. 듣고 있을게.",
        "lore_hook": "식물 학교 수석 배지를 달고 비밀 온실의 열쇠를 관리한다.",
        "collection_quote": "온실 점검 끝. 다음 구역으로 가지.",
    },
    "character_pretty_pot": {
        "description": "초록 케이프를 휘날리는 정원 스테이지의 센터",
        "personality": "분위기를 읽고 무대를 여는 씩씩한 센터",
        "catchphrase": "좋아, 오늘 장면은 네가 골라!",
        "lore_hook": "정원 축제 메인 스테이지의 순서표와 조명을 직접 챙기는 새싹 아이돌.",
        "collection_quote": "조명 켜! 이번 무대 센터는 나야.",
    },
    "character_tsundere_pot": {
        "description": "깨진 화분 보호구를 고집하는 성질 급한 라이벌",
        "personality": "툴툴대도 필요한 건 미리 챙기는 라이벌",
        "catchphrase": "늦었잖아. 기다린 건 아니고.",
        "lore_hook": "가시 울타리 경비대 소속으로, 분실한 씨앗 주머니를 몰래 주인에게 돌려놓는다.",
        "collection_quote": "예비 씨앗은 남아서 주는 거야.",
    },
    "character_zombie_pot": {
        "description": "잠이 덜 깬 얼굴로 매일 출석하는 화분 좀비",
        "personality": "느리지만 한번 정한 길은 끝까지 가는 생존왕",
        "catchphrase": "으으… 출석은 했어.",
        "lore_hook": "해가 지면 묘목 창고에서 깨어나 야간 출석 도장을 찍는다.",
        "collection_quote": "으으… 해 뜨기 전에 한 바퀴 더.",
    },
    "character_gumiho_pot": {
        "description": "아홉 꼬리로 전시실 소문을 모으는 달밤의 장난꾼",
        "personality": "능청스러운 눈치와 대담함을 가진 여우",
        "catchphrase": "후후, 꼬리 아홉 개를 다 찾았어?",
        "lore_hook": "달빛 신사의 봉인이 풀린 밤, 아홉 꼬리불을 훔쳐 달아난 여우 화분.",
        "collection_quote": "후후, 마지막 꼬리불은 어디 있게?",
    },
    "character_ninja_pot": {
        "description": "화분 배낭에 임무 도구를 꽉 채운 잎 닌자",
        "personality": "작은 목표를 빠르게 끝내는 정찰꾼",
        "catchphrase": "표적 확인. 한 가지만 끝낸다.",
        "lore_hook": "잎 수리검과 연막 씨앗으로 정원 외곽을 정찰하는 그림자 대원.",
        "collection_quote": "연막 씨앗 장전. 셋에 이동한다.",
    },
    "character_magical_pot": {
        "description": "덩굴 모자와 화분 가방을 든 식물 마법사",
        "personality": "규칙보다 새 실험을 좋아하는 마법학교 우등생",
        "catchphrase": "정답이 없으면 주문부터 만들자.",
        "lore_hook": "별잎 마법학원에서 금지된 잡초 변환식을 시험해 온실 지붕을 덩굴로 덮었다.",
        "collection_quote": "별자리 세 번째 줄, 주문 개시!",
    },
    "character_aloof_pot": {
        "description": "흰 연구 코트와 반듯한 검은 단발의 식물 연구원",
        "personality": "표정은 차갑지만 관찰은 누구보다 세심한 연구원",
        "catchphrase": "흐트러졌네. 내가 정리해 줄게.",
        "lore_hook": "서리동백 연구소에서 희귀 꽃의 개화 시간을 초 단위로 기록하는 책임자.",
        "collection_quote": "표본은 손대지 마. 기록부터 확인해.",
    },
    "character_student_pot": {
        "description": "새싹 배지와 화분 책가방을 맨 학생회장",
        "personality": "계획표는 꼼꼼하지만 웃음은 시원한 학생회장",
        "catchphrase": "오늘은 한 칸만 체크하자.",
        "lore_hook": "식물 학교 학생회장으로 축제 당번표와 씨앗 창고 장부를 동시에 관리한다.",
        "collection_quote": "수첩 펴. 오늘 순서는 내가 정리할게.",
    },
}

COMPANION_COPY = {
    "character_mongle": "새싹을 달고 둥실 떠다니는 구름 친구",
    "companion_dewdrop": "잎 목도리를 두른 물방울 탐험가",
    "companion_star": "앞장서서 길을 가리키는 별 모양 씨앗",
    "companion_bunny": "씨앗 가방을 메고 정원을 뛰어다니는 잎귀 토끼",
}

OLD_CHARACTER_COPY = {
    "character_baby_pot": ("민트 쪽쪽이와 포근한 싸개잎을 두른 정원의 막내", "호기심이 자라는 순수한 막내", "오늘 마음도 내가 꼭 안아 둘게!"),
    "character_handsome_pot": ("말수는 적지만 언제나 먼저 곁을 지키는 무심한 정원 에이스", "차가워 보여도 속은 다정한 냉미남", "말 안 해도 괜찮아. 여기 있을게."),
    "character_pretty_pot": ("솔직한 마음을 가장 반짝이는 무대로 만드는 정원의 센터", "자신감 넘치고 다정한 센터 아이돌", "솔직한 네 마음이 오늘의 하이라이트야!"),
    "character_tsundere_pot": ("딱히 기다린 건 아니지만 네 자리는 미리 데워 둔 새침한 화분", "툴툴대면서 은근히 챙기는 단짝", "딱히 네가 와서 좋은 건 아니거든!"),
    "character_zombie_pot": ("새벽에도 비틀비틀 출석하는 끈질긴 생명력의 언데드 화분", "느긋하지만 절대 포기하지 않는 생존왕", "느려도 괜찮아… 결국 도착하니까."),
    "character_gumiho_pot": ("부채 뒤 미소와 아홉 꼬리로 숨긴 마음까지 알아채는 장난꾸러기", "발칙한 장난기와 천년의 여유를 품은 여우", "숨긴 마음은 꼬리 끝에 다 보이거든?"),
    "character_ninja_pot": ("그림자 사이로 슝 나타나 오늘의 작은 임무를 함께하는 화분", "말수는 적고 의리는 깊은 임무 달인", "오늘의 임무, 조용히 시작하지."),
    "character_magical_pot": ("별자리 망토와 식물 마도서를 펼치는 마법학원 최고의 문제아", "영리하고 대담한 마법학원 에이스", "정답 없는 마음이라면, 새 주문을 만들면 되지!"),
    "character_aloof_pot": ("서리 맺힌 동백잎을 우아하게 두른, 눈길 한 번도 특별한 화분", "도도하고 말수는 적지만 은근히 곁을 지키는 동백 아가씨", "흥, 이 정도 추위에 흔들릴 내가 아니야."),
    "character_student_pot": ("반듯한 교복 차림으로 오늘의 계획을 야무지게 챙기는 학생회장 화분", "꼼꼼하고 책임감 넘치지만 웃을 때는 한없이 다정한 학생회장", "오늘 할 일은 작게 나누면 금방 끝나."),
}

OLD_COMPANION_COPY = {
    "character_mongle": "마음을 포근하게 안아 주는 구름 친구",
    "companion_dewdrop": "반짝이는 아침 이슬 요정",
    "companion_star": "작게 반짝이며 곁을 지키는 별 친구",
    "companion_bunny": "조용히 귀를 기울여 주는 토끼 친구",
}


def _apply_character_copy(copy: dict[str, dict[str, str]]) -> None:
    bind = op.get_bind()
    items = sa.table(
        "items",
        sa.column("code", sa.String),
        sa.column("description", sa.String),
        sa.column("asset_manifest", sa.JSON),
    )
    rows = bind.execute(
        sa.select(items.c.code, items.c.asset_manifest).where(
            items.c.code.in_(tuple(copy))
        )
    ).mappings()
    for row in rows:
        values = copy[row["code"]]
        manifest = dict(row["asset_manifest"] or {})
        for key in (
            "personality",
            "catchphrase",
            "lore_hook",
            "collection_quote",
        ):
            if key in values:
                manifest[key] = values[key]
        bind.execute(
            sa.update(items)
            .where(items.c.code == row["code"])
            .values(description=values["description"], asset_manifest=manifest)
        )


def _apply_companion_copy(copy: dict[str, str]) -> None:
    items = sa.table(
        "items",
        sa.column("code", sa.String),
        sa.column("description", sa.String),
    )
    bind = op.get_bind()
    for code, description in copy.items():
        bind.execute(
            sa.update(items)
            .where(items.c.code == code)
            .values(description=description)
        )


def upgrade() -> None:
    _apply_character_copy(CHARACTER_COPY)
    _apply_companion_copy(COMPANION_COPY)


def downgrade() -> None:
    restored = {
        code: {
            "description": values[0],
            "personality": values[1],
            "catchphrase": values[2],
        }
        for code, values in OLD_CHARACTER_COPY.items()
    }
    _apply_character_copy(restored)
    _apply_companion_copy(OLD_COMPANION_COPY)
