import '../../home/domain/plant.dart';
import '../../home/domain/reward_result.dart';
import '../../safety/domain/safety_action.dart';

class ChatSession {
  const ChatSession({
    required this.id,
    required this.plantId,
    required this.reflectionStage,
    required this.status,
    required this.startedAt,
    required this.lastMessageAt,
  });

  final int id;
  final int? plantId;
  final String reflectionStage;
  final String status;
  final DateTime? startedAt;
  final DateTime? lastMessageAt;

  bool get isClosed => status == 'closed';

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: json['id'] as int,
        plantId: json['plant_id'] as int?,
        reflectionStage: (json['reflection_stage'] as String?) ?? 'greeting',
        status: (json['status'] as String?) ?? 'active',
        startedAt: json['started_at'] == null
            ? null
            : DateTime.tryParse(json['started_at'] as String),
        lastMessageAt: json['last_message_at'] == null
            ? null
            : DateTime.tryParse(json['last_message_at'] as String),
      );
}

/// 대화를 시작한 순간의 식물 모습과 말투를 고정한 세션 캐릭터.
///
/// 홈의 활성 식물이 수확·교체되거나 분석 갱신으로 외형이 바뀌더라도 진행 중인
/// 대화에서는 이 값만 사용한다. 새 대화를 시작할 때만 새 스냅샷을 만든다.
class ChatCharacterSnapshot {
  const ChatCharacterSnapshot({
    required this.plantId,
    required this.name,
    required this.stage,
    required this.speciesCode,
    required this.speciesName,
    required this.visualForm,
    required this.dominantForm,
    required this.secondaryForm,
    required this.growthVisual,
    required this.personalityName,
    required this.personalityDescription,
    required this.temperament,
    required this.conversationProfile,
  });

  final int plantId;
  final String name;
  final int stage;
  final String speciesCode;
  final String speciesName;
  final PlantGrowthForm? visualForm;
  final PlantGrowthForm? dominantForm;
  final PlantGrowthForm? secondaryForm;
  final PlantGrowthVisual? growthVisual;
  final String personalityName;
  final String personalityDescription;
  final PlantTemperament temperament;
  final PlantConversationProfile conversationProfile;

  String get stageName => plantStageName(stage);

  String get dominantLabel =>
      dominantForm?.emotionLabel ?? (stage >= 2 ? '마음빛 관찰 중' : '잠든 마음씨앗');

  String? get secondaryLabel => secondaryForm?.emotionLabel;

  String get temperamentSummary => temperament.hasDetails
      ? temperament.summary
      : stage >= 3
          ? personalityDescription
          : '일기를 들으며 말투와 성격을 알아 가는 중';

  String get conversationSummary {
    final focus = conversationProfile.focus.trim();
    if (focus.isNotEmpty) return '$focus에 귀 기울여요.';
    if (stage < 3) return '아직 판단하지 않고 오늘 이야기를 천천히 들어요.';
    return '$personalityName의 말걸음으로 오늘 장면을 함께 살펴봐요.';
  }

  String get semanticDescription {
    final secondary = secondaryLabel;
    final personality = stage >= 3 && personalityName.trim().isNotEmpty
        ? ', 성장 성격 $personalityName'
        : '';
    return '$name, $stageName 단계, $dominantLabel'
        '${secondary == null ? '' : ', 보조 마음빛 $secondary'}$personality, '
        '$temperamentSummary';
  }

  List<String> get suggestedStarters {
    final suggestions = <String>[
      _stageStarter(stage),
      if (dominantForm != null) _dominantStarter(dominantForm!),
    ];
    if (stage <= 2) {
      suggestions.add('아직 이름 붙이기 어려운 마음부터 들려줄게');
    } else if (secondaryForm != null) {
      suggestions.add(
        _secondaryStarter(secondaryForm!, conversationProfile),
      );
    } else {
      suggestions.add(
        _temperamentStarter(temperament, conversationProfile),
      );
    }
    return List.unmodifiable(suggestions.toSet().take(3));
  }

  factory ChatCharacterSnapshot.fromPlant(ActivePlant plant) =>
      ChatCharacterSnapshot(
        plantId: plant.id,
        name: plant.name,
        stage: plant.stage,
        speciesCode: plant.species.code,
        speciesName: plant.species.name,
        visualForm: plant.visualForm,
        dominantForm: plant.dominantForm,
        secondaryForm: plant.secondaryForm,
        growthVisual: plant.growthVisual,
        personalityName: plant.personalityName,
        personalityDescription: plant.personalityDescription,
        temperament: plant.growthTraits.temperament,
        conversationProfile: plant.conversationProfile,
      );
}

String _stageStarter(int stage) => switch (stage.clamp(1, 5).toInt()) {
      1 => '오늘 있었던 일부터 작은 씨앗에게 들려줄게',
      2 => '새잎에 남은 오늘 장면부터 말해볼게',
      3 => '오늘 내 마음빛이 선명해진 순간부터 말해볼게',
      4 => '꽃봉오리에 함께 남은 마음들을 들려줄게',
      _ => '오늘 가장 오래 남은 장면을 같이 돌아볼래',
    };

String _dominantStarter(PlantGrowthForm form) => switch (form) {
      PlantGrowthForm.sunny => '작지만 오래 간직하고 싶은 좋은 순간이 있어',
      PlantGrowthForm.rainy => '놓치거나 잃어서 아쉬운 일을 말해보고 싶어',
      PlantGrowthForm.ember => '오늘 내 선을 넘었다고 느낀 일이 있어',
      PlantGrowthForm.moonlit => '자꾸 걱정되는 일을 하나씩 정리하고 싶어',
      PlantGrowthForm.sparkling => '오늘 정말 예상 밖이었던 일이 있었어',
      PlantGrowthForm.mosaic => '서로 다른 마음이 같이 들어서 하나씩 말해볼게',
    };

