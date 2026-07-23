import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/features/home/data/plant_repository.dart';
import 'package:mongroo/features/home/domain/plant.dart';
import 'package:mongroo/features/home/presentation/home_controller.dart';

class _PollingPlantRepository extends PlantRepository {
  _PollingPlantRepository({
    required this.pending,
    required this.ready,
    this.readyOnCall = 2,
  }) : super(Dio());

  final ActivePlant pending;
  final ActivePlant ready;
  final int readyOnCall;
  int calls = 0;

  @override
  Future<ActivePlant?> getActivePlant() async {
    calls++;
    return calls < readyOnCall ? pending : ready;
  }
}

ActivePlant _plant({required bool pending}) => ActivePlant(
      id: 1,
      name: '새봄이',
      species: const PlantSpecies(id: 1, code: 'seed', name: '마음씨앗'),
      exp: 430,
      stage: 3,
      stageThresholds: const [0, 100, 300, 600, 1000],
      nextStageExp: 600,
      harvestable: false,
      plantedAt: DateTime.utc(2026, 7, 1),
      growthForm: pending ? null : PlantGrowthForm.sunny,
      branchStatus:
          pending ? PlantBranchStatus.emerging : PlantBranchStatus.stable,
      branchPhase:
          pending ? PlantBranchPhase.hinting : PlantBranchPhase.branched,
      profileState:
          pending ? PlantProfileState.analyzing : PlantProfileState.ready,
      emotionProfile: ActivePlantEmotionProfile(
        total: pending ? 2 : 3,
        pendingCount: pending ? 1 : 0,
        counts: const {'joy': 2},
      ),
      visualKey: pending ? 'stage_3_base' : 'stage_3_sunny',
    );

void main() {
  testWidgets('pending 일기 분석이 끝나면 홈 식물 분기를 자동 갱신한다', (tester) async {
    final repository = _PollingPlantRepository(
      pending: _plant(pending: true),
      ready: _plant(pending: false),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [plantRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              final plant = ref.watch(homeControllerProvider).valueOrNull;
              return Text(plant?.visualKey ?? 'loading');
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('stage_3_base'), findsOneWidget);
    expect(repository.calls, 1);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('stage_3_sunny'), findsOneWidget);
    expect(repository.calls, 2);
  });

  testWidgets('worker 재시도 창이 끝날 때까지 pending 분석을 확인한다', (tester) async {
    final repository = _PollingPlantRepository(
      pending: _plant(pending: true),
      ready: _plant(pending: false),
      // 첫 조회 뒤 12번째 polling에서 terminal 결과를 받는 상황이다.
      readyOnCall: 13,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [plantRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              final plant = ref.watch(homeControllerProvider).valueOrNull;
              return Text(plant?.visualKey ?? 'loading');
            },
          ),
        ),
      ),
    );
    await tester.pump();

    for (final seconds in [2, 3, 5, 8, 13, 21, 21, 21, 21, 21, 21, 21]) {
      await tester.pump(Duration(seconds: seconds));
      await tester.pump();
    }

    expect(repository.calls, 13);
    expect(find.text('stage_3_sunny'), findsOneWidget);
  });
}
