import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test('출시용 도트 아틀라스와 4지역 85종 스프라이트 표가 번들에서 열린다', () async {
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
      expect(entries, hasLength(85));
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
    expect(diagnostics['chunkCount'], 35);
    expect(diagnostics['maxCellsPerChunk'], lessThanOrEqualTo(64));
    expect(diagnostics['staticScenery'], greaterThan(0));
    expect(diagnostics['interactables'], greaterThan(0));
    // 배우는 기록지기와 길 잃은 기록원 둘이다. 엉킴은 수호 스테이지에만
    // 선다 - 사건 스테이지에서 붙으면 열리는 것이 전투가 아니라 엉뚱한
    // 사건이 되기 때문이다.
    expect(diagnostics['actors'], 2);
    expect(diagnostics['visibleChunks'], lessThan(diagnostics['chunkCount']!));

    final guarded = expeditionTileWorldChunkDiagnostics(
      'moss_archive',
      1,
      withGuardian: true,
    );
    expect(guarded['actors'], 3);
  });

  test('지형 생성기는 어느 플랫폼에서나 같은 땅을 만든다', () {
    // 웹에서 직접 걸어 보니 테스트가 보는 땅과 출발 칸부터 달랐다. 원인은
    // `hash * 16777619`를 한 번에 곱한 것이었다 - dart2js에서 int는 double이라
    // 2^53을 넘으면 아래 비트가 날아간다. 값으로 못 박아 다시 흔들리면 잡는다.
    const expected = <String, List<int>>{
      'moss_archive': <int>[8, 33],
      'echo_well': <int>[8, 33],
      'starlight_seed_vault': <int>[8, 33],
      'heartwood_observatory': <int>[9, 33],
    };
    expected.forEach((region, spawn) {
      final diagnostics = expeditionTileWorldTravelDiagnostics(region, 1);
      expect(diagnostics['spawnX'], spawn.first, reason: region);
      expect(diagnostics['spawnY'], spawn.last, reason: region);
    });
  });

  test('한 판에 걸을 곳과 볼 것이 충분히 있다', () {
    // 앞 판은 1260칸 격자에 바닥이 279칸(22%)뿐이었고, 상호작용할 수 있는
    // 것이 스테이지 전체에 셋이었다. 넓어 보이지만 실제로는 방 하나를 돌다
    // 나오는 것이었다. 다시 휑해지면 여기서 걸린다.
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
          greaterThanOrEqualTo(480),
          reason: '$region $stage장 바닥 칸',
        );
        expect(
          chunk['interactables'],
          greaterThanOrEqualTo(8),
          reason: '$region $stage장 상호작용',
        );
        expect(
          chunk['staticScenery'],
          greaterThanOrEqualTo(12),
          reason: '$region $stage장 조형물',
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
}
