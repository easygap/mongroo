"""상태값 정의. DB CHECK 제약과 같은 값을 유지한다 (design.md 4)."""


class AnalysisStatus:
    NOT_REQUESTED = "not_requested"
    PENDING = "pending"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    ALL = (NOT_REQUESTED, PENDING, RUNNING, SUCCEEDED, FAILED)


class PlantStatus:
    ACTIVE = "active"
    HARVESTED = "harvested"
    ALL = (ACTIVE, HARVESTED)


class ChatSessionStatus:
    ACTIVE = "active"
    CLOSED = "closed"
    ALL = (ACTIVE, CLOSED)


class ReflectionStage:
    GREETING = "greeting"
    EMOTION_CHECK = "emotion_check"
    EXPLORE = "explore"
    REFRAME_OPTION = "reframe_option"
    ACTION = "action"
    CLOSING = "closing"
    ORDER = (GREETING, EMOTION_CHECK, EXPLORE, REFRAME_OPTION, ACTION, CLOSING)


class SafetyState:
    NORMAL = "normal"
    CONCERN = "concern"
    IMMINENT = "imminent"
    ALL = (NORMAL, CONCERN, IMMINENT)


class RunStatus:
    QUEUED = "queued"
    GENERATING = "generating"
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    ALL = (QUEUED, GENERATING, SUCCEEDED, FAILED)


class ReportStatus:
    PENDING = "pending"
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    ALL = (PENDING, SUCCEEDED, FAILED)


class JobStatus:
    PENDING = "pending"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    ALL = (PENDING, RUNNING, SUCCEEDED, FAILED)


class JobType:
    MOOD_ANALYSIS = "mood_analysis"
    CHAT_GENERATION = "chat_generation"
    REPORT_SUMMARY = "report_summary"
    ALL = (MOOD_ANALYSIS, CHAT_GENERATION, REPORT_SUMMARY)


class RewardEventType:
    MOOD_FIRST_DAILY = "mood_first_daily"
    DIARY_FIRST_DAILY = "diary_first_daily"
    CHAT_FIRST_DAILY = "chat_first_daily"
    STREAK_WEEK = "streak_week"
    QUEST_COMPLETED = "quest_completed"
    SHOP_PURCHASE = "shop_purchase"
    ALL = (
        MOOD_FIRST_DAILY,
        DIARY_FIRST_DAILY,
        CHAT_FIRST_DAILY,
        STREAK_WEEK,
        QUEST_COMPLETED,
        SHOP_PURCHASE,
    )


REWARD_AMOUNTS = {
    RewardEventType.MOOD_FIRST_DAILY: (20, 0),
    RewardEventType.DIARY_FIRST_DAILY: (10, 0),
    RewardEventType.CHAT_FIRST_DAILY: (5, 0),
    RewardEventType.STREAK_WEEK: (0, 30),
    RewardEventType.QUEST_COMPLETED: (20, 5),
}
