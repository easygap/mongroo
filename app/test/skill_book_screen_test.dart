import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mongroo/core/error/api_exception.dart';
import 'package:mongroo/features/expedition/data/skill_book_repository.dart';
import 'package:mongroo/features/expedition/domain/expedition_models.dart';
import 'package:mongroo/features/expedition/domain/skill_book_models.dart';
import 'package:mongroo/features/expedition/presentation/skill_book_screen.dart';

Map<String, dynamic> _book(
  String code,
  String name, {
  int grade = 1,
  bool owned = true,
  bool combatEffect = true,
  String activationMode = 'trigger',
  String? tradeoff,
  int? priceSeeds = 40,
  String acquireKind = 'shop',
  String? unlockHint,
}) =>
    {
      'code': code,
      'name': name,
      'grade': grade,
      'min_slot': grade == 3 ? 'B2' : 'B1',
      'activation_mode': activationMode,
      'effect_summary': '$name의 효과',
      'stack_group': code,
      'acquire_kind': acquireKind,
      'price_seeds': priceSeeds,
      'unlock_hint': unlockHint,
      'tradeoff': tradeoff,
      'owned': owned,
      'combat_effect': combatEffect,
    };

Map<String, dynamic> _loadout({
  int revision = 1,
  int level = 30,
  String? storedB1,
  String? storedB2,
  Map<String, dynamic>? b1,
  Map<String, dynamic>? b2,
}) =>
    {
      'plant_id': 7,
      'preset_code': 'guard',
      'revision': revision,
      'level': level,
      'stored': {'slot_b1_code': storedB1, 'slot_b2_code': storedB2},
      'resolved': {
        'B1': b1 ??
            {
              'slot': 'B1',
              'source': 'emotion',
              'code': 'emotion.primary',
              'locked': false,
              'lock_reason': null,
              'fell_back': false,
            },
        'B2': b2 ??
            {
              'slot': 'B2',
              'source': 'default_book',
              'code': 'field_note_echo',
              'locked': false,
              'lock_reason': null,
              'fell_back': false,
            },
      },
      'slot_unlock_level': {'B1': 9, 'B2': 23},
    };

class _FakeSkillBookRepository implements SkillBookRepository {
  _FakeSkillBookRepository({
    required this.library,
    required this.loadout,
    this.saveError,
  });

  final Map<String, dynamic> library;
  Map<String, dynamic> loadout;
  ApiException? saveError;
  final List<Map<String, Object?>> saves = [];

  @override
  Future<SkillBookLibrary> getLibrary() async =>
      SkillBookLibrary.fromJson(library);

  @override
  Future<SkillLoadout> getLoadout({
    required int plantId,
    required String presetCode,
  }) async =>
      SkillLoadout.fromJson(loadout);

  @override
  Future<SkillLoadout> saveLoadout({
    required int plantId,
    required String presetCode,
    required String? slotB1Code,
    required String? slotB2Code,
    required int expectedRevision,
  }) async {
    saves.add({
      'preset': presetCode,
      'b1': slotB1Code,
      'b2': slotB2Code,
      'revision': expectedRevision,
    });
    final error = saveError;
    if (error != null) throw error;
    loadout = _loadout(
      revision: expectedRevision + 1,
      storedB1: slotB1Code,
      storedB2: slotB2Code,
      b1: slotB1Code == null
          ? null
          : {
              'slot': 'B1',
              'source': 'skillbook',
              'code': slotB1Code,
              'locked': false,
              'lock_reason': null,
              'fell_back': false,
              'book': {'name': '또렷한 겨냥'},
            },
    );
    return SkillLoadout.fromJson(loadout);
  }
}

