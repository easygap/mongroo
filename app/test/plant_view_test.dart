import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/features/home/domain/plant.dart';
import 'package:mongroo/features/home/presentation/plant_view.dart';

Future<PlantPainter> _pumpAndGetPainter(
  WidgetTester tester, {
  required int stage,
  PlantExpression expression = PlantExpression.neutral,
  PlantGrowthForm? form,
  PlantGrowthForm? secondaryForm,
  String speciesCode = 'basic_sprout',
  PlantGrowthVisual? growthVisual,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: PlantView(
            stage: stage,
            expression: expression,
            form: form,
            secondaryForm: secondaryForm,
            speciesCode: speciesCode,
            growthVisual: growthVisual,
            preferRasterAssets: false,
          ),
        ),
      ),
    ),
  );
  final customPaint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(PlantView),
      matching: find.byType(CustomPaint),
    ),
  );
  final painter = customPaint.painter;
  expect(painter, isA<PlantPainter>());
  return painter! as PlantPainter;
}

Future<int> _pixelHash(PlantPainter painter) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  painter.paint(canvas, const Size.square(180));
  final picture = recorder.endRecording();
  final image = await picture.toImage(180, 180);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  var hash = 0x811C9DC5;
  for (final value in bytes!.buffer.asUint8List()) {
    hash = ((hash ^ value) * 0x01000193) & 0xFFFFFFFF;
  }
  image.dispose();
  picture.dispose();
  return hash;
}

