"""요청 DTO. 응답 형태는 docs/api.md 계약을 따른다."""

from math import pi

from pydantic import BaseModel, EmailStr, Field, field_validator, model_validator


class SignupRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    nickname: str = Field(min_length=1, max_length=30)
    terms_accepted: bool = False
    privacy_accepted: bool = False
    sensitive_data_consent: bool = False
    age_over_18: bool = False
    terms_version: str | None = Field(default=None, min_length=1, max_length=32)
    privacy_version: str | None = Field(default=None, min_length=1, max_length=32)
    sensitive_consent_version: str | None = Field(
        default=None, min_length=1, max_length=32
    )

    @field_validator("nickname")
    @classmethod
    def normalize_nickname(cls, nickname: str) -> str:
        cleaned = nickname.strip()
        if not cleaned:
            raise ValueError("닉네임은 한 글자 이상이어야 합니다")
        return cleaned


class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)


class RefreshRequest(BaseModel):
    refresh_token: str


class LogoutRequest(BaseModel):
    refresh_token: str


class AccountDeleteRequest(BaseModel):
    password: str = Field(min_length=1, max_length=128)
    confirmation: str = Field(min_length=1, max_length=30)


class MoodCreateRequest(BaseModel):
    # 신규 기록은 일기 본문만으로 만들 수 있다. 값이 없는 경우 DB 하위 호환용
    # 중립값 3을 저장하지만 식물 감정 분기에는 이 필드를 사용하지 않는다.
    mood_level: int | None = Field(default=None, ge=1, le=5)
    emotion_tags: list[str] = Field(default_factory=list, max_length=10)
    content: str | None = Field(default=None, max_length=5000)

    @field_validator("emotion_tags")
    @classmethod
    def validate_tags(cls, tags: list[str]) -> list[str]:
        cleaned = [t.strip() for t in tags if t.strip()]
        if any(len(t) > 20 for t in cleaned):
            raise ValueError("감정 태그는 20자 이하여야 합니다")
        return cleaned

    @model_validator(mode="after")
    def require_diary_or_legacy_mood(self):
        if self.mood_level is None and not (self.content and self.content.strip()):
            raise ValueError("일기 본문 또는 기분 값 중 하나가 필요합니다")
        return self


class MoodPatchRequest(BaseModel):
    expected_version: int | None = Field(default=None, ge=0)
    mood_level: int | None = Field(default=None, ge=1, le=5)
    emotion_tags: list[str] | None = Field(default=None, max_length=10)
    content: str | None = Field(default=None, max_length=5000)
    ai_emotion_override: str | None = Field(default=None, max_length=20)
    ai_label_hidden: bool | None = None

    @field_validator("emotion_tags")
    @classmethod
    def validate_tags(cls, tags: list[str] | None) -> list[str] | None:
        if tags is None:
            return None
        cleaned = [t.strip() for t in tags if t.strip()]
        if any(len(t) > 20 for t in cleaned):
            raise ValueError("감정 태그는 20자 이하여야 합니다")
        return cleaned


class PlantCreateRequest(BaseModel):
    species_id: int | None = None
    name: str | None = Field(default=None, min_length=1, max_length=20)

    @field_validator("name")
    @classmethod
    def normalize_name(cls, name: str | None) -> str | None:
        if name is None:
            return None
        cleaned = name.strip()
        if not cleaned:
            raise ValueError("식물 이름은 한 글자 이상이어야 합니다")
        return cleaned


class PlantMuseumFeatureRequest(BaseModel):
    is_featured: bool


class PatrolStartRequest(BaseModel):
    route_code: str = Field(min_length=1, max_length=40, pattern=r"^[a-z0-9_]+$")


class DungeonRunRequest(BaseModel):
    approach_code: str | None = Field(
        default=None,
        min_length=1,
        max_length=40,
        pattern=r"^[a-z0-9_]+$",
    )


class AdventureDonationRequest(BaseModel):
    item_code: str = Field(min_length=1, max_length=40, pattern=r"^[a-z0-9_]+$")


