"""사전 검수형 탐험대 관계 장면.

사용자 일기나 런타임 생성 모델을 입력으로 쓰지 않는다. 품종마다 직접 쓴 세 장면을
이름만 치환해 조합하므로 현재 15품종의 모든 동종·이종 파티를 빈칸 없이 다룬다.
야영지의 긴 대화도 품종별 질문·응답을 미리 쓴 뒤 두 캐릭터의 목소리를 조합한다.
"""

from __future__ import annotations

import hashlib
from typing import Any, Mapping, Sequence


RELATIONSHIP_MOMENTS = ("departure", "camp", "return")

SPECIES_RELATIONSHIP_LINES: dict[str, dict[str, str]] = {
    "baby-pot": {
        "departure": "{speaker}가 앞장서다 돌아와 {partner}의 손을 꼭 잡아요. ‘길은 같이 찾으면 덜 무서워!’",
        "camp": "{speaker}가 가장 동그란 잎을 골라 {partner}의 찻잔 받침으로 놓아 줘요.",
        "return": "{speaker}가 {partner}의 발자국 옆에 자기 발자국을 포개며 다음에도 같이 가자고 웃어요.",
    },
    "handsome-pot": {
        "departure": "{speaker}가 지도의 접힌 선을 반듯하게 펴고 {partner}가 걷기 편한 길을 먼저 짚어요.",
        "camp": "{speaker}는 괜찮은 척하다 {partner}가 건넨 물을 받고서야 어깨의 힘을 풀어요.",
        "return": "{speaker}가 오늘의 멋진 선택은 자기 것이 아니라 {partner}의 판단이었다고 또렷이 기록해요.",
    },
    "pretty-pot": {
        "departure": "{speaker}가 {partner}의 옷깃에 작은 꽃 한 송이를 달아 주며 탐험대 표식이라고 말해요.",
        "camp": "{speaker}가 쉼터의 빛을 {partner} 쪽으로 돌리고, 둘이 가장 예쁜 그림자를 골라요.",
        "return": "{speaker}가 흙 묻은 모습도 오늘만의 장식이라며 {partner}와 나란히 사진 자세를 잡아요.",
    },
    "tsundere-pot": {
        "departure": "{speaker}가 ‘뒤처지면 곤란하니까’라며 {partner}의 짐을 슬쩍 절반 들어요.",
        "camp": "{speaker}가 자기 몫의 따뜻한 차를 {partner} 앞에 밀어 놓고는 원래 뜨거운 건 싫다고 둘러대요.",
        "return": "{speaker}는 별일 아니었다고 말하면서도 {partner}가 문을 통과할 때까지 끝까지 기다려요.",
    },
    "zombie-pot": {
        "departure": "{speaker}가 느린 걸음으로도 {partner}의 보폭을 정확히 맞추며 절대 놓치지 않겠다고 해요.",
        "camp": "{speaker}는 졸린 눈으로 {partner}의 불침번까지 함께 서다가 둘이 동시에 꾸벅 졸아요.",
        "return": "{speaker}가 오늘도 함께 돌아왔다는 사실을 세 번 확인하고 {partner} 곁에서 안심해요.",
    },
    "gumiho-pot": {
        "departure": "{speaker}가 꼬리 끝 불빛 하나를 {partner}에게 떼어 주며 길을 잃으면 흔들어 보라고 해요.",
        "camp": "{speaker}의 불빛과 {partner}의 그림자가 쉼터 벽에서 작은 여우 한 마리를 만들어요.",
        "return": "{speaker}가 장난스러운 환영으로 {partner}의 귀환을 먼저 알리고, 진짜 모습으로 문 뒤에서 웃어요.",
    },
    "ninja-pot": {
        "departure": "{speaker}가 말없이 {partner}의 발소리에 자기 호흡을 맞춰 둘의 기척을 하나로 줄여요.",
        "camp": "{speaker}가 가장 안전한 자리를 비워 두자 {partner}가 그 자리에 간식 절반을 놓아요.",
        "return": "{speaker}는 먼저 도착할 수 있었지만 {partner}와 같은 순간 귀환선 위에 발을 디뎌요.",
    },
    "magical-pot": {
        "departure": "{speaker}가 {partner}의 지도 귀퉁이에 길을 비추는 별가루 주문을 조심스럽게 걸어요.",
        "camp": "{speaker}와 {partner}가 실패한 작은 주문을 함께 웃자, 별가루가 오히려 더 오래 반짝여요.",
        "return": "{speaker}가 오늘의 마지막 마법은 무사 귀환이라며 {partner} 머리 위에 작은 별을 띄워요.",
    },
    "aloof-pot": {
        "departure": "{speaker}가 아무 말 없이 위험한 쪽에 서자 {partner}도 말없이 반대편을 지켜요.",
        "camp": "{speaker}가 혼자 보던 먼 풍경을 {partner}에게만 조금 비켜 보여 줘요.",
        "return": "{speaker}가 먼저 문을 잡아 주고, {partner}가 지나간 뒤에야 희미하게 웃어요.",
    },
    "student-pot": {
        "departure": "{speaker}가 수첩 첫 줄에 {partner}와 함께 확인할 질문 하나를 적어요.",
        "camp": "{speaker}의 빽빽한 메모 옆에 {partner}가 작은 낙서를 더하자 오늘의 기록이 한결 따뜻해져요.",
        "return": "{speaker}가 정답보다 {partner}와 함께 찾은 과정이 더 중요했다며 페이지에 별표를 쳐요.",
    },
    "nurse-pot": {
        "departure": "{speaker}가 {partner}의 가방끈과 호흡을 차례로 살핀 뒤 이제 출발해도 좋다고 고개를 끄덕여요.",
        "camp": "{speaker}가 모두를 돌본 뒤 자기 손의 작은 흠집은 {partner}에게 조용히 맡겨요.",
        "return": "{speaker}가 {partner}의 무사 귀환을 확인하고서야 자기 이름에도 완료 표시를 해요.",
    },
    "maestro-pot": {
        "departure": "{speaker}가 지휘봉으로 두 번 박자를 세자 {partner}의 걸음과 문 여는 소리가 한 곡처럼 이어져요.",
        "camp": "{speaker}가 쉼표를 길게 그리자 {partner}도 말없이 쉬며 둘만의 고요한 악장을 만들어요.",
        "return": "{speaker}가 오늘의 마지막 박자를 {partner}에게 맡기고 둘이 함께 귀환 종을 울려요.",
    },
    "restorer-pot": {
        "departure": "{speaker}가 금 간 표찰을 금빛 선으로 잇고 {partner}에게 흠집도 길을 알려 준다고 말해요.",
        "camp": "{speaker}가 고치려던 물건을 내려놓자 {partner}가 지금은 쉬는 것도 복원이라고 알려 줘요.",
        "return": "{speaker}와 {partner}가 오늘 생긴 작은 흠집을 숨기지 않고 나란히 귀환 기록에 남겨요.",
    },
    "marten-pot": {
        "departure": "{speaker}가 앞길을 한 바퀴 재빨리 살핀 뒤 가장 안전한 발자국을 {partner}에게 알려 줘요.",
        "camp": "{speaker}가 모아 온 반짝이는 조약돌 중 가장 둥근 것을 {partner}의 자리 앞에 놓아요.",
        "return": "{speaker}가 몇 번이나 앞서 달려갔다 돌아오며 {partner}와 마지막 발걸음은 꼭 나란히 맞춰요.",
    },
    "gal-pot": {
        "departure": "{speaker}가 {partner}의 옷깃을 탐험에 맞게 고쳐 주고 둘만의 출발 자세를 정해요.",
        "camp": "{speaker}는 빛이 가장 좋은 자리를 찾고도 {partner}가 앉을 공간을 먼저 남겨 둬요.",
        "return": "{speaker}가 오늘의 흙먼지까지 멋진 기록이라며 {partner}와 당당하게 귀환선을 넘어요.",
    },
}

