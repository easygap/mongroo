import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tap_target.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/garden/domain/garden_models.dart';
import 'package:mongroo/features/garden/presentation/collection_tab.dart';

void main() {
  Future<void> pumpCollection(
    WidgetTester tester,
    GardenCollection collection, {
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(
            disableAnimations: true,
            textScaler: textScaler,
          ),
          child: Scaffold(body: CollectionCatalogView(data: collection)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('성장 씨앗은 성장 캐릭터 도감에만 한 번 나타난다', (tester) async {
    final collection = GardenCollection.fromJson({
      'seed_balance': 20,
      'items': [
        {
          'id': 71,
          'item': {
            'id': 33,
            'code': 'species_cactus',
            'type': 'species_unlock',
            'name': '선인장',
            'price_seeds': 90,
            'rarity': 2,
            'asset_manifest': {
              'asset_key': 'species/cactus',
              'species_code': 'cactus',
            },
          },
        },
      ],
      'species': [
        {
          'id': 1,
          'code': 'cactus',
          'name': '선인장',
          'rarity': 2,
          'unlock_price': 90,
          'is_unlocked': true,
        },
      ],
      'catalog_items': [
        {
          'id': 33,
          'code': 'species_cactus',
          'type': 'species_unlock',
          'name': '선인장',
          'price_seeds': 90,
          'rarity': 2,
          'asset_manifest': {
            'asset_key': 'species/cactus',
            'species_code': 'cactus',
          },
          'owned': true,
        },
      ],
    });

    await pumpCollection(
      tester,
      collection,
      textScaler: const TextScaler.linear(2),
    );
    expectTapTargets(tester, screen: '도감');

    expect(find.text('선인장'), findsOneWidget);
    expect(find.text('상점에서 첫 꾸미기 아이템을 만나 보세요.'), findsOneWidget);
    expect(find.textContaining('성장 캐릭터 1/1'), findsOneWidget);
    expect(find.textContaining('전체 수집 1/1'), findsOneWidget);
    expect(find.text('성장 캐릭터 도감'), findsOneWidget);
  });

  testWidgets('사람형 완전체 원화도 같은 성장 캐릭터 도감에 노출한다', (tester) async {
    final collection = GardenCollection.fromJson({
      'seed_balance': 20,
      'items': const [],
      'species': const [],
      'catalog_items': [
        {
          'id': 41,
          'code': 'character_gumiho_pot',
          'type': 'main_character',
          'name': '여우비',
          'description': '비밀 이야기를 좋아하는 장난꾸러기',
          'price_seeds': 240,
          'rarity': 4,
          'asset_manifest': {
            'asset_key': 'characters/gumiho-pot',
            'personality': '부채 뒤로 장난을 꾸미는 구미호',
            'catchphrase': '후후, 꼬리 아홉 개를 다 찾았어?',
            'story_role': '달빛 온실의 장난꾼',
            'lore_hook': '달빛 신사의 봉인이 풀린 밤, 아홉 꼬리불을 훔쳐 달아난 여우 화분.',
            'collection_quote': '후후, 마지막 꼬리불은 어디 있게?',
          },
          'owned': true,
        },
        {
          'id': 42,
          'code': 'character_ninja_pot',
          'type': 'main_character',
          'name': '그림싹',
          'description': '그림자 임무의 동료',
          'price_seeds': 180,
          'rarity': 3,
          'asset_manifest': {
            'asset_key': 'characters/ninja-pot',
            'story_role': '그림자 임무의 동료',
            'lore_hook': '이 문장은 잠긴 상태에서 보이면 안 된다.',
            'collection_quote': '연막 씨앗 장전. 셋에 이동한다.',
          },
          'owned': false,
        },
      ],
    });

    await pumpCollection(
      tester,
      collection,
      textScaler: const TextScaler.linear(2),
    );

    expect(
      find.text('달빛 신사의 봉인이 풀린 밤, 아홉 꼬리불을 훔쳐 달아난 여우 화분.'),
      findsNothing,
    );
    expect(find.text('이 문장은 잠긴 상태에서 보이면 안 된다.'), findsNothing);
    expect(find.text('여우비'), findsOneWidget);
    expect(find.text('그림싹'), findsNothing);
    expect(find.text('씨앗부터 여섯 감정의 성인 모습까지 성장'), findsOneWidget);
    expect(find.text('아직 비밀이에요'), findsOneWidget);
    expect(find.text('성장 캐릭터 도감'), findsOneWidget);
    expect(find.textContaining('성장 캐릭터 1/2'), findsOneWidget);

    await tester.ensureVisible(find.text('여우비'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('여우비'));
    await tester.pumpAndSettle();

    expect(find.text('여우비 감정별 성장 도감'), findsOneWidget);
    expect(find.text('씨앗 · 새싹 · 유아기 · 성장기 · 성인'), findsOneWidget);
    expect(find.textContaining('기쁨'), findsOneWidget);
    expect(find.textContaining('슬픔'), findsOneWidget);
  });

  testWidgets('같은 캐릭터를 품종·계보로 두 번 세우지 않는다', (tester) async {
    // `species`와 상점 캐릭터 항목은 같은 캐릭터를 둘 다 담는다. 그대로
    // 이어 붙이면 도감에 뽀또가 두 번 서고 수집 숫자도 두 번 세인다.
    // 품종 카드는 눌러도 아무 일이 없어서, 같아 보이는 둘 중 하나만 열렸다.
    final collection = GardenCollection.fromJson({
      'seed_balance': 0,
      'items': const [],
      'catalog_items': [
        {
          'id': 41,
          'code': 'character_baby_pot',
          'type': 'main_character',
          'name': '아기 화분 뽀또',
          'description': '첫 캐릭터',
          'price_seeds': 0,
          'rarity': 1,
          'asset_manifest': {
            'asset_key': 'characters/baby-pot',
            'species_code': 'baby-pot',
          },
          'owned': true,
        },
      ],
      'species': [
        {
          'id': 1,
          'code': 'baby-pot',
          'name': '아기 화분 뽀또',
          'rarity': 1,
          'unlock_price': 0,
          'is_unlocked': true,
        },
        {
          'id': 2,
          'code': 'basic_sprout',
          'name': '새싹몬',
          'rarity': 1,
          'unlock_price': 0,
          'is_unlocked': true,
        },
      ],
    });

    expect(
      collection.standaloneSpecies.map((entry) => entry.code),
      ['basic_sprout'],
    );

    await pumpCollection(tester, collection);

    expect(find.text('아기 화분 뽀또'), findsOneWidget);
    expect(find.text('새싹몬'), findsOneWidget);
    expect(find.textContaining('성장 캐릭터 2/2'), findsOneWidget);

    // 짝이 없는 품종 카드도 계보 카드와 같은 시트를 연다.
    await tester.tap(find.text('새싹몬'));
    await tester.pumpAndSettle();
    expect(find.text('새싹몬 감정별 성장 도감'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('잠긴 방 테마도 이름과 구체적인 획득 힌트를 보여 준다', (tester) async {
    final semantics = tester.ensureSemantics();
    final collection = GardenCollection.fromJson({
      'seed_balance': 20,
      'items': const [],
      'species': const [],
      'catalog_items': [
        {
          'id': 70,
          'code': 'room_fox_shrine',
          'type': 'room_theme',
          'name': '별여우 신사',
          'description': '별빛이 머무는 여우 신사',
          'rarity': 4,
          'asset_manifest': {'asset_key': 'room/fox_star_shrine'},
          'owned': false,
          'acquisition': {
            'type': 'own_item',
            'label': '구미호 화분 보유',
            'current': 0,
            'target': 1,
            'eligible': false,
          },
        },
      ],
    });

    await pumpCollection(
      tester,
      collection,
      textScaler: const TextScaler.linear(2),
    );

    expect(find.text('별여우 신사'), findsOneWidget);
    expect(find.text('구미호 화분 보유 · 0/1'), findsOneWidget);
    final node = tester.getSemantics(
      find.bySemanticsLabel('별여우 신사, 아직 수집하지 못함'),
    );
    expect(node.hint, '구미호 화분 보유 · 0/1');
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('마음결 기념품을 일반 아이템과 나누고 수확 기억을 연다', (tester) async {
    final collection = GardenCollection.fromJson({
      'seed_balance': 20,
      'items': const [],
      'species': const [],
      'catalog_items': [
        {
          'id': 170,
          'code': 'deco_resonance_rainy',
          'type': 'deco',
          'name': '빗방울 경청 풍경',
          'description': '첫 빗방울꽃의 기억',
          'price_seeds': 0,
          'rarity': 2,
          'asset_manifest': {
            'asset_key': 'deco/resonance_rainy',
            'collection': 'mood_resonance',
            'affinity_forms': ['rainy'],
            'reaction_copy': '빗소리를 들으면 잎이 조용히 기울어요.',
          },
          'owned': true,
          'acquisition': {
            'type': 'harvest_form',
            'label': '빗방울꽃 첫 수확',
            'current': 1,
            'target': 1,
            'eligible': false,
          },
        },
      ],
    });

    await pumpCollection(tester, collection);

    expect(find.text('마음결 기념품'), findsOneWidget);
    expect(find.textContaining('감정마다 가치와 획득 난이도는 같아요'), findsOneWidget);
    expect(find.text('빗방울 경청 풍경'), findsOneWidget);
    await tester.ensureVisible(find.text('빗방울 경청 풍경'));
    await tester.tap(find.text('빗방울 경청 풍경'));
    await tester.pumpAndSettle();

    expect(find.text('식물의 기억'), findsOneWidget);
    expect(find.text('빗소리를 들으면 잎이 조용히 기울어요.'), findsOneWidget);
    expect(find.textContaining('성장 속도나 보상에는 영향을 주지 않아요'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
