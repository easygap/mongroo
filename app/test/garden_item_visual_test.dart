import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/garden/domain/garden_models.dart';
import 'package:mongroo/features/garden/presentation/garden_item_visual.dart';
import 'package:mongroo/features/home/presentation/plant_view.dart';

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

  ShopItem growthSeed({
    bool owned = true,
    String code = 'species_basic_sprout',
    String name = '기본 새싹',
  }) =>
      ShopItem.fromJson({
        'id': 41,
        'code': code,
        'type': 'species_unlock',
        'name': name,
        'description': '새로운 감정을 배우는 친구',
        'price_seeds': 80,
        'rarity': 2,
        'asset_manifest': {
          'asset_key': 'species/basic_sprout',
          'species_code': 'basic_sprout',
        },
        'owned': owned,
      });

  ShopItem companion({
    required String code,
    required String name,
    required String assetKey,
    required String motionKey,
  }) =>
      ShopItem.fromJson({
        'id': code.hashCode,
        'code': code,
        'type': 'companion',
        'name': name,
        'description': '정원의 작은 동행 소품',
        'price_seeds': 80,
        'rarity': 2,
        'asset_manifest': {
          'asset_key': assetKey,
          'motion_key': motionKey,
          'personality': '작고 다정한 정원 친구',
          'catchphrase': '같이 정원을 둘러볼까?',
        },
        'owned': true,
      });

  ShopItem mainCharacter({
    required String slug,
    required String motionKey,
  }) =>
      ShopItem.fromJson({
        'id': slug.hashCode,
        'code': 'character_${slug.replaceAll('-', '_')}',
        'type': 'main_character',
        'name': slug,
        'description': '감정일기로 자라는 캐릭터',
        'price_seeds': 240,
        'rarity': 3,
        'asset_manifest': {
          'asset_key': 'characters/$slug',
          'motion_key': motionKey,
          'personality': '고유한 움직임을 가진 성장 캐릭터',
          'catchphrase': '오늘 마음은 어땠어?',
        },
        'owned': true,
      });

  ShopItem humanoidLineage() => ShopItem.fromJson({
        'id': 42,
        'code': 'character_gumiho_pot',
        'type': 'main_character',
        'name': '여우비',
        'description': '씨앗에서 자라는 구미호 성장 계보',
        'price_seeds': 240,
        'rarity': 4,
        'asset_manifest': {
          'asset_key': 'characters/gumiho-pot',
          'species_code': 'basic_sprout',
        },
        'owned': true,
      });

  testWidgets('성장 씨앗은 같은 캐릭터의 성장 가능성을 접근성 정보로 제공한다', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.square(
            dimension: 160,
            child: GardenItemVisual(item: growthSeed()),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.bySemanticsLabel('기본 새싹, 씨앗부터 만개까지 자라는 성장 캐릭터'),
      findsOneWidget,
    );
    expect(find.byType(PlantStagePreview), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('동작 줄이기 설정에서도 성장 씨앗이 안정적으로 렌더링된다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: SizedBox.square(
              dimension: 160,
              child: GardenItemVisual(item: growthSeed()),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(PlantStagePreview), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('사람형 계보는 씨앗과 완전체를 한 성장선으로 보여 준다', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 300,
            child: GardenItemVisual(
              item: humanoidLineage(),
              animateIdle: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(PlantStagePreview), findsOneWidget);
    expect(find.byType(AnimatedGardenCharacter), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    expect(
      find.bySemanticsLabel(
        '여우비, 씨앗에서 사람형 완전체까지 자라는 성장 캐릭터',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('그리드 성장 씨앗은 유휴 애니메이션 프레임을 예약하지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.square(
            dimension: 160,
            child: GardenItemVisual(
              item: growthSeed(),
              animateIdle: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('카드 성장 씨앗 이미지는 표시 크기에 맞춰 축소 디코딩한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GardenItemVisual(
            item: growthSeed(),
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

  testWidgets('잠긴 성장 씨앗은 잠금 상태를 읽어 준다', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.square(
            dimension: 160,
            child:
                GardenItemVisual(item: growthSeed(owned: false), locked: true),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.bySemanticsLabel('기본 새싹, 아직 해금하지 않은 성장 씨앗'),
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

  testWidgets('동행 소품은 각 motion key에 맞춰 탭 반응을 보인다', (tester) async {
    final dewdrop = companion(
      code: 'companion_dewdrop',
      name: '이슬이',
      assetKey: 'companion/dewdrop',
      motionKey: 'aloof_glance',
    );
    final star = companion(
      code: 'companion_star',
      name: '별콩이',
      assetKey: 'companion/star',
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
                  child: GardenItemVisual(item: dewdrop),
                ),
                SizedBox.square(
                  dimension: 180,
                  child: GardenItemVisual(item: star),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final dewdropPose = find.byKey(
      const ValueKey('character-pose-companion_dewdrop'),
    );
    final starPose = find.byKey(
      const ValueKey('character-pose-companion_star'),
    );
    Listener reactionListener(int index) => tester
        .widgetList<Listener>(
          find.descendant(
            of: find.byType(AnimatedGardenCharacter).at(index),
            matching: find.byType(Listener),
          ),
        )
        .firstWhere((listener) => listener.onPointerDown != null);
    final dewdropBefore =
        tester.widget<Transform>(dewdropPose).transform.getTranslation();
    reactionListener(0).onPointerDown!(const PointerDownEvent());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    final dewdropAfter =
        tester.widget<Transform>(dewdropPose).transform.getTranslation();
    expect(dewdropAfter.x, lessThan(dewdropBefore.x - 1));

    final starBefore =
        tester.widget<Transform>(starPose).transform.getTranslation();
    reactionListener(1).onPointerDown!(const PointerDownEvent());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    final starAfter =
        tester.widget<Transform>(starPose).transform.getTranslation();
    expect(starAfter.y, lessThan(starBefore.y - 1));
  });

  testWidgets('10종 성장 캐릭터는 모두 서로 다른 탭 모션을 지원한다', (tester) async {
    const characters = {
      'baby-pot': 'baby_bounce',
      'handsome-pot': 'prince_flourish',
      'pretty-pot': 'pretty_sparkle',
      'tsundere-pot': 'tsundere_turn_away',
      'zombie-pot': 'zombie_sway',
      'gumiho-pot': 'gumiho_float',
      'ninja-pot': 'ninja_snap',
      'magical-pot': 'magical_hover',
      'aloof-pot': 'aloof_glance',
      'student-pot': 'student_adjust',
    };

    for (final entry in characters.entries) {
      final item = mainCharacter(
        slug: entry.key,
        motionKey: entry.value,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.square(
              dimension: 180,
              child: AnimatedGardenCharacter(
                item: item,
                animateIdle: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final poseFinder = find.byKey(
        ValueKey('character-pose-${item.code}'),
      );
      final before =
          tester.widget<Transform>(poseFinder).transform.getTranslation();
      final listener = tester
          .widgetList<Listener>(
            find.descendant(
              of: find.byType(AnimatedGardenCharacter),
              matching: find.byType(Listener),
            ),
          )
          .firstWhere((candidate) => candidate.onPointerDown != null);
      listener.onPointerDown!(const PointerDownEvent());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));
      final after =
          tester.widget<Transform>(poseFinder).transform.getTranslation();

      expect(
        (after - before).length,
        greaterThan(1),
        reason: '${entry.key} (${entry.value}) 탭 모션이 정지해 있습니다.',
      );
    }
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