class ExpeditionStartRequest(BaseModel):
    region_code: str = Field(
        default="moss_archive",
        min_length=1,
        max_length=40,
        pattern=r"^[a-z0-9_]+$",
    )
    mode: str = Field(pattern="^(tutorial|heart_resonance|free_explore)$")
    plant_ids: list[int] = Field(min_length=1, max_length=3)
    guide_count: int = Field(default=0, ge=0, le=2)

    @field_validator("plant_ids")
    @classmethod
    def validate_unique_plants(cls, plant_ids: list[int]) -> list[int]:
        if len(plant_ids) != len(set(plant_ids)):
            raise ValueError("같은 캐릭터를 두 번 편성할 수 없습니다")
        return plant_ids

    @model_validator(mode="after")
    def validate_party_size(self):
        if not 1 <= len(self.plant_ids) + self.guide_count <= 3:
            raise ValueError("탐험대는 1명 이상 3명 이하여야 합니다")
        return self


class ExpeditionActionRequest(BaseModel):
    expected_revision: int = Field(ge=0)
    client_action_id: str = Field(
        min_length=8,
        max_length=64,
        pattern=r"^[A-Za-z0-9_-]+$",
    )


class ExpeditionMoveRequest(ExpeditionActionRequest):
    node_code: str = Field(min_length=1, max_length=40, pattern=r"^[a-z0-9_-]+$")


class ExpeditionChoiceRequest(ExpeditionActionRequest):
    choice_code: str = Field(min_length=1, max_length=40, pattern=r"^[a-z0-9_-]+$")
    acting_member_id: int = Field(ge=1)


class ExpeditionSkillRequest(ExpeditionActionRequest):
    member_id: int = Field(ge=1)
    skill_type: str = Field(pattern="^(signature|form)$")
    mode_code: str | None = Field(
        default=None, min_length=1, max_length=40, pattern=r"^[a-z0-9_-]+$"
    )


class ExpeditionCombatCommand(BaseModel):
    member_id: int = Field(ge=1)
    action: str = Field(pattern="^(attack|skill|guard)$")


class ExpeditionCombatTurnRequest(ExpeditionActionRequest):
    commands: list[ExpeditionCombatCommand] = Field(min_length=1, max_length=3)

    @field_validator("commands")
    @classmethod
    def validate_unique_members(
        cls, commands: list[ExpeditionCombatCommand]
    ) -> list[ExpeditionCombatCommand]:
        member_ids = [command.member_id for command in commands]
        if len(member_ids) != len(set(member_ids)):
            raise ValueError("한 라운드에는 대원별 행동을 한 번만 정할 수 있습니다")
        return commands


class ExpeditionFinishRequest(ExpeditionActionRequest):
    pass


class ChatSessionCreateRequest(BaseModel):
    plant_id: int | None = None


class ChatMessageRequest(BaseModel):
    content: str = Field(min_length=1, max_length=2000)
    client_message_id: str = Field(min_length=8, max_length=64)
    # 확정적으로 failed가 된 기존 run만 같은 사용자 메시지로 재큐잉한다.
    # 전송 응답 유실 재시도는 false인 채 같은 멱등 키를 사용한다.
    retry_failed: bool = False


class ReportCreateRequest(BaseModel):
    period_type: str = Field(pattern="^(weekly|monthly)$")
    period_start: str  # YYYY-MM-DD, 서버에서 검증


class FarmDecorationRequest(BaseModel):
    user_item_id: int
    x: float = Field(ge=0, le=1)
    y: float = Field(ge=0, le=1)
    scale: float = Field(default=1, ge=0.5, le=2)
    rotation: float = Field(
        default=0,
        ge=-pi,
        le=pi,
        description="회전각(라디안, -pi~pi)",
    )
    z_index: int = Field(default=0, ge=0, le=100)


class FarmLayoutRequest(BaseModel):
    expected_version: int = Field(ge=0)
    room_theme_user_item_id: int | None = None
    main_character_user_item_id: int | None = None
    wardrobe_user_item_id: int | None = None
    companion_user_item_ids: list[int] = Field(default_factory=list, max_length=3)
    decorations: list[FarmDecorationRequest] = Field(
        default_factory=list, max_length=30
    )

    @model_validator(mode="after")
    def validate_unique_items(self):
        ids = [
            i
            for i in (
                self.room_theme_user_item_id,
                self.main_character_user_item_id,
                self.wardrobe_user_item_id,
            )
            if i is not None
        ]
        ids.extend(self.companion_user_item_ids)
        ids.extend(d.user_item_id for d in self.decorations)
        if len(ids) != len(set(ids)):
            raise ValueError("같은 보유 아이템을 여러 위치에 배치할 수 없습니다")
        return self
