import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/theme/app_theme.dart';
import 'package:mongroo/features/expedition/domain/expedition_models.dart';
import 'package:mongroo/features/expedition/presentation/expedition_controller.dart';
import 'package:mongroo/features/expedition/presentation/moss_archive_scene.dart';
import 'package:mongroo/features/expedition/presentation/expedition_screen.dart';

Map<String, dynamic> _snapshotJson() => {
      'run': {
        'id': 7,
        'mode': 'heart_resonance',
        'status': 'active',
        'phase': 'awaiting_event',
        'revision': 1,
        'current_node_code': 'wet_labels',
        'trail_light': 9,
        'resolve': 6,
        'objective_secured': false,
        'reward_eligible': true,
      },
      'region': {
        'code': 'moss_archive',
        'name': '이끼 기억서고',
        'description': '첫 탐험지',
        'recommended_stage': 2,
        'reward': {'exp': 6, 'seeds': 2},
      },
      'party': [
        {
          'id': 11,
          'name': '새싹몬',
          'species': {'name': '새싹몬'},
          'stage': 2,
          'form': 'sunny',
          'stats': {'care': 7, 'focus': 6, 'courage': 6, 'insight': 5},
          'is_guide': false,
          'skills': {
            'signature': {
              'code': 'baby-pot.sprout-cheer',
              'name': '새싹 응원',
              'description': '이번 우회의 결의 손실을 한 번 막아요.',
              'phases': ['awaiting_event'],
              'modes': [
                {'code': 'guard', 'label': '결의 지키기'},
              ],
              'used': false,
              'available': true,
            },
            'form': {
              'code': 'sunny.share-warmth',
              'name': '온기 나누기',
              'description': '돌봄 판정에 +3을 더하거나 결의 1을 회복해요.',
              'phases': ['exploring', 'awaiting_event'],
              'modes': [
                {'code': 'care_bonus', 'label': '돌봄 +3'},
                {'code': 'restore_resolve', 'label': '결의 1 회복'},
              ],
              'used': false,
              'available': true,
            },
          },
        },
      ],
      'map': {
        'nodes': [
          {
            'code': 'entrance',
            'name': '서고 입구',
            'type': 'entrance',
            'status': 'visited',
            'x': .08,
            'y': .5,
            'cost': 0,
          },
          {
            'code': 'wet_labels',
            'name': '젖은 표찰길',
            'type': 'event',
            'status': 'visited',
            'x': .28,
            'y': .27,
            'cost': 1,
          },
          {
            'code': 'ledger_keeper',
            'status': 'hidden',
            'type': 'unknown',
          },
        ],
        'edges': [
          ['entrance', 'wet_labels'],
          ['wet_labels', 'ledger_keeper'],
        ],
      },
      'current_event': {
        'code': 'wet_label_order',
        'title': '번진 이름들',
        'text': '젖은 표찰의 글자를 어떤 방식으로 되살릴까요?',
        'spotlight_member_id': 11,
        'choices': [
          {
            'code': 'trace_ink',
            'label': '번진 잉크의 결을 따라간다',
            'previews': [
              {
                'member_id': 11,
                'label': '관찰 5 · 기준 8',
                'forecast': '도전',
              },
            ],
          },
        ],
      },
      'available_actions': [
        {'type': 'choice'},
        {'type': 'skill'},
      ],
      'run_thread': {'current_text': '서고 전체가 천천히 숨 쉬어요.'},
      'memory': {'discoveries': [], 'outcomes': []},
      'loot': [],
      'summary': null,
    };

class _FakeExpeditionController extends ExpeditionController {
  _FakeExpeditionController(this.initial);

  final ExpeditionUiState initial;

  @override
  ExpeditionUiState build() => initial;
}

