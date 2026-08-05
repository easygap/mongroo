import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web loading shell stays until Flutter renders its first frame', () {
    final html = File('web/index.html').readAsStringSync();
    final shellScript = html.indexOf('src="mongroo-shell.js"');
    final bootstrapScript = html.indexOf('id="flutter-bootstrap"');
    final shell = File('web/mongroo-shell.js').readAsStringSync();

    expect(shellScript, greaterThanOrEqualTo(0));
    expect(bootstrapScript, greaterThan(shellScript));
    expect(shell, contains('window.addEventListener'));
    expect(shell, contains("'flutter-first-frame'"));
    expect(shell, contains("performance.mark('mongroo-flutter-first-frame')"));
    expect(html, contains('id="loading-retry"'));
    expect(html, contains('prefers-reduced-motion: reduce'));
    expect(html, contains('name="mobile-web-app-capable"'));
  });

  test('production web resolves Korean fonts without an external CDN', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final dockerfile = File('Dockerfile').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(
      File('assets/fonts/GothicA1-Regular.ttf').lengthSync(),
      greaterThan(2000000),
    );
    expect(
      File('assets/fonts/GothicA1-Bold.ttf').lengthSync(),
      greaterThan(2000000),
    );
    expect(File('assets/fonts/LICENSE-GothicA1.txt').existsSync(), isTrue);
    expect(pubspec, contains('family: GothicA1'));
    expect(pubspec, contains('family: Roboto'));
    expect(pubspec, contains('family: Noto Sans KR'));
    expect(main, contains("FontLoader('Roboto')"));
    expect(main, contains('GothicA1-Regular.ttf'));
    expect(dockerfile, contains('--no-web-resources-cdn'));
  });
}
