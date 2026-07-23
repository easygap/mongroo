import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/api/sse_client.dart';
import 'package:mongroo/core/error/api_exception.dart';
import 'package:mongroo/features/chat/data/chat_repository.dart';
import 'package:mongroo/features/chat/data/chat_run_watcher.dart';
import 'package:mongroo/features/chat/domain/chat_models.dart';
import 'package:mongroo/features/chat/presentation/chat_controller.dart';

class _LostResponseChatRepository extends ChatRepository {
  _LostResponseChatRepository() : super(Dio());

  final List<String> clientMessageIds = [];
  final List<String> idempotencyKeys = [];
  final List<bool> retryFailedFlags = [];

  @override
  Future<StartSessionResult> startSession({int? plantId}) async {
    return const StartSessionResult(
      session: ChatSession(
        id: 1,
        plantId: 2,
        reflectionStage: 'greeting',
        status: 'active',
        startedAt: null,
        lastMessageAt: null,
      ),
      reward: null,
      greeting: '',
    );
  }

  @override
  Future<SendMessageResult> sendMessage({
    required int sessionId,
    required String content,
    required String clientMessageId,
    required String idempotencyKey,
    bool retryFailed = false,
  }) async {
    clientMessageIds.add(clientMessageId);
    idempotencyKeys.add(idempotencyKey);
    retryFailedFlags.add(retryFailed);
    if (clientMessageIds.length == 1) {
      throw const ApiException(
        code: 'NETWORK_ERROR',
        message: '응답을 받지 못했어요.',
      );
    }
    return const SendMessageResult(
      runId: null,
      userMessage: null,
      safetyAction: null,
    );
  }
}

class _TerminalFailureChatRepository extends ChatRepository {
  _TerminalFailureChatRepository() : super(Dio());

  final List<String> clientMessageIds = [];
  final List<String> idempotencyKeys = [];
  final List<bool> retryFailedFlags = [];

  @override
  Future<StartSessionResult> startSession({int? plantId}) async =>
      const StartSessionResult(
        session: ChatSession(
          id: 1,
          plantId: 2,
          reflectionStage: 'greeting',
          status: 'active',
          startedAt: null,
          lastMessageAt: null,
        ),
        reward: null,
        greeting: '',
      );

  @override
  Future<SendMessageResult> sendMessage({
    required int sessionId,
    required String content,
    required String clientMessageId,
    required String idempotencyKey,
    bool retryFailed = false,
  }) async {
    clientMessageIds.add(clientMessageId);
    idempotencyKeys.add(idempotencyKey);
    retryFailedFlags.add(retryFailed);
    return const SendMessageResult(
      runId: 11,
      userMessage: null,
      safetyAction: null,
    );
  }
}

class _DeferredSendRepository extends ChatRepository {
  _DeferredSendRepository() : super(Dio());

  final sendCompleter = Completer<SendMessageResult>();

  @override
  Future<StartSessionResult> startSession({int? plantId}) async =>
      const StartSessionResult(
        session: ChatSession(
          id: 1,
          plantId: 2,
          reflectionStage: 'greeting',
          status: 'active',
          startedAt: null,
          lastMessageAt: null,
        ),
        reward: null,
        greeting: '첫 인사',
      );

  @override
  Future<SendMessageResult> sendMessage({
    required int sessionId,
    required String content,
    required String clientMessageId,
    required String idempotencyKey,
    bool retryFailed = false,
  }) =>
      sendCompleter.future;
}

class _DeferredStartRepository extends ChatRepository {
  _DeferredStartRepository() : super(Dio());

  final starts = <Completer<StartSessionResult>>[];

  @override
  Future<StartSessionResult> startSession({int? plantId}) {
    final completer = Completer<StartSessionResult>();
    starts.add(completer);
    return completer.future;
  }
}

StartSessionResult _startResult(int id, String greeting) => StartSessionResult(
      session: ChatSession(
        id: id,
        plantId: 2,
        reflectionStage: 'greeting',
        status: 'active',
        startedAt: null,
        lastMessageAt: null,
      ),
      reward: null,
      greeting: greeting,
    );

class _TerminalThenSuccessWatcher extends ChatRunWatcher {
  _TerminalThenSuccessWatcher()
      : super(
          sseClient: SseClient(Dio()),
          fetchRun: (_) => throw UnimplementedError(),
        );

  int watches = 0;

  @override
  Stream<RunUpdate> watch(int runId) async* {
    watches++;
    if (watches == 1) {
      yield const RunFailed('GUARD_REJECTED');
      return;
    }
    yield const RunMessageReceived(messageId: 20, content: '다시 생각해 봤어.');
    yield const RunCompleted();
  }
}