_GUIDE_LINES = {
    "departure": "{speaker}가 {partner}와 같은 속도로 걸으며 오늘의 첫 줄을 함께 읽어요.",
    "camp": "{speaker}와 {partner}가 말 없는 쉼표 하나를 탐험 기록 사이에 남겨요.",
    "return": "{speaker}가 {partner}의 이름 옆에 ‘함께 돌아옴’이라고 정성껏 적어요.",
}


# 핵심 대화는 아래 네 슬롯 가운데 두 품종의 질문과 응답을 교차한다. 질문은 각
# 캐릭터의 장기 아크를, 응답은 어느 파트너에게도 성립하는 말투를 직접 썼다. 따라서
# 15C2=105쌍 모두가 4줄짜리 고유 장면을 가지면서 런타임 생성 모델에 의존하지 않는다.
SPECIES_DUET_VOICES: dict[str, dict[str, str]] = {
    "baby-pot": {
        "question": "나도 누군가를 지켜 주는 쪽이 될 수 있을까?",
        "answer": "아직 답을 몰라도 같이 해 보면 돼. 내가 옆에서 손잡아 줄게!",
        "reprise": "다음에는 내가 먼저 그늘을 만들어 줄게!",
    },
    "handsome-pot": {
        "question": "점검표에 없는 일이 생기면, 내 판단을 믿어도 될까?",
        "answer": "정답이 없어도 네가 고른 길이라면 내가 뒤를 정리하지.",
        "reprise": "오늘 명단의 마지막 칸은 네 판단에 맡겨 둘게.",
    },
    "pretty-pot": {
        "question": "조명이 없는 곳에서도 내가 나답게 보일까?",
        "answer": "조명 밖이어도 네 모습은 사라지지 않아. 내가 첫 관객이 될게!",
        "reprise": "오늘의 가장 좋은 자리는 여전히 네 옆이야.",
    },
    "tsundere-pot": {
        "question": "지켜 주고 싶다는 마음을 꼭 숨겨야 하는 걸까?",
        "answer": "그런 걸 왜 혼자 고민해? …같이 하자는 뜻이야.",
        "reprise": "착각하지 마. 오늘도 네 발밑만 미리 봐 둔 거야.",
    },
    "zombie-pot": {
        "question": "모두 잠든 밤에만 또렷한 나도 도움이 될까?",
        "answer": "느려도… 끝까지 들을 수 있어. 답이 올 때까지 여기 있을게.",
        "reprise": "오늘 밤 순찰도… 네 걸음에 맞출게.",
    },
    "gumiho-pot": {
        "question": "내 장난이 도움으로 남는 선은 어디쯤일까?",
        "answer": "숨기지 않은 마음이 제일 밝네. 이번만큼은 장난 아니야.",
        "reprise": "길을 밝힐 불 하나는 네 몫으로 남겨 뒀어.",
    },
    "ninja-pot": {
        "question": "반 걸음 앞을 맡으면, 뒤의 친구와 멀어지지 않을까?",
        "answer": "앞은 내가 살핀다. 네가 돌아볼 때 같은 자리에 있겠다.",
        "reprise": "먼저 살펴도 돌아오는 자리는 잊지 않겠다.",
    },
    "magical-pot": {
        "question": "금지된 주문에도 나눠 쓸 방법이 숨어 있을까?",
        "answer": "금지 표시는 끝이 아니라 이유를 찾으라는 첫 줄일지도 몰라!",
        "reprise": "다음 변환식에는 네 이름을 안전 주문으로 넣을게.",
    },
    "aloof-pot": {
        "question": "기록보다 먼저 피어난 순간도 남길 수 있을까?",
        "answer": "기록은 나중이어도 돼. 먼저 피어난 순간은 내가 보고 있을게.",
        "reprise": "오늘은 여백부터 남겨 둘게. 네 순간이 먼저니까.",
    },
    "student-pot": {
        "question": "모두를 챙긴 다음, 내 이름은 언제 적어야 할까?",
        "answer": "네 이름도 지금 적자. 한 사람이 빠진 계획표는 정답이 아니니까.",
        "reprise": "오늘 당번표에는 우리 둘 이름부터 적었어.",
    },
    "nurse-pot": {
        "question": "모두를 돌본 뒤에 내 차례를 받아도 괜찮을까요?",
        "answer": "돌보는 사람도 돌봄을 받아야 해요. 오늘은 제가 확인할게요.",
        "reprise": "서로의 이름에 무사 표시를 함께 남겨요.",
    },
    "maestro-pot": {
        "question": "내가 멈춘 박자가 누군가의 리듬까지 빼앗진 않을까?",
        "answer": "완벽한 박자보다 다시 시작할 쉼표가 필요한 때가 있어.",
        "reprise": "다음 쉼표 뒤의 첫박은 네 호흡에 맞추지.",
    },
    "restorer-pot": {
        "question": "흔적을 남긴 채 고쳐도 완전하다고 할 수 있을까?",
        "answer": "금은 지우지 않아도 돼. 버텨 온 모양까지 이어 붙이면 되니까.",
        "reprise": "오늘의 작은 흠집도 지우지 않고 잘 이어 둘게.",
    },
    "marten-pot": {
        "question": "흩어진 발자국 사이에서 혼자 남은 냄새를 오래 살펴요.",
        "answer": "상대의 손등에 코를 대고 같은 무리라는 듯 꼬리를 감아요.",
        "reprise": "익숙한 발자국 옆에 자기 앞발 자국을 포개요.",
    },
    "gal-pot": {
        "question": "좋아하는 걸 크게 보여 주면 마음까지 가벼워 보일까?",
        "answer": "좋아한다는 마음은 숨길수록 흐려져. 네 방식대로 보여 줘!",
        "reprise": "오늘의 흔적도 우리답게 멋진 패치로 남기자.",
    },
}


