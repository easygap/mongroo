import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/features/home/domain/plant.dart';
import 'package:mongroo/features/home/domain/plant_story.dart';
import 'package:mongroo/features/home/presentation/plant_story_card.dart';
import 'package:mongroo/features/home/presentation/plant_view.dart';

ActivePlant _plant({
  required int stage,
  PlantGrowthForm? form,
  PlantGrowthForm? secondaryForm,
  PlantGrowthTraits growthTraits = const PlantGrowthTraits(),
  String name = '모리',
}) =>
    ActivePlant(
      id: 1,
      name: name,
      species: const PlantSpecies(
        id: 1,
        code: 'basic_sprout',
        name: '새싹몬',
        rarity: 1,
        unlockPrice: 0,
        assetManifest: {},
        isUnlocked: true,
      ),
      exp: 120,
      stage: stage,
      stageThresholds: const [0, 20, 100, 250, 450],
      nextStageExp: stage >= 5 ? null : 250,
      harvestable: stage >= 5,
      plantedAt: DateTime(2026, 7, 1),
      growthForm: form,
      secondaryForm: secondaryForm,
      growthTraits: growthTraits,
      emotionProfile: const ActivePlantEmotionProfile(
        total: 8,
        ratios: {
          'joy': .5,
          'anger': .3,
          'anxiety': .2,
        },
      ),
    );

const _nuancedTraits = PlantGrowthTraits(
  stage: 4,
  revealState: 'secondary_revealed',
  title: '별빛 품은 빗물결',
  traits: ['물방울을 오래 바라보는 결', '뜻밖의 반짝임을 좇는 결'],
  temperament: PlantTemperament(
    revealed: true,
    fictionalCharacterAxes: true,
    summary: '잔잔한 움직임 · 호기심 많은 시선',
  ),
);

