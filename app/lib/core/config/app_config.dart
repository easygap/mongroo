import 'package:flutter/foundation.dart';

/// 실행 환경 설정. 값은 --dart-define으로 주입한다.
///
/// 에뮬레이터 기본값은 10.0.2.2(호스트 loopback), 실기기는
/// `adb reverse tcp:8000 tcp:8000` 후 API_BASE_URL=http://127.0.0.1:8000/api/v1 로 넘긴다.
abstract final class AppConfig {
  static const String _configuredBaseUrl =
      String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_configuredBaseUrl.isNotEmpty) return _configuredBaseUrl;
    if (kIsWeb) return '${Uri.base.origin}/api/v1';
    return 'http://10.0.2.2:8000/api/v1';
  }

  /// access token TTL(서버 15분)보다 훨씬 짧은 일반 요청 timeout.
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 30);
}
