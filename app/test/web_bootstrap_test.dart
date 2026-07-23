import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web loading shell stays until Flutter renders its first frame', () {
    final html = File('web/index.html').readAsStringSync();
    final firstFrameListener =
        html.indexOf("window.addEventListener('flutter-first-frame'");
    final bootstrapScript = html.indexOf('id="flutter-bootstrap"');

    expect(firstFrameListener, greaterThanOrEqualTo(0));
    expect(bootstrapScript, greaterThan(firstFrameListener));
    expect(html, contains("performance.mark('mongroo-flutter-first-frame')"));
    expect(html, contains('id="loading-retry"'));
    expect(html, contains('prefers-reduced-motion: reduce'));
  });
}