def relationship_beat(
    members: Sequence[Mapping[str, Any]], *, moment: str, seed: str
) -> dict[str, str] | None:
    """Return one deterministic party beat, or ``None`` for a solo party."""
    if moment not in RELATIONSHIP_MOMENTS:
        raise ValueError(f"unsupported relationship moment: {moment}")
    if len(members) < 2:
        return None
    fingerprint = "|".join(
        f"{member.get('species_code', '')}:{member.get('name', '')}"
        for member in members
    )
    digest = hashlib.sha256(f"{seed}:{moment}:{fingerprint}".encode()).digest()
    speaker_index = digest[0] % len(members)
    partner_index = (speaker_index + 1 + digest[1] % (len(members) - 1)) % len(members)
    speaker = members[speaker_index]
    partner = members[partner_index]
    speaker_code = str(speaker.get("species_code", "archive_guide"))
    partner_code = str(partner.get("species_code", "archive_guide"))
    line = SPECIES_RELATIONSHIP_LINES.get(speaker_code, _GUIDE_LINES)[moment]
    pair_code = ".".join(sorted((speaker_code, partner_code)))
    return {
        "code": f"relationship.{pair_code}.{moment}",
        "moment": moment,
        "title": {
            "departure": "출발 전의 약속",
            "camp": "쉼터의 한 장면",
            "return": "함께 돌아온 순간",
        }[moment],
        "caption": line.format(
            speaker=str(speaker.get("name", "탐험대원")),
            partner=str(partner.get("name", "탐험대원")),
        ),
        "speaker_name": str(speaker.get("name", "탐험대원")),
        "partner_name": str(partner.get("name", "탐험대원")),
    }