void main() {
  test('탐험 편성 목록에서 현재 성장 캐릭터를 구분한다', () {
    final item = ExpeditionRosterItem.fromJson({
      'plant_id': 12,
      'name': '하루',
      'status': 'active',
      'species': {'code': 'student-pot', 'name': '학생화분'},
      'stage': 2,
      'form': 'sunny',
      'stats': {'care': 6, 'focus': 7, 'courage': 5, 'insight': 6},
      'eligible': true,
    });

    expect(item.isActive, isTrue);
    expect(item.eligible, isTrue);
  });

  test('탐험 응답에서 숨은 노드와 행동 가능 상태를 보존한다', () {
    final snapshot = ExpeditionSnapshot.fromJson(_snapshotJson());

    expect(snapshot.run.revision, 1);
    expect(snapshot.currentEvent?.spotlightMemberId, 11);
    expect(snapshot.nodes.last.isPositioned, isFalse);
    expect(snapshot.currentEvent?.choices.first.previewFor(11)?.forecast, '도전');
    expect(snapshot.canExtract, isFalse);
    expect(snapshot.party.first.signatureSkill.name, '새싹 응원');
    expect(snapshot.party.first.formSkill.modes, hasLength(2));
  });

  testWidgets('사건 화면에 담당 캐릭터, 스킬, 판정 미리보기를 함께 표시한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final snapshot = ExpeditionSnapshot.fromJson(_snapshotJson());
    final state = ExpeditionUiState(
      loading: false,
      expedition: snapshot,
      selectedMemberId: 11,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expeditionControllerProvider.overrideWith(
            () => _FakeExpeditionController(state),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ExpeditionScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('번진 이름들'), findsOneWidget);
    expect(find.text('새싹몬'), findsOneWidget);
    expect(find.text('새싹 응원'), findsOneWidget);
    expect(find.text('온기 나누기'), findsOneWidget);
    expect(find.textContaining('관찰 5 · 기준 8'), findsOneWidget);
    expect(find.byTooltip('젖은 표찰길'), findsOneWidget);
    expect(find.byType(MossArchiveScene), findsOneWidget);
    expect(find.text('현재 · 젖은 표찰길'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px과 200% 글자에서도 사건 선택을 읽을 수 있다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final snapshot = ExpeditionSnapshot.fromJson(_snapshotJson());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expeditionControllerProvider.overrideWith(
            () => _FakeExpeditionController(
              ExpeditionUiState(
                loading: false,
                expedition: snapshot,
                selectedMemberId: 11,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const ExpeditionScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('번진 이름들'), findsOneWidget);
    expect(find.textContaining('관찰 5 · 기준 8'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('선택형 스킬은 효과를 고른 뒤 사용한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final snapshot = ExpeditionSnapshot.fromJson(_snapshotJson());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expeditionControllerProvider.overrideWith(
            () => _FakeExpeditionController(
              ExpeditionUiState(
                loading: false,
                expedition: snapshot,
                selectedMemberId: 11,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ExpeditionScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.ensureVisible(find.text('온기 나누기'));
    await tester.tap(find.text('온기 나누기'));
    // 탐험 배경의 잔잔한 환경 모션은 계속 재생되므로 바텀시트 전환
    // 시간만 진행하고 무한 애니메이션의 settle을 기다리지 않는다.
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('돌봄 +3'), findsOneWidget);
    expect(find.text('결의 1 회복'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('튜토리얼은 한 번에 현재 단계 안내만 보여 준다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final raw = _snapshotJson();
    (raw['run'] as Map<String, dynamic>)['mode'] = 'tutorial';
    final snapshot = ExpeditionSnapshot.fromJson(raw);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expeditionControllerProvider.overrideWith(
            () => _FakeExpeditionController(
              ExpeditionUiState(
                loading: false,
                expedition: snapshot,
                selectedMemberId: 11,
                tutorialCoachStep: 3,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ExpeditionScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('사건에 맞는 캐릭터를 골라요'), findsOneWidget);
    expect(find.text('다음: 스킬 보기'), findsOneWidget);
    expect(find.byTooltip('현재 조작 도움말 다시 보기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