Future<_FakeSkillBookRepository> _pump(
  WidgetTester tester, {
  Map<String, dynamic>? library,
  Map<String, dynamic>? loadout,
  ApiException? saveError,
}) async {
  final repository = _FakeSkillBookRepository(
    library: library ??
        {
          'catalog': [
            _book('clear_aim', '또렷한 겨냥'),
            _book('short_cheer', '짧은 격려',
                combatEffect: false, activationMode: 'command'),
            _book(
              'shadow_oath',
              '그림자 서약',
              grade: 3,
              acquireKind: 'challenge',
              priceSeeds: null,
              unlockHint: '약점 30회',
              tradeoff: '중립 공격은 ×0.60',
            ),
            _book('focus_knot', '집중의 매듭',
                grade: 2, owned: false, priceSeeds: 120),
            _book(
              'ringcount_record',
              '나이테 관측 기록',
              grade: 3,
              owned: false,
              acquireKind: 'challenge',
              priceSeeds: null,
              unlockHint: '관측실 깊은 조사',
              tradeoff: '장착자는 그 전투에서 방어 선택 불가',
            ),
          ],
          'presets': ['explore', 'guard', 'personal'],
        },
    loadout: loadout ?? _loadout(),
    saveError: saveError,
  );
  // 서고 목록까지 한 번에 배치되도록 세로로 넉넉한 화면을 쓴다. 좁은 화면
  // 계약은 별도 테스트가 320px에서 따로 확인한다.
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        skillBookRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(home: SkillBookScreen(plantId: 7)),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  testWidgets('두 칸의 현재 내용과 서고 전체를 함께 보여 준다', (tester) async {
    await _pump(tester);

    expect(find.byKey(const ValueKey('slot-B1')), findsOneWidget);
    expect(find.byKey(const ValueKey('slot-B2')), findsOneWidget);
    // 저장한 것이 없으면 안전 기본값이 읽힌다.
    expect(find.text('성장결 기본'), findsWidgets);
    expect(find.text('현장 기록'), findsOneWidget);

    // 아직 없는 책도 숨기지 않고 획득처를 함께 보여 준다.
    expect(find.byKey(const ValueKey('book-focus_knot')), findsOneWidget);
    expect(find.text('상점 씨앗 120'), findsOneWidget);
  });

  testWidgets('효과가 아직 없는 책은 있는 척하지 않는다', (tester) async {
    await _pump(tester);
    expect(find.byKey(const ValueKey('pending-short_cheer')), findsOneWidget);
    expect(find.byKey(const ValueKey('pending-clear_aim')), findsNothing);
  });

  testWidgets('3등급의 대가와 획득 조건을 함께 읽는다', (tester) async {
    await _pump(tester);
    // 예산 2를 쓰는 대신 지는 대가는 보유 여부와 무관하게 보여 준다.
    expect(find.text('대가 · 중립 공격은 ×0.60'), findsOneWidget);
    expect(find.text('대가 · 장착자는 그 전투에서 방어 선택 불가'), findsOneWidget);
    // 획득처는 아직 없는 책에만 붙는다. 이미 가진 책에는 필요 없다.
    expect(find.text('도전 · 관측실 깊은 조사'), findsOneWidget);
    expect(find.text('도전 · 약점 30회'), findsNothing);
  });

  testWidgets('기록서를 고르면 저장되고 현재 revision을 함께 보낸다', (tester) async {
    final repository = await _pump(tester);

    await tester.tap(find.byKey(const ValueKey('equip-B1-clear_aim')));
    await tester.pumpAndSettle();

    expect(repository.saves.single, {
      'preset': 'guard',
      'b1': 'clear_aim',
      'b2': null,
      'revision': 1,
    });
    expect(find.text('또렷한 겨냥'), findsWidgets);
    expect(find.text('기록서를 정리했어요.'), findsOneWidget);
  });

  testWidgets('3등급은 첫 칸에서 누를 수 없고 이유를 함께 읽는다', (tester) async {
    await _pump(tester);

    final first = tester.widget<FilterChip>(
      find.byKey(const ValueKey('equip-B1-shadow_oath')),
    );
    expect(first.onSelected, isNull);
    expect(first.tooltip, '3등급은 두 번째 칸에서만 펼쳐져요');

    // 두 번째 칸에서는 열린다.
    final second = tester.widget<FilterChip>(
      find.byKey(const ValueKey('equip-B2-shadow_oath')),
    );
    expect(second.onSelected, isNotNull);
  });

  testWidgets('잠긴 칸은 해금 레벨을 보여 주고 누를 수 없다', (tester) async {
    await _pump(
      tester,
      loadout: _loadout(
        level: 9,
        b2: {
          'slot': 'B2',
          'source': 'locked',
          'code': null,
          'locked': true,
          'lock_reason': 'Lv23부터 열려요',
          'fell_back': false,
        },
      ),
    );

    expect(find.text('Lv23부터'), findsOneWidget);
    expect(find.byKey(const ValueKey('slot-B2-reason')), findsOneWidget);
    final chip = tester.widget<FilterChip>(
      find.byKey(const ValueKey('equip-B2-clear_aim')),
    );
    expect(chip.onSelected, isNull);
  });

  testWidgets('선택이 되돌려졌으면 조용히 넘어가지 않고 이유를 띄운다', (tester) async {
    await _pump(
      tester,
      loadout: _loadout(
        storedB1: 'short_cheer',
        b1: {
          'slot': 'B1',
          'source': 'emotion',
          'code': 'emotion.primary',
          'locked': false,
          'lock_reason': '아직 서고에 없어요',
          'fell_back': true,
        },
      ),
    );

    expect(find.text('B1 칸: 아직 서고에 없어요'), findsOneWidget);
  });

  testWidgets('저장이 거부되면 서버가 준 문장을 그대로 보여 준다', (tester) async {
    final repository = await _pump(
      tester,
      saveError: const ApiException(
        code: 'LOADOUT_STACK_CONFLICT',
        message: '같은 결의 기록서를 두 칸에 함께 둘 수 없어요.',
        statusCode: 422,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('equip-B1-clear_aim')));
    await tester.pumpAndSettle();

    expect(repository.saves, hasLength(1));
    expect(find.text('같은 결의 기록서를 두 칸에 함께 둘 수 없어요.'), findsOneWidget);
  });

  testWidgets('320px 200% 글자에서도 슬롯과 서고가 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeSkillBookRepository(
      library: {
        'catalog': [_book('clear_aim', '또렷한 겨냥')],
        'presets': ['explore', 'guard', 'personal'],
      },
      loadout: _loadout(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          skillBookRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const SkillBookScreen(plantId: 7),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('slot-B1')), findsOneWidget);
  });

  testWidgets('라우터가 캐릭터별 기록서 화면을 열고 이름을 함께 받는다', (tester) async {
    final repository = _FakeSkillBookRepository(
      library: {
        'catalog': [_book('clear_aim', '또렷한 겨냥')],
        'presets': ['explore', 'guard', 'personal'],
      },
      loadout: _loadout(),
    );
    final router = GoRouter(
      initialLocation: '/skill-books/7?name=%EB%8B%AC%EB%B9%9B%EC%9D%B4',
      routes: [
        GoRoute(
          path: '/skill-books/:plantId',
          builder: (context, state) => SkillBookScreen(
            plantId: int.parse(state.pathParameters['plantId']!),
            plantName: state.uri.queryParameters['name'],
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          skillBookRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    // 캐릭터 이름을 제목에 실어 어느 캐릭터를 정리하는지 헷갈리지 않게 한다.
    expect(find.text('달빛이의 기록서'), findsOneWidget);
    expect(find.byKey(const ValueKey('slot-B1')), findsOneWidget);
  });

  test('전투 응답의 새 기록서 소식을 이름과 함께 읽는다', () {
    final snapshot = ExpeditionSnapshot.fromJson(const {
      'run': <String, dynamic>{},
      'region': <String, dynamic>{},
      'party': <Map<String, dynamic>>[],
      'map': <String, dynamic>{},
      'available_actions': <Map<String, dynamic>>[],
      'run_thread': <String, dynamic>{},
      'memory': <String, dynamic>{},
      'loot': <Map<String, dynamic>>[],
      'unlocked_skill_books': [
        {
          'code': 'double_leaf',
          'source': 'unlock',
          'name': '두 겹 잎방패',
          'effect_summary': '마음 지키기 잔여 방어 1을 다음 라운드로 이월',
          'grade': 2,
        },
      ],
    });

    expect(snapshot.unlockedSkillBooks, hasLength(1));
    final book = snapshot.unlockedSkillBooks.single;
    expect(book.code, 'double_leaf');
    expect(book.name, '두 겹 잎방패');
    expect(book.sourceLabel, '조건 달성');
    // 보유해도 자동 장착되지 않으므로 다음 행동까지 알려 준다.
    expect(book.notice, contains('두 겹 잎방패'));
    expect(book.notice, contains('장착'));
  });

  test('소식이 없는 응답과 이름이 빠진 구버전도 깨지지 않는다', () {
    final none = ExpeditionSnapshot.fromJson(const {
      'run': <String, dynamic>{},
      'region': <String, dynamic>{},
      'party': <Map<String, dynamic>>[],
      'map': <String, dynamic>{},
      'available_actions': <Map<String, dynamic>>[],
      'run_thread': <String, dynamic>{},
      'memory': <String, dynamic>{},
      'loot': <Map<String, dynamic>>[],
    });
    expect(none.unlockedSkillBooks, isEmpty);

    final legacy = ExpeditionUnlockedSkillBook.fromJson(const {
      'code': 'double_leaf',
    });
    // 이름이 없으면 코드로 떨어져 문구가 비지 않는다.
    expect(legacy.name, 'double_leaf');
    expect(legacy.sourceLabel, '조건 달성');
  });
}
