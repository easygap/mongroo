import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/chat/data/chat_repository.dart';
import 'package:mongroo/features/chat/domain/chat_models.dart';
import 'package:mongroo/features/chat/presentation/chat_controller.dart';
import 'package:mongroo/features/chat/presentation/chat_screen.dart';
import 'package:mongroo/features/home/data/plant_repository.dart';
import 'package:mongroo/features/home/domain/plant.dart';
import 'package:mongroo/features/home/presentation/home_controller.dart';
import 'package:mongroo/features/home/presentation/plant_view.dart';

const _conversationProfile = PlantConversationProfile(
  cadence: '조용하고 여백 있는 두세 문장',
  focus: '잃거나 놓친 것, 아쉬움이 머무는 지점',
  questionStyle: '장면 하나를 천천히 되묻기',
  secondaryModifier: '예상 밖의 단서를 가볍게 짚기',
  stageExpression: '서로 다른 마음을 함께 품는 꽃봉오리',
);

ActivePlant _plant({
  int id = 7,
  String name = '모아',
  PlantGrowthForm dominant = PlantGrowthForm.rainy,
  PlantGrowthForm secondary = PlantGrowthForm.sparkling,
}) =>
    ActivePlant(
      id: id,
      name: name,
      species: const PlantSpecies(
        id: 2,
        code: 'cactus',
        name: '별선인장',
        rarity: 2,
      ),
      exp: 320,
      stage: 4,
      stageThresholds: const [0, 20, 100, 250, 450],
      nextStageExp: 450,
      harvestable: false,
      plantedAt: DateTime(2026, 7, 1),
      growthForm: dominant,
      secondaryForm: secondary,
      growthTraits: const PlantGrowthTraits(
        version: 1,
        stage: 4,
        revealState: 'temperament_revealed',
        title: '별빛 품은 빗물결',
        traits: ['작은 상실을 오래 살피는', '뜻밖의 단서를 발견하는'],
        temperament: PlantTemperament(
          revealed: true,
          fictionalCharacterAxes: true,
          labels: {'deliberation': '한 박자 살피는'},
          summary: '서두르지 않고 작은 변화를 오래 살펴요.',
        ),
        chatStyle: _conversationProfile,
      ),
      conversationProfile: _conversationProfile,
      growthVisual: PlantGrowthVisual.fallback(
        speciesCode: 'cactus',
        rarity: 2,
      ),
    );

class _CharacterChatRepository extends ChatRepository {
  _CharacterChatRepository() : super(Dio());

  int? startedPlantId;
  int sendCalls = 0;

  @override
  Future<StartSessionResult> startSession({int? plantId}) async {
    startedPlantId = plantId;
    return StartSessionResult(
      session: ChatSession(
        id: 31,
        plantId: plantId,
        reflectionStage: 'greeting',
        status: 'active',
        startedAt: null,
        lastMessageAt: null,
      ),
      reward: null,
      greeting: '오늘 이야기를 천천히 들려줘.',
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
    sendCalls++;
    return const SendMessageResult(
      runId: null,
      userMessage: null,
      safetyAction: null,
    );
  }
}

class _MutablePlantRepository extends PlantRepository {
  _MutablePlantRepository(this.current) : super(Dio());

  ActivePlant current;

  @override
  Future<ActivePlant?> getActivePlant() async => current;
}

void main() {
  test('성장 단계·주결·보조결·기질이 서로 다른 시작 문장을 만든다', () {
    final snapshot = ChatCharacterSnapshot.fromPlant(_plant());

    expect(snapshot.stageName, '개화');
    expect(snapshot.dominantLabel, '슬픔');
    expect(snapshot.secondaryLabel, '놀람');
    expect(snapshot.conversationProfile, same(_conversationProfile));
    expect(snapshot.suggestedStarters, hasLength(3));
    expect(snapshot.suggestedStarters, contains(contains('꽃봉오리')));
    expect(snapshot.suggestedStarters, contains(contains('아쉬운')));
    expect(snapshot.suggestedStarters, contains(contains('놀랐던')));
    expect(snapshot.suggestedStarters, contains(contains('천천히')));
  });

  test('세션 시작 시 식물 스냅샷을 고정하고 10번째 전송 뒤 닫는다', () async {
    final repository = _CharacterChatRepository();
    final container = ProviderContainer(
      overrides: [chatRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final plant = _plant();

    await container
        .read(chatControllerProvider.notifier)
        .startSession(plant: plant);

    expect(repository.startedPlantId, plant.id);
    expect(container.read(chatControllerProvider).character?.name, '모아');
    expect(container.read(chatControllerProvider).remainingTurns, 10);

    for (var turn = 1; turn <= ChatController.maxUserTurns; turn++) {
      await container.read(chatControllerProvider.notifier).send('$turn번째 이야기');
    }

    final closed = container.read(chatControllerProvider);
    expect(closed.userTurns, ChatController.maxUserTurns);
    expect(closed.remainingTurns, 0);
    expect(closed.closed, isTrue);
    expect(closed.closureMessage, contains('10번'));

    await container
        .read(chatControllerProvider.notifier)
        .send('열한 번째 이야기는 보내지지 않아야 해');
    expect(repository.sendCalls, ChatController.maxUserTurns);
    expect(container.read(chatControllerProvider).character?.name, '모아');
  });

  testWidgets('채팅 화면은 실제 성장 모습을 쓰고 활성 식물이 바뀌어도 캐릭터를 유지한다', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final firstPlant = _plant();
    final plants = _MutablePlantRepository(firstPlant);
    final chats = _CharacterChatRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          plantRepositoryProvider.overrideWithValue(plants),
          chatRepositoryProvider.overrideWithValue(chats),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const ChatScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('대화 시작'));
    await tester.pump();
    await tester.pump();

    expect(chats.startedPlantId, firstPlant.id);
    expect(find.byType(PlantStagePreview), findsWidgets);
    expect(find.byIcon(Icons.local_florist), findsNothing);
    expect(find.text('0 / 10'), findsOneWidget);
    expect(find.text('주결 · 슬픔'), findsOneWidget);
    expect(find.text('보조결 · 놀람'), findsOneWidget);

    final starter =
        ChatCharacterSnapshot.fromPlant(firstPlant).suggestedStarters.first;
    await tester.ensureVisible(find.text(starter));
    await tester.tap(find.text(starter));
    await tester.pump();
    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.controller?.text, starter);
    expect(chats.sendCalls, 0);

    plants.current = _plant(
      id: 99,
      name: '새별',
      dominant: PlantGrowthForm.ember,
      secondary: PlantGrowthForm.sunny,
    );
    final context = tester.element(find.byType(ChatScreen));
    final container = ProviderScope.containerOf(context, listen: false);
    await container.read(homeControllerProvider.notifier).refresh();
    await tester.pump();

    expect(container.read(chatControllerProvider).character?.name, '모아');
    expect(find.text('모아'), findsOneWidget);
    expect(find.text('새별'), findsNothing);
    expect(find.text('주결 · 슬픔'), findsOneWidget);

    for (var turn = 1; turn <= ChatController.maxUserTurns; turn++) {
      await container.read(chatControllerProvider.notifier).send('$turn번째 이야기');
    }
    await tester.pump();

    expect(find.text('오늘 대화를 잘 마쳤어요'), findsOneWidget);
    expect(find.text('새 대화'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
