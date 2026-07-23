import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/gallery/presentation/gallery_screen.dart';
import '../../features/garden/presentation/garden_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/mood/domain/mood_entry.dart';
import '../../features/mood/presentation/calendar_screen.dart';
import '../../features/mood/presentation/day_entries_screen.dart';
import '../../features/mood/presentation/mood_detail_screen.dart';
import '../../features/mood/presentation/mood_entries_by_ids_screen.dart';
import '../../features/mood/presentation/mood_record_screen.dart';
import '../../features/report/presentation/report_screen.dart';
import '../../features/quest/presentation/quest_screen.dart';
import '../../features/safety/domain/safety_action.dart';
import '../../features/safety/presentation/safety_screen.dart';
import 'app_shell.dart';

/// 전역 navigator/messenger key.
/// 화면 pop 이후에도 보상 스낵바·성장 다이얼로그를 띄울 때 쓴다.
final rootNavigatorKey = GlobalKey<NavigatorState>();
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

final routerProvider = Provider<GoRouter>((ref) {
  // 인증 상태가 바뀔 때만 redirect를 다시 평가한다.
  final refreshNotifier = ValueNotifier(0);
  ref.listen(authControllerProvider, (_, __) => refreshNotifier.value++);
  ref.onDispose(refreshNotifier.dispose);
  // 웹 새로고침/외부 딥링크가 인증 복원용 splash를 거쳐도 목적지를 잃지 않는다.
  String? pendingLocation;

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;
      final onAuthScreen = location == '/login' || location == '/signup';
      switch (auth.status) {
        case AuthStatus.restoring:
          if (location != '/splash') {
            pendingLocation = state.uri.toString();
          }
          return location == '/splash' ? null : '/splash';
        case AuthStatus.signedOut:
          pendingLocation = null;
          return onAuthScreen ? null : '/login';
        case AuthStatus.signedIn:
          if (onAuthScreen || location == '/splash') {
            final destination = pendingLocation ?? '/home';
            pendingLocation = null;
            return destination;
          }
          return null;
      }
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: '/record',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) =>
            MoodRecordScreen(existing: state.extra as MoodEntry?),
      ),
      GoRoute(
        path: '/moods/:id/edit',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => MoodEditLoader(
          moodId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/moods/day/:date',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) =>
            DayEntriesScreen(date: state.pathParameters['date']!),
      ),
      GoRoute(
        path: '/moods/entries',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final args = state.extra as MoodEntriesByIdsArgs? ??
              const MoodEntriesByIdsArgs(title: '기록', entryIds: []);
          return MoodEntriesByIdsScreen(args: args);
        },
      ),
      GoRoute(
        path: '/moods/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) =>
            MoodDetailScreen(moodId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/chat',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ChatScreen(),
      ),
      GoRoute(
        path: '/gallery',
        parentNavigatorKey: rootNavigatorKey,
        redirect: (context, state) => '/museum',
      ),
      GoRoute(
        path: '/quests',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const QuestScreen(),
      ),
      GoRoute(
        path: '/safety',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) =>
            SafetyScreen(action: state.extra as SafetyAction?),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomeScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/calendar',
              builder: (context, state) => const CalendarScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/garden',
              builder: (context, state) => GardenScreen(
                initialTab: int.tryParse(
                      state.uri.queryParameters['tab'] ?? '',
                    ) ??
                    0,
                initialSpeciesCode: state.uri.queryParameters['species'],
              ),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/museum',
              builder: (context, state) => const GalleryScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/reports',
              builder: (context, state) => const ReportScreen(),
            ),
          ]),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
