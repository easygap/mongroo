import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tap_target.dart';
import 'package:mongroo/core/error/api_exception.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/gallery/data/gallery_repository.dart';
import 'package:mongroo/features/gallery/domain/harvested_plant.dart';
import 'package:mongroo/features/gallery/presentation/emotion_plant_view.dart';
import 'package:mongroo/features/gallery/presentation/gallery_screen.dart';
import 'package:mongroo/features/home/domain/plant.dart';
import 'package:mongroo/features/home/presentation/plant_view.dart';

class _FakeGalleryRepository extends GalleryRepository {
  _FakeGalleryRepository({
    List<HarvestedPlant>? plants,
    this.harvestedPages = const {},
  })  : plants = plants ?? [],
        super(Dio());

  List<HarvestedPlant> plants;
  final Map<String?, HarvestedPage> harvestedPages;
  final List<String?> harvestCursors = [];
  final List<(int, bool)> featureCalls = [];
  ApiException? featureError;

  @override
  Future<MuseumPage> getMuseum({
    MuseumMode mode = MuseumMode.recent,
    int limit = 10,
  }) async {
    final items = mode == MuseumMode.featured
        ? plants.where((plant) => plant.museumFeatured)
        : plants;
    return MuseumPage(
      items: items.take(limit).toList(),
      mode: mode,
      limit: limit,
      maxFeatured: 10,
    );
  }

  @override
  Future<HarvestedPage> getHarvested({String? cursor}) async {
    harvestCursors.add(cursor);
    if (harvestedPages.isEmpty) {
      return HarvestedPage(items: plants, nextCursor: null);
    }
    return harvestedPages[cursor] ??
        const HarvestedPage(items: [], nextCursor: null);
  }

  @override
  Future<MuseumFeatureResult> setFeatured({
    required int plantId,
    required bool isFeatured,
  }) async {
    featureCalls.add((plantId, isFeatured));
    final error = featureError;
    if (error != null) throw error;
    final index = plants.indexWhere((plant) => plant.id == plantId);
    plants = [...plants]..[index] =
        plants[index].copyWith(museumFeatured: isFeatured);
    return MuseumFeatureResult(
      plant: plants[index],
      featuredCount: plants.where((plant) => plant.museumFeatured).length,
      maxFeatured: 10,
    );
  }
}

const _sunnyPlant = HarvestedPlant(
  id: 14,
  name: '해님이',
  species: PlantSpecies(id: 1, code: 'sunflower', name: '해바라기'),
  exp: 1200,
  plantedAt: null,
  harvestedAt: null,
  finalForm: PlantFinalForm.sunny,
  emotionProfile: PlantEmotionProfile(
    total: 5,
    counts: {
      'joy': 4,
      'sadness': 1,
    },
    ratios: {
      'joy': .8,
      'sadness': .2,
    },
  ),
);

const _rainyPlant = HarvestedPlant(
  id: 15,
  name: '비구름이',
  species: PlantSpecies(id: 2, code: 'cactus', name: '가시니'),
  exp: 1300,
  plantedAt: null,
  harvestedAt: null,
  finalForm: PlantFinalForm.rainy,
);

const _branchedPlant = HarvestedPlant(
  id: 16,
  name: '빗별이',
  species: PlantSpecies(id: 3, code: 'basic_sprout', name: '마음새싹'),
  exp: 1400,
  plantedAt: null,
  harvestedAt: null,
  finalForm: PlantFinalForm.rainy,
  secondaryForm: PlantGrowthForm.sunny,
  growthTraits: PlantGrowthTraits(
    title: '햇살 한 줌 품은 빗물결',
    traits: ['오래 귀 기울이는 결', '빛을 조심스럽게 나누는 결'],
    temperament: PlantTemperament(
      revealed: true,
      fictionalCharacterAxes: true,
      summary: '섬세한 반응 · 천천히 고르는 말',
    ),
  ),
  conversationProfile: PlantConversationProfile(
    cadence: '숨을 고르고 천천히 말해요',
    focus: '지나친 마음을 오래 들어요',
    questionStyle: '답을 재촉하지 않고 하나씩 물어요',
    secondaryModifier: '가끔 따뜻한 농담을 건네요',
  ),
);

