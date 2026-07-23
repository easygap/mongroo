import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';
import 'core/session/session_boundary.dart';
import 'core/theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: MongrooApp()));
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
      routerConfig: router,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
    );
  }
}