def relationship_duet(
    members: Sequence[Mapping[str, Any]], *, reprise: bool = False
) -> dict[str, Any] | None:
    """Render one pre-authored distinct-species camp dialogue.

    The caller chooses which party pair receives the scene and whether the
    account has already seen its core version. Sorting by species keeps the
    content key stable when party order changes.
    """
    if len(members) != 2:
        raise ValueError("relationship duet requires exactly two members")
    pair = sorted(
        members,
        key=lambda member: (
            str(member.get("species_code", "")),
            str(member.get("name", "")),
        ),
    )
    left, right = pair
    left_code = str(left.get("species_code", ""))
    right_code = str(right.get("species_code", ""))
    if left_code == right_code:
        return None
    if left_code not in SPECIES_DUET_VOICES or right_code not in SPECIES_DUET_VOICES:
        return None

    left_name = str(left.get("name", "탐험대원"))
    right_name = str(right.get("name", "탐험대원"))
    pair_code = f"{left_code}__{right_code}"
    variant = "reprise" if reprise else "core"
    if reprise:
        lines = [
            {
                "speaker_name": left_name,
                "text": SPECIES_DUET_VOICES[left_code]["reprise"],
            },
            {
                "speaker_name": right_name,
                "text": SPECIES_DUET_VOICES[right_code]["reprise"],
            },
        ]
        narration = ""
        title = "다시 이어진 야영지 이야기"
    else:
        lines = [
            {
                "speaker_name": left_name,
                "text": SPECIES_DUET_VOICES[left_code]["question"],
            },
            {
                "speaker_name": right_name,
                "text": SPECIES_DUET_VOICES[right_code]["answer"],
            },
            {
                "speaker_name": right_name,
                "text": SPECIES_DUET_VOICES[right_code]["question"],
            },
            {
                "speaker_name": left_name,
                "text": SPECIES_DUET_VOICES[left_code]["answer"],
            },
        ]
        narration = (
            f"야영지의 불빛이 낮아지자 {left_name}와 {right_name}이(가) "
            "평소 미뤄 둔 질문을 하나씩 꺼내요."
        )
        title = "불빛 곁의 깊은 이야기"
    return {
        "code": f"story.duet.{pair_code}.{variant}",
        "pair_code": pair_code,
        "variant": variant,
        "title": title,
        "narration": narration,
        "lines": lines,
    }
