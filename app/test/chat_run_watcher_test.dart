import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/api/sse_client.dart';
import 'package:mongroo/features/chat/data/chat_run_watcher.dart';
import 'package:mongroo/features/chat/domain/chat_models.dart';

class _ReplayMessageSseClient extends SseClient {
  _ReplayMessageSseClient() : super(Dio());

  int connections = 0;

  @override
  Stream<SseEvent> connect(String path, {CancelToken? cancelToken}) async* {
    connections++;
    yield const SseEvent(
      event: 'message',
      data: '{"message_id":42,"content":"같은 답변"}',
    );
    if (connections > 1) {
      yield const SseEvent(event: 'done', data: '{"run_id":7}');
    }
  }
}

class _MessageThenDisconnectSseClient extends SseClient {
  _MessageThenDisconnectSseClient() : super(Dio());

  int connections = 0;

  @override
  Stream<SseEvent> connect(String path, {CancelToken? cancelToken}) async* {
    connections++;
    if (connections == 1) {
      yield const SseEvent(
        event: 'message',
        data: '{"message_id":42,"content":"복구할 답변"}',
      );
      return;
    }
    throw StateError('연결 끊김');
  }
}

class _NeverEndingSseClient extends SseClient {
  _NeverEndingSseClient() : super(Dio());

  final started = Completer<void>();
  CancelToken? receivedToken;

  @override
  Stream<SseEvent> connect(String path, {CancelToken? cancelToken}) {
    receivedToken = cancelToken;
    if (cancelToken == null) {
      return Stream.error(StateError('CancelToken이 필요합니다.'));
    }
    final controller = StreamController<SseEvent>();
    controller.onListen = () {
      if (!started.isCompleted) started.complete();
      unawaited(cancelToken.whenCancel.then((_) async {
        if (!controller.isClosed) await controller.close();
      }));
    };
    controller.onCancel = () {
      if (!cancelToken.isCancelled) {
        cancelToken.cancel('test consumer canceled');
      }
    };
    return controller.stream;
  }
}

class _SseTimeoutClient extends SseClient {
  _SseTimeoutClient() : super(Dio());

  @override
  Stream<SseEvent> connect(String path, {CancelToken? cancelToken}) async* {
    yield const SseEvent(
      event: 'error',
      data: '{"run_id":7,"error_code":"SSE_TIMEOUT"}',
    );
  }
}

class _ConsumerCancelableSseClient extends SseClient {
  _ConsumerCancelableSseClient() : super(Dio());

  final started = Completer<void>();
  CancelToken? receivedToken;

  @override
  Stream<SseEvent> connect(String path, {CancelToken? cancelToken}) {
    receivedToken = cancelToken;
    final controller = StreamController<SseEvent>();
    controller.onListen = started.complete;
    controller.onCancel = () {
      if (cancelToken != null && !cancelToken.isCancelled) {
        cancelToken.cancel('test consumer canceled');
      }
    };
    return controller.stream;
  }
}

ChatRun _succeededRun() => const ChatRun(
      runId: 7,
      status: 'succeeded',
      message: ChatMessage(
        id: 42,
        role: 'plant',
        content: '복구할 답변',
        createdAt: null,
      ),
      errorCode: null,
    );

const _queuedRun = ChatRun(
  runId: 7,
  status: 'queued',
  message: null,
  errorCode: null,
);

void main() {
  test('message 뒤 done 전에 재연결돼도 같은 assistant message는 한 번만 전달한다', () async {
    final sse = _ReplayMessageSseClient();
    final watcher = ChatRunWatcher(
      sseClient: sse,
      fetchRun: (_) async => _succeededRun(),
      reconnectDelay: Duration.zero,
      totalTimeout: const Duration(milliseconds: 100),
    );

    final updates = await watcher.watch(7).toList();

    expect(updates.whereType<RunMessageReceived>(), hasLength(1));
    expect(updates.whereType<RunCompleted>(), hasLength(1));
    expect(sse.connections, 2);
  });

  test('60초 GET fallback도 이미 받은 assistant message를 다시 내보내지 않는다', () async {
    final sse = _MessageThenDisconnectSseClient();
    final watcher = ChatRunWatcher(
      sseClient: sse,
      fetchRun: (_) async => _succeededRun(),
      reconnectDelay: const Duration(milliseconds: 1),
      totalTimeout: const Duration(milliseconds: 12),
    );

    final updates = await watcher.watch(7).toList();

    expect(updates.whereType<RunMessageReceived>(), hasLength(1));
    expect(updates.whereType<RunCompleted>(), hasLength(1));
  });

  test('끝나지 않는 SSE도 hard deadline에 token을 취소하고 timed out으로 끝낸다', () async {
    final sse = _NeverEndingSseClient();
    final watcher = ChatRunWatcher(
      sseClient: sse,
      fetchRun: (_) async => _queuedRun,
      totalTimeout: const Duration(milliseconds: 20),
      reconnectDelay: Duration.zero,
    );

    final updates = await watcher.watch(7).toList();

    expect(updates.whereType<RunTimedOut>(), hasLength(1));
    expect(sse.receivedToken?.isCancelled, isTrue);
  });

  test('SSE_TIMEOUT 뒤 GET이 succeeded면 실패 없이 message와 completed로 복구한다',
      () async {
    final watcher = ChatRunWatcher(
      sseClient: _SseTimeoutClient(),
      fetchRun: (_) async => _succeededRun(),
    );

    final updates = await watcher.watch(7).toList();

    expect(updates.whereType<RunFailed>(), isEmpty);
    expect(updates.whereType<RunMessageReceived>(), hasLength(1));
    expect(updates.whereType<RunCompleted>(), hasLength(1));
  });

  test('SSE_TIMEOUT 뒤 GET도 queued면 RunTimedOut을 전달한다', () async {
    final watcher = ChatRunWatcher(
      sseClient: _SseTimeoutClient(),
      fetchRun: (_) async => _queuedRun,
    );

    final updates = await watcher.watch(7).toList();

    expect(updates.whereType<RunFailed>(), isEmpty);
    expect(updates.whereType<RunTimedOut>(), hasLength(1));
  });

  test('consumer가 watch를 취소하면 현재 SSE token도 취소한다', () async {
    final sse = _ConsumerCancelableSseClient();
    final watcher = ChatRunWatcher(
      sseClient: sse,
      fetchRun: (_) async => _queuedRun,
      totalTimeout: const Duration(minutes: 1),
    );

    final subscription = watcher.watch(7).listen((_) {});
    await sse.started.future;
    await subscription.cancel();

    expect(sse.receivedToken?.isCancelled, isTrue);
  });
}
