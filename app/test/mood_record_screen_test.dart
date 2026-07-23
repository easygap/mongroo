import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mongroo/core/error/api_exception.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/auth/domain/user.dart';
import 'package:mongroo/features/auth/presentation/auth_controller.dart';
import 'package:mongroo/features/home/domain/reward_result.dart';
import 'package:mongroo/features/mood/data/mood_repository.dart';
import 'package:mongroo/features/mood/domain/mood_entry.dart';
import 'package:mongroo/features/mood/presentation/mood_record_screen.dart';

/// 네트워크 없이 동작하는 저장소 fake.
class FakeMoodRepository implements MoodRepository {
  FakeMoodRepository({
    this.reward,
    this.patchError,
    this.latestEntry,
    this.createGate,
    this.createFailures = 0,
  });

  final RewardResult? reward;
  ApiException? patchError;
  final MoodEntry? latestEntry;
  final Completer<void>? createGate;
  int createFailures;
  int createCalls = 0;
  int getByIdCalls = 0;
  int patchCalls = 0;
  Map<String, dynamic>? lastPatchChanges;
  int? lastCreateMoodLevel;
  List<String>? lastCreateTags;
  String? lastCreateContent;
  final List<String> createKeys = [];

  MoodEntry _entry(
    int moodLevel, {
    String? content,
    List<String> emotionTags = const [],
    int? editVersion,
  }) =>
      MoodEntry(
        id: 1,
        localDate: '2026-07-10',
        recordedAt: DateTime.utc(2026, 7, 10, 3),
        moodLevel: moodLevel,
        emotionTags: emotionTags,
        content: content,
        analysisStatus: 'not_requested',
        aiEmotion: null,
        aiScores: const {},
        aiEmotionOverride: null,
        aiLabelHidden: false,
        analysisModelVersion: null,
        analyzedAt: null,
        createdAt: null,
        updatedAt: null,
        editVersion: editVersion,
      );

  @override
  Future<MoodSaveResult> create({
    required int moodLevel,
    required List<String> emotionTags,
    required String? content,
    required String idempotencyKey,
  }) async {
    createCalls++;
    lastCreateMoodLevel = moodLevel;
    lastCreateTags = List.of(emotionTags);
    lastCreateContent = content;
    createKeys.add(idempotencyKey);
    await createGate?.future;
    if (createFailures > 0) {
      createFailures--;
      throw const ApiException(
        code: 'NETWORK_ERROR',
        message: '잠시 저장하지 못했어요.',
      );
    }
    return MoodSaveResult(
      mood: _entry(moodLevel),
      reward: reward,
      safetyAction: null,
    );
  }

  @override
  Future<void> delete(int id) => throw UnimplementedError();

  @override
  Future<MoodCalendar> getCalendar({required int year, required int month}) =>
      throw UnimplementedError();

  @override
  Future<List<MoodEntry>> getByDate(String date) => throw UnimplementedError();

  @override
  Future<List<MoodEntry>> getByIds(List<int> ids) => throw UnimplementedError();

  @override
  Future<MoodEntry> getById(int id) async {
    getByIdCalls++;
    final latest = latestEntry;
    if (latest == null) throw UnimplementedError();
    return latest;
  }

  @override
  Future<MoodSaveResult> patch(int id, Map<String, dynamic> changes) async {
    patchCalls++;
    lastPatchChanges = Map<String, dynamic>.from(changes);
    final error = patchError;
    if (error != null) {
      patchError = null;
      throw error;
    }
    return MoodSaveResult(
      mood: latestEntry ?? _entry(changes['mood_level'] as int? ?? 3),
      reward: reward,
      safetyAction: null,
    );
  }
}

class _SignedInAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.signedIn,
        user: User(
          id: 1,
          email: 'user@example.com',
          nickname: '테스터',
          timezone: 'Asia/Seoul',
          seedBalance: 5,
          streakDays: 6,
        ),
      );
}

Future<void> _pumpRecordScreen(
  WidgetTester tester, {
  required FakeMoodRepository repository,
  MoodEntry? existing,
  Size size = const Size(800, 2400),
  double textScale = 1,
}) async {
  // ListView 하단의 저장 버튼까지 모두 빌드되도록 화면을 길게 잡는다.
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/record',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, state) => const Scaffold(body: Text('홈')),
      ),
      GoRoute(
        path: '/record',
        builder: (context, state) => MoodRecordScreen(existing: existing),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        moodRepositoryProvider.overrideWithValue(repository),
        authControllerProvider.overrideWith(_SignedInAuthController.new),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        routerConfig: router,
      ),
    ),
  );
}

FilledButton _saveButton(WidgetTester tester) {
  return tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, '저장하기'),
  );
}