void main() {
  test('성장 단계에 따라 다섯 장 이야기가 순서대로 열린다', () {
    final plant = _plant(stage: 3, form: PlantGrowthForm.sunny);

    expect(plant.storyChapters, hasLength(5));
    expect(
        plant.storyChapters.where((chapter) => chapter.unlocked), hasLength(3));
    expect(plant.currentStoryChapter.title, '햇빛 자리의 발견');
    expect(plant.nextStoryChapter?.stage, 4);
  });

  test('같은 단계라도 감정 분기에 따라 에피소드가 달라진다', () {
    final sunny = _plant(stage: 4, form: PlantGrowthForm.sunny);
    final rainy = _plant(stage: 4, form: PlantGrowthForm.rainy);

    expect(sunny.currentStoryChapter.title,
        isNot(rainy.currentStoryChapter.title));
    expect(sunny.currentStoryChapter.story,
        isNot(rainy.currentStoryChapter.story));
  });

  test('만개하면 마지막 장이 열리고 다음 장은 없다', () {
    final plant = _plant(stage: 5, form: PlantGrowthForm.mosaic);

    expect(plant.currentStoryChapter.title, contains('초대장'));
    expect(plant.nextStoryChapter, isNull);
    expect(plant.storyChapters.every((chapter) => chapter.unlocked), isTrue);
  });

  test('4단계 이야기는 보조결과 공개된 식물 기질을 함께 담는다', () {
    final plant = _plant(
      stage: 4,
      form: PlantGrowthForm.rainy,
      secondaryForm: PlantGrowthForm.sparkling,
      growthTraits: _nuancedTraits,
    );

    expect(plant.currentStoryChapter.title, contains('놀람빛'));
    expect(plant.currentStoryChapter.story, contains('뜻밖의 반짝임을 좇는 결'));
    expect(plant.currentStoryChapter.story, contains('호기심 많은 시선'));
  });

  test('5단계 이야기는 완성된 보조결·기질·캐릭터 이름을 보존한다', () {
    final plant = _plant(
      stage: 5,
      form: PlantGrowthForm.rainy,
      secondaryForm: PlantGrowthForm.sparkling,
      growthTraits: _nuancedTraits,
    );

    expect(plant.currentStoryChapter.title, contains('별빛 품은 빗물결'));
    expect(plant.currentStoryChapter.story, contains('놀람 보조결'));
    expect(plant.currentStoryChapter.story, contains('대화 습관으로 완성'));
  });

  testWidgets('카드에서 씨앗부터 만개까지 다섯 모습을 한눈에 보여 준다', (tester) async {
    final plant = _plant(stage: 3, form: PlantGrowthForm.ember);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlantStoryCard(plant: plant, onMuseum: () {}),
        ),
      ),
    );

    expect(find.byType(PlantStagePreview), findsNWidgets(5));
    final stages = tester
        .widgetList<PlantStagePreview>(find.byType(PlantStagePreview))
        .map((preview) => preview.stage)
        .toList();
    expect(stages, [1, 2, 3, 4, 5]);
    expect(
      tester
          .widgetList<PlantStagePreview>(find.byType(PlantStagePreview))
          .where((preview) => preview.stage >= 3)
          .every((preview) => preview.form == PlantGrowthForm.ember),
      isTrue,
    );
  });

  testWidgets('320px과 200% 글자에서도 긴 이름과 성장 기질이 넘치지 않는다', (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.reset);
    final plant = _plant(
      stage: 4,
      form: PlantGrowthForm.rainy,
      secondaryForm: PlantGrowthForm.sparkling,
      name: '비 오는 날의 아주 긴 해바라기 이름',
      growthTraits: const PlantGrowthTraits(
        stage: 4,
        revealState: 'secondary_revealed',
        title: '별빛 품은 빗물결',
        traits: [
          '작은 소리도 끝까지 기다렸다가 차분하게 대답하는 아주 긴 캐릭터 특성',
          '뜻밖의 반짝임을 발견하면 잎 끝을 빠르게 흔드는 호기심 많은 습관',
        ],
        temperament: PlantTemperament(
          revealed: true,
          fictionalCharacterAxes: true,
          summary: '잔잔한 움직임 · 호기심 많은 시선',
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: PlantStoryCard(plant: plant, onMuseum: () {}),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text(plant.currentStoryChapter.title));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(Scrollable).last,
      const Offset(0, -620),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp('주결 빗방울꽃, 보조결 반짝꽃')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('성장 이야기에서 상위 마음빛 3개와 동등한 성장 규칙을 설명한다', (tester) async {
    final plant = _plant(stage: 3, form: PlantGrowthForm.sunny);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlantStoryCard(plant: plant, onMuseum: () {}),
        ),
      ),
    );

    await tester.tap(find.text('햇빛 자리의 발견'));
    await tester.pumpAndSettle();

    expect(find.text('마음빛 조합'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('30%'), findsOneWidget);
    expect(find.text('20%'), findsOneWidget);
    expect(
      find.textContaining('어떤 마음도 실패가 아니에요'),
      findsOneWidget,
    );
    expect(
      find.textContaining('성장 속도·보상에는 영향을 주지 않아요'),
      findsOneWidget,
    );
  });

  testWidgets('2단계에서는 잠긴 성장 분기 실루엣을 미리 확정하지 않는다', (tester) async {
    final plant = _plant(stage: 2);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlantStoryCard(plant: plant, onMuseum: () {}),
        ),
      ),
    );

    final previews = tester
        .widgetList<PlantStagePreview>(find.byType(PlantStagePreview))
        .where((preview) => preview.stage >= 3);
    expect(previews.every((preview) => preview.form == null), isTrue);

    await tester.tap(find.text(plant.currentStoryChapter.title));
    await tester.pumpAndSettle();

    expect(find.text('마음빛 조합'), findsNothing);
    expect(find.text('50%'), findsNothing);
    expect(find.textContaining('새싹에 첫 마음빛이'), findsOneWidget);
  });

  testWidgets('씨앗 단계에서는 마음빛 비율과 새싹 외형을 미리 공개하지 않는다', (tester) async {
    final plant = _plant(stage: 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlantStoryCard(plant: plant, onMuseum: () {}),
        ),
      ),
    );

    expect(
      tester
          .widgetList<PlantStagePreview>(find.byType(PlantStagePreview))
          .where((preview) => preview.stage == 2)
          .every((preview) => preview.form == null),
      isTrue,
    );

    await tester.tap(find.text(plant.currentStoryChapter.title));
    await tester.pumpAndSettle();

    expect(find.text('마음빛 조합'), findsNothing);
    expect(find.text('50%'), findsNothing);
    expect(find.textContaining('씨앗 안에서는 아직 마음빛이'), findsOneWidget);
  });
}
