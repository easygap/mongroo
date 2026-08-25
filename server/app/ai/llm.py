"""LLM 클라이언트. local=Ollama, fake=결정적 응답 (design.md 2.2, 6.2)."""

import json
from typing import Protocol

import httpx

from app.core.config import get_settings


class LlmError(Exception):
    def __init__(self, code: str) -> None:
        self.code = code  # LLM_TIMEOUT | LLM_UNAVAILABLE


class LlmClient(Protocol):
    model_version: str

    async def chat(self, messages: list[dict]) -> str: ...


class OllamaClient:
    def __init__(self) -> None:
        settings = get_settings()
        self._base = settings.ollama_base_url.rstrip("/")
        self._model = settings.ollama_model
        self._timeout = settings.ollama_timeout_seconds
        self._options = {
            "num_ctx": settings.ollama_num_ctx,
            "num_predict": settings.ollama_num_predict,
            "temperature": settings.ollama_temperature,
        }
        self.model_version = self._model

    async def chat(self, messages: list[dict]) -> str:
        payload = {
            "model": self._model,
            "messages": messages,
            "stream": False,
            "think": False,
            "options": self._options,
        }
        try:
            async with httpx.AsyncClient(timeout=self._timeout) as client:
                res = await client.post(f"{self._base}/api/chat", json=payload)
                res.raise_for_status()
        except httpx.TimeoutException as exc:
            raise LlmError("LLM_TIMEOUT") from exc
        except httpx.HTTPError as exc:
            raise LlmError("LLM_UNAVAILABLE") from exc
        try:
            return res.json()["message"]["content"].strip()
        except (KeyError, ValueError) as exc:
            raise LlmError("LLM_UNAVAILABLE") from exc

    async def ping(self) -> bool:
        try:
            async with httpx.AsyncClient(timeout=3) as client:
                res = await client.get(f"{self._base}/api/tags")
                return res.status_code == 200
        except httpx.HTTPError:
            return False


