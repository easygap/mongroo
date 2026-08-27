import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/features/chat/data/chat_repository.dart';
import 'package:mongroo/features/chat/domain/chat_models.dart';
import 'package:mongroo/features/chat/presentation/chat_controller.dart';
import 'package:mongroo/features/quest/data/quest_repository.dart';
import 'package:mongroo/features/quest/domain/daily_quest.dart';
import 'package:mongroo/features/quest/presentation/quest_controller.dart';
import 'package:mongroo/features/safety/domain/safety_action.dart';

class _SafetyChatRepository extends ChatRepository {
  _SafetyChatRepository() : super(Dio());

  @override
  Future<StartSessionResult> startSession({int? plantId}) async {
    return const StartSessionResult(
      session: ChatSession(
        id: 1,
        plantId: 2,
        reflectionStage: 'greeting',
        status: 'active',
        startedAt: null,
        lastMessageAt: null,
      ),
      reward: null,
      greeting: '안녕!',
    );
  }

  @override
  Future<SendMessageResult> sendMessage({
    required int sessionId,
    required String content,
    required String clientMessageId,
    required String idempotencyKey,
    bool retryFailed = false,
  }) async {
    return const SendMessageResult(
      runId: null,
      userMessage: null,
      safetyAction: SafetyAction(
        action: 'show_support_screen',
        severity: 'concern',
        message: '도움을 받을 수 있어요.',
        resources: [],
      ),
    );
  }
}

class _SafetyQuestRepository extends QuestRepository {
  _SafetyQuestRepository() : super(Dio());

  bool suspended = false;

  @override
  Future<DailyQuestFeed> getToday() async => DailyQuestFeed(
        date: '2026-07-13',
        suspended: suspended,
        items: const [],
        suspensionReason: suspended ? 'safety_route' : null,
      );
}

void main() {
  test('대화 안전 신호가 오면 오늘의 작은 행동 캐시를 다시 불러온다', () async {
    final questRepository = _SafetyQuestRepository();
    final container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(_SafetyChatRepository()),
        questRepositoryProvider.overrideWithValue(questRepository),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      questControllerProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(questControllerProvider).feed.valueOrNull?.suspended,
      isFalse,
    );

    questRepository.suspended = true;
    await container.read(chatControllerProvider.notifier).startSession();
    await container.read(chatControllerProvider.notifier).send('너무 힘들어');
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(questControllerProvider).feed.valueOrNull?.suspended,
      isTrue,
    );
  });
}
