/// 안전 경로 응답의 리소스 항목(전화 연결 대상).
class SafetyResource {
  const SafetyResource({required this.label, required this.phone});

  final String label;
  final String phone;

  factory SafetyResource.fromJson(Map<String, dynamic> json) => SafetyResource(
        label: (json['label'] as String?) ?? '',
        phone: (json['phone'] as String?) ?? '',
      );
}

/// 서버가 안전 경로 진입 시 내려주는 safety_action.
/// severity는 내부 라우팅 값이며 진단·위험등급이 아니다.
class SafetyAction {
  const SafetyAction({
    required this.action,
    required this.severity,
    required this.message,
    required this.resources,
  });

  final String action;
  final String severity;
  final String message;
  final List<SafetyResource> resources;

  bool get isImminent => severity == 'imminent';

  /// imminent면 112/119 계열을 최상단으로 정렬한다.
  List<SafetyResource> get orderedResources {
    if (!isImminent) return resources;
    final urgent = <SafetyResource>[];
    final rest = <SafetyResource>[];
    for (final r in resources) {
      if (r.phone == '112' || r.phone == '119') {
        urgent.add(r);
      } else {
        rest.add(r);
      }
    }
    return [...urgent, ...rest];
  }

  factory SafetyAction.fromJson(Map<String, dynamic> json) => SafetyAction(
        action: (json['action'] as String?) ?? 'show_support_screen',
        severity: (json['severity'] as String?) ?? 'concern',
        message: (json['message'] as String?) ?? '',
        resources: ((json['resources'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SafetyResource.fromJson)
            .toList(),
      );

  static SafetyAction? fromJsonOrNull(Object? json) {
    if (json is Map<String, dynamic>) return SafetyAction.fromJson(json);
    return null;
  }
}
