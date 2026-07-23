import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/garden/domain/garden_models.dart';
import 'package:mongroo/features/garden/presentation/garden_item_visual.dart';

void main() {
  double contrastRatio(Color foreground, Color background) {
    final lighter =
        foreground.computeLuminance() > background.computeLuminance()
            ? foreground.computeLuminance()
            : background.computeLuminance();
    final darker = foreground.computeLuminance() > background.computeLuminance()
        ? background.computeLuminance()
        : foreground.computeLuminance();
    return (lighter + 0.05) / (darker + 0.05);
  }

  ShopItem character({
    bool owned = true,
    String code = 'character_baby_pot',
    String name = '아기 화분',
    String assetKey = 'characters/baby-pot',
    String motionKey = 'baby_bounce',
  }) =>
      ShopItem.fromJson({
        'id': 41,
        'code': code,
        'type': 'main_character',
        'name': name,
        'description': '새로운 감정을 배우는 친구',
        'price_seeds': 80,
        'rarity': 2,
        'asset_manifest': {
          'asset_key': assetKey,
          'motion_key': motionKey,
          'personality': '쪽쪽이를 문 호기심쟁이 막내',
          'catchphrase': '뽀또! 새싹 하나 더 찾았어!',
        },
        'owned': owned,
      });

  testWidgets('캐릭터 이름과 성격, 대사를 접근성 정보로 제공한다', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.square(
            dimension: 160,
            child: GardenItemVisual(item: character()),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.bySemanticsLabel('아기 화분, 쪽쪽이를 문 호기심쟁이 막내'),
      findsOneWidget,
    );
    final node = tester.getSemantics(
      find.bySemanticsLabel('아기 화분, 쪽쪽이를 문 호기심쟁이 막내'),
    );
    expect(node.hint, '뽀또! 새싹 하나 더 찾았어!');
    semantics.dispose();
  });

  testWidgets('동작 줄이기 설정에서도 캐릭터가 안정적으로 렌더링된다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: SizedBox.square(
              dimension: 160,
              child: GardenItemVisual(item: character()),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(AnimatedGardenCharacter), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('그리드 캐릭터는 유휴 애니메이션 프레임을 계속 예약하지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.square(
            dimension: 160,
            child: GardenItemVisual(
              item: character(),
              animateIdle: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('카드 캐릭터 이미지는 표시 크기에 맞춰 축소 디코딩한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GardenItemVisual(
            item: character(),
            animateIdle: false,
            cacheWidth: 512,
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<ResizeImage>());
    expect((image.image as ResizeImage).width, 512);
  });

  testWidgets('잠긴 캐릭터는 잠금 상태를 읽어 준다', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.square(
            dimension: 160,
            child:
                GardenItemVisual(item: character(owned: false), locked: true),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.bySemanticsLabel('아기 화분, 아직 만나지 못한 캐릭터'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  test('희귀도 글자색은 밝고 어두운 surface에서 WCAG AA 대비를 만족한다', () {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      final scheme = theme.colorScheme;
      final palette = theme.extension<MongrooPalette>()!;
      for (var rarity = 1; rarity <= 4; rarity++) {
        for (final background in [
          scheme.surface,
          scheme.surfaceContainerHighest,
        ]) {
          expect(
            contrastRatio(
              gardenRarityColor(scheme, rarity, palette: palette),
              background,
            ),
            greaterThanOrEqualTo(4.5),
            reason: '${scheme.brightness} rarity $rarity on $background',
          );
        }
      }
    }
  });

  testWidgets('무심이와 모범생 화분은 탭에 서로 다른 방향으로 반응한다', (tester) async {
    final aloof = character(
      code: 'character_aloof_pot',
      name: '무심이 화분',
      assetKey: 'characters/aloof-pot',
      motionKey: 'aloof_glance',
    );
    final student = character(
      code: 'character_student_pot',
      name: '모범생 화분',
      assetKey: 'characters/student-pot',
      motionKey: 'student_adjust',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 180,
                  child: GardenItemVisual(item: aloof),
                ),
                SizedBox.square(
                  dimension: 180,
                  child: GardenItemVisual(item: student),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final aloofPose = find.byKey(
      const ValueKey('character-pose-character_aloof_pot'),
    );
    final studentPose = find.byKey(
      const ValueKey('character-pose-character_student_pot'),
    );
    Listener reactionListener(int index) => tester
        .widgetList<Listener>(
          find.descendant(
            of: find.byType(AnimatedGardenCharacter).at(index),
            matching: find.byType(Listener),
          ),
        )
        .firstWhere((listener) => listener.onPointerDown != null);
    final aloofBefore =
        tester.widget<Transform>(aloofPose).transform.getTranslation();
    reactionListener(0).onPointerDown!(const PointerDownEvent());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    final aloofAfter =
        tester.widget<Transform>(aloofPose).transform.getTranslation();
    expect(aloofAfter.x, lessThan(aloofBefore.x - 1));

    final studentBefore =
        tester.widget<Transform>(studentPose).transform.getTranslation();
    reactionListener(1).onPointerDown!(const PointerDownEvent());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    final studentAfter =
        tester.widget<Transform>(studentPose).transform.getTranslation();
    expect(studentAfter.y, lessThan(studentBefore.y - 1));
  });

  test('신규 방 테마 asset_key와 code fallback을 중앙 매핑에서 찾는다', () {
    final byKey = ShopItem.fromJson({
      'id': 90,
      'code': 'future_room_code',
      'type': 'room_theme',
      'name': '달빛 꿈방',
      'asset_manifest': {'asset_key': 'room/moonlit_dream'},
    });
    final byCode = ShopItem.fromJson({
      'id': 91,
      'code': 'room_cloud_cafe',
      'type': 'room_theme',
      'name': '구름 카페',
      'asset_manifest': const {},
    });
    final sunnyByKey = ShopItem.fromJson({
      'id': 92,
      'code': 'legacy_sunny_room',
      'type': 'room_theme',
      'name': '햇살 온실',
      'asset_manifest': {
        'asset_key': 'room/sunny_greenhouse',
        'preview_url': 'https://example.com/legacy-glossy.webp',
      },
    });
    final sunnyByCode = ShopItem.fromJson({
      'id': 93,
      'code': 'room_sunny',
      'type': 'room_theme',
      'name': '기본 온실',
      'asset_manifest': const {},
    });

    expect(gardenVisualAssetPath(byKey), 'assets/rooms/moonlit-dream.webp');
    expect(gardenVisualAssetPath(byCode), 'assets/rooms/cloud-cafe.webp');
    expect(
      gardenVisualAssetPath(sunnyByKey),
      'assets/rooms/sunny-greenhouse.webp',
    );
    expect(
      gardenVisualAssetPath(sunnyByCode),
      'assets/rooms/sunny-greenhouse.webp',
    );
  });

  test('압화 작업실과 여섯 소품의 번들 자산을 찾는다', () {
    const expected = {
      'deco/mushroom_reading_lamp':
          'assets/decorations/mushroom-reading-lamp.webp',
      'deco/strawberry_radio': 'assets/decorations/strawberry-radio.webp',
      'deco/frog_stool': 'assets/decorations/frog-stool.webp',
      'deco/pressed_flower_books':
          'assets/decorations/pressed-flower-books.webp',
      'deco/moon_seed_mobile': 'assets/decorations/moon-seed-mobile.webp',
      'deco/teacup_planter': 'assets/decorations/teacup-planter.webp',
      'room/pressed_flower_studio': 'assets/rooms/pressed-flower-studio.webp',
    };
    var id = 100;
    for (final entry in expected.entries) {
      final item = ShopItem.fromJson({
        'id': id++,
        'code': 'new_collection_$id',
        'type': entry.key.startsWith('room/') ? 'room_theme' : 'deco',
        'name': '압화 컬렉션',
        'asset_manifest': {'asset_key': entry.key},
      });
      expect(gardenVisualAssetPath(item), entry.value);
    }
  });

  test('여섯 마음결 기념품의 번들 자산을 감정별로 찾는다', () {
    const expected = {
      'deco/resonance_sunny': 'assets/decorations/mood-lamp-sunny.webp',
      'deco/resonance_rainy': 'assets/decorations/listening-chime-rainy.webp',
      'deco/resonance_ember': 'assets/decorations/courage-lantern-ember.webp',
      'deco/resonance_moonlit':
          'assets/decorations/preparation-lamp-moonlit.webp',
      'deco/resonance_sparkling': 'assets/decorations/prism-bud-sparkling.webp',
      'deco/resonance_mosaic':
          'assets/decorations/many-heart-mobile-mosaic.webp',
    };
    var id = 170;
    for (final entry in expected.entries) {
      final item = ShopItem.fromJson({
        'id': id++,
        'code': 'resonance_$id',
        'type': 'deco',
        'name': '마음결 기념품',
        'asset_manifest': {'asset_key': entry.key},
      });
      expect(gardenVisualAssetPath(item), entry.value);
    }
  });

  testWidgets('비캐릭터 소품은 잉크 색조 보정을 한 번만 적용한다', (tester) async {
    final decoration = ShopItem.fromJson({
      'id': 94,
      'code': 'deco_rug_cloud',
      'type': 'deco',
      'name': '구름 러그',
      'asset_manifest': {'asset_key': 'deco/rug_cloud'},
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox.square(
            dimension: 160,
            child: GardenItemVisual(item: decoration),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('garden-ink-tone-deco_rug_cloud')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('garden-ink-tone-deco_rug_cloud')),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
  });
}
