import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'core/routing/app_router.dart';
import 'core/session/session_boundary.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerBundledFontLicenses();
  await _primeBundledWebFallbackFont();
  runApp(const ProviderScope(child: MongrooApp()));
}

Future<void> _primeBundledWebFallbackFont() async {
  if (!kIsWeb) return;
  try {
    // Web renderer의 기본 family cache를 앱 시작 전에 비워 한글을 원격
    // Noto fallback으로 다시 찾지 않고 번들 서체만 사용하게 한다.
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/GothicA1-Regular.ttf')))
        .load();
  } catch (_) {
    // 서체 캐시 준비가 실패해도 로그인과 로컬 체험 진입은 막지 않는다.
  }
}

void _registerBundledFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['Gothic A1'],
      await rootBundle.loadString('assets/fonts/LICENSE-GothicA1.txt'),
    );
    yield LicenseEntryWithLineBreaks(
      const ['Galmuri11'],
      await rootBundle.loadString('assets/fonts/LICENSE-Galmuri.txt'),
    );
  });
}

class MongrooApp extends ConsumerWidget {
  const MongrooApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(sessionBoundaryProvider);
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: '몽그루',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
    );
  }
}
