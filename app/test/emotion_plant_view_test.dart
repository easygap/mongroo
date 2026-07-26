import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/features/gallery/domain/harvested_plant.dart';
import 'package:mongroo/features/gallery/presentation/emotion_plant_view.dart';

void main() {
  testWidgets('모든 최종 형태가 작은 크기에서도 예외 없이 그려진다', (tester) async {
    for (final speciesCode in ['basic_sprout', 'cactus', 'sunflower']) {
      for (final form in PlantFinalForm.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: EmotionPlantView(
                  form: form,
                  speciesCode: speciesCode,
                  size: 48,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: '${form.code} $speciesCode',
        );

        if (speciesCode == 'basic_sprout') {
          expect(
            find.byKey(
              ValueKey(
                'assets/plants/basic-sprout-25d-full-bloom-${form.code}.webp',
              ),
            ),
            findsOneWidget,
          );
        } else {
          final paint = tester.widget<CustomPaint>(
            find.descendant(
              of: find.byType(EmotionPlantView),
              matching: find.byType(CustomPaint),
            ),
          );
          expect(paint.painter, isA<EmotionPlantPainter>());
          expect((paint.painter! as EmotionPlantPainter).form, form);
          expect(
              (paint.painter! as EmotionPlantPainter).speciesCode, speciesCode);
          expect(paint.isComplex, isTrue);
          expect(paint.willChange, isFalse);
        }
      }
    }
  });

  testWidgets('품종과 최종 형태, 감정 이름을 접근성 라벨로 제공한다', (tester) async {
    final semantics = tester.ensureSemantics();
    for (final form in PlantFinalForm.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: EmotionPlantView(
            form: form,
            speciesCode: 'cactus',
            speciesName: '가시니',
          ),
        ),
      );
      expect(
        find.bySemanticsLabel(
          '가시니 품종, ${form.label}, ${form.emotionLabel}의 기록으로 자란 식물',
        ),
        findsOneWidget,
      );
    }
    semantics.dispose();
  });

  test('형태나 품종이 바뀔 때만 다시 그린다', () {
    const sunny = EmotionPlantPainter(PlantFinalForm.sunny);
    const sameSunny = EmotionPlantPainter(PlantFinalForm.sunny);
    const rainy = EmotionPlantPainter(PlantFinalForm.rainy);
    const cactus = EmotionPlantPainter(
      PlantFinalForm.sunny,
      speciesCode: 'cactus',
    );

    expect(sunny.shouldRepaint(sameSunny), isFalse);
    expect(rainy.shouldRepaint(sunny), isTrue);
    expect(cactus.shouldRepaint(sunny), isTrue);
  });
}
