from app.ai.prompts import build_chat_messages, greeting_line
from app.ai.llm import FakeLlm


GROWTH_PERSONA = {
    "persona_key": "gentle_listener",
    "persona_name": "빗방울",
    "trait": "섬세함·경청",
    "voice_line": "잎 끝의 물방울, 떨어질 때까지 지켜볼래.",
}


def test_greetings_are_short_dialogue_without_self_narration():
    assert greeting_line("sprout", "새싹몬") == "왔구나. 오늘 무슨 일 있었어?"
    assert greeting_line("sunflower", "해바라기").startswith("안녕!")
    assert "이(가)" not in greeting_line("sprout", "새싹몬")


def test_greeting_never_puts_a_speaker_tag_inside_the_bubble():
    """대화 화면은 말풍선 옆에 이름과 그림을 이미 붙인다.

    첫 인사에만 `새싹몬: `이 붙어 있어서 같은 캐릭터의 첫 줄과 다음 줄이
    다른 말투로 보였다.
    """
    lines = [
        greeting_line("sprout", "새싹몬"),
        greeting_line("cactus", "가시니"),
        greeting_line("sunflower", "해바라기"),
        greeting_line("sprout", "초록이", GROWTH_PERSONA),
    ]
    for line in lines:
        assert not line.startswith(("새싹몬:", "가시니:", "해바라기:", "초록이:")), line


def test_growth_persona_is_added_to_prompt_without_replacing_species_identity():
    messages = build_chat_messages(
        "cactus", "가시니", "explore", [], None, GROWTH_PERSONA
    )
    system = messages[0]["content"]
    assert "가시니" in system and "무뚝뚝하지만 속정 깊은 선인장" in system
    assert "빗방울" in system and "섬세함·경청" in system
    assert GROWTH_PERSONA["voice_line"] in system
    assert "사용자를 진단하거나 평가" in system


def test_growth_persona_greeting_keeps_voice_without_reciting_lore():
    line = greeting_line("sprout", "초록이", GROWTH_PERSONA)
    assert line == "여기 있어. 천천히 얘기해도 돼."
    assert GROWTH_PERSONA["voice_line"] not in line


def test_growth_context_adds_secondary_temperament_and_stage_to_prompt():
    context = {
        "stage": 4,
        "growth_phase": "bloom",
        "growth_traits": {
            "title": "별빛 품은 빗방울",
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
                "stage_expression": "보조 타입의 관찰 방식이 섞인다",
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
    assert "꽃봉오리" not in greeting
    assert len(greeting) < 40


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
    assert "결국 못 찾았구나" in reply
    assert "가시" not in reply
    assert reply.count("?") == 1
    assert len(reply) < 90
    assert "가장 아쉬움이 남은 지점" in reply

    angry_persona = {
        **GROWTH_PERSONA,
        "persona_key": "brave_guardian",
        "persona_name": "불씨",
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
    assert "그 일에 화가 났구나" in angry_reply
    assert "큰 잎" not in angry_reply
    assert "무엇을 지키고 싶었어" in angry_reply
    assert angry_reply != reply


async def test_fake_llm_keeps_early_species_voice_before_growth_branch():
    sprout = build_chat_messages("sprout", "콩이", "greeting", [], None)
    cactus = build_chat_messages("cactus", "가시", "greeting", [], None)
    sprout_reply = await FakeLlm().chat(sprout)
    cactus_reply = await FakeLlm().chat(cactus)
    assert sprout_reply.startswith("왔구나.")
    assert cactus_reply.startswith("왔네.")
    assert sprout_reply != cactus_reply


async def test_replies_do_not_insert_body_language_or_growth_lore():
    for stage in (1, 2, 4, 5):
        messages = build_chat_messages(
            "sprout",
            "모아",
            "explore",
            [{"role": "user", "content": "오늘은 좀 지쳤어."}],
            None,
            GROWTH_PERSONA,
            {"stage": stage, "growth_phase": "bloom", "growth_traits": {}},
        )
        reply = await FakeLlm().chat(messages)
        assert "여린 줄기" not in reply
        assert "몸을" not in reply
        assert "꽃봉오리" not in reply
        assert len(reply) < 90


async def test_crying_emoticon_does_not_invent_a_lost_object():
    messages = build_chat_messages(
        "sprout",
        "콩이",
        "explore",
        [{"role": "user", "content": "오늘은 너무 피곤해 ㅠㅠ"}],
        None,
        GROWTH_PERSONA,
    )
    reply = await FakeLlm().chat(messages)
    assert "못 찾" not in reply


def test_live_prompt_requires_specific_brief_nonjudgmental_dialogue():
    system = build_chat_messages("sprout", "콩이", "explore", [], None)[0]["content"]
    assert "사용자가 말하지 않은" in system
    assert "보통 1~2문장" in system
    assert "모든 답을 질문이나 조언으로 끝내지 않는다" in system
    assert "진단, 처방" in system
