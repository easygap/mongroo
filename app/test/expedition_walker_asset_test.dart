import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/features/expedition/presentation/expedition_scene.dart';

/// 품종별 걷기 시트 계약.
///
/// 앱은 `expedition-walker-<품종>-v1.png`가 번들에 있으면 그것을 쓰고 없으면
/// 공용 시트로 **조용히** 떨어진다(`expeditionWalkerAssetCandidates`). 조용한
/// 폴백이라 파일이 빠지거나 규격이 어긋나도 화면만 보고는 모른다 — 어떤
/// 캐릭터로 들어가도 같은 사람이 걸을 뿐이다. 그래서 여기서 잰다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// `plant_species` 테이블의 code 전부. `plant_sprite_coverage_test.dart`의
  /// 목록과 같아야 한다 — 상점에 올라가는 종이 곧 이 목록이다.
  const catalog = <String>[
    'basic_sprout',
    'cactus',
    'sunflower',
    'aloof-pot',
    'baby-pot',
    'gal-pot',
    'gumiho-pot',
    'handsome-pot',
    'maestro-pot',
    'magical-pot',
    'marten-pot',
    'ninja-pot',
    'nurse-pot',
    'pretty-pot',
    'restorer-pot',
    'student-pot',
    'tsundere-pot',
    'zombie-pot',
  ];

  /// 일부러 공용 시트로 걷는 종.
  ///
  /// 공용 시트가 곧 **새싹몬**이라, 새싹몬에게 따로 시트를 만드는 것은 같은
  /// 그림을 두 번 넣는 일이다. 여기가 비어 있지 않은 상태를 지킨다 — 새 종을
  /// 올리면서 걷기 도트를 빼먹으면 아래 검사가 알려 준다.
  const sharedOnPurpose = <String>{'basic_sprout'};

  final species =
      catalog.where((code) => !sharedOnPurpose.contains(code)).toList();

  const cellWidth = 96;
  const cellHeight = 120;
  const columns = 3;
  const rows = 4;

  Future<ui.Image> load(String path) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }

  Future<ByteData> pixels(String path) async =>
      (await (await load(path)).toByteData())!;

  test('품종 시트는 후보 목록의 첫 자리에서 열린다', () async {
    for (final code in species) {
      final candidates = expeditionWalkerAssetCandidates(code);
      expect(candidates.first, 'assets/adventure/overworld/expedition-walker-$code-v1.png');
      final image = await load(candidates.first);
      expect(image.width, columns * cellWidth, reason: code);
      expect(image.height, rows * cellHeight, reason: code);
    }
  });

  test('시트는 도트 규격을 지킨다 — 1비트 알파, 24색 이하', () async {
    for (final path in [
      expeditionSharedWalkerAsset,
      for (final code in species) expeditionWalkerAssetCandidates(code).first,
    ]) {
      final data = await pixels(path);
      final palette = <int>{};
      for (var i = 0; i < data.lengthInBytes; i += 4) {
        final alpha = data.getUint8(i + 3);
        // 어중간한 알파는 최근접으로 키울 때 지저분한 띠를 남긴다.
        expect(alpha == 0 || alpha == 255, isTrue, reason: '$path 알파 $alpha');
        if (alpha == 0) continue;
        palette.add((data.getUint8(i) << 16) |
            (data.getUint8(i + 1) << 8) |
            data.getUint8(i + 2));
      }
      expect(palette.length, lessThanOrEqualTo(24), reason: path);
    }
  });

  test('열두 칸이 모두 차 있고 위아래로 잘리지 않는다', () async {
    for (final code in species) {
      final data = await pixels(expeditionWalkerAssetCandidates(code).first);
      for (var row = 0; row < rows; row++) {
        for (var column = 0; column < columns; column++) {
          var filled = 0;
          var top = cellHeight;
          var bottom = -1;
          for (var y = 0; y < cellHeight; y++) {
            for (var x = 0; x < cellWidth; x++) {
              final px = column * cellWidth + x;
              final py = row * cellHeight + y;
              final i = (py * columns * cellWidth + px) * 4;
              if (data.getUint8(i + 3) == 0) continue;
              filled++;
              if (y < top) top = y;
              if (y > bottom) bottom = y;
            }
          }
          final where = '$code $row행 $column칸';
          expect(filled, greaterThan(200), reason: '$where 이 비어 있다');
          expect(top, greaterThan(0), reason: '$where 위가 잘렸다');
          expect(bottom, lessThan(cellHeight - 1), reason: '$where 아래가 잘렸다');
        }
      }
    }
  });

  test('품종마다 다른 사람이 걷는다', () async {
    // 자기 시트를 넣었는데 공용 시트와 같으면 넣으나 마나다. 서로도 달라야
    // 한다 — 같은 프롬프트를 두 번 구우면 조용히 같은 그림이 들어온다.
    final sheets = <String, ByteData>{
      'shared': await pixels(expeditionSharedWalkerAsset),
      for (final code in species)
        code: await pixels(expeditionWalkerAssetCandidates(code).first),
    };
    final names = sheets.keys.toList();
    for (var a = 0; a < names.length; a++) {
      for (var b = a + 1; b < names.length; b++) {
        final first = sheets[names[a]]!;
        final second = sheets[names[b]]!;
        // 열여섯 장을 전부 맞대면 120쌍이라, 네 픽셀에 하나만 본다. 서로 다른
        // 캐릭터라면 이 성김으로도 충분히 갈린다.
        var different = 0;
        var counted = 0;
        for (var i = 0; i < first.lengthInBytes; i += 16) {
          counted++;
          if (first.getUint32(i) != second.getUint32(i)) different++;
        }
        final ratio = different / counted;
        expect(ratio, greaterThan(.2),
            reason: '${names[a]} 와 ${names[b]} 가 ${(ratio * 100).round()}%만 다르다');
      }
    }
  });

  test('공용 시트로 두기로 한 종은 첫 후보가 번들에 없다', () async {
    for (final code in sharedOnPurpose) {
      final own = expeditionWalkerAssetCandidates(code).first;
      var found = true;
      try {
        await rootBundle.load(own);
      } on Object {
        found = false;
      }
      expect(found, isFalse,
          reason: '$code 는 공용 시트로 걷기로 했는데 $own 이 번들에 들어 있다');
    }
  });

  test('모르는 품종은 공용으로 떨어진다', () {
    // 카탈로그를 다 채웠어도 폴백은 남는다. 새 품종이 추가되면 그림이 오기
    // 전까지 이 길로 걷는다.
    final candidates = expeditionWalkerAssetCandidates('someday-pot');
    expect(candidates.last, expeditionSharedWalkerAsset);
    expect(candidates.first,
        'assets/adventure/overworld/expedition-walker-someday-pot-v1.png');
    // 품종을 모르면 공용 한 장만 시도한다.
    expect(expeditionWalkerAssetCandidates(null),
        [expeditionSharedWalkerAsset]);
  });
}