String _secondaryStarter(
  PlantGrowthForm form,
  PlantConversationProfile profile,
) {
  final subject = switch (form) {
    PlantGrowthForm.sunny => '작게 반가웠던 순간',
    PlantGrowthForm.rainy => '아쉬움이 남은 부분',
    PlantGrowthForm.ember => '선을 넘었다고 느낀 지점',
    PlantGrowthForm.moonlit => '아직 걱정되는 부분',
    PlantGrowthForm.sparkling => '뜻밖이라 놀랐던 순간',
    PlantGrowthForm.mosaic => '서로 다른 두 마음',
  };
  return '한편으로 $subject도 ${_paceEnding(profile)}';
}

String _temperamentStarter(
  PlantTemperament temperament,
  PlantConversationProfile profile,
) {
  final labels = temperament.labels.values.join(' ');
  if (labels.contains('차분히') || labels.contains('한 박자')) {
    return '천천히, 지금 확실한 장면부터 말해볼게';
  }
  if (labels.contains('깊이 느끼는')) {
    return '아직 여운이 남은 장면을 서두르지 않고 들려줄게';
  }
  if (labels.contains('생기찬') || profile.cadence.contains('생기')) {
    return '가장 선명하게 떠오르는 장면부터 바로 말해볼게';
  }
  return '편한 속도로 오늘 가장 마음에 남은 것부터 말해볼게';
}

String _paceEnding(PlantConversationProfile profile) {
  final cadence = profile.cadence;
  if (cadence.contains('조용') ||
      cadence.contains('차분') ||
      cadence.contains('여백')) {
    return '천천히 말해볼게';
  }
  if (cadence.contains('짧고 힘')) return '핵심부터 솔직하게 말해볼게';
  if (cadence.contains('생기') || cadence.contains('가볍')) {
    return '떠오르는 대로 말해볼게';
  }
  return '같이 살펴보고 싶어';
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final int id;
  final String role; // "user" | "plant"
  final String content;
  final DateTime? createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: (json['id'] as int?) ?? (json['message_id'] as int?) ?? 0,
        role: (json['role'] as String?) ?? 'plant',
        content: (json['content'] as String?) ?? '',
        createdAt: json['created_at'] == null
            ? null
            : DateTime.tryParse(json['created_at'] as String),
      );
}

/// POST /chat/sessions 응답 {session, reward, greeting}.
class StartSessionResult {
  const StartSessionResult({
    required this.session,
    required this.reward,
    required this.greeting,
  });

  final ChatSession session;
  final RewardResult? reward;
  final String greeting;

  factory StartSessionResult.fromJson(Map<String, dynamic> json) {
    final rawGreeting = json['greeting'];
    final greeting = switch (rawGreeting) {
      String value => value,
      Map<String, dynamic> value => (value['content'] as String?) ?? '',
      _ => '',
    };
    return StartSessionResult(
      session: ChatSession.fromJson(json['session'] as Map<String, dynamic>),
      reward: RewardResult.fromJsonOrNull(json['reward']),
      greeting: greeting,
    );
  }
}

/// POST /chat/sessions/{id}/messages 응답.
/// 202: run_id 존재. 200(안전 경로): run_id null + safety_action.
class SendMessageResult {
  const SendMessageResult({
    required this.runId,
    required this.userMessage,
    required this.safetyAction,
  });

  final int? runId;
  final ChatMessage? userMessage;
  final SafetyAction? safetyAction;

  factory SendMessageResult.fromJson(Map<String, dynamic> json) =>
      SendMessageResult(
        runId: json['run_id'] as int?,
        userMessage: json['user_message'] is Map<String, dynamic>
            ? ChatMessage.fromJson(json['user_message'] as Map<String, dynamic>)
            : null,
        safetyAction: SafetyAction.fromJsonOrNull(json['safety_action']),
      );
}

/// GET /chat/runs/{id} 응답.
class ChatRun {
  const ChatRun({
    required this.runId,
    required this.status,
    required this.message,
    required this.errorCode,
  });

  final int runId;
  final String status; // queued | generating | succeeded | failed
  final ChatMessage? message;
  final String? errorCode;

  bool get isTerminal => status == 'succeeded' || status == 'failed';

  factory ChatRun.fromJson(Map<String, dynamic> json) => ChatRun(
        runId: (json['run_id'] as int?) ?? 0,
        status: (json['status'] as String?) ?? 'queued',
        message: json['message'] is Map<String, dynamic>
            ? ChatMessage.fromJson(json['message'] as Map<String, dynamic>)
            : null,
        errorCode: json['error_code'] as String?,
      );
}

/// run 진행 상황을 UI로 전달하는 갱신 이벤트.
sealed class RunUpdate {
  const RunUpdate();
}

class RunGenerating extends RunUpdate {
  const RunGenerating();
}

class RunMessageReceived extends RunUpdate {
  const RunMessageReceived({required this.messageId, required this.content});

  final int messageId;
  final String content;
}

class RunCompleted extends RunUpdate {
  const RunCompleted();
}

class RunFailed extends RunUpdate {
  const RunFailed(this.errorCode);

  final String? errorCode;
}

class RunTimedOut extends RunUpdate {
  const RunTimedOut();
}
