import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/session/session_boundary.dart';
import 'package:mongroo/features/chat/data/chat_repository.dart';
import 'package:mongroo/features/chat/domain/chat_models.dart';
import 'package:mongroo/features/chat/presentation/chat_controller.dart';

final _testIdentityProvider = StateProvider<int?>((ref) => 1);

class _FakeChatRepository extends ChatRepository {
  _FakeChatRepository() : super(Dio());

  @override
  Future<StartSessionResult> startSession({int? plantId}) async {
    return const StartSessionResult(
      session: ChatSession(
        id: 10,
        plantId: 20,
        reflectionStage: 'greeting',
        status: 'active',
        startedAt: null,
        lastMessageAt: null,
      ),
      reward: null,
      greeting: '안녕!',
    );
  }
}

void main() {
  test('계정 ID가 바뀌면 이전 계정의 대화 상태를 폐기한다', () async {
    final container = ProviderContainer(
      overrides: [
        authSessionIdentityProvider.overrideWith(
          (ref) => ref.watch(_testIdentityProvider),
        ),
        chatRepositoryProvider.overrideWithValue(_FakeChatRepository()),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionBoundaryProvider);
    await container.read(chatControllerProvider.notifier).startSession();
    expect(container.read(chatControllerProvider).hasSession, isTrue);

    container.read(_testIdentityProvider.notifier).state = 2;
    await Future<void>.delayed(Duration.zero);

    expect(container.read(chatControllerProvider).hasSession, isFalse);
    expect(container.read(chatControllerProvider).bubbles, isEmpty);
  });

  test('로그아웃은 화면 전환 뒤에 이전 계정 상태를 폐기한다', () async {
    final container = ProviderContainer(
      overrides: [
        authSessionIdentityProvider.overrideWith(
          (ref) => ref.watch(_testIdentityProvider),
        ),
        chatRepositoryProvider.overrideWithValue(_FakeChatRepository()),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionBoundaryProvider);
    await container.read(chatControllerProvider.notifier).startSession();
    expect(container.read(chatControllerProvider).hasSession, isTrue);

    container.read(_testIdentityProvider.notifier).state = null;
    await Future<void>.delayed(Duration.zero);
    expect(container.read(chatControllerProvider).hasSession, isTrue);

    await Future<void>.delayed(
      signedOutSessionPurgeDelay + const Duration(milliseconds: 50),
    );
    expect(container.read(chatControllerProvider).hasSession, isFalse);
    expect(container.read(chatControllerProvider).bubbles, isEmpty);
  });
}
