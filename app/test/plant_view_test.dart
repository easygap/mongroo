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
          home: Scaffold(body: PlantView(stage: stage)),
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
        home: Scaffold(body: PlantView(stage: 5)),
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

  testWidgets('동작 줄이기 환경에서 idle transform이 완전히 멈춘다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: PlantView(stage: 4, form: PlantGrowthForm.sparkling),
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