class _DuplicateAssistantWatcher extends ChatRunWatcher {
  _DuplicateAssistantWatcher()
      : super(
          sseClient: SseClient(Dio()),
          fetchRun: (_) => throw UnimplementedError(),
        );

  @override
  Stream<RunUpdate> watch(int runId) async* {
    yield const RunMessageReceived(messageId: 20, content: '첫 답변');
    yield const RunMessageReceived(messageId: 21, content: '중복 답변');
    yield const RunCompleted();
  }
}

class _LeakyRunStream extends Stream<RunUpdate> {
  void Function(RunUpdate)? _onData;

  void add(RunUpdate update) => _onData?.call(update);

  @override
  StreamSubscription<RunUpdate> listen(
    void Function(RunUpdate)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    _onData = onData;
    return _LeakySubscription(this);
  }
}

/// cancel 뒤에도 이벤트를 잘못 전달하는 transport를 흉내 내 epoch 방어를 검증한다.
class _LeakySubscription implements StreamSubscription<RunUpdate> {
  _LeakySubscription(this.stream);

  final _LeakyRunStream stream;

  @override
  Future<void> cancel() async {
    // 의도적으로 listener를 제거하지 않는다.
  }

  @override
  void onData(void Function(RunUpdate)? handleData) =>
      stream._onData = handleData;

  @override
  void onError(Function? handleError) {}

  @override
  void onDone(void Function()? handleDone) {}

  @override
  void pause([Future<void>? resumeSignal]) {}

  @override
  void resume() {}

  @override
  bool get isPaused => false;

  @override
  Future<E> asFuture<E>([E? futureValue]) => Completer<E>().future;
}

class _LeakyWatcher extends ChatRunWatcher {
  _LeakyWatcher()
      : super(
          sseClient: SseClient(Dio()),
          fetchRun: (_) => throw UnimplementedError(),
        );

  final stream = _LeakyRunStream();

  @override
  Stream<RunUpdate> watch(int runId) => stream;
}

class _StaleRetryRepository extends _TerminalFailureChatRepository {
  @override
  Future<SendMessageResult> sendMessage({
    required int sessionId,
    required String content,
    required String clientMessageId,
    required String idempotencyKey,
    bool retryFailed = false,
  }) async {
    if (retryFailed) {
      clientMessageIds.add(clientMessageId);
      idempotencyKeys.add(idempotencyKey);
      retryFailedFlags.add(retryFailed);
      throw const ApiException(
        code: 'CHAT_RETRY_STALE',
        message: '이후 대화가 있어 재시도할 수 없습니다.',
        statusCode: 409,
      );
    }
    return super.sendMessage(
      sessionId: sessionId,
      content: content,
      clientMessageId: clientMessageId,
      idempotencyKey: idempotencyKey,
      retryFailed: retryFailed,
    );
  }
}

