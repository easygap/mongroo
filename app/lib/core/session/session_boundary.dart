import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../../features/chat/presentation/chat_controller.dart';
import '../../features/expedition/presentation/expedition_controller.dart';
import '../../features/gallery/presentation/gallery_screen.dart';
import '../../features/garden/presentation/garden_controller.dart';
import '../../features/home/presentation/home_controller.dart';
import '../../features/mood/presentation/mood_providers.dart';
import '../../features/quest/presentation/quest_controller.dart';
import '../../features/report/presentation/report_controller.dart';

/// 인증 상태를 사용자 ID로 축약한다. 테스트에서는 이 경계만 독립적으로 대체한다.
final authSessionIdentityProvider = Provider<int?>((ref) {
  return ref.watch(
    authControllerProvider.select(
      (state) => state.status == AuthStatus.signedIn ? state.user?.id : null,
    ),
  );
});

/// 사용자 ID가 바뀔 때 메모리에 남은 사용자 전용 화면 상태를 모두 폐기한다.
///
/// `StatefulShellRoute.indexedStack`는 탭 화면을 의도적으로 보존하므로 로그아웃만
/// 처리하면 다음 계정에 이전 사용자의 데이터가 노출될 수 있다. 앱 루트에서 이
/// provider를 watch해 계정 경계를 한곳에서 관리한다. 일반 refresh는 ID가
/// 유지되므로 화면 상태를 불필요하게 버리지 않는다.
final sessionBoundaryProvider = Provider<void>((ref) {
  ref.listen<int?>(authSessionIdentityProvider, (previous, next) {
    if (previous == next) return;

    ref.invalidate(homeControllerProvider);
    ref.invalidate(plantReactionProvider);
    ref.invalidate(chatControllerProvider);
    ref.invalidate(expeditionControllerProvider);
    ref.invalidate(questControllerProvider);
    ref.invalidate(shopControllerProvider);
    ref.invalidate(collectionControllerProvider);
    ref.invalidate(farmControllerProvider);
    ref.invalidate(galleryControllerProvider);
    ref.invalidate(reportControllerProvider);
    ref.invalidate(moodCalendarProvider);
    ref.invalidate(dayEntriesProvider);
    ref.invalidate(moodDetailProvider);
  });
});
