import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/features/garden/domain/garden_models.dart';

void main() {
  test('의상 탐험 보너스 메타데이터를 읽는다', () {
    final item = ShopItem.fromJson({
      'id': 99,
      'code': 'wardrobe_garden_daily',
      'type': 'wardrobe',
      'name': '정원 데일리 셋',
      'description': '정원 의상',
      'price_seeds': 180,
      'rarity': 2,
      'asset_manifest': {
        'wardrobe_layer_key': 'garden-daily',
        'adventure_bonus': {
          'context': 'patrol',
          'stat': 'care',
          'amount': 2,
          'label': '순찰 돌봄 +2',
        },
      },
    });

    expect(item.isWardrobe, isTrue);
    expect(item.adventureBonusContext, 'patrol');
    expect(item.adventureBonusStat, 'care');
    expect(item.adventureBonusAmount, 2);
    expect(item.adventureBonusLabel, '순찰 돌봄 +2');
  });

  test('상점 카탈로그와 구매 가능 정보를 파싱한다', () {
    final catalog = ShopCatalog.fromJson({
      'seed_balance': 35,
      'items': [
        {
          'id': 4,
          'code': 'pink_cushion',
          'type': 'deco',
          'name': '분홍 쿠션',
          'description': '포근한 쿠션',
          'price_seeds': 25,
          'rarity': 2,
          'asset_manifest': {'thumbnail': 'assets/items/pink_cushion.webp'},
          'owned': false,
        },
      ],
    });

    expect(catalog.seedBalance, 35);
    expect(catalog.items.single.typeLabel, '꾸미기');
    expect(catalog.items.single.assetPath, 'assets/items/pink_cushion.webp');
    expect(catalog.items.single.owned, isFalse);
  });

  test('구매형과 조건형 acquisition의 진행률과 claim 가능 여부를 파싱한다', () {
    final catalog = ShopCatalog.fromJson({
      'seed_balance': 35,
      'items': [
        {
          'id': 10,
          'code': 'room_sunny',
          'type': 'room_theme',
          'name': '햇살 온실',
          'price_seeds': 100,
          'rarity': 2,
          'asset_manifest': {'asset_key': 'room/sunny_greenhouse'},
          'owned': false,
          'acquisition': {
            'type': 'purchase',
            'label': '씨앗으로 구매',
            'current': 35,
            'target': 100,
            'eligible': false,
          },
        },
        {
          'id': 11,
          'code': 'room_fox_shrine',
          'type': 'room_theme',
          'name': '별여우 신사',
          'price_seeds': 0,
          'rarity': 4,
          'asset_manifest': {'asset_key': 'room/fox_star_shrine'},
          'owned': false,
          'acquisition': {
            'type': 'own_item',
            'label': '구미호 화분 보유',
            'current': 1,
            'target': 1,
            'eligible': true,
          },
        },
      ],
    });

    final purchase = catalog.items.first;
    final reward = catalog.items.last;
    expect(purchase.acquisition?.isPurchase, isTrue);
    expect(purchase.acquisition?.progress, closeTo(0.35, 0.001));
    expect(purchase.requiresClaim, isFalse);
    expect(reward.requiresClaim, isTrue);
    expect(reward.canClaim, isTrue);
    expect(reward.acquisitionHint, '구미호 화분 보유 · 1/1');
  });

  test('방 배치 좌표와 크기는 안전한 범위로 보정된다', () {
    final decoration = FarmDecoration.fromJson({
      'user_item_id': 9,
      'x': 1.7,
      'y': -0.4,
      'scale': 9,
      'rotation': -8,
      'z_index': 2,
    });

    expect(decoration.x, 1);
    expect(decoration.y, 0);
    expect(decoration.scale, 2);
    expect(decoration.rotation, -math.pi);

    final moved = decoration.copyWith(x: -1, y: 2, scale: 0.1);
    expect(moved.x, 0);
    expect(moved.y, 1);
    expect(moved.scale, 0.5);
  });

  test('farm update 요청에 optimistic version과 전체 배치를 포함한다', () {
    final layout = FarmLayout(
      version: 7,
      roomThemeUserItemId: 10,
      mainCharacterUserItemId: 11,
      wardrobeUserItemId: 14,
      companionUserItemIds: const [12],
      decorations: const [
        FarmDecoration(
          userItemId: 13,
          x: 0.25,
          y: 0.75,
          scale: 1,
          rotation: 0,
          zIndex: 1,
        ),
      ],
    );

    final body = layout.toUpdateJson();
    expect(body['expected_version'], 7);
    expect(body['room_theme_user_item_id'], 10);
    expect(body['wardrobe_user_item_id'], 14);
    expect(body['companion_user_item_ids'], [12]);
    expect((body['decorations'] as List).single['user_item_id'], 13);
  });

  test('의상 manifest에서 레이어 키와 호환 캐릭터를 해석한다', () {
    final wardrobe = ShopItem.fromJson({
      'id': 31,
      'code': 'wardrobe_garden_daily',
      'type': 'wardrobe',
      'name': '정원 데일리 셋',
      'price_seeds': 180,
      'rarity': 2,
      'asset_manifest': {
        'wardrobe_layer_key': 'garden-daily',
        'wardrobe_slot': 'outfit',
        'compatible_species': ['gumiho-pot', 'magical-pot'],
      },
      'owned': true,
    });

    expect(wardrobe.isWardrobe, isTrue);
    expect(wardrobe.typeLabel, '의상');
    expect(wardrobe.wardrobeLayerKey, 'garden-daily');
    expect(wardrobe.wardrobeSlot, 'outfit');
    expect(wardrobe.supportsSpecies('gumiho-pot'), isTrue);
    expect(wardrobe.supportsSpecies('baby-pot'), isFalse);
  });

  test('저장된 배치의 메인 캐릭터를 보유 아이템에서 찾는다', () {
    const equipped = UserGardenItem(
      id: 11,
      item: ShopItem(
        id: 21,
        code: 'character_gumiho_pot',
        type: 'main_character',
        name: '여우비',
        description: '',
        priceSeeds: 240,
        rarity: 4,
        assetManifest: {'asset_key': 'characters/gumiho-pot'},
        owned: true,
      ),
    );
    const farm = FarmData(
      layout: FarmLayout(
        version: 1,
        mainCharacterUserItemId: 11,
        companionUserItemIds: [],
        decorations: [],
      ),
      ownedItems: [equipped],
    );

    expect(farm.equippedMainCharacter, same(equipped));
    expect(
      FarmData(
        layout: farm.layout.copyWith(mainCharacterUserItemId: 999),
        ownedItems: farm.ownedItems,
      ).equippedMainCharacter,
      isNull,
    );
  });

  test('캐릭터 manifest에서 번들 경로와 성격, 모션을 해석한다', () {
    final character = ShopItem.fromJson({
      'id': 21,
      'code': 'character_gumiho_pot',
      'type': 'main_character',
      'name': '구미호 화분',
      'price_seeds': 240,
      'rarity': 4,
      'asset_manifest': {
        'asset_key': 'characters/gumiho-pot',
        'motion_key': 'gumiho_float',
        'personality': '부채 뒤로 장난을 꾸미는 구미호',
        'catchphrase': '후후, 꼬리 아홉 개를 다 찾았어?',
        'story_role': '달빛 온실의 장난꾼',
        'lore_hook': '달빛 신사의 봉인이 풀린 밤, 아홉 꼬리불을 훔쳐 달아난 여우 화분.',
        'collection_quote': '후후, 마지막 꼬리불은 어디 있게?',
      },
      'owned': false,
    });

    expect(character.isCharacter, isTrue);
    expect(character.characterSlug, 'gumiho-pot');
    expect(character.growthSpeciesCode, 'gumiho_pot');
    expect(
      character.bundledCharacterAssetPath,
      'assets/characters/gumiho-pot-v3.webp',
    );
    expect(character.motionKey, 'gumiho_float');
    expect(character.personality, '부채 뒤로 장난을 꾸미는 구미호');
    expect(character.catchphrase, '후후, 꼬리 아홉 개를 다 찾았어?');
    expect(character.storyRole, '달빛 온실의 장난꾼');
    expect(
      character.loreHook,
      '달빛 신사의 봉인이 풀린 밤, 아홉 꼬리불을 훔쳐 달아난 여우 화분.',
    );
    expect(character.collectionQuote, '후후, 마지막 꼬리불은 어디 있게?');
    expect(character.hasCollectionStory, isTrue);
  });

  test('상점 보상 code마다 고유 번들 자산을 연결한다', () {
    ShopItem item(String code, String type, String assetKey) =>
        ShopItem.fromJson({
          'id': 1,
          'code': code,
          'type': type,
          'name': code,
          'price_seeds': 25,
          'rarity': 1,
          'asset_manifest': {'asset_key': assetKey},
          'owned': false,
        });

    expect(
      item('deco_cushion_leaf', 'deco', 'deco/cushion_leaf').bundledAssetPath,
      'assets/decorations/leaf-cushion.webp',
    );
    expect(
      item('room_sunny', 'room_theme', 'room/sunny_greenhouse')
          .bundledAssetPath,
      'assets/rooms/sunny-greenhouse.webp',
    );
    expect(
      item('companion_star', 'companion', 'companion/star')
          .bundledCharacterAssetPath,
      'assets/companions/star-bean.webp',
    );
    expect(
      item('species_sunflower', 'species_unlock', 'species/sunflower')
          .bundledAssetPath,
      'assets/species/sunflower-seed.webp',
    );
  });

  test('사람형 완전체 원화는 아이템이 아닌 성장 계보로 집계한다', () {
    final collection = GardenCollection.fromJson({
      'seed_balance': 80,
      'items': const [],
      'species': const [],
      'catalog_items': [
        {
          'item': {
            'id': 30,
            'code': 'character_ninja_pot',
            'type': 'main_character',
            'name': '닌자 화분',
            'price_seeds': 180,
            'rarity': 3,
            'asset_manifest': {
              'asset_key': 'characters/ninja_pot',
              'motion_key': 'ninja_snap',
            },
          },
          'owned': true,
        },
        {
          'id': 31,
          'code': 'character_zombie_pot',
          'type': 'main_character',
          'name': '좀비 화분',
          'price_seeds': 160,
          'rarity': 3,
          'asset_manifest': {
            'asset_key': 'characters/zombie_pot',
          },
          'owned': false,
        },
      ],
    });

    expect(collection.catalogItems, hasLength(2));
    expect(collection.catalogItems.first.owned, isTrue);
    expect(collection.catalogItems.last.motionKey, 'zombie_sway');
    expect(collection.collectionCatalogItems, isEmpty);
    expect(collection.growthLineageItems, hasLength(2));
    expect(collection.unlockedCount, 1);
    expect(collection.totalCount, 2);
  });

  test('품종 해금 상품은 상점에는 남고 도감 분류와 수집 수에서는 한 번만 센다', () {
    final speciesShopItem = {
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
    };
    final collection = GardenCollection.fromJson({
      'seed_balance': 80,
      'items': const [],
      'species': [
        {
          'id': 1,
          'code': 'basic',
          'name': '기본 새싹',
          'rarity': 1,
          'unlock_price': 0,
          'is_unlocked': true,
        },
        {
          'id': 2,
          'code': 'cactus',
          'name': '선인장',
          'rarity': 2,
          'unlock_price': 90,
          'is_unlocked': true,
        },
      ],
      'catalog_items': [
        {
          'id': 31,
          'code': 'character_baby_pot',
          'type': 'main_character',
          'name': '뽀또',
          'price_seeds': 0,
          'rarity': 1,
          'asset_manifest': {'asset_key': 'characters/baby-pot'},
          'owned': true,
        },
        {
          'id': 32,
          'code': 'deco_leaf',
          'type': 'deco',
          'name': '잎 쿠션',
          'price_seeds': 30,
          'rarity': 1,
          'asset_manifest': const {},
          'owned': false,
        },
        speciesShopItem,
      ],
    });
    final shop = ShopCatalog.fromJson({
      'seed_balance': 80,
      'items': [speciesShopItem],
    });

    expect(collection.catalogItems, hasLength(3));
    expect(collection.collectionCatalogItems, hasLength(1));
    expect(
      collection.collectionCatalogItems.any((item) => item.isSpeciesUnlock),
      isFalse,
    );
    expect(collection.growthLineageItems, hasLength(1));
    expect(collection.unlockedCount, 3);
    expect(collection.totalCount, 4);
    expect(shop.items.single.isSpeciesUnlock, isTrue);
  });

  test('v2·v3 캐릭터의 이미지 경로와 모션 키를 매핑한다', () {
    ShopItem item(String slug, String motionKey) => ShopItem.fromJson({
          'id': 40,
          'code': 'character_${slug.replaceAll('-', '_')}',
          'type': 'main_character',
          'name': slug,
          'price_seeds': 100,
          'rarity': 2,
          'asset_manifest': {
            'asset_key': 'characters/$slug',
            'motion_key': motionKey,
          },
        });

    final aloof = item('aloof-pot', 'aloof_glance');
    final student = item('student-pot', 'student_adjust');
    final gumiho = item('gumiho-pot', 'gumiho_float');
    final tsundere = item('tsundere-pot', 'tsundere_turn_away');

    expect(
      aloof.bundledCharacterAssetPath,
      'assets/characters/aloof-pot-v2.webp',
    );
    expect(aloof.motionKey, 'aloof_glance');
    expect(student.bundledCharacterAssetPath,
        'assets/characters/student-pot-v2.webp');
    expect(student.motionKey, 'student_adjust');
    expect(
      gumiho.bundledCharacterAssetPath,
      'assets/characters/gumiho-pot-v3.webp',
    );
    expect(gumiho.motionKey, 'gumiho_float');
    expect(
      tsundere.bundledCharacterAssetPath,
      'assets/characters/tsundere-pot-v3.webp',
    );
    expect(tsundere.motionKey, 'tsundere_turn_away');
  });

  test('프리미엄 지원가 v6 이미지와 구매 포함 복장을 노출한다', () {
    ShopItem premium({
      required String slug,
      required String outfit,
      required String motionKey,
    }) =>
        ShopItem.fromJson({
          'id': slug == 'nurse-pot' ? 51 : 52,
          'code': 'character_${slug.replaceAll('-', '_')}',
          'type': 'main_character',
          'name': slug,
          'price_seeds': slug == 'nurse-pot' ? 280 : 240,
          'rarity': 5,
          'asset_manifest': {
            'asset_key': 'characters/$slug',
            'asset_version': 4,
            'species_code': slug,
            'motion_key': motionKey,
            'base_outfit': {
              'key': outfit.toLowerCase().replaceAll(' ', '-'),
              'name': outfit,
              'included_with_character': true,
            },
          },
        });

    final nurse = premium(
      slug: 'nurse-pot',
      outfit: '순백 트리아주',
      motionKey: 'nurse_breathe',
    );
    final maestro = premium(
      slug: 'maestro-pot',
      outfit: '미드나잇 레조넌스',
      motionKey: 'maestro_cue',
    );

    expect(
        nurse.bundledCharacterAssetPath, 'assets/characters/nurse-pot-v6.webp');
    expect(maestro.bundledCharacterAssetPath,
        'assets/characters/maestro-pot-v6.webp');
    expect(nurse.growthSpeciesCode, 'nurse-pot');
    expect(maestro.growthSpeciesCode, 'maestro-pot');
    expect(nurse.baseOutfitName, '순백 트리아주');
    expect(maestro.baseOutfitName, '미드나잇 레조넌스');
    expect(nurse.includesBaseOutfit, isTrue);
    expect(maestro.includesBaseOutfit, isTrue);
    expect(nurse.motionKey, 'nurse_breathe');
    expect(maestro.motionKey, 'maestro_cue');
  });

  test('신규 성장 캐릭터 v7 이미지와 구매 포함 복장을 노출한다', () {
    ShopItem character({
      required String slug,
      required String outfit,
      required String motionKey,
    }) =>
        ShopItem.fromJson({
          'id': slug.hashCode,
          'code': 'character_${slug.replaceAll('-', '_')}',
          'type': 'main_character',
          'name': slug,
          'price_seeds': 320,
          'rarity': 5,
          'asset_manifest': {
            'asset_key': 'characters/$slug',
            'asset_version': 7,
            'species_code': slug,
            'motion_key': motionKey,
            'base_outfit': {
              'key': outfit,
              'name': outfit,
              'included_with_character': true,
            },
          },
        });

    final characters = [
      character(
        slug: 'restorer-pot',
        outfit: '블루그레이 복원 워크웨어',
        motionKey: 'restorer_settle',
      ),
      character(
        slug: 'marten-pot',
        outfit: '잎길 탐험 하네스',
        motionKey: 'marten_scout',
      ),
      character(
        slug: 'gal-pot',
        outfit: '코랄 란제리 워크 스트리트',
        motionKey: 'gal_style_step',
      ),
    ];

    expect(
      characters.map((item) => item.bundledCharacterAssetPath),
      [
        'assets/characters/restorer-pot-v7.webp',
        'assets/characters/marten-pot-v7.webp',
        'assets/characters/gal-pot-v7.webp',
      ],
    );
    expect(characters.every((item) => item.includesBaseOutfit), isTrue);
    expect(
      characters.map((item) => item.motionKey),
      ['restorer_settle', 'marten_scout', 'gal_style_step'],
    );
  });

  test('캐릭터 기본 소개와 대사는 성격별로 구분된다', () {
    const expected = <String, List<String>>{
      'baby-pot': ['쪽쪽이를 문 호기심쟁이 막내', '뽀또! 새싹 하나 더 찾았어!'],
      'handsome-pot': ['흐트러짐을 못 보는 냉정한 리더', '소매부터 바로잡아. 출발하지.'],
      'pretty-pot': ['무대 체질인 새싹 아이돌', '센터는 나야. 박자 맞춰!'],
      'tsundere-pot': ['시선을 피하며 챙겨 주는 정석 츤데레', '오해하지 마. 네가 걱정돼서 그런 건 아니니까.'],
      'zombie-pot': ['해 질 무렵 깨어나는 느긋한 좀비', '해 뜨기 전까진… 아직 시간 많아.'],
      'gumiho-pot': ['눈맞춤과 부채로 홀리는 요염한 구미호', '후후, 그렇게 빤히 보면 내가 먼저 홀려버릴지도 몰라.'],
      'ninja-pot': ['잎 수리검을 다루는 재빠른 정찰꾼', '연막 잎 준비. 셋에 움직여.'],
      'magical-pot': ['별자리 주문을 연구하는 마법학교 우등생', '별자리 세 번째 줄, 주문 시작!'],
      'aloof-pot': ['서리꽃을 지키는 말수 적은 라이벌', '서리꽃은 함부로 만지지 마.'],
      'student-pot': ['수첩부터 펴는 원칙주의 학생회장', '수첩 펴. 할 일부터 정리하자.'],
    };

    final personalities = <String>{};
    final catchphrases = <String>{};
    for (final entry in expected.entries) {
      final character = ShopItem.fromJson({
        'id': expected.keys.toList().indexOf(entry.key) + 1,
        'code': 'character_${entry.key.replaceAll('-', '_')}',
        'type': 'main_character',
        'name': entry.key,
        'description': '',
        'price_seeds': 0,
        'rarity': 1,
        'asset_manifest': {'asset_key': 'characters/${entry.key}'},
      });

      expect(character.personality, entry.value[0], reason: entry.key);
      expect(character.catchphrase, entry.value[1], reason: entry.key);
      personalities.add(character.personality);
      catchphrases.add(character.catchphrase);
      for (final repeatedWord in ['마음', '빛나', '곁에', '천천히', '나한테만']) {
        expect(
          '${character.personality} ${character.catchphrase}',
          isNot(contains(repeatedWord)),
          reason: '${entry.key}: $repeatedWord',
        );
      }
    }

    expect(personalities, hasLength(expected.length));
    expect(catchphrases, hasLength(expected.length));
  });

  test('친구 캐릭터는 마법사 대사를 재사용하지 않는다', () {
    const expected = <String, String>{
      'dewdrop': '이슬길은 내가 먼저 살펴볼게!',
      'star': '반짝! 이쪽 길이야.',
      'bunny': '새 씨앗 냄새가 나. 따라와!',
      'mongle': '둥실둥실, 오늘은 어디로 갈까?',
    };

    for (final entry in expected.entries) {
      final companion = ShopItem.fromJson({
        'id': expected.keys.toList().indexOf(entry.key) + 1,
        'code': 'companion_${entry.key}',
        'type': 'companion',
        'name': entry.key,
        'description': '',
        'price_seeds': 0,
        'rarity': 1,
        'asset_manifest': const {},
      });

      expect(companion.catchphrase, entry.value, reason: entry.key);
      expect(companion.catchphrase, isNot(contains('별자리')));
    }
  });

  test('구매 뒤 남은 씨앗으로 다른 구매 상품의 가능 상태를 다시 계산한다', () {
    ShopItem item(int id, int price) => ShopItem.fromJson({
          'id': id,
          'code': 'deco_$id',
          'type': 'deco',
          'name': '소품 $id',
          'price_seeds': price,
          'rarity': 1,
          'asset_manifest': {
            'acquisition': {
              'type': 'purchase',
              'label': '씨앗 $price개로 구매',
              'current': 300,
              'target': price,
              'eligible': true,
            },
          },
        });

    final updated = ShopCatalog(
      items: [item(1, 240), item(2, 100)],
      seedBalance: 300,
    ).markOwned(1, 60);

    expect(updated.seedBalance, 60);
    expect(updated.items.first.owned, isTrue);
    expect(updated.items.last.acquisition?.eligible, isFalse);
  });

  test('첫 마음꽃 수확 소품의 친화도와 반응 문구를 해석한다', () {
    final relic = ShopItem.fromJson({
      'id': 170,
      'code': 'deco_resonance_rainy',
      'type': 'deco',
      'name': '빗방울 경청 풍경',
      'price_seeds': 0,
      'rarity': 2,
      'asset_manifest': {
        'asset_key': 'deco/resonance_rainy',
        'collection': 'mood_resonance',
        'affinity_forms': ['rainy'],
        'reaction_copy': '빗소리를 들으면 잎이 조용히 기울어요.',
      },
      'acquisition': {
        'type': 'harvest_form',
        'current': 1,
        'target': 1,
        'eligible': true,
      },
    });

    expect(relic.isMoodResonance, isTrue);
    expect(relic.affinityForms, ['rainy']);
    expect(relic.affinityLabel, '빗방울꽃');
    expect(relic.reactionCopy, '빗소리를 들으면 잎이 조용히 기울어요.');
    expect(relic.canClaim, isTrue);
    expect(relic.acquisition?.label, '해당 마음꽃 첫 수확');
    expect(
      relic.bundledAssetPath,
      'assets/decorations/listening-chime-rainy.webp',
    );
  });

  test('과거 주 캐릭터와 품종 해금은 모두 성장 씨앗으로 표시한다', () {
    final guide = ShopItem.fromJson({
      'id': 171,
      'code': 'character_ninja_pot',
      'type': 'main_character',
      'name': '닌자 화분',
      'asset_manifest': const {},
    });
    final companion = ShopItem.fromJson({
      'id': 172,
      'code': 'companion_star',
      'type': 'companion',
      'name': '별콩',
      'asset_manifest': const {},
    });

    expect(guide.typeLabel, '성장 씨앗');
    expect(guide.isGrowthCharacter, isTrue);
    expect(companion.typeLabel, '동행 친구');
    expect(companion.isGrowthCharacter, isFalse);
  });
}
