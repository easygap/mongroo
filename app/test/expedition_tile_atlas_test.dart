import 'dart:convert';

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

  test('출시용 페인터리 아틀라스와 4지역 61종 스프라이트 표가 번들에서 열린다', () async {
    final manifestText = await rootBundle.loadString(
      'assets/adventure/overworld/expedition-tile-atlas-v2.json',
    );
    final manifest = jsonDecode(manifestText) as Map<String, dynamic>;
    expect(manifest['version'], 3);
    expect(manifest['cell'], 96);
    expect(manifest['gutter'], 2);
    expect(manifest['stride'], 100);
    expect(manifest['columns'], 8);
    expect(manifest['sprites_per_region_padded'], 64);
    final regions = manifest['regions'] as Map<String, dynamic>;
    expect(regions, hasLength(4));
    for (final sprites in regions.values) {
      final entries = sprites as Map<String, dynamic>;
      expect(entries, hasLength(61));
      for (final value in entries.values) {
        final rect = value as Map<String, dynamic>;
        expect((rect['x'] as int) % 100, 2);
        expect((rect['y'] as int) % 100, 2);
        expect(rect['w'], 96);
        expect(rect['h'], 96);
      }
    }
    final textureQa = manifest['texture_qa'] as Map<String, dynamic>;
    expect(textureQa['policy'], 'painted-broad-planes-no-stipple-no-dither');
    expect(textureQa['resampling'], 'lanczos-median-unsharp');
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

    final bytes = await rootBundle.load(
      'assets/adventure/overworld/expedition-tile-atlas-v2.png',
    );
    // PNG IHDR stores width and height as big-endian uint32 at 16 and 20.
    expect(bytes.getUint32(16), 800);
    expect(bytes.getUint32(20), 3200);
  });

  test('월드는 8x8 청크와 정적·상호작용·배우 레이어로 분리된다', () {
    final diagnostics = expeditionTileWorldChunkDiagnostics('moss_archive', 1);
    expect(diagnostics['chunkSize'], 8);
    expect(diagnostics['chunkCount'], 24);
    expect(diagnostics['maxCellsPerChunk'], lessThanOrEqualTo(64));
    expect(diagnostics['staticScenery'], greaterThan(0));
    expect(diagnostics['interactables'], 3);
    expect(diagnostics['actors'], 2);
    expect(diagnostics['visibleChunks'], lessThan(diagnostics['chunkCount']!));
  });
}
