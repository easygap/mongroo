import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/branding/mongroo_brand.dart';

void main() {
  test('BI는 서명 초록과 잉크, 종이색만 쓴다', () {
    expect(MongrooBrandColors.sprout, const Color(0xFFB9EE84));
    expect(MongrooBrandColors.soil, const Color(0xFF3B1F06));
    expect(MongrooBrandColors.paper, const Color(0xFFEFEFEF));
  });

  testWidgets('심볼은 작은 favicon 대응 크기부터 큰 타이틀까지 그려진다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              MongrooBrandMark(size: 16),
              MongrooBrandMark(size: 34, withPlate: true),
              MongrooBrandMark(size: 160),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(MongrooBrandMark), findsNWidgets(3));
    expect(
      find.bySemanticsLabel('몽그루, 오늘의 마음이 한 그루 자라나요'),
      findsNWidgets(3),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                MongrooBrandMark.assetPath,
      ),
      findsNWidgets(3),
    );
    expect(tester.takeException(), isNull);
  });
}