void main() {
  Future<void> pumpMuseum(
    WidgetTester tester,
    _FakeGalleryRepository repository, {
    Size size = const Size(390, 844),
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          galleryRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(
              disableAnimations: true,
              textScaler: textScaler,
            ),
            child: const GalleryScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('최근 식물을 최종 형태로 전시하고 상세 감정 분포를 연다', (tester) async {
    await pumpMuseum(tester, _FakeGalleryRepository(plants: [_sunnyPlant]));
    expectTapTargets(tester, screen: '박물관');
    final semantics = tester.ensureSemantics();

    expect(find.text('마음 식물 박물관'), findsOneWidget);
    expect(find.text('최근 1/10'), findsOneWidget);
    expect(find.byKey(const ValueKey('museum-room-background')), findsNothing);
    expect(
      find.byKey(const ValueKey('museum-mobile-card-14')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        '해님이, 해바라기, 햇살꽃, 수확 날짜 기록 없음, 상세 보기',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      ),
      findsNothing,
    );

    await tester.scrollUntilVisible(
      find.text('해님이'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('해님이'), findsOneWidget);
    expect(find.text('햇살꽃 · 햇살결 · 해바라기'), findsOneWidget);
    expect(find.byType(EmotionPlantView), findsWidgets);
    expect(
      tester.widgetList<EmotionPlantView>(find.byType(EmotionPlantView)).where(
          (view) =>
              view.speciesCode == 'sunflower' && view.speciesName == '해바라기'),
      isNotEmpty,
    );

    await tester.tap(find.text('해님이'));
    await tester.pumpAndSettle();

    expect(find.text(PlantFinalForm.sunny.description), findsWidgets);
    expect(find.text('감정 기록 구성'), findsOneWidget);
    expect(find.text('4 · 80%'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('상세 시트가 다섯 성장 단계와 주결·보조결·기질·말걸음을 공개한다', (tester) async {
    await pumpMuseum(tester, _FakeGalleryRepository(plants: [_branchedPlant]));

    await tester.tap(find.text('빗별이'));
    await tester.pumpAndSettle();

    expect(find.text('이 식물이 자란 다섯 장면'), findsOneWidget);
    expect(find.byType(PlantStagePreview), findsNWidgets(5));
    final previews = tester
        .widgetList<PlantStagePreview>(find.byType(PlantStagePreview))
        .toList();
    final stage3 = previews.singleWhere((preview) => preview.stage == 3);
    final stage4 = previews.singleWhere((preview) => preview.stage == 4);
    final stage5 = previews.singleWhere((preview) => preview.stage == 5);
    expect(stage3.form, PlantGrowthForm.rainy);
    expect(stage3.secondaryForm, isNull);
    expect(stage4.form, PlantGrowthForm.rainy);
    expect(stage4.secondaryForm, PlantGrowthForm.sunny);
    expect(stage5.secondaryForm, PlantGrowthForm.sunny);
    expect(find.text('주결'), findsOneWidget);
    expect(find.text('보조결'), findsOneWidget);
    expect(find.text('식물 캐릭터 기질'), findsOneWidget);
    expect(find.text('말걸음'), findsOneWidget);
    expect(find.textContaining('섬세한 반응'), findsOneWidget);
    expect(find.textContaining('숨을 고르고 천천히'), findsOneWidget);
    expect(
      find.text('식물 캐릭터의 연출 설정이며, 사용자 성격 진단·성장 속도·보상 차등과 관계없어요.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('새 성장 필드가 없는 이전 식물도 기본 계보와 설명을 안전하게 연다', (tester) async {
    await pumpMuseum(tester, _FakeGalleryRepository(plants: [_rainyPlant]));

    await tester.tap(find.byKey(const ValueKey('museum-mobile-card-15')));
    await tester.pumpAndSettle();

    final previews = tester
        .widgetList<PlantStagePreview>(find.byType(PlantStagePreview))
        .toList();
    expect(previews, hasLength(5));
    expect(
        previews.where((preview) => preview.stage >= 4),
        everyElement(predicate<PlantStagePreview>(
          (preview) => preview.secondaryForm == null,
        )));
    expect(find.textContaining('별도 보조결 없이'), findsOneWidget);
    expect(find.textContaining('대표 대사에 남은 말투'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('책갈피로 대표 식물을 고른 뒤 대표 전시에서 다시 보여 준다', (tester) async {
    final repository = _FakeGalleryRepository(plants: [_sunnyPlant]);
    await pumpMuseum(tester, repository);

    await tester.ensureVisible(find.byIcon(Icons.bookmark_border_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
    await tester.pumpAndSettle();

    expect(repository.featureCalls, [(14, true)]);
    expect(find.text('대표 전시에 놓았어요.'), findsOneWidget);

    await tester.ensureVisible(find.text('대표 전시'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('대표 전시'));
    await tester.pumpAndSettle();

    expect(find.text('대표 1/10'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('해님이'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('해님이'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_rounded), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('대표 전시가 비면 최근 식물로 돌아가는 안내를 제공한다', (tester) async {
    await pumpMuseum(tester, _FakeGalleryRepository(plants: [_sunnyPlant]));

    await tester.tap(find.text('대표 전시'));
    await tester.pumpAndSettle();

    expect(find.text('대표 전시장이 비어 있어요'), findsOneWidget);
    expect(find.text('최근 식물 보러 가기'), findsOneWidget);

    await tester.ensureVisible(find.text('최근 식물 보러 가기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('최근 식물 보러 가기'));
    await tester.pumpAndSettle();
    expect(find.text('해님이'), findsOneWidget);
  });

  testWidgets('대표 전시 10그루 제한 오류는 선택을 되돌리고 이유를 알려 준다', (tester) async {
    final repository = _FakeGalleryRepository(plants: [_sunnyPlant])
      ..featureError = const ApiException(
        code: 'MUSEUM_FEATURED_LIMIT',
        message: '대표 전시가 가득 찼어요.',
        statusCode: 409,
      );
    await pumpMuseum(tester, repository);

    await tester.ensureVisible(find.byIcon(Icons.bookmark_border_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
    expect(find.text('대표 전시는 최대 10그루까지 선택할 수 있어요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('작은 화면과 큰 글자에서도 전시 카드가 넘치지 않는다', (tester) async {
    await pumpMuseum(
      tester,
      _FakeGalleryRepository(plants: [_sunnyPlant]),
      size: const Size(320, 640),
      textScaler: const TextScaler.linear(2),
    );

    await tester.scrollUntilVisible(
      find.text('해님이'),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('해님이'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('museum-mobile-card-14')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('museum-room-background')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('museum-mobile-card-14')));
    await tester.pumpAndSettle();
    expect(find.text('이 식물이 자란 다섯 장면'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('넓은 화면에서는 밤 박물관 전경을 보여 준다', (tester) async {
    await pumpMuseum(
      tester,
      _FakeGalleryRepository(plants: [_sunnyPlant]),
      size: const Size(1024, 900),
    );
    final semantics = tester.ensureSemantics();

    expect(
      find.byKey(const ValueKey('museum-mobile-card-14')),
      findsNothing,
    );
    final backgroundFinder =
        find.byKey(const ValueKey('museum-room-background'));
    expect(backgroundFinder, findsOneWidget);
    final background = tester.widget<Image>(backgroundFinder);
    final provider = background.image;
    expect(provider, isA<ResizeImage>());
    expect(
      ((provider as ResizeImage).imageProvider as AssetImage).assetName,
      'assets/rooms/night-museum-ink.webp',
    );
    final roomPlant = find.byKey(const ValueKey('museum-room-plant-14'));
    expect(roomPlant, findsOneWidget);
    expect(
      find.bySemanticsLabel('해님이, 햇살꽃, 실제 전시 식물'),
      findsOneWidget,
    );
    await tester.tap(roomPlant);
    await tester.pumpAndSettle();
    expect(find.text('이 식물이 자란 다섯 장면'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('전체 식물은 다음 수확 목록을 불러와 이어 붙인다', (tester) async {
    final repository = _FakeGalleryRepository(
      harvestedPages: const {
        null: HarvestedPage(
          items: [_sunnyPlant],
          nextCursor: 'page-2',
        ),
        'page-2': HarvestedPage(
          items: [_rainyPlant],
          nextCursor: null,
        ),
      },
    );
    await pumpMuseum(tester, repository);

    await tester.tap(find.text('전체 식물'));
    await tester.pumpAndSettle();

    expect(find.text('현재 1그루'), findsOneWidget);
    expect(find.text('해님이'), findsOneWidget);
    final loadMore = find.byKey(const ValueKey('museum-load-more'));
    await tester.scrollUntilVisible(
      loadMore,
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(loadMore);
    await tester.pumpAndSettle();

    expect(repository.harvestCursors, [null, 'page-2']);
    expect(find.text('현재 2그루'), findsOneWidget);
    expect(find.text('비구름이'), findsOneWidget);
    expect(loadMore, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
