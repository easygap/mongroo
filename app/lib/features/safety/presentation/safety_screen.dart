import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/safety_action.dart';

/// 안전 지원 화면. 게이미피케이션 요소 없이 차분하게,
/// 도움받을 수 있는 연락처를 큰 버튼으로 보여준다.
class SafetyScreen extends StatelessWidget {
  const SafetyScreen({super.key, this.action});

  final SafetyAction? action;

  static const _fallbackResources = [
    SafetyResource(label: '자살예방 상담전화', phone: '109'),
    SafetyResource(label: '정신건강 위기상담', phone: '1577-0199'),
    SafetyResource(label: '긴급 상황', phone: '112'),
  ];

  Future<void> _call(BuildContext context, String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    final messenger = ScaffoldMessenger.of(context);
    var launched = false;
    try {
      launched = await launchUrl(uri);
    } catch (_) {
      launched = false;
    }
    if (!launched) {
      messenger.showSnackBar(
        SnackBar(content: Text('전화 연결을 열 수 없어요. 직접 $phone로 전화해 주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final safety = action;
    final resources = (safety == null || safety.resources.isEmpty)
        ? _fallbackResources
        : safety.orderedResources;
    final calmSurface = scheme.surfaceContainerLowest;

    return Scaffold(
      backgroundColor: calmSurface,
      appBar: AppBar(
        backgroundColor: calmSurface,
        title: const Text('지금 도움받을 수 있는 곳'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              safety?.message.isNotEmpty == true
                  ? safety!.message
                  : '지금 마음이 많이 힘드신 것 같아요. 혼자 견디지 않아도 됩니다.',
              style: const TextStyle(fontSize: 17, height: 1.5),
            ),
            const SizedBox(height: 8),
            Text(
              '아래 번호를 누르면 바로 전화 앱으로 연결돼요.',
              style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            for (final resource in resources)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Semantics(
                  button: true,
                  label: '${resource.label} ${resource.phone} 전화 걸기',
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(64),
                      backgroundColor:
                          (resource.phone == '112' || resource.phone == '119')
                              ? scheme.error
                              : scheme.primary,
                      textStyle: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    onPressed: () => _call(context, resource.phone),
                    icon: const Icon(Icons.call),
                    label: Text('${resource.label} · ${resource.phone}'),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              '몽그루는 의료적 진단이나 치료를 제공하지 않는 자기 기록 도구예요. '
              '위기 상황에서는 위의 전문 기관이 도움을 드릴 수 있어요.',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            Semantics(
              button: true,
              label: '안전 안내 닫기',
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/home');
                  }
                },
                child: const Text('닫기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
