import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/home/data/plant_repository.dart';
import 'package:mongroo/features/home/domain/plant.dart';
import 'package:mongroo/features/home/presentation/plant_view.dart';
import 'package:mongroo/features/home/presentation/species_picker_dialog.dart';

const _species = [
  PlantSpecies(
    id: 1,
    code: 'basic_sprout',
    name: '새싹몬',
    rarity: 1,
    unlockPrice: 0,
    assetManifest: {
      'growth': {
        'seed_shape': 'heart_speck_seed',
        'vessel_style': 'round_terracotta_pot',
        'rarity_effect': 'none',
        'asset_namespace': 'plants/basic_sprout',
      },
    },
  ),
  PlantSpecies(
    id: 2,
    code: 'cactus',
    name: '가시니',
    rarity: 2,
    unlockPrice: 100,
    isUnlocked: false,
    assetManifest: {
      'growth': {
        'seed_shape': 'spined_star_seed',
        'vessel_style': 'ribbed_desert_incubator',
        'rarity_effect': 'warm_dust_glint',
        'asset_namespace': 'plants/cactus',
      },
    },
  ),
  PlantSpecies(
    id: 3,
    code: 'sunflower',
    name: '해바라기',
    rarity: 2,
    unlockPrice: 100,
    assetManifest: {
      'growth': {
        'seed_shape': 'striped_sun_seed',
        'vessel_style': 'sunbeam_bell_jar',
        'rarity_effect': 'soft_sun_motes',
        'asset_namespace': 'plants/sunflower',
      },
    },
  ),
];

class _SpeciesRepository extends PlantRepository {
  _SpeciesRepository(this.items) : super(Dio());

  final List<PlantSpecies> items;

  @override
  Future<List<PlantSpecies>> getSpecies() async => items;
}

Future<void> _pumpLauncher(
  WidgetTester tester, {
  required ValueChanged<SpeciesPickResult?> onResult,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        plantRepositoryProvider.overrideWithValue(
          _SpeciesRepository(_species),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                onResult(await showSpeciesPickerDialog(context));
              },
              child: const Text('새 식물 심기'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('새 식물 심기'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('품종별 1단계 씨앗·용기와 희귀도·해금 비용을 보여 준다', (tester) async {
    SpeciesPickResult? result;
    await _pumpLauncher(tester, onResult: (value) => result = value);

    expect(find.byType(PlantStagePreview), findsNWidgets(3));
    final previews = tester
        .widgetList<PlantStagePreview>(find.byType(PlantStagePreview))
        .toList();
    expect(previews.map((preview) => preview.stage), everyElement(1));
    expect(
      previews.map((preview) => preview.speciesCode),
      ['basic_sprout', 'cactus', 'sunflower'],
    );

    expect(find.text('하트점 씨앗 · 포근한 토분'), findsOneWidget);
    expect(find.text('가시별 씨앗 · 사막결 육묘분'), findsOneWidget);
    expect(find.text('해무늬 씨앗 · 햇살 유리 육묘관'), findsOneWidget);
    expect(find.text('기본 품종 · ★'), findsOneWidget);
    expect(find.text('특별 품종 · ★★'), findsNWidgets(2));
    expect(find.text('정원 상점 · 씨앗 100개'), findsOneWidget);
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('잠긴 품종은 상점 열기 결과를 돌려준다', (tester) async {
    SpeciesPickResult? result;
    await _pumpLauncher(tester, onResult: (value) => result = value);

    await tester.ensureVisible(find.byKey(const ValueKey('species-2')));
    await tester.tap(find.byKey(const ValueKey('species-2')));
    await tester.pumpAndSettle();

    expect(result?.openShop, isTrue);
    expect(result?.speciesId, isNull);
    expect(result?.speciesCode, 'cactus');
    expect(result?.name, isNull);
  });

  testWidgets('해금된 품종과 입력한 이름을 기존 결과로 돌려준다', (tester) async {
    SpeciesPickResult? result;
    await _pumpLauncher(tester, onResult: (value) => result = value);

    await tester.ensureVisible(find.byKey(const ValueKey('species-3')));
    await tester.tap(find.byKey(const ValueKey('species-3')));
    await tester.pump();
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), ' 노을이 ');
    await tester.tap(find.text('이 씨앗 심기'));
    await tester.pumpAndSettle();

    expect(result?.speciesId, 3);
    expect(result?.name, '노을이');
  });

  testWidgets('320px과 큰 글자에서도 레이아웃이 넘치지 않는다', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    SpeciesPickResult? result;
    await _pumpLauncher(
      tester,
      onResult: (value) => result = value,
      textScale: 2,
    );

    expect(find.text('어떤 씨앗으로 시작할까요?'), findsOneWidget);
    expect(find.text('이 씨앗 심기'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });
}
