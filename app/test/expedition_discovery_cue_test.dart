import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/features/expedition/domain/expedition_models.dart';
import 'package:mongroo/features/expedition/presentation/expedition_discovery_audio.dart';

ExpeditionSnapshot _snapshot({
  int runId = 7,
  bool objectiveSecured = false,
  String threadText = '서가 사이에서 낯선 표식을 봤어요.',
  int discoveries = 0,
  bool wonBattle = false,
}) =>
    ExpeditionSnapshot.fromJson({
      'run': {
        'id': runId,
        'mode': 'heart_resonance',
        'status': 'active',
        'phase': 'exploring',
        'revision': 1,
        'current_node_code': 'wet_labels',
        'trail_light': 9,
        'resolve': 6,
        'objective_secured': objectiveSecured,
        'reward_eligible': true,
      },
      'run_thread': {'title': '젖은 이름표', 'current_text': threadText},
      'memory': {
        'discoveries': [
          for (var index = 0; index < discoveries; index++)
            {'code': 'spot_$index'},
        ],
      },
      'last_combat_exchange': [
        if (wonBattle)
          {'sequence': 1, 'type': 'outcome', 'outcome': 'victory', 'caption': ''},
      ],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('첫 스냅숏과 다른 탐험은 발견으로 세지 않는다', () {
    expect(expeditionDiscoveryCueFor(null, _snapshot()), isNull);
    expect(
      expeditionDiscoveryCueFor(
        _snapshot(runId: 7),
        _snapshot(runId: 8, objectiveSecured: true),
      ),
      isNull,
      reason: '탐험을 갈아탄 것은 찾은 게 아니다',
    );
  });

  test('바뀐 것이 없으면 아무 소리도 내지 않는다', () {
    expect(expeditionDiscoveryCueFor(_snapshot(), _snapshot()), isNull);
  });

  test('새 장소·이야기·목표를 저마다 다른 무게로 알린다', () {
    expect(
      expeditionDiscoveryCueFor(
        _snapshot(discoveries: 1),
        _snapshot(discoveries: 2),
      ),
      ExpeditionDiscoveryCue.place,
    );
    expect(
      expeditionDiscoveryCueFor(
        _snapshot(threadText: '낯선 표식을 봤어요.'),
        _snapshot(threadText: '표식이 이어진 곳을 알아냈어요.'),
      ),
      ExpeditionDiscoveryCue.story,
    );
    expect(
      expeditionDiscoveryCueFor(
        _snapshot(),
        _snapshot(objectiveSecured: true),
      ),
      ExpeditionDiscoveryCue.objective,
    );
  });

  test('한 번에 여러 개가 열려도 가장 무거운 것만 낸다', () {
    // 목표를 확보하면 이야기도 결말로 넘어가고 발견도 함께 쌓인다.
    final cue = expeditionDiscoveryCueFor(
      _snapshot(threadText: '낯선 표식을 봤어요.', discoveries: 1),
      _snapshot(
        threadText: '표식이 가리키던 것을 품에 안았어요.',
        discoveries: 2,
        objectiveSecured: true,
      ),
    );
    expect(cue, ExpeditionDiscoveryCue.objective);
  });

  test('전투로 목표를 확보하면 풀려남 소리에 발견음을 얹지 않는다', () {
    expect(
      expeditionDiscoveryCueFor(
        _snapshot(),
        _snapshot(objectiveSecured: true, wonBattle: true),
      ),
      isNull,
    );
    // 전투 없이 닿았을 때는 그대로 울린다.
    expect(
      expeditionDiscoveryCueFor(
        _snapshot(),
        _snapshot(objectiveSecured: true),
      ),
      ExpeditionDiscoveryCue.objective,
    );
  });

  test('빈 이야기 문장으로 바뀌는 것은 발견이 아니다', () {
    expect(
      expeditionDiscoveryCueFor(
        _snapshot(threadText: '낯선 표식을 봤어요.'),
        _snapshot(threadText: ''),
      ),
      isNull,
    );
  });

  testWidgets('발견음 세 장을 번들에서 실제로 읽는다', (tester) async {
    const assets = <String>[
      'assets/adventure/sfx/discover-normal.wav',
      'assets/adventure/sfx/discover-story.wav',
      'assets/adventure/sfx/discover-target.wav',
    ];
    for (final asset in assets) {
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(2000), reason: asset);
      expect(data.getUint32(0, Endian.big), 0x52494646, reason: '$asset RIFF');
      expect(data.getUint32(8, Endian.big), 0x57415645, reason: '$asset WAVE');
    }
  });
}
