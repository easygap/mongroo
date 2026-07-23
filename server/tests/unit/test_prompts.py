from app.ai.prompts import build_chat_messages, greeting_line
from app.ai.llm import FakeLlm


GROWTH_PERSONA = {
    "persona_key": "gentle_listener",
    "persona_name": "빗물결",
    "trait": "섬세함·경청",
    "voice_line": "잎 끝의 물방울, 떨어질 때까지 지켜볼래.",
}


def test_greeting_uses_natural_korean_subject_particle():
    assert greeting_line("sprout", "새싹몬").startswith("새싹몬이 ")
    assert greeting_line("sunflower", "해바라기").startswith("해바라기가 ")
    assert "이(가)" not in greeting_line("sprout", "새싹몬")


def test_growth_persona_is_added_to_prompt_without_replacing_species_identity():
    messages = build_chat_messages(
        "cactus", "가시니", "explore", [], None, GROWTH_PERSONA
    )
    system = messages[0]["content"]
    assert "가시니" in system and "무뚝뚝하지만 속정 깊은 선인장" in system
    assert "빗물결" in system and "섬세함·경청" in system
    assert GROWTH_PERSONA["voice_line"] in system
    assert "사용자를 진단하거나 평가" in system


def test_growth_persona_greeting_uses_the_revealed_voice_line():
    line = greeting_line("sprout", "초록이", GROWTH_PERSONA)
    assert line.startswith("초록이: 잎 끝의 물방울")
    assert line.endswith("오늘 이야기도 들려줄래?")


def test_growth_context_adds_secondary_temperament_and_stage_to_prompt():
    context = {
        "stage": 4,
        "growth_phase": "bloom",
        "growth_traits": {
            "title": "별빛 품은 빗물결",
            "secondary": {
                "emotion": "surprise",
                "emotion_name": "놀람",
                "accent_name": "별빛",
                "ratio": 0.2,
            },
            "temperament": {
                "revealed": True,
                "summary": "고요한 움직임 · 깊이 느끼는 반응",
            },
            "chat_style": {
                "cadence": "조용하고 여백 있는 두세 문장",
                "focus": "잃거나 놓친 것",
                "question_style": "가장 아쉬운 한 가지 묻기",
                "secondary_modifier": "예상 밖의 단서를 놓치지 않는다",
                "stage_expression": "보조결의 관찰 방식이 섞인다",
            },
        },
    }
    messages = build_chat_messages(
        "cactus",
        "초록이",
        "explore",
        [{"role": "user", "content": "동전을 못 찾았어"}],
        "슬픔",
        GROWTH_PERSONA,
        context,
    )
    system = messages[0]["content"]
    assert "품종 말투 코드: cactus" in system
    assert "성장 페르소나 코드: gentle_listener" in system
    assert "현재 성장 단계: 4 (bloom)" in system
    assert "보조 감정 결: surprise(놀람, 비중 0.2)" in system
    assert "고요한 움직임 · 깊이 느끼는 반응" in system

    greeting = greeting_line("cactus", "초록이", GROWTH_PERSONA, context)
    assert "별빛도 꽃봉오리에 같이 번졌어" in greeting


async def test_fake_llm_varies_by_scene_species_growth_persona_and_secondary():
    context = {
        "stage": 4,
        "growth_phase": "bloom",
        "growth_traits": {
            "secondary": {
                "emotion": "surprise",
                "emotion_name": "놀람",
                "ratio": 0.2,
            },
            "temperament": {"revealed": False},
            "chat_style": {},
        },
    }
    messages = build_chat_messages(
        "cactus",
        "초록이",
        "explore",
        [
            {
                "role": "user",
                "content": "오늘 자판기 밑에 500원 빠뜨렸는데 결국 못찾음ㅜㅜ",
            }
        ],
        None,
        GROWTH_PERSONA,
        context,
    )
    reply = await FakeLlm().chat(messages)
    assert "단단한 몸을 네 쪽으로" in reply
    assert "찾지 못한 채 돌아서야 했던" in reply
    assert "예상 밖의 작은 단서" in reply
    assert "가장 아쉬움이 남은 지점" in reply

    angry_persona = {
        **GROWTH_PERSONA,
        "persona_key": "brave_guardian",
        "persona_name": "불씨결",
        "trait": "강인함·솔직함",
    }
    angry_messages = build_chat_messages(
        "sunflower",
        "불꽃이",
        "explore",
        [{"role": "user", "content": "오늘 내 일이 아닌데 억울하게 맡았어"}],
        None,
        angry_persona,
        {"stage": 3, "growth_phase": "branching", "growth_traits": {}},
    )
    angry_reply = await FakeLlm().chat(angry_messages)
    assert "큰 잎을 살짝 모으고" in angry_reply
    assert "경계가 세게 건드려졌던" in angry_reply
    assert "무엇을 지키고 싶었어" in angry_reply
    assert angry_reply != reply


async def test_fake_llm_keeps_early_species_voice_before_growth_branch():
    sprout = build_chat_messages("sprout", "콩이", "emotion_check", [], None)
    cactus = build_chat_messages("cactus", "가시", "emotion_check", [], None)
    sprout_reply = await FakeLlm().chat(sprout)
    cactus_reply = await FakeLlm().chat(cactus)
    assert sprout_reply.startswith("새잎을 네 쪽으로")
    assert cactus_reply.startswith("가시는 세워 둔 채")
    assert sprout_reply != cactus_reply
