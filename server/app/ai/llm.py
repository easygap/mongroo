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

    model_version = "fake-llm-2"

    _STAGE_REPLIES = {
        "greeting": "오늘 무슨 일 있었어?",
        "emotion_check": "지금은 어떤 기분이야?",
        "explore": "그때 무슨 일이 있었어?",
        "reframe_option": "다른 가능성도 같이 생각해 볼까?",
        "action": "지금 해 보고 싶은 일이 있어?",
        "closing": "응, 오늘 얘기는 여기까지 하자.",
    }

    _PERSONA_ACKS = {
        "sunny_optimist": "응, 듣고 있어.",
        "gentle_listener": "그랬구나.",
        "brave_guardian": "응. 그 얘기였구나.",
        "careful_observer": "하나씩 보자.",
        "curious_explorer": "그 얘기 좀 더 듣고 싶어.",
        "free_spirit": "응. 계속 듣고 있어.",
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
        "sunny_optimist": "응, 다음에 또 얘기하자.",
        "gentle_listener": "오늘은 여기까지 하자. 잘 가.",
        "brave_guardian": "알았어. 오늘 얘기는 여기까지.",
        "careful_observer": "응, 정리됐네. 다음에 보자.",
        "curious_explorer": "그랬구나. 오늘 얘기 잘 들었어.",
        "free_spirit": "응. 또 얘기하고 싶을 때 보자.",
    }

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
        if any(token in lowered for token in ("못찾", "못 찾", "잃어", "빠뜨")):
            return "결국 못 찾았구나."
        if any(token in lowered for token in ("화나", "빡치", "짜증", "억울")):
            return "그 일에 화가 났구나."
        if any(token in lowered for token in ("걱정", "불안", "무서", "어떡")):
            return "아직 걱정되는구나."
        if any(token in lowered for token in ("행복", "기뻐", "즐거", "좋았")):
            return "그 일이 좋았구나."
        if any(token in lowered for token in ("놀랐", "깜짝", "뜻밖", "헐")):
            return "그건 예상 못 했겠다."
        return None

    def _character_reply(
        self,
        stage: str,
        persona_code: str,
        secondary: str | None,
        latest_user_text: str,
    ) -> str:
        acknowledgement = self._scene_acknowledgement(latest_user_text)
        acknowledgement = acknowledgement or self._PERSONA_ACKS[persona_code]
        opening = acknowledgement

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
        # 보조 성격은 질문의 초점에만 반영한다. 인사·몸짓·감정 비유를
        # 한 응답에 차례로 붙이면 캐릭터가 사용자보다 길게 독백하게 된다.
        if stage == "emotion_check" and secondary == "surprise":
            question = "예상과 달랐던 부분은 뭐였어?"
        return f"{opening} {question}"

    async def chat(self, messages: list[dict]) -> str:
        system = messages[0]["content"] if messages else ""
        if "리포트 요약" in system:
            return json.dumps(
                {
                    "overview": "기록한 날짜와 감정 분포를 아래 표에서 확인할 수 있습니다.",
                    "patterns": ["기록이 없는 날은 감정 분포 계산에서 제외합니다."],
                    "reflection_questions": ["다시 읽어 보고 싶은 기록이 있나요?"],
                },
                ensure_ascii=False,
            )
        persona_code = self._marker(system, "성장 페르소나 코드")
        species_code = self._marker(system, "품종 말투 코드") or "sprout"
        secondary = self._marker(system, "보조 감정 결")
        for stage, reply in self._STAGE_REPLIES.items():
            if f"지금 대화 단계: {stage}" in system:
                if persona_code in self._PERSONA_ACKS:
                    return self._character_reply(
                        stage,
                        persona_code,
                        secondary,
                        self._latest_user_text(messages),
                    )
                if stage == "greeting":
                    from app.ai.prompts import GREETING_TEMPLATES

                    return GREETING_TEMPLATES.get(species_code, reply)
                return reply
        return self._STAGE_REPLIES["explore"]

    async def ping(self) -> bool:
        return True


class RulesLlm(FakeLlm):
    """검수된 결정적 문장만 조합하는 운영 fallback 대화·요약 엔진."""

    model_version = "rules-dialogue-2"


def get_llm() -> LlmClient | None:
    mode = get_settings().ai_mode
    if mode == "local":
        return OllamaClient()
    if mode == "rules":
        return RulesLlm()
    if mode == "fake":
        return FakeLlm()
    return None