void main() {
  test('MoodEntry가 서버 편집 버전을 파싱한다', () {
    final entry = MoodEntry.fromJson({
      'id': 7,
      'local_date': '2026-07-10',
      'recorded_at': '2026-07-10T03:00:00Z',
      'mood_level': 3,
      'edit_version': 123456,
    });

    expect(entry.editVersion, 123456);
  });

  testWidgets('일기 본문이 비어 있으면 저장 버튼이 비활성화된다', (tester) async {
    await _pumpRecordScreen(tester, repository: FakeMoodRepository());

    expect(find.text('저장하기'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);
  });

  testWidgets('일기 본문을 적으면 저장하고 수동 감정 값은 보내지 않는다', (tester) async {
    final repository = FakeMoodRepository();
    await _pumpRecordScreen(tester, repository: repository);

    await tester.enterText(
      find.byKey(const ValueKey('mood-diary-field')),
      '오늘은 새로운 팀원과 천천히 이야기를 나누었다.',
    );
    await tester.pump();
    expect(_saveButton(tester).onPressed, isNotNull);

    await tester.tap(find.text('저장하기'));
    await tester.pump();
    expect(repository.createCalls, 1);
    expect(repository.lastCreateMoodLevel, 3, reason: 'fake 하위 호환용 중립값');
    expect(repository.lastCreateTags, isEmpty);
    expect(repository.lastCreateContent, contains('새로운 팀원'));
    await tester.pumpAndSettle();
    expect(find.text('이야기가 화분에 닿았어요'), findsOneWidget);
    await tester.tap(find.text('목록으로 돌아가기'));
    await tester.pumpAndSettle();
    expect(find.byType(MoodRecordScreen), findsNothing);
    expect(find.text('홈'), findsOneWidget);
  });

  testWidgets('저장 뒤 식물 변화로 바로 이어 갈 수 있다', (tester) async {
    await _pumpRecordScreen(tester, repository: FakeMoodRepository());

    await tester.enterText(
      find.byKey(const ValueKey('mood-diary-field')),
      '창가에 들어온 햇빛이 오래 기억에 남았다.',
    );
    await tester.pump();
    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();

    expect(find.text('식물 변화 보기'), findsOneWidget);
    await tester.tap(find.text('식물 변화 보기'));
    await tester.pumpAndSettle();
    expect(find.text('홈'), findsOneWidget);
  });

  testWidgets('저장 중에는 본문 수정과 화면 이탈을 막아 입력 유실을 예방한다', (tester) async {
    final gate = Completer<void>();
    final repository = FakeMoodRepository(createGate: gate);
    await _pumpRecordScreen(tester, repository: repository);
    final diary = find.byKey(const ValueKey('mood-diary-field'));

    await tester.enterText(diary, '저장 중에 잃으면 안 되는 일기');
    await tester.pump();
    await tester.tap(find.text('저장하기'));
    await tester.pump();

    expect(tester.widget<TextField>(diary).readOnly, isTrue);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(MoodRecordScreen), findsOneWidget);
    expect(find.text('일기를 저장하고 있어요.'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('실패 후 같은 본문은 저장 키를 재사용하고 본문을 고치면 새 키를 쓴다', (tester) async {
    final repository = FakeMoodRepository(createFailures: 2);
    await _pumpRecordScreen(tester, repository: repository);
    final diary = find.byKey(const ValueKey('mood-diary-field'));

    await tester.enterText(diary, '첫 번째 본문');
    await tester.pump();
    await tester.tap(find.text('저장하기'));
    await tester.pump();
    expect(repository.createKeys, hasLength(1));

    await tester.enterText(diary, '고쳐 쓴 본문');
    await tester.pump();
    await tester.tap(find.text('저장하기'));
    await tester.pump();
    expect(repository.createKeys, hasLength(2));
    expect(repository.createKeys[1], isNot(repository.createKeys[0]));

    await tester.tap(find.text('저장하기'));
    await tester.pump();
    expect(repository.createKeys, hasLength(3));
    expect(repository.createKeys[2], repository.createKeys[1]);
    await tester.pumpAndSettle();
  });

  testWidgets('320px 화면과 200% 글자 크기에서도 관찰 노트가 넘치지 않는다', (tester) async {
    await _pumpRecordScreen(
      tester,
      repository: FakeMoodRepository(),
      size: const Size(320, 800),
      textScale: 2,
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('작은 화면과 200% 글자에서도 저장 결과를 스크롤해 선택할 수 있다', (tester) async {
    await _pumpRecordScreen(
      tester,
      repository: FakeMoodRepository(),
      size: const Size(320, 520),
      textScale: 2,
    );
    final diary = find.byKey(const ValueKey('mood-diary-field'));
    await tester.enterText(diary, '작은 화면에서도 잃지 않을 오늘의 기록');
    await tester.scrollUntilVisible(
      find.text('저장하기'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();

    expect(find.text('이야기가 화분에 닿았어요'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final sheetScroll = find.ancestor(
      of: find.text('이야기가 화분에 닿았어요'),
      matching: find.byType(SingleChildScrollView),
    );
    expect(sheetScroll, findsOneWidget);
    await tester.drag(sheetScroll, const Offset(0, -180));
    await tester.pump();
    expect(find.text('식물 변화 보기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('감정 선택 없이 일기 본문 중심으로 안내한다', (tester) async {
    await _pumpRecordScreen(tester, repository: FakeMoodRepository());

    expect(find.text('오늘 기록'), findsOneWidget);
    expect(find.text('오늘의 일기'), findsOneWidget);
    expect(find.text('오늘을 글로 남겨요'), findsOneWidget);
    expect(find.text('마음 날씨'), findsNothing);
    expect(find.text('감정 단서'), findsNothing);
  });

  testWidgets('작성 중 뒤로 가면 저장되지 않은 내용의 이탈을 확인한다', (tester) async {
    await _pumpRecordScreen(tester, repository: FakeMoodRepository());

    await tester.enterText(
      find.byKey(const ValueKey('mood-diary-field')),
      '아직 저장하지 않은 오늘의 기록',
    );
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('작성 중인 기록을 닫을까요?'), findsOneWidget);
    expect(find.text('계속 작성'), findsOneWidget);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(find.byType(MoodRecordScreen), findsNothing);
  });

  testWidgets('연속 기록 씨앗 보상이 전역 잔액에 즉시 반영된다', (tester) async {
    const reward = RewardResult(
      events: [
        RewardEvent(eventType: 'streak_7d', expDelta: 0, seedDelta: 72),
      ],
      plant: null,
      dailyExpGranted: 0,
      dailyExpCap: 30,
      seedBalance: 77,
    );
    await _pumpRecordScreen(
      tester,
      repository: FakeMoodRepository(reward: reward),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MoodRecordScreen)),
    );

    await tester.enterText(
      find.byKey(const ValueKey('mood-diary-field')),
      '오늘 장면을 일기로 남겨 본다.',
    );
    await tester.pump();
    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();

    expect(container.read(authControllerProvider).user?.seedBalance, 77);
  });

  testWidgets('편집 충돌은 초안을 보존하고 최신 버전 재로드 후 다시 저장한다', (tester) async {
    final original = FakeMoodRepository()._entry(
      3,
      content: '처음 서버 기록',
      editVersion: 7,
    );
    final latest = FakeMoodRepository()._entry(
      4,
      content: '다른 기기에서 바뀐 기록',
      emotionTags: const ['차분'],
      editVersion: 8,
    );
    final repository = FakeMoodRepository(
      latestEntry: latest,
      patchError: const ApiException(
        code: 'MOOD_VERSION_CONFLICT',
        message: '다른 기기에서 감정 기록이 변경되었습니다.',
        statusCode: 409,
      ),
    );
    await _pumpRecordScreen(
      tester,
      repository: repository,
      existing: original,
    );

    final diary = find.byType(TextField).last;
    await tester.enterText(diary, '내가 작성 중인 초안');
    await tester.tap(find.text('수정하기'));
    await tester.pumpAndSettle();

    expect(repository.lastPatchChanges?['expected_version'], 7);
    expect(find.text('다른 곳에서 기록이 바뀌었어요'), findsOneWidget);
    expect(tester.widget<TextField>(diary).controller?.text, '내가 작성 중인 초안');

    await tester.tap(find.text('최신 기록 불러오기'));
    await tester.pumpAndSettle();

    expect(repository.getByIdCalls, 1);
    expect(tester.widget<TextField>(diary).controller?.text, '다른 기기에서 바뀐 기록');

    await tester.enterText(diary, '최신 기록을 보고 다시 쓴 내용');
    await tester.tap(find.text('수정하기'));
    await tester.pump();

    expect(repository.patchCalls, 2);
    expect(repository.lastPatchChanges?['expected_version'], 8);
    expect(repository.lastPatchChanges, isNot(contains('mood_level')));
    expect(repository.lastPatchChanges, isNot(contains('emotion_tags')));
  });

  testWidgets('편집 충돌에서 내 초안을 유지하면 최신 버전으로 이어서 저장한다', (tester) async {
    final original = FakeMoodRepository()._entry(
      3,
      content: '처음 서버 기록',
      editVersion: 7,
    );
    final latest = FakeMoodRepository()._entry(
      4,
      content: '다른 기기에서 바뀐 기록',
      editVersion: 8,
    );
    final repository = FakeMoodRepository(
      latestEntry: latest,
      patchError: const ApiException(
        code: 'MOOD_VERSION_CONFLICT',
        message: '다른 기기에서 감정 기록이 변경되었습니다.',
        statusCode: 409,
      ),
    );
    await _pumpRecordScreen(
      tester,
      repository: repository,
      existing: original,
    );

    final diary = find.byType(TextField).last;
    await tester.enterText(diary, '지키고 싶은 내 초안');
    await tester.tap(find.text('수정하기'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('내 초안 유지'));
    await tester.pumpAndSettle();

    expect(repository.getByIdCalls, 1);
    expect(tester.widget<TextField>(diary).controller?.text, '지키고 싶은 내 초안');

    await tester.tap(find.text('수정하기'));
    await tester.pump();

    expect(repository.patchCalls, 2);
    expect(repository.lastPatchChanges?['expected_version'], 8);
    expect(repository.lastPatchChanges?['content'], '지키고 싶은 내 초안');
  });
}
