import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/config/bundled_assets.dart';
import 'package:mongroo/features/home/domain/plant.dart';
import 'package:mongroo/features/home/presentation/plant_view.dart';

/// 후보 경로가 실제 그림으로 이어지는지 파일로 확인한다.
///
/// 기존 테스트는 `candidates`가 어떤 문자열을 내놓는지만 봤다. 그래서 규칙은
/// 맞는데 그 이름의 파일이 없는 경우 — 2단계는 결이 언제나 null이라 접미사
/// 없는 공통 파일을 찾는데 대부분의 종에는 그 파일이 없었다 — 를 놓쳤고,
/// 새싹 단계 캐릭터가 통째로 벡터 폴백으로 그려지고 있었다.
void main() {
  final plants = Directory('assets/plants');
  final bundled = plants
      .listSync()
      .whereType<File>()
      .map((file) => 'assets/plants/${file.uri.pathSegments.last}')
      .toSet();

  /// `plant_species` 테이블의 code와 같다. 상점에 올라가는 종이 곧 이 목록이다.
  const species = <String>[
    'baby-pot',
    'cactus',
    'sunflower',
    'handsome-pot',
    'pretty-pot',
    'tsundere-pot',
    'zombie-pot',
    'gumiho-pot',
    'ninja-pot',
    'student-pot',
    'magical-pot',
    'aloof-pot',
    'maestro-pot',
    'nurse-pot',
    'restorer-pot',
    'marten-pot',
    'gal-pot',
  ];

  /// 원화가 없어 벡터 폴백으로 내려가는 조합.
  ///
  /// 2026-08-25에 마지막 넷(세렌·백화·가시니·해바라기)을 채워 지금은 비어
  /// 있다. **여기가 비어 있는 상태를 지킨다.** 새 종을 올리면서 원화를 빼먹으면
  /// 이 테스트가 깨져서 알려 준다.
  const knownGaps = <String>{};

  /// 서버가 결을 내려 주는 시점. 2단계까지는 `ActivePlant.fromJson`이 언제나
  /// null로 만들고, 3단계 이후에도 표본이 모자라면 계속 null이다.
  Iterable<PlantGrowthForm?> formsFor(int stage) =>
      stage < 3
          ? const <PlantGrowthForm?>[null]
          : <PlantGrowthForm?>[null, ...PlantGrowthForm.values];

  test('모든 종·단계·결 조합이 번들에 있는 그림 하나로 이어진다', () {
    final gaps = <String>{};
    for (final code in species) {
      for (var stage = 1; stage <= 5; stage++) {
        for (final form in formsFor(stage)) {
          final resolved = PlantGrowthAssetResolver.candidates(
            speciesCode: code,
            stage: stage,
            form: form,
          ).any(bundled.contains);
          if (!resolved) gaps.add('$code:$stage');
        }
      }
    }
    expect(
      gaps,
      knownGaps,
      reason: '원화를 채웠으면 knownGaps에서 지우고, 새로 빈 조합이면 원화를 채워 주세요.',
    );
  });

  test('결이 정해지기 전에도 같은 화풍의 그림을 집는다', () {
    // 2단계는 언제나 결이 없다. 그림이 있는 종은 예외 없이 이 구간에서도
    // 2.5D 원화로 그려져야 한다 — 여기가 비면 사용자가 첫 며칠 동안 보는
    // 캐릭터가 배경과 다른 화풍이 된다.
    for (final code in species) {
      if (knownGaps.contains('$code:2')) continue;
      final resolved = PlantGrowthAssetResolver.candidates(
        speciesCode: code,
        stage: 2,
        form: null,
      ).where(bundled.contains);
      expect(resolved, isNotEmpty, reason: '$code 새싹 그림이 없습니다');
    }
  });

  test('번들에 없는 후보는 걸러 내고 요청하지 않는다', () {
    BundledAssets.overrideAssetsForTest(bundled);
    addTearDown(() => BundledAssets.overrideAssetsForTest(null));

    final raw = PlantGrowthAssetResolver.candidates(
      speciesCode: 'baby-pot',
      stage: 2,
      form: null,
    );
    // 규칙이 만든 후보에는 없는 파일이 섞여 있다.
    expect(raw.any((path) => !bundled.contains(path)), isTrue);

    final filtered = PlantSpriteBundle.filter(raw);
    expect(filtered, isNotEmpty);
    expect(filtered.every(bundled.contains), isTrue);
  });
}
