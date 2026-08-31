import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/account_screen.dart';
import '../../features/auth/presentation/legal_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/expedition/presentation/expedition_screen.dart';
import '../../features/expedition/presentation/skill_book_screen.dart';
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
import '../../features/trial/presentation/trial_screen.dart';
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
    // 없는 주소로 들어오면 go_router 기본 화면이 뜬다 - 영어로 `Page Not
    // Found`와 `GoException: no routes for location: …`을 그대로 보여 준다.
    // 웹은 주소창을 고칠 수 있고 지워진 링크도 남으니 실제로 닿는 화면이다.
    errorBuilder: (context, state) => const _RouteNotFoundScreen(),
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;
      final onAuthScreen = location == '/login' || location == '/signup';
      final onLegalScreen = location.startsWith('/legal/');
      final onTrialScreen = location == '/trial';
      // 안전 지원 화면은 로그인을 요구하지 않는다. 서버 없이 도는 연락처
      // 목록이고, 정작 이 화면이 가장 필요한 사람이 계정을 아직 안 만든
      // 사람일 수 있다. 로그인으로 되돌리면 그 자리에서 길이 끊긴다.
      final onSafetyScreen = location == '/safety';
      switch (auth.status) {
        case AuthStatus.restoring:
          if (location != '/splash') {
            pendingLocation = state.uri.toString();
          }
          return location == '/splash' ? null : '/splash';
        case AuthStatus.signedOut:
          pendingLocation = null;
          return onAuthScreen ||
                  onLegalScreen ||
                  onTrialScreen ||
                  onSafetyScreen
              ? null
              : '/login';
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
        path: '/trial',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const TrialScreen(),
      ),
      GoRoute(
        path: '/legal/:document',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => LegalScreen(
          document: LegalDocument.fromPath(state.pathParameters['document']),
        ),
      ),
      GoRoute(
        path: '/account',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const AccountScreen(),
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
        path: '/expedition',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ExpeditionScreen(),
      ),
      GoRoute(
        // 장착은 출발 전과 캐릭터 상세 두 곳에서 연다. 전투 중에는 열지 않는다.
        path: '/skill-books/:plantId',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final plantId = int.tryParse(state.pathParameters['plantId'] ?? '');
          if (plantId == null) return const ExpeditionScreen();
          return SkillBookScreen(
            plantId: plantId,
            plantName: state.uri.queryParameters['name'],
          );
        },
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

/// 없는 주소로 들어왔을 때 서는 화면.
class _RouteNotFoundScreen extends StatelessWidget {
  const _RouteNotFoundScreen();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('길을 찾지 못했어요')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.explore_off_outlined,
                  size: 56,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  '여기엔 아무것도 없어요',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '주소가 바뀌었거나 지워진 화면이에요. 기록은 그대로 있어요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const Key('route-not-found-home'),
                  onPressed: () => context.go('/home'),
                  icon: const Icon(Icons.wb_sunny_outlined),
                  label: const Text('오늘 화면으로'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
