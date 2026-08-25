import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/features/expedition/domain/expedition_models.dart';
import 'package:mongroo/features/expedition/presentation/expedition_scene.dart';
import 'package:mongroo/features/expedition/presentation/expedition_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('4개 지역의 8개 스테이지는 출발점에서 제단까지 연결된다', () {
    const regions = <String>[
      'moss_archive',
      'echo_well',
      'starlight_seed_vault',
      'heartwood_observatory',
    ];
    for (final region in regions) {
      for (var stage = 1; stage <= 8; stage++) {
        expect(
          expeditionTileWorldHasRoute(region, stage),
          isTrue,
          reason: '$region stage $stage route must remain traversable',
        );
      }
    }
  });

  test('출시용 도트 아틀라스와 4지역 87종 스프라이트 표가 번들에서 열린다', () async {
    final manifestText = await rootBundle.loadString(
      'assets/adventure/overworld/expedition-tile-atlas-v2.json',
    );
    final manifest = jsonDecode(manifestText) as Map<String, dynamic>;
    expect(manifest['version'], 3);
    expect(manifest['cell'], 96);
    expect(manifest['gutter'], 2);
    expect(manifest['stride'], 100);
    expect(manifest['columns'], 8);
    expect(manifest['sprites_per_region_padded'], 88);
    final regions = manifest['regions'] as Map<String, dynamic>;
    expect(regions, hasLength(4));
    for (final sprites in regions.values) {
      final entries = sprites as Map<String, dynamic>;
      // 85종에 파생 조형물 둘(석주·기억 결정)을 더했다. 패딩 88 안이라
      // 아틀라스 크기는 그대로다.
      expect(entries, hasLength(87));
      expect(entries.containsKey('pillar'), isTrue);
      expect(entries.containsKey('crystal'), isTrue);
      // 오토타일에 필요한 조각이 다 있어야 한다. 하나라도 빠지면 그 자리에
      // 아무것도 안 그려져 경계가 다시 직선으로 잘린다.
      for (final key in <String>['n', 'e', 's', 'w', 'ne', 'nw', 'se', 'sw']) {
        expect(entries.containsKey('rim_$key'), isTrue, reason: 'rim_$key');
        expect(entries.containsKey('edge_$key'), isTrue, reason: 'edge_$key');
        expect(entries.containsKey('shore_$key'), isTrue, reason: 'shore_$key');
      }
      for (final suffix in <String>['a', 'b', 'c', 'd']) {
        expect(entries.containsKey('wall_top_$suffix'), isTrue);
      }
      for (final value in entries.values) {
        final rect = value as Map<String, dynamic>;
        expect((rect['x'] as int) % 100, 2);
        expect((rect['y'] as int) % 100, 2);
        expect(rect['w'], 96);
        expect(rect['h'], 96);
      }
    }
    final textureQa = manifest['texture_qa'] as Map<String, dynamic>;
    expect(textureQa['policy'], 'ds-era-dot-one-palette-per-region-1bit-alpha');
    expect(
      textureQa['resampling'],
      'lanczos-median-unsharp-then-alpha-weighted-box-and-nearest',
    );
    // 한 칸은 24×24 도트, 지역마다 색 서른두 개. 캐릭터 시트도 같은 격자라
    // 발밑과 캐릭터가 한 세계로 읽힌다.
    expect(textureQa['dot_grid'], 24);
    expect(textureQa['palette_colors'], 32);
    expect(textureQa['ground_alpha_min'], 255);
    expect(textureQa['prop_alpha_min'], 0);
    expect(
      textureQa['max_seam_channel_error'] as num,
      lessThanOrEqualTo(textureQa['seam_channel_limit'] as num),
    );
    expect(
      textureQa['max_opaque_high_frequency_ratio'] as num,
      lessThanOrEqualTo(textureQa['high_frequency_limit'] as num),
    );
    expect(
      textureQa['max_isolated_speck_ratio'] as num,
      lessThanOrEqualTo(textureQa['isolated_speck_limit'] as num),
    );
    // 칸끼리 밝기가 벌어지면 네 칸 주기의 마름모 벽지가 된다. 거울을 걷어낸
    // 뒤에도 벽지가 남아 있던 진짜 원인이라 수치로 못 박는다.
    expect(
      textureQa['max_phase_mean_spread'] as num,
      lessThanOrEqualTo(textureQa['phase_mean_spread_limit'] as num),
    );

    final bytes = await rootBundle.load(
      'assets/adventure/overworld/expedition-tile-atlas-v2.png',
    );
    // PNG IHDR stores width and height as big-endian uint32 at 16 and 20.
    expect(bytes.getUint32(16), 800);
    expect(bytes.getUint32(20), 4400);

    // 표만 믿지 않는다. 실제로 그림을 풀어서 도트 규칙이 지켜졌는지 본다.
    final decoded = await ui.instantiateImageCodec(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    final frame = await decoded.getNextFrame();
    final pixels = await frame.image.toByteData();
    decoded.dispose();
    final alphas = <int>{};
    final colors = <int>{};
    for (var offset = 0; offset < pixels!.lengthInBytes; offset += 4) {
      final alpha = pixels.getUint8(offset + 3);
      alphas.add(alpha);
      if (alpha > 8) colors.add(pixels.getUint32(offset));
    }
    frame.image.dispose();
    // 반투명 가장자리가 남아 있으면 최근접으로 키울 때 지저분한 테두리가 된다.
    expect(alphas, <int>{0, 255});
    // 네 지역이 각자 서른두 색이니 전부 합쳐도 이 수를 넘을 수 없다.
    expect(colors.length, lessThanOrEqualTo(4 * 32));
  });

  test('월드는 8x8 청크와 정적·상호작용·배우 레이어로 분리된다', () {
    final diagnostics = expeditionTileWorldChunkDiagnostics('moss_archive', 1);
    expect(diagnostics['chunkSize'], 8);
    // 72×52 격자라 9×7 청크다.
    expect(diagnostics['chunkCount'], 63);
    expect(diagnostics['maxCellsPerChunk'], lessThanOrEqualTo(64));
    expect(diagnostics['staticScenery'], greaterThan(0));
    expect(diagnostics['interactables'], greaterThan(0));
    // 배우는 기록지기·물가 기록원·길 잃은 기록원·정원지기·견습 기록원
    // 다섯이다. 엉킴은 수호 스테이지에만 선다 - 사건 스테이지에서 붙으면
    // 열리는 것이 전투가 아니라 엉뚱한 사건이 되기 때문이다. 길 복구가
    // 사람을 치우면 이 수가 깨진다 — 실제로 세 지역에서 그랬다.
    expect(diagnostics['actors'], 5);
    expect(diagnostics['visibleChunks'], lessThan(diagnostics['chunkCount']!));

    final guarded = expeditionTileWorldChunkDiagnostics(
      'moss_archive',
      1,
      withGuardian: true,
    );
    expect(guarded['actors'], 6);
  });

  test('길 복구가 어느 지역·어느 판에서도 기록원을 지우지 않는다', () {
    for (final region in <String>[
      'moss_archive',
      'echo_well',
      'starlight_seed_vault',
      'heartwood_observatory',
    ]) {
      for (var stage = 1; stage <= 8; stage++) {
        final chunk = expeditionTileWorldChunkDiagnostics(region, stage);
        expect(chunk['actors'], 5, reason: '$region $stage장 기록원 수');
      }
    }
  });

  test('지형 생성기는 어느 플랫폼에서나 같은 땅을 만든다', () {
    // 웹에서 직접 걸어 보니 테스트가 보는 땅과 출발 칸부터 달랐다. 원인은
    // `hash * 16777619`를 한 번에 곱한 것이었다 - dart2js에서 int는 double이라
    // 2^53을 넘으면 아래 비트가 날아간다. 값으로 못 박아 다시 흔들리면 잡는다.
    const expected = <String, List<int>>{
      'moss_archive': <int>[9, 44],
      'echo_well': <int>[9, 44],
      'starlight_seed_vault': <int>[9, 44],
      'heartwood_observatory': <int>[10, 44],
    };
    expected.forEach((region, spawn) {
      final diagnostics = expeditionTileWorldTravelDiagnostics(region, 1);
      expect(diagnostics['spawnX'], spawn.first, reason: region);
      expect(diagnostics['spawnY'], spawn.last, reason: region);
    });
  });

  test('한 판에 걸을 곳과 볼 것이 충분히 있다', () {
    // 56×40 판은 바닥이 480칸 남짓에 상호작용 여덟이었다. 방마다 볼 것은
    // 생겼지만 갈림길이 없어 `길을 고른다`가 없었다. 72×52로 넓히고 본길
    // 열 방 + 곁가지 셋 + 순환 복도를 깐 지금의 바닥선이다(실측 최저
    // 1076·23·47). 다시 휑해지면 여기서 걸린다.
    for (final region in <String>[
      'moss_archive',
      'echo_well',
      'starlight_seed_vault',
      'heartwood_observatory',
    ]) {
      for (var stage = 1; stage <= 8; stage++) {
        final chunk = expeditionTileWorldChunkDiagnostics(region, stage);
        expect(
          chunk['walkable'],
          greaterThanOrEqualTo(1000),
          reason: '$region $stage장 바닥 칸',
        );
        expect(
          chunk['interactables'],
          greaterThanOrEqualTo(18),
          reason: '$region $stage장 상호작용',
        );
        expect(
          chunk['staticScenery'],
          greaterThanOrEqualTo(40),
          reason: '$region $stage장 조형물',
        );
      }
    }
  });

  test('물건이 겹치거나 벽에 박히거나 혼자 서 있지 않다', () {
    // 넓히고 채우는 것만으로는 부족했다. 발 높이가 종류마다 달라서 예약한
    // 칸과 실제로 선 칸이 한 칸씩 어긋나 있었고, 그래서 서가가 벽에 박히고
    // 두 물건이 같은 자리에 겹쳐 섰다. 한 판에 여덟 군데가 그랬다.
    // 눈으로는 못 세니 여기서 센다.
    for (final region in <String>[
      'moss_archive',
      'echo_well',
      'starlight_seed_vault',
      'heartwood_observatory',
    ]) {
      for (var stage = 1; stage <= 8; stage++) {
        final metrics = expeditionTileWorldPlacementDiagnostics(
          region,
          stage,
          // 엉킴이 서는 판과 안 서는 판을 섞어 본다.
          withGuardian: stage.isEven,
        );
        final where = '$region $stage장';
        expect(metrics['overlapping'], 0, reason: '$where 겹친 물건');
        expect(metrics['standingOffFloor'], 0, reason: '$where 바닥 밖에 선 물건');
        // 벌판에 하나만 선 조형물은 무리가 아니라 버려진 것으로 보인다.
        expect(metrics['lonelyScenery'], 0, reason: '$where 혼자 선 조형물');
        // 서가와 등불은 벽에 등을 붙인다. 방 한가운데 떠 있는 쪽이 많아지면
        // 벽을 따라 세운다는 규칙이 깨진 것이다.
        expect(
          metrics['wallBackedProps']!,
          greaterThan(metrics['freeStandingProps']! * 4),
          reason: '$where 벽에 붙은 물건',
        );
      }
    }
  });

  test('아치로 실내 방을 드나들 수 있고 문이 막혀 있지 않다', () {
    for (final region in <String>[
      'moss_archive',
      'echo_well',
      'starlight_seed_vault',
      'heartwood_observatory',
    ]) {
      final travel = expeditionTileWorldTravelDiagnostics(region, 1);
      // 들어가는 문 하나, 나오는 문 하나. 나오는 문이 없으면 갇힌다.
      expect(travel['outsideWarps'], 1, reason: region);
      expect(travel['insideWarps'], 1, reason: region);
      // 문이 막혀 있으면 지나갈 수 없다.
      expect(travel['blockingWarps'], 0, reason: region);
      // 실내는 벽으로 둘러싸여야 방으로 읽힌다.
      expect(travel['insideWalls'], greaterThan(20), reason: region);
      // 들어서자마자 벽에 끼면 조작이 고장 난 것처럼 보인다.
      expect(travel['insideSpawnBlocked'], 0, reason: region);
    }
  });

  test('걷기 시트는 품종 시트를 먼저 찾고 공용으로 떨어진다', () async {
    // 품종별 도트는 방향마다 그림을 받아야 하는 원화 작업이라 아직 없다.
    // 시트가 들어오는 순간 코드를 고치지 않고 그 품종부터 바뀌도록 자리만
    // 열어 뒀다. 여기서 지키는 것은 그 순서와 이름 규칙이다.
    expect(
      expeditionWalkerAssetCandidates('cactus'),
      const [
        'assets/adventure/overworld/expedition-walker-cactus-v1.png',
        expeditionSharedWalkerAsset,
      ],
    );
    // 서버 코드는 밑줄, 파일은 붙임표를 쓴다. 굽는 쪽(`import_expedition_walker.py`의
    // `out_path`)과 같은 규칙이어야 서로 못 찾는 일이 없다.
    expect(
      expeditionWalkerAssetCandidates('baby_pot').first,
      'assets/adventure/overworld/expedition-walker-baby-pot-v1.png',
    );
    // 품종을 모르면 공용 한 장만 시도한다.
    for (final unknown in <String?>[null, '', '   ', 'generic']) {
      expect(
        expeditionWalkerAssetCandidates(unknown),
        const [expeditionSharedWalkerAsset],
        reason: '$unknown',
      );
    }

    // 마지막 후보는 실제로 번들에 있어야 한다. 없으면 폴백이 폴백이 아니다.
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final bundled = manifest.listAssets().toSet();
    expect(bundled, contains(expeditionSharedWalkerAsset));
  });

  test('던전을 걷는 대원은 안내자가 아니라 실제 캐릭터다', () {
    ExpeditionMember member(String code, {bool guide = false}) =>
        ExpeditionMember.fromJson(<String, dynamic>{
          'id': code.hashCode,
          'name': code,
          'species': <String, dynamic>{'code': code, 'name': code},
          'is_guide': guide,
        });

    // 안내자가 앞에 서 있어도 시트는 뒤에 있는 진짜 캐릭터로 고른다.
    expect(
      expeditionWalkerMember([
        member('archive_guide', guide: true),
        member('cactus'),
      ])?.speciesCode,
      'cactus',
    );
    expect(
      expeditionWalkerMember([member('baby-pot'), member('cactus')])
          ?.speciesCode,
      'baby-pot',
    );
    // 안내자밖에 없는 튜토리얼에서는 그 사람이라도 쓴다.
    expect(
      expeditionWalkerMember([member('archive_guide', guide: true)])
          ?.speciesCode,
      'archive_guide',
    );
    expect(expeditionWalkerMember(const []), isNull);
  });
}