void main() {
  test('전송 응답 유실 후 재시도는 같은 논리 요청 ID를 재사용한다', () async {
    final repository = _LostResponseChatRepository();
    final container = ProviderContainer(
      overrides: [chatRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(chatControllerProvider.notifier).startSession();
    await container.read(chatControllerProvider.notifier).send('오늘은 지쳤어');
    expect(container.read(chatControllerProvider).failedContent, isNotNull);
    await container.read(chatControllerProvider.notifier).send('새 턴으로 건너뛰기');
    expect(repository.clientMessageIds, hasLength(1));

    await container.read(chatControllerProvider.notifier).retryFailed();

    expect(repository.clientMessageIds, hasLength(2));
    expect(repository.clientMessageIds[1], repository.clientMessageIds[0]);
    expect(repository.idempotencyKeys[1], repository.idempotencyKeys[0]);
    expect(repository.retryFailedFlags, [false, false]);
    expect(container.read(chatControllerProvider).userTurns, 1);
    expect(container.read(chatControllerProvider).bubbles, hasLength(1));
  });

  test('확정 실패 후 재시도는 본문 ID를 유지하고 새 멱등 키로 재큐잉한다', () async {
    final repository = _TerminalFailureChatRepository();
    final watcher = _TerminalThenSuccessWatcher();
    final container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repository),
        chatRunWatcherProvider.overrideWithValue(watcher),
      ],
    );
    addTearDown(container.dispose);

    await container.read(chatControllerProvider.notifier).startSession();
    await container.read(chatControllerProvider.notifier).send('오늘은 지쳤어');
    await Future<void>.delayed(Duration.zero);
    expect(container.read(chatControllerProvider).failedContent, '오늘은 지쳤어');

    await container.read(chatControllerProvider.notifier).retryFailed();
    await Future<void>.delayed(Duration.zero);

    expect(repository.clientMessageIds, hasLength(2));
    expect(repository.clientMessageIds[1], repository.clientMessageIds[0]);
    expect(repository.idempotencyKeys[1], isNot(repository.idempotencyKeys[0]));
    expect(repository.retryFailedFlags, [false, true]);
    expect(container.read(chatControllerProvider).userTurns, 1);
    expect(
      container
          .read(chatControllerProvider)
          .bubbles
          .map((bubble) => bubble.role),
      ['user', 'plant'],
    );
  });

  test('watcher가 서로 다른 ID의 답변을 재생해도 run당 식물 말풍선은 하나다', () async {
    final repository = _TerminalFailureChatRepository();
    final container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repository),
        chatRunWatcherProvider.overrideWithValue(_DuplicateAssistantWatcher()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(chatControllerProvider.notifier).startSession();
    await container.read(chatControllerProvider.notifier).send('한 번만 답해 줘');
    await Future<void>.delayed(Duration.zero);

    final plantBubbles = container
        .read(chatControllerProvider)
        .bubbles
        .where((bubble) => bubble.role == 'plant')
        .toList();
    expect(plantBubbles, hasLength(1));
    expect(plantBubbles.single.content, '첫 답변');
  });

  test('stale 재시도 충돌 뒤 다시 시도 버튼 상태를 제거한다', () async {
    final repository = _StaleRetryRepository();
    final container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repository),
        chatRunWatcherProvider.overrideWithValue(_TerminalThenSuccessWatcher()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(chatControllerProvider.notifier).startSession();
    await container.read(chatControllerProvider.notifier).send('실패할 이야기');
    await Future<void>.delayed(Duration.zero);
    expect(container.read(chatControllerProvider).failedContent, isNotNull);

    await container.read(chatControllerProvider.notifier).retryFailed();
    final callsAfterConflict = repository.clientMessageIds.length;
    expect(container.read(chatControllerProvider).failedContent, isNull);

    await container.read(chatControllerProvider.notifier).retryFailed();
    expect(repository.clientMessageIds, hasLength(callsAfterConflict));
  });

  test('종료한 세션의 늦은 watcher 이벤트는 새 UI 상태를 바꾸지 않는다', () async {
    final watcher = _LeakyWatcher();
    final container = ProviderContainer(
      overrides: [
        chatRepositoryProvider
            .overrideWithValue(_TerminalFailureChatRepository()),
        chatRunWatcherProvider.overrideWithValue(watcher),
      ],
    );
    addTearDown(container.dispose);

    await container.read(chatControllerProvider.notifier).startSession();
    await container.read(chatControllerProvider.notifier).send('곧 세션을 닫을게');
    container.read(chatControllerProvider.notifier).endSession();

    watcher.stream.add(
      const RunMessageReceived(messageId: 99, content: '취소 뒤 늦게 온 답변'),
    );

    final state = container.read(chatControllerProvider);
    expect(state.hasSession, isFalse);
    expect(state.bubbles, isEmpty);
  });

  test('send 대기 중 세션을 종료하면 늦은 202 응답을 무시한다', () async {
    final repository = _DeferredSendRepository();
    final watcher = _TerminalThenSuccessWatcher();
    final container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repository),
        chatRunWatcherProvider.overrideWithValue(watcher),
      ],
    );
    addTearDown(container.dispose);

    await container.read(chatControllerProvider.notifier).startSession();
    final send =
        container.read(chatControllerProvider.notifier).send('응답 전에 대화를 닫을게');
    await Future<void>.delayed(Duration.zero);

    container.read(chatControllerProvider.notifier).endSession();
    repository.sendCompleter.complete(
      const SendMessageResult(
        runId: 11,
        userMessage: null,
        safetyAction: null,
      ),
    );
    await send;
    await Future<void>.delayed(Duration.zero);

    final state = container.read(chatControllerProvider);
    expect(state.hasSession, isFalse);
    expect(state.bubbles, isEmpty);
    expect(state.userTurns, 0);
    expect(watcher.watches, 0);
  });

  test('종료 후 시작한 두 번째 세션보다 늦은 첫 start 응답을 무시한다', () async {
    final repository = _DeferredStartRepository();
    final container = ProviderContainer(
      overrides: [chatRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final first =
        container.read(chatControllerProvider.notifier).startSession();
    await Future<void>.delayed(Duration.zero);
    expect(repository.starts, hasLength(1));

    container.read(chatControllerProvider.notifier).endSession();
    final second =
        container.read(chatControllerProvider.notifier).startSession();
    await Future<void>.delayed(Duration.zero);
    expect(repository.starts, hasLength(2));

    repository.starts[1].complete(_startResult(2, '두 번째 인사'));
    await second;
    expect(container.read(chatControllerProvider).session?.id, 2);

    repository.starts[0].complete(_startResult(1, '늦은 첫 인사'));
    await first;

    final state = container.read(chatControllerProvider);
    expect(state.session?.id, 2);
    expect(state.bubbles.single.content, '두 번째 인사');
  });
}
