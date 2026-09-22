import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/branding/mongroo_brand.dart';

void main() {
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
      find.bySemanticsLabel('몽그루'),
      findsNWidgets(3),
    );
    expect(tester.getSize(find.byType(MongrooBrandMark).first),
        const Size(16, 16));
    expect(tester.getSize(find.byType(MongrooBrandMark).last),
        const Size(160, 160));
    expect(tester.takeException(), isNull);
  });
}