class FakeLlm:
    """테스트·CI·모델 미설치 데모용 결정적 캐릭터 응답기."""

    model_version = "fake-llm-1"

    _STAGE_REPLIES = {
        "greeting": "오늘 하루는 어땠어? 나한테 편하게 이야기해 줘.",
        "emotion_check": "그랬구나. 지금 마음에 가장 크게 남아 있는 감정은 뭐라고 부르고 싶어?",
        "explore": "조금 더 듣고 싶어. 그때 어떤 상황이었고, 어떤 생각이 스쳐 갔어?",
        "reframe_option": "혹시 괜찮다면, 그 일을 다른 각도에서 보면 어떤 게 보일지 같이 생각해 볼래? 싫으면 넘어가도 돼.",
        "action": "오늘은 물 한 잔 천천히 마시면서 쉬어 가는 건 어때? 아주 작은 것부터면 충분해.",
        "closing": "오늘 이야기해 줘서 고마워. 네 마음을 이렇게 들려준 것만으로도 충분했어. 내일 또 보자.",
    }

    _PERSONA_ACKS = {
        "sunny_optimist": "네가 건넨 장면을 잎 위 햇살처럼 찬찬히 보고 있어.",
        "gentle_listener": "그 여운이 급히 마르지 않도록 빗물 잎을 조금 낮출게.",
        "brave_guardian": "그 말 속에서 중요했던 경계가 어디인지 불씨를 세워 듣고 있어.",
        "careful_observer": "걱정과 확인된 사실이 섞이지 않게 달빛 아래 하나씩 볼게.",
        "curious_explorer": "예상과 달랐던 지점에서 별잎 하나가 반짝였어.",
        "free_spirit": "서로 다른 마음을 한 화분에 그대로 두고 들을게.",
    }

    _EXPLORE_QUESTIONS = {
        "sunny_optimist": "그중 마음에 오래 남기고 싶은 순간은 어디였어?",
        "gentle_listener": "그 일에서 가장 아쉬움이 남은 지점은 어디였어?",
        "brave_guardian": "그 순간 사실은 무엇을 지키고 싶었어?",
        "careful_observer": "그 걱정 속에서 지금 확실히 아는 사실 하나는 뭐야?",
        "curious_explorer": "가장 예상 밖이었다고 느낀 부분은 뭐였어?",
        "free_spirit": "겹쳐 있는 마음 중 먼저 말하고 싶은 건 어느 쪽이야?",
    }

    _REFRAME_QUESTIONS = {
        "sunny_optimist": "원한다면 좋았던 점을 지우지 않은 채 다른 가능성도 하나 찾아볼까?",
        "gentle_listener": "그 아쉬움을 없애려 하지 않고 다른 각도도 잠깐 바라볼까?",
        "brave_guardian": "네 경계를 지키면서도 다르게 볼 수 있는 지점이 있을까?",
        "careful_observer": "확인된 사실만 놓고 보면 다르게 보이는 부분도 있을까?",
        "curious_explorer": "처음엔 못 봤던 낯선 각도도 하나 살펴볼까?",
        "free_spirit": "두 마음을 모두 그대로 둔 채 다른 관점도 곁에 놓아볼까?",
    }

    _ACTIONS = {
        "sunny_optimist": "창가나 밝은 곳을 한 번 바라보고, 기억하고 싶은 장면을 한 단어로 적어보는 건 어때?",
        "gentle_listener": "따뜻하거나 미지근한 물을 한 모금 천천히 마셔보는 건 어때?",
        "brave_guardian": "쥔 손을 펴고 어깨를 한 번 올렸다 천천히 내려놓아 보는 건 어때?",
        "careful_observer": "지금 손댈 수 있는 아주 작은 한 칸만 정리해 보는 건 어때?",
        "curious_explorer": "주변에서 처음 눈에 들어오는 색 하나를 찾아 이름 붙여보는 건 어때?",
        "free_spirit": "지금 마음을 서로 다른 두 단어로 나란히 적어보는 건 어때?",
    }

    _CLOSINGS = {
        "sunny_optimist": "오늘 네가 남긴 장면을 햇살 잎에 잘 간직할게. 이야기해 줘서 고마워.",
        "gentle_listener": "오늘의 여운은 서둘러 말리지 않고 빗물 잎에 두고 있을게. 이야기해 줘서 고마워.",
        "brave_guardian": "오늘 중요했던 마음을 작은 불씨처럼 지켜둘게. 솔직하게 들려줘서 고마워.",
        "careful_observer": "오늘 확인한 마음을 달빛 아래 차분히 정리해 둘게. 이야기해 줘서 고마워.",
        "curious_explorer": "오늘 발견한 뜻밖의 장면을 별잎에 표시해 둘게. 이야기해 줘서 고마워.",
        "free_spirit": "오늘의 여러 마음을 어느 하나 숨기지 않고 함께 간직할게. 이야기해 줘서 고마워.",
    }

    _SECONDARY_NOTES = {
        "joy": "한편으로 남아 있는 작은 가능성도 같이 볼게.",
        "sadness": "사라진 자리의 아쉬움도 서둘러 덮지 않을게.",
        "anger": "그 안에서 건드려진 경계도 놓치지 않을게.",
        "anxiety": "아직 모르는 부분은 모르는 채로 안전하게 둘게.",
        "surprise": "예상 밖의 작은 단서도 곁에 표시해 둘게.",
        "mixed": "한 가지 이름으로 묶이지 않는 마음도 함께 둘게.",
    }

    _SPECIES_TOUCHES = {
        "sprout": {
            "greeting": "흙을 톡 밀고 네 쪽으로 고개를 내밀었어.",
            "emotion_check": "새잎을 네 쪽으로 살짝 기울였어.",
            "explore": "여린 줄기를 곧게 세우고 듣고 있어.",
            "reframe_option": "잎맥 사이로 다른 빛이 드는지 살펴보고 있어.",
            "action": "화분 가장자리에서 가볍게 몸을 흔들었어.",
        },
        "cactus": {
            "greeting": "동그란 가시 사이로 눈을 빼꼼 내밀었어.",
            "emotion_check": "가시는 세워 둔 채 네 쪽을 보고 있어.",
            "explore": "단단한 몸을 네 쪽으로 조금 기울였어.",
            "reframe_option": "가시 사이 빈틈으로 다른 쪽도 바라보고 있어.",
            "action": "모래를 톡 털고 짧게 고개를 끄덕였어.",
        },
        "sunflower": {
            "greeting": "햇빛을 보던 꽃 고개가 네 쪽으로 돌아왔어.",
            "emotion_check": "꽃 고개를 네 쪽으로 돌렸어.",
            "explore": "큰 잎을 살짝 모으고 네 말을 듣고 있어.",
            "reframe_option": "꽃잎 사이로 들어오는 다른 빛도 살펴보고 있어.",
            "action": "줄기를 한 번 쭉 펴고 씨앗을 토닥였어.",
        },
    }

    #: 개화(4)·만개(5) 단계의 몸짓.
    #:
    #: 위 표는 화분에 담긴 어린 몸을 그린다. 그런데 4단계부터는 원화가 사람
    #: 형태라, 다 자란 캐릭터 그림 바로 아래에서 자기를 "여린 줄기"라고
    #: 말하거나 "화분 가장자리에서 몸을 흔들었어"라고 하는 문장이 붙었다.
    #: 같은 성격·같은 품종색을 유지하되 자란 몸으로 다시 쓴다.
    _GROWN_SPECIES_TOUCHES = {
        "sprout": {
            "greeting": "잎으로 엮은 옷자락을 스치며 네 쪽으로 다가왔어.",
            "emotion_check": "손에 든 꽃대를 내려놓고 네 쪽을 바라봤어.",
            "explore": "잎끝을 모아 쥐고 네 말을 끝까지 듣고 있어.",
            "reframe_option": "머리에 얹힌 잎 사이로 다른 빛이 드는지 살펴보고 있어.",
            "action": "발끝으로 바닥을 톡 두드리며 박자를 맞췄어.",
        },
        "cactus": {
            "greeting": "세워 뒀던 가시를 눕히고 네 쪽으로 성큼 다가왔어.",
            "emotion_check": "팔짱을 풀고 네 쪽으로 몸을 돌렸어.",
            "explore": "가시를 세우지 않은 채 네 말을 듣고 있어.",
            "reframe_option": "가시 사이 빈틈으로 다른 쪽도 바라보고 있어.",
            "action": "손끝에 남은 모래를 털고 짧게 고개를 끄덕였어.",
        },
        "sunflower": {
            "greeting": "빛을 좇던 고개를 돌려 네 쪽으로 걸어왔어.",
            "emotion_check": "쓰고 있던 꽃 모자를 살짝 들고 네 쪽을 봤어.",
            "explore": "두 손을 모으고 네 말을 듣고 있어.",
            "reframe_option": "꽃잎 사이로 들어오는 다른 빛도 살펴보고 있어.",
            "action": "허리를 한 번 쭉 펴고 주머니 속 씨앗을 토닥였어.",
        },
    }

    #: 원화가 사람 형태로 바뀌는 성장 단계.
    _GROWN_STAGE = 4

    @classmethod
    def _species_touch(
        cls, species_code: str, stage: str, growth_stage: int
    ) -> str | None:
        table = (
            cls._GROWN_SPECIES_TOUCHES
            if growth_stage >= cls._GROWN_STAGE
            else cls._SPECIES_TOUCHES
        )
        return table.get(species_code, {}).get(stage)

    @staticmethod
    def _growth_stage(system: str) -> int:
        raw = FakeLlm._marker(system, "현재 성장 단계")
        try:
            return max(1, min(5, int(raw or 1)))
        except ValueError:
            return 1

    @staticmethod
    def _marker(system: str, label: str) -> str | None:
        prefix = f"{label}:"
        for line in system.splitlines():
            if line.startswith(prefix):
                value = line[len(prefix) :].strip()
                return value.split("(", 1)[0].strip() or None
        return None

    @staticmethod
    def _latest_user_text(messages: list[dict]) -> str:
        return next(
            (
                str(message.get("content", ""))
                for message in reversed(messages)
                if message.get("role") == "user"
            ),
            "",
        )

    @staticmethod
    def _scene_acknowledgement(text: str) -> str | None:
        lowered = text.casefold()
        if any(
            token in lowered for token in ("못찾", "못 찾", "잃어", "빠뜨", "ㅠ", "ㅜ")
        ):
            return "찾지 못한 채 돌아서야 했던 그 장면이 아쉬움으로 남았구나."
        if any(token in lowered for token in ("화나", "빡치", "짜증", "억울")):
            return "참아 낸 순간에 네 경계가 세게 건드려졌던 것 같아."
        if any(token in lowered for token in ("걱정", "불안", "무서", "어떡")):
            return "아직 정해지지 않은 부분이 마음을 계속 붙잡고 있구나."
        if any(token in lowered for token in ("행복", "기뻐", "즐거", "좋았")):
            return "그 장면의 반가운 기운이 아직 마음에 남아 있구나."
        if any(token in lowered for token in ("놀랐", "깜짝", "뜻밖", "헐")):
            return "예상과 달랐던 순간이 크게 반짝였구나."
        return None

    def _character_reply(
        self,
        stage: str,
        persona_code: str,
        species_code: str,
        secondary: str | None,
        latest_user_text: str,
        growth_stage: int = 1,
    ) -> str:
        acknowledgement = self._scene_acknowledgement(latest_user_text)
        acknowledgement = acknowledgement or self._PERSONA_ACKS[persona_code]
        species_touch = self._species_touch(species_code, stage, growth_stage)
        opening = (
            f"{species_touch} {acknowledgement}" if species_touch else acknowledgement
        )
        secondary_note = self._SECONDARY_NOTES.get(secondary or "")

        if stage == "closing":
            return self._CLOSINGS[persona_code]
        if stage == "action":
            return f"{opening} {self._ACTIONS[persona_code]}"
        if stage == "reframe_option":
            question = self._REFRAME_QUESTIONS[persona_code]
        elif stage == "explore":
            question = self._EXPLORE_QUESTIONS[persona_code]
        elif stage == "emotion_check":
            question = "지금 가장 먼저 이름 붙여 보고 싶은 마음은 뭐야?"
        else:
            question = "오늘 가장 먼저 들려주고 싶은 장면은 뭐야?"
        parts = [opening]
        if secondary_note:
            parts.append(secondary_note)
        parts.append(question)
        return " ".join(parts)

    async def chat(self, messages: list[dict]) -> str:
        system = messages[0]["content"] if messages else ""
        if "리포트 요약" in system:
            return json.dumps(
                {
                    "overview": "이번 기간에도 꾸준히 마음을 기록했어요. 기록 자체가 나를 돌보는 시간이었어요.",
                    "patterns": ["기록을 남긴 날에는 하루를 돌아보는 시간이 있었어요."],
                    "reflection_questions": [
                        "이번 주 나를 가장 웃게 한 순간은 언제였나요?"
                    ],
                },
                ensure_ascii=False,
            )
        persona_code = self._marker(system, "성장 페르소나 코드")
        species_code = self._marker(system, "품종 말투 코드") or "sprout"
        secondary = self._marker(system, "보조 감정 결")
        growth_stage = self._growth_stage(system)
        for stage, reply in self._STAGE_REPLIES.items():
            if f"지금 대화 단계: {stage}" in system:
                if persona_code in self._PERSONA_ACKS:
                    return self._character_reply(
                        stage,
                        persona_code,
                        species_code,
                        secondary,
                        self._latest_user_text(messages),
                        growth_stage,
                    )
                species_touch = self._species_touch(
                    species_code, stage, growth_stage
                )
                if species_touch:
                    return f"{species_touch} {reply}"
                return reply
        return self._STAGE_REPLIES["explore"]

    async def ping(self) -> bool:
        return True


class RulesLlm(FakeLlm):
    """검수된 결정적 문장만 조합하는 운영 fallback 대화·요약 엔진."""

    model_version = "rules-dialogue-1"


def get_llm() -> LlmClient | None:
    mode = get_settings().ai_mode
    if mode == "local":
        return OllamaClient()
    if mode == "rules":
        return RulesLlm()
    if mode == "fake":
        return FakeLlm()
    return None