void main() {
  testWidgets('단계 1~5가 서로 다른 painter 구성으로 렌더링된다', (tester) async {
    final painters = <PlantPainter>[];
    for (final stage in [1, 2, 3, 4, 5]) {
      painters.add(await _pumpAndGetPainter(tester, stage: stage));
    }

    // 각 단계가 그대로 반영되고 중복이 없다.
    expect(painters.map((p) => p.stage).toList(), [1, 2, 3, 4, 5]);

    // 단계가 바뀌면 다시 그린다(=시각 표현이 달라진다).
    for (var i = 0; i < painters.length - 1; i++) {
      expect(painters[i + 1].shouldRepaint(painters[i]), isTrue);
    }
  });

  test('씨앗부터 만개까지 다섯 단계의 실제 픽셀이 모두 다르다', () async {
    final hashes = <int>[];
    for (final stage in [1, 2, 3, 4, 5]) {
      hashes.add(await _pixelHash(const PlantPainter(
        stage: 1,
        expression: PlantExpression.neutral,
      ).copyWithStage(stage)));
    }
    expect(hashes.toSet(), hasLength(5));
  });

  testWidgets('범위를 벗어난 stage는 1~5로 보정된다', (tester) async {
    final low = await _pumpAndGetPainter(tester, stage: 0);
    expect(low.stage, 1);

    final high = await _pumpAndGetPainter(tester, stage: 9);
    expect(high.stage, 5);
  });

  testWidgets('저장 확인 표시가 painter에 반영되고 성장 감정으로 오해되지 않는다', (tester) async {
    final happy = await _pumpAndGetPainter(
      tester,
      stage: 3,
      expression: PlantExpression.acknowledged,
      form: PlantGrowthForm.ember,
    );
    expect(happy.expression, PlantExpression.acknowledged);

    final sad = await _pumpAndGetPainter(
      tester,
      stage: 3,
      expression: PlantExpression.sad,
      form: PlantGrowthForm.ember,
    );
    expect(sad.shouldRepaint(happy), isTrue);
    expect(sad.stage, happy.stage, reason: '표정은 단계(성장)에 영향을 주지 않는다');
  });

  testWidgets('단계와 분기 상태가 접근성 라벨로 노출된다', (tester) async {
    final handle = tester.ensureSemantics();
    for (final stage in [1, 2, 3, 4, 5]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlantView(stage: stage, preferRasterAssets: false),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel(
          '식물 모습: 새싹몬, ${plantStageName(stage)} 단계, '
          '${stage == 1 ? '하트점 씨앗, ' : ''}포근한 토분, 성장 분기 관찰 중',
        ),
        findsOneWidget,
      );
    }
    handle.dispose();
  });

  testWidgets('4단계 주결과 보조결이 하나의 이미지 접근성 라벨로 노출된다', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlantView(
            stage: 4,
            form: PlantGrowthForm.rainy,
            secondaryForm: PlantGrowthForm.sparkling,
            speciesCode: 'sunflower',
            speciesName: '해바라기',
            preferRasterAssets: false,
          ),
        ),
      ),
    );

    final plant = find.bySemanticsLabel(
      '식물 모습: 해바라기, 개화 단계, 햇살 유리 육묘관, 빗방울꽃 주결, 반짝꽃 보조결',
    );
    expect(plant, findsOneWidget);
    expect(tester.getSemantics(plant).flagsCollection.isImage, isTrue);
    handle.dispose();
  });

  testWidgets('정적 painter는 래스터 캐시를 쓰고 매 프레임 다시 그리지 않는다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlantView(stage: 5, preferRasterAssets: false),
        ),
      ),
    );
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(PlantView),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(paint.isComplex, isTrue);
    expect(paint.willChange, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('3단계부터 여섯 형태가 painter에 별도 분기로 전달된다', (tester) async {
    final painters = <PlantPainter>[];
    for (final form in PlantGrowthForm.values) {
      painters.add(await _pumpAndGetPainter(tester, stage: 4, form: form));
    }
    expect(painters.map((painter) => painter.form).toSet(),
        PlantGrowthForm.values.toSet());
    for (var index = 1; index < painters.length; index++) {
      expect(painters[index].shouldRepaint(painters[index - 1]), isTrue);
    }
  });

  testWidgets('품종이 바뀌면 같은 성장 단계도 다른 모습으로 다시 그린다', (tester) async {
    final defaultPlant = await _pumpAndGetPainter(tester, stage: 4);
    final cactus = await _pumpAndGetPainter(
      tester,
      stage: 4,
      speciesCode: 'cactus',
    );
    final sunflower = await _pumpAndGetPainter(
      tester,
      stage: 4,
      speciesCode: 'sunflower',
    );

    expect(cactus.speciesCode, 'cactus');
    expect(sunflower.speciesCode, 'sunflower');
    expect(cactus.shouldRepaint(defaultPlant), isTrue);
    expect(sunflower.shouldRepaint(cactus), isTrue);
  });

  test('기본·가시니·해바라기는 씨앗과 육묘 용기부터 서로 다르게 그려진다', () async {
    final hashes = <int>[];
    for (final code in ['basic_sprout', 'cactus', 'sunflower']) {
      hashes.add(await _pixelHash(PlantPainter(
        stage: 1,
        expression: PlantExpression.neutral,
        speciesCode: code,
      )));
    }
    expect(hashes.toSet(), hasLength(3));
  });

  test('3단계부터 여섯 마음 분기가 체형과 오라까지 다르게 그려진다', () async {
    final hashes = <int>[];
    for (final form in PlantGrowthForm.values) {
      hashes.add(await _pixelHash(PlantPainter(
        stage: 3,
        expression: PlantExpression.neutral,
        form: form,
      )));
    }
    expect(hashes.toSet(), hasLength(PlantGrowthForm.values.length));
  });

  test('4단계부터 같은 주결에도 보조결 표식이 서로 다르게 그려진다', () async {
    final hashes = <int>[];
    for (final secondary in [
      PlantGrowthForm.rainy,
      PlantGrowthForm.ember,
      PlantGrowthForm.sparkling,
    ]) {
      hashes.add(await _pixelHash(PlantPainter(
        stage: 4,
        expression: PlantExpression.neutral,
        form: PlantGrowthForm.sunny,
        secondaryForm: secondary,
      )));
    }
    expect(hashes.toSet(), hasLength(3));
  });

  test('같은 품종에서 서버 시각 계약이 바뀌면 다시 그린다', () {
    const previous = PlantPainter(
      stage: 1,
      expression: PlantExpression.neutral,
      speciesCode: 'basic_sprout',
      growthVisual: PlantGrowthVisual(
        seedShape: 'heart_speck_seed',
        vesselStyle: 'round_terracotta_pot',
        rarityEffect: 'none',
        assetNamespace: 'plants/basic_sprout',
        rarity: 1,
      ),
    );
    const changed = PlantPainter(
      stage: 1,
      expression: PlantExpression.neutral,
      speciesCode: 'basic_sprout',
      growthVisual: PlantGrowthVisual(
        seedShape: 'crystal_seed',
        vesselStyle: 'crystal_growth_tube',
        rarityEffect: 'prismatic',
        assetNamespace: 'plants/basic_sprout-deluxe',
        rarity: 4,
      ),
    );

    expect(changed.shouldRepaint(previous), isTrue);
  });

  test('기본 품종은 2.5D 감정 성장 아트 뒤에 기존 대체 파일을 찾는다', () {
    const visual = PlantGrowthVisual(
      seedShape: 'heart_speck_seed',
      vesselStyle: 'round_terracotta_pot',
      rarityEffect: 'none',
      assetNamespace: 'plants/basic_sprout',
      rarity: 1,
      phase: 'full_bloom',
    );

    final candidates = PlantGrowthAssetResolver.candidates(
      speciesCode: 'basic_sprout',
      stage: 5,
      form: PlantGrowthForm.rainy,
      secondaryForm: PlantGrowthForm.sparkling,
      visual: visual,
    );

    expect(candidates, [
      'assets/plants/basic-sprout-25d-full-bloom-rainy-sparkling.webp',
      'assets/plants/basic-sprout-25d-full-bloom-rainy.webp',
      'assets/plants/basic-sprout-25d-full-bloom.webp',
      'assets/plants/basic-sprout-cute-full-bloom-rainy-sparkling.webp',
      'assets/plants/basic-sprout-cute-full-bloom-rainy.webp',
      'assets/plants/basic-sprout-cute-full-bloom.webp',
      'assets/plants/basic-sprout-full-bloom-rainy-sparkling.webp',
      'assets/plants/basic-sprout-full-bloom-rainy.webp',
      'assets/plants/basic-sprout-full-bloom.webp',
    ]);
  });

  test('사람형 성장 계보는 전용 2.5D 파일을 먼저 찾는다', () {
    final candidates = PlantGrowthAssetResolver.candidates(
      speciesCode: 'gumiho_pot',
      stage: 5,
      form: PlantGrowthForm.rainy,
      secondaryForm: PlantGrowthForm.sparkling,
    );

    expect(candidates.take(6), [
      'assets/plants/gumiho-pot-25d-full-bloom-rainy-v4-idle.webp',
      'assets/plants/gumiho-pot-25d-full-bloom-rainy-v3.webp',
      'assets/plants/gumiho-pot-25d-full-bloom-rainy-v2.webp',
      'assets/plants/gumiho-pot-25d-full-bloom-rainy-sparkling.webp',
      'assets/plants/gumiho-pot-25d-full-bloom-rainy.webp',
      'assets/plants/gumiho-pot-25d-full-bloom.webp',
    ]);
  });

  test('감정 성체는 여섯 감정과 세 자세를 전환 전에 모두 준비한다', () {
    final candidates = PlantGrowthAssetResolver.preloadCandidates(
      speciesCode: 'gumiho_pot',
      stage: 5,
      form: PlantGrowthForm.sunny,
    );

    expect(candidates, hasLength(18));
    expect(candidates.toSet(), hasLength(18));
    for (final form in PlantGrowthForm.values) {
      for (final pose in PlantSpritePose.values) {
        expect(
          candidates,
          contains(
            'assets/plants/gumiho-pot-25d-full-bloom-${form.code}'
            '-v4-${pose.code}.webp',
          ),
        );
      }
    }
  });

  test('구매 의상은 바디와 같은 프레임 묶음으로 준비한다', () {
    final candidates = PlantGrowthAssetResolver.layeredCandidates(
      speciesCode: 'gumiho_pot',
      stage: 5,
      form: PlantGrowthForm.rainy,
      pose: PlantSpritePose.diary,
      outfitKey: 'garden_daily',
    );

    // 최소 가림이 바디에 포함돼 있어 지금은 이너 레이어 파일이 없다. 없는
    // 경로를 후보에 넣으면 프레임마다 디코딩이 한 번씩 실패하므로 넣지 않는다.
    expect(candidates, [
      [
        'assets/wardrobe/bodies/gumiho-pot-diary-rainy.webp',
        'assets/wardrobe/outfits/garden-daily-gumiho-pot-diary-rainy.webp',
      ],
    ]);
    expect(
      PlantGrowthAssetResolver.preloadLayeredCandidates(
        speciesCode: 'gumiho_pot',
        stage: 5,
        outfitKey: 'garden_daily',
      ),
      hasLength(36),
    );
    expect(
      PlantGrowthAssetResolver.layeredCandidates(
        speciesCode: 'gumiho_pot',
        stage: 4,
        form: PlantGrowthForm.rainy,
        pose: PlantSpritePose.diary,
        outfitKey: 'garden_daily',
      ),
      isEmpty,
    );
  });

  test('감정 성체 10종 모두 캐릭터 고유 부분 모션과 눈 깜빡임을 제공한다', () {
    const speciesCodes = [
      'baby_pot',
      'handsome_pot',
      'pretty_pot',
      'tsundere_pot',
      'zombie_pot',
      'gumiho_pot',
      'ninja_pot',
      'magical_pot',
      'aloof_pot',
      'student_pot',
    ];

    for (final speciesCode in speciesCodes) {
      expect(
        PlantView.debugHasCharacterMotionProfile(speciesCode),
        isTrue,
        reason: '$speciesCode 모션 프로필이 누락됨',
      );
      expect(
        PlantGrowthAssetResolver.preloadCandidates(
          speciesCode: speciesCode,
          stage: 5,
          form: PlantGrowthForm.sunny,
        ),
        hasLength(18),
        reason: '$speciesCode 스프라이트 사전 로딩 목록이 누락됨',
      );
    }
  });

  test('캐릭터 고유 모션을 더해도 감정별 호흡 속도는 유지한다', () {
    const speciesCode = 'gumiho_pot';
    expect(
      PlantView.debugMotionDuration(
        stage: 5,
        form: PlantGrowthForm.sunny,
        speciesCode: speciesCode,
      ),
      const Duration(milliseconds: 1900),
    );
    expect(
      PlantView.debugMotionDuration(
        stage: 5,
        form: PlantGrowthForm.ember,
        speciesCode: speciesCode,
      ),
      const Duration(milliseconds: 1250),
    );
    expect(
      PlantView.debugMotionDuration(
        stage: 5,
        form: PlantGrowthForm.moonlit,
        speciesCode: speciesCode,
      ),
      const Duration(milliseconds: 3800),
    );
  });

  testWidgets('사람형 계보의 최고 성장 단계는 최신 감정 성체를 사용한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: PlantView(
              stage: 5,
              speciesCode: 'gumiho_pot',
              speciesName: '여우비',
              form: PlantGrowthForm.moonlit,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey(
          'assets/plants/gumiho-pot-25d-full-bloom-moonlit-v4-idle.webp',
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('일기 반응과 성장 축하는 전용 감정 성체 자세를 사용한다', (tester) async {
    Future<void> pumpExpression(PlantExpression expression) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: PlantView(
                stage: 5,
                speciesCode: 'tsundere_pot',
                form: PlantGrowthForm.ember,
                expression: expression,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpExpression(PlantExpression.acknowledged);
    expect(
      find.byKey(
        const ValueKey(
          'assets/plants/tsundere-pot-25d-full-bloom-ember-v4-diary.webp',
        ),
      ),
      findsOneWidget,
    );

    await pumpExpression(PlantExpression.happy);
    expect(
      find.byKey(
        const ValueKey(
          'assets/plants/tsundere-pot-25d-full-bloom-ember-v4-grow.webp',
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('기본 품종은 공통 씨앗 뒤 감정별 2.5D 성장 래스터를 우선 사용한다', (tester) async {
    const assets = {
      1: 'assets/plants/basic-sprout-25d-seed.webp',
      2: 'assets/plants/basic-sprout-25d-sprout-sunny.webp',
      3: 'assets/plants/basic-sprout-25d-branching-sunny.webp',
      4: 'assets/plants/basic-sprout-25d-bloom-sunny.webp',
      5: 'assets/plants/basic-sprout-25d-full-bloom-sunny.webp',
    };

    for (final entry in assets.entries) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: PlantView(
                stage: entry.key,
                form: entry.key >= 2 ? PlantGrowthForm.sunny : null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ValueKey(entry.value)), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('2단계 감정 단서가 없으면 같은 화풍의 관찰 중 새싹을 사용한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: PlantView(stage: 2)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey('assets/plants/basic-sprout-25d-sprout.webp'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('성장 단계 미리보기도 검수한 래스터 에셋을 사용한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlantStagePreview(
            stage: 4,
            form: PlantGrowthForm.sunny,
            size: 96,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey(
          'assets/plants/basic-sprout-25d-bloom-sunny.webp',
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('모션 여백이 이동과 회전 중 캐릭터가 잘리지 않도록 확보된다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlantView(
            stage: 5,
            form: PlantGrowthForm.ember,
            speciesCode: 'gumiho_pot',
            width: 270,
            height: 405,
            preferRasterAssets: false,
          ),
        ),
      ),
    );

    final padding = tester.widget<Padding>(
      find.byKey(const ValueKey('plant-motion-safe-area')),
    );
    final insets = padding.padding as EdgeInsets;
    expect(insets.left, greaterThan(2));
    expect(insets.right, insets.left);
    expect(insets.top, greaterThan(8));
    expect(insets.bottom, greaterThanOrEqualTo(2));
  });

  test('워드로브 바디는 감정별로 측정한 얼굴 위치에 눈 깜빡임을 맞춘다', () {
    for (final testCase in [
      (
        species: 'gumiho_pot',
        form: PlantGrowthForm.sunny,
        expectedOffset: const Offset(-38, 2),
      ),
      (
        species: 'baby_pot',
        form: PlantGrowthForm.mosaic,
        expectedOffset: const Offset(9, -1),
      ),
      (
        species: 'handsome_pot',
        form: PlantGrowthForm.sunny,
        expectedOffset: const Offset(6, 1),
      ),
    ]) {
      final legacy = PlantView.debugBlinkEyeCenters(
        speciesCode: testCase.species,
        form: testCase.form,
      );
      final wardrobe = PlantView.debugBlinkEyeCenters(
        speciesCode: testCase.species,
        form: testCase.form,
        wardrobeLayered: true,
      );

      expect(legacy, hasLength(wardrobe.length));
      for (var index = 0; index < legacy.length; index++) {
        expect(wardrobe[index] - legacy[index], testCase.expectedOffset);
      }
    }
  });

  testWidgets('감정 성체는 원자 전환과 캐릭터 고유 부분 모션·눈 깜빡임을 연결한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlantView(
            stage: 5,
            form: PlantGrowthForm.ember,
            speciesCode: 'gumiho_pot',
            width: 270,
            height: 405,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('plant-sprite-atomic-swap')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('plant-sprite-atomic-swap')),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('plant-part-motion-gumiho-pot')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('plant-blink-gumiho-pot')),
      findsOneWidget,
    );
  });

  testWidgets('동작 줄이기 환경에서는 래스터 부분 모션과 눈 깜빡임도 만들지 않는다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: PlantView(
              stage: 5,
              form: PlantGrowthForm.ember,
              speciesCode: 'gumiho_pot',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('plant-part-motion-gumiho-pot')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('plant-blink-gumiho-pot')),
      findsNothing,
    );
  });

  testWidgets('제작되지 않은 품종은 기존 벡터 painter로 돌아간다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: PlantView(stage: 1, speciesCode: 'future_species'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(PlantView),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('동작 줄이기 환경에서 idle transform이 완전히 멈춘다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: PlantView(
              stage: 4,
              form: PlantGrowthForm.sparkling,
              preferRasterAssets: false,
            ),
          ),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(PlantView),
        matching: find.byType(AnimatedBuilder),
      ),
      findsNothing,
    );
  });
}

extension on PlantPainter {
  PlantPainter copyWithStage(int value) => PlantPainter(
        stage: value,
        expression: expression,
        form: form,
        secondaryForm: secondaryForm,
        speciesCode: speciesCode,
        growthVisual: growthVisual,
      );
}
