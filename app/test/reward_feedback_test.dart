import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/core/theme/mongroo_ui.dart';
import 'package:mongroo/features/expedition/presentation/expedition_combat_audio.dart';
import 'package:mongroo/features/expedition/presentation/expedition_settings.dart';
import 'package:mongroo/features/garden/domain/garden_models.dart';
import 'package:mongroo/features/garden/presentation/garden_unlock_dialog.dart';
import 'package:mongroo/features/home/domain/reward_result.dart';
import 'package:mongroo/features/home/presentation/reward_feedback.dart';

class _MutedSettings extends ExpeditionBattleSettingsNotifier {
  @override
  ExpeditionBattleSettings build() =>
      const ExpeditionBattleSettings(audioMode: ExpeditionAudioMode.muted);
}

RewardResult _reward({int seeds = 10, int exp = 20, int balance = 100}) =>
    RewardResult(
      events: [
        RewardEvent(
            eventType: 'quest_complete', expDelta: exp, seedDelta: seeds)
      ],
      plant: null,
      dailyExpGranted: exp,
      dailyExpCap: 30,
      seedBalance: balance,
    );

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool reducedMotion = false,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(320, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      expeditionBattleSettingsProvider.overrideWith(_MutedSettings.new)
    ],
    child: MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(
              disableAnimations: reducedMotion,
              textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
              body: Padding(padding: const EdgeInsets.all(24), child: child)),
        )),
  ));
  await tester.pump();
}

int _shownBalance(WidgetTester tester) =>
    tester.widget<MongrooSeedToken>(find.byType(MongrooSeedToken)).value;

void main() {
  testWidgets('해금은 받은 아이템과 잔액을 보여 주며 연출 중에도 닫을 수 있다', (tester) async {
    const item = ShopItem(
        id: 1,
        code: 'species_cactus',
        type: 'species_unlock',
        name: '가시니',
        description: '선인장 친구',
        priceSeeds: 90,
        rarity: 2,
        assetManifest: {'species_code': 'cactus'},
        owned: true);
    await _pump(
        tester,
        Builder(
            builder: (context) => FilledButton(
                  onPressed: () =>
                      showGardenUnlock(context, item: item, seedBalance: 12),
                  child: const Text('해금 결과 열기'),
                )),
        textScale: 2);
    await tester.tap(find.text('해금 결과 열기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('가시니'), findsOneWidget);
    expect(_shownBalance(tester), 12);
    await tester.ensureVisible(find.text('확인'));
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('씨앗이 도착한 뒤 잔액이 오르고 서버의 잔액에서 정확히 멈춘다', (tester) async {
    await _pump(tester, RewardReceipt(reward: _reward()));
    expect(_shownBalance(tester), 90);
    await tester.pump(const Duration(milliseconds: 580));
    expect(_shownBalance(tester), 90);
    await tester.pump(const Duration(milliseconds: 150));
    expect(_shownBalance(tester), inExclusiveRange(90, 100));
    await tester.pumpAndSettle();
    expect(_shownBalance(tester), 100);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('모션 줄이기에서는 대기 없이 최종 잔액을 표시한다', (tester) async {
    await _pump(tester, RewardReceipt(reward: _reward()), reducedMotion: true);
    expect(_shownBalance(tester), 100);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('보상이 없으면 지급 연출을 재생하지 않는다', (tester) async {
    await _pump(tester, RewardReceipt(reward: _reward(seeds: 0, exp: 0)));
    expect(_shownBalance(tester), 100);
    expect(find.text('이미 받은 보상이에요.'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('닫기와 백그라운드 전환은 남은 타이머나 지연된 보상을 남기지 않는다', (tester) async {
    await _pump(tester, RewardReceipt(reward: _reward()));
    await tester.pump(const Duration(milliseconds: 200));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(_shownBalance(tester), 100);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('320px와 글자 200%에서도 금액이 잘리지 않는다', (tester) async {
    await _pump(
        tester, RewardReceipt(reward: _reward(seeds: 120, balance: 12345)),
        reducedMotion: true, textScale: 2);
    await tester.pumpAndSettle();
    expect(find.text('씨앗 +120'), findsOneWidget);
    expect(find.text('경험치 +20'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('화면 갱신은 지급을 재연하지 않고 더 최근 잔액을 유지한다', (tester) async {
    final reward = ValueNotifier(_reward());
    addTearDown(reward.dispose);
    await _pump(
        tester,
        ValueListenableBuilder<RewardResult>(
          valueListenable: reward,
          builder: (_, value, __) => RewardReceipt(reward: value),
        ));
    await tester.pump(const Duration(milliseconds: 300));
    reward.value = _reward(seeds: 0, exp: 0, balance: 140);
    await tester.pumpAndSettle();
    expect(_shownBalance(tester), 140);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('해금 효과가 움직여도 캐릭터 위젯은 매 프레임 다시 만들지 않는다', (tester) async {
    var builds = 0;
    await _pump(tester, MilestoneReveal(child: Builder(builder: (_) {
      builds++;
      return const SizedBox(width: 180, height: 180, child: Text('새 캐릭터'));
    })));
    final initial = builds;
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(builds, initial);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}
