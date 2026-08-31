import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tap_target.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/auth/presentation/auth_controller.dart';
import 'package:mongroo/features/expedition/presentation/expedition_scene.dart';
import 'package:mongroo/features/expedition/presentation/moss_archive_scene.dart';
import 'package:mongroo/features/trial/data/trial_progress_store.dart';
import 'package:mongroo/features/home/domain/plant.dart';
import 'package:mongroo/features/trial/domain/trial_progress.dart';
import 'package:mongroo/features/trial/presentation/trial_screen.dart';

class _MemoryTrialStorage implements TrialProgressStorage {
  _MemoryTrialStorage({this.value, this.failWrites = false});

  String? value;
  final bool failWrites;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    if (failWrites) throw StateError('storage disabled');
    this.value = value;
  }
}

class _SignedOutAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.signedOut);
}

Future<void> _pumpTrial(
  WidgetTester tester,
  _MemoryTrialStorage storage, {
  Size size = const Size(390, 844),
  double textScale = 1,
  bool dark = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trialProgressStorageProvider.overrideWithValue(storage),
        authControllerProvider.overrideWith(_SignedOutAuthController.new),
      ],
      child: MaterialApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: const TrialScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

/// 화면에 실제로 그려진 글자가 잘렸는지. `maxLines`를 넘으면 말줄임표가 붙는다.
bool _ellipsized(WidgetTester tester, Finder finder) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: finder, matching: find.byType(RichText)).first,
  );
  return paragraph.didExceedMaxLines;
}

void main() {
  testWidgets('가입 없이 일기부터 선택 탐험과 귀환까지 직접 진행한다', (tester) async {
    final storage = _MemoryTrialStorage();
    await _pumpTrial(tester, storage);
    expectTapTargets(tester, screen: '체험');

    expect(find.text('회원가입 없는 로컬 체험'), findsOneWidget);
    expect(find.text('이 기기에만 저장'), findsOneWidget);
    expect(find.byKey(const Key('trial-diary-growth-hero')), findsOneWidget);
    expect(find.byKey(const Key('trial-growth-character')), findsOneWidget);
    expect(find.text('탐험은 보조 활동'), findsOneWidget);
    expect(find.byType(MossArchiveScene), findsNothing);

    await _tapVisible(tester, find.byKey(const Key('trial-start')));
    // 마음을 먼저 고르라고 묻지 않는다. 글 칸이 먼저고, 결 고르기는
    // 서버가 없어서 대신 묻는 것이라 그 아래에 온다.
    expect(find.text('오늘 기억에 남은 순간을 적어 보세요'), findsOneWidget);
    expect(find.textContaining('먼저 고르지 않아도 돼요'), findsOneWidget);
    expect(find.textContaining('글을 읽어 줄 서버가 없어요'), findsOneWidget);
    // 여섯 결이 모두 있고 본편과 같은 이름을 쓴다.
    for (final form in PlantGrowthForm.values) {
      expect(
        find.byKey(Key('trial-emotion-${form.code}')),
        findsOneWidget,
        reason: form.personalityName,
      );
    }
    expect(find.text('불안 · 달빛결'), findsOneWidget);

    await _tapVisible(tester, find.byKey(const Key('trial-sample')));
    final save = tester.widget<FilledButton>(
      find.byKey(const Key('trial-save-diary')),
    );
    expect(save.onPressed, isNotNull);
    await _tapVisible(tester, find.byKey(const Key('trial-save-diary')));

    expect(find.textContaining('햇살결 새싹'), findsOneWidget);
    expect(find.text('성장 +30 · 씨앗 +12'), findsOneWidget);
    await _tapVisible(tester, find.byKey(const Key('trial-open-exploration')));

    expect(find.text('첫 갈림길'), findsOneWidget);
    expect(find.byType(MossArchiveScene), findsOneWidget);
    expect(find.byType(ExpeditionSceneBackdrop), findsOneWidget);
    expect(find.text('침수 표찰 동굴'), findsOneWidget);
    expect(find.text('기억 뿌리 땅굴'), findsOneWidget);
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(scrollable.position.pixels, 0);
    await _tapVisible(tester, find.byKey(const Key('trial-path-labels')));
    expect(find.text('번진 이름표'), findsOneWidget);
    expect(find.text('수정빛 물길 위로 젖은 이름표가 흘러가요.'), findsOneWidget);
    await _tapVisible(tester, find.byKey(const Key('trial-resolve-event')));

    expect(find.text('첫 마음 탐험을 마쳤어요'), findsOneWidget);
    expect(find.text('체험 발견물 · 이끼 열쇠 조각'), findsOneWidget);
    final restored = TrialProgress.decode(storage.value!);
    expect(restored.stage, TrialStage.complete);
    expect(restored.selectedPath, 'labels');
    expect(restored.selectedChoice, 'trace');
    expect(tester.takeException(), isNull);
  });

  testWidgets('저장된 단계에서 체험을 이어서 시작한다', (tester) async {
    final storage = _MemoryTrialStorage(
      value: const TrialProgress(
        stage: TrialStage.growth,
        diaryText: '조용히 산책해서 마음이 조금 편안해졌다.',
        emotionCode: 'rainy',
      ).encode(),
    );

    await _pumpTrial(tester, storage);

    expect(find.textContaining('빗물결 새싹'), findsOneWidget);
    expect(find.byKey(const Key('trial-start')), findsNothing);
  });

  testWidgets('기기 저장이 막혀도 안내 후 체험은 계속된다', (tester) async {
    final storage = _MemoryTrialStorage(failWrites: true);
    await _pumpTrial(tester, storage);

    await _tapVisible(tester, find.byKey(const Key('trial-start')));
    expect(find.textContaining('저장소를 사용할 수 없어'), findsOneWidget);
    expect(find.text('오늘 기억에 남은 순간을 적어 보세요'), findsOneWidget);
  });

  testWidgets('마음 기록 칸의 안내 문구가 글자 수 표시에 밀려 잘리지 않는다', (tester) async {
    // helperText와 counter는 한 줄을 나눠 쓴다. 안내가 길면 `0/280`에 밀려
    // `10자 이상이면 캐릭터가 마음의 결을 받…`으로 끊겼다. 하필 무슨 일이
    // 일어나는지 말해 주는 뒷부분이 잘린다.
    final storage = _MemoryTrialStorage();
    await _pumpTrial(tester, storage);
    await _tapVisible(tester, find.byKey(const Key('trial-start')));

    final helper = find.text('10자 이상이면 캐릭터가 마음의 결을 받아요.');
    expect(helper, findsOneWidget);
    expect(
      _ellipsized(tester, helper),
      isFalse,
      reason: '안내 문구가 잘렸습니다',
    );
  });

  testWidgets('320px 200% 글자에서도 체험 시작 화면이 오버플로우하지 않는다', (tester) async {
    await _pumpTrial(
      tester,
      _MemoryTrialStorage(),
      size: const Size(320, 720),
      textScale: 2,
    );

    expect(find.text('가입하기 전에, 마음 하나를 키워 봐요'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('trial-start')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('가로 화면과 어두운 테마에서도 핵심 CTA를 스크롤해 사용할 수 있다', (tester) async {
    await _pumpTrial(
      tester,
      _MemoryTrialStorage(),
      size: const Size(640, 360),
      textScale: 1.25,
      dark: true,
    );

    expect(find.byKey(const Key('trial-diary-growth-hero')), findsOneWidget);
    final start = find.byKey(const Key('trial-start'));
    await tester.ensureVisible(start);
    await tester.pump();
    expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
