import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_providers.dart';
import '../../../core/api/sse_client.dart';
import '../domain/chat_models.dart';
import 'chat_repository.dart';

class _WatchCancellation {
  CancelToken? _activeToken;
  bool _consumerCanceled = false;

  bool get consumerCanceled => _consumerCanceled;

  void attach(CancelToken token) {
    _activeToken = token;
    if (_consumerCanceled && !token.isCancelled) {
      token.cancel('Chat run watcher consumer canceled');
    }
  }

  void detach(CancelToken token) {
    if (identical(_activeToken, token)) _activeToken = null;
  }

  void cancelActive(String reason) {
    final token = _activeToken;
    if (token != null && !token.isCancelled) token.cancel(reason);
  }

  void cancelConsumer() {
    _consumerCanceled = true;
    cancelActive('Chat run watcher consumer canceled');
  }
}

/// chat run의 SSE 구독을 감싸는 감시자.
///
/// - GET /chat/runs/{id}/events를 구독하고 status/message/done/error를 매핑한다.
/// - 25초 무이벤트(SseIdleTimeoutException)나 연결 오류면 재연결한다.
/// - 전체 60초를 넘으면 GET /chat/runs/{id} 단건 조회로 복구를 시도하고,
///   열린 SSE도 CancelToken으로 중단한다. 그래도 terminal이 아니면 RunTimedOut.
class ChatRunWatcher {
  ChatRunWatcher({
    required SseClient sseClient,
    required Future<ChatRun> Function(int runId) fetchRun,
    Duration totalTimeout = const Duration(seconds: 60),
    Duration reconnectDelay = const Duration(milliseconds: 800),
  })  : _sseClient = sseClient,
        _fetchRun = fetchRun,
        _totalTimeout = totalTimeout,
        _reconnectDelay = reconnectDelay;

  final SseClient _sseClient;
  final Future<ChatRun> Function(int runId) _fetchRun;
  final Duration _totalTimeout;
  final Duration _reconnectDelay;

  /// 구독 취소 시 내부 async*가 다음 이벤트를 기다리지 않도록 HTTP 토큰부터 끊는다.
  /// 이 래퍼가 없으면 끝나지 않는 SSE의 `await for`와 바깥 구독 취소가 서로를
  /// 기다리는 순환 대기가 생길 수 있다.
  Stream<RunUpdate> watch(int runId) {
    final cancellation = _WatchCancellation();
    StreamSubscription<RunUpdate>? subscription;
    late final StreamController<RunUpdate> controller;

    controller = StreamController<RunUpdate>(
      onListen: () {
        subscription = _watchCore(runId, cancellation).listen(
          (update) {
            if (!controller.isClosed) controller.add(update);
          },
          onError: (Object error, StackTrace stack) {
            if (!controller.isClosed) controller.addError(error, stack);
          },
          onDone: () {
            if (!controller.isClosed) unawaited(controller.close());
          },
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () {
        cancellation.cancelConsumer();
        // 토큰 취소가 실제 HTTP 스트림을 닫도록 먼저 요청한 뒤, 내부 async*
        // 정리는 백그라운드에서 마친다. 여기서 내부 cancel 완료를 기다리면
        // 일부 스트림 구현은 서로의 종료를 기다리는 순환 대기가 될 수 있다.
        final activeSubscription = subscription;
        if (activeSubscription != null) {
          unawaited(activeSubscription.cancel());
        }
      },
    );
    return controller.stream;
  }

  Stream<RunUpdate> _watchCore(
    int runId,
    _WatchCancellation cancellation,
  ) async* {
    final stopwatch = Stopwatch()..start();
    final deliveredMessageKeys = <String>{};
    final deadlineReached = Completer<void>();
    var fallbackRequested = false;

    void reachDeadline() {
      if (!deadlineReached.isCompleted) deadlineReached.complete();
      cancellation.cancelActive('Chat run watcher total deadline');
    }

    final deadlineTimer = Timer(_totalTimeout, reachDeadline);

    try {
      while (!cancellation.consumerCanceled &&
          !deadlineReached.isCompleted &&
          stopwatch.elapsed < _totalTimeout) {
        var shouldDelayBeforeReconnect = false;
        final cancelToken = CancelToken();
        cancellation.attach(cancelToken);
        try {
          await for (final event in _sseClient.connect(
            '/chat/runs/$runId/events',
            cancelToken: cancelToken,
          )) {
            switch (event.event) {
              case 'status':
                final status = _decodeField(event.data, 'status');
                if (status == 'generating' || status == 'queued') {
                  yield const RunGenerating();
                }
              case 'message':
                final decoded = _decode(event.data);
                final update = RunMessageReceived(
                  messageId: (decoded['message_id'] as int?) ?? 0,
                  content: (decoded['content'] as String?) ?? '',
                );
                if (deliveredMessageKeys.add(_messageKey(update))) {
                  yield update;
                }
              case 'done':
                if (deliveredMessageKeys.isEmpty) {
                  // message 이벤트를 놓친 재연결 등 — 단건 조회로 보강한다.
                  final recovered = await _recoverFromRun(runId);
                  if (recovered != null &&
                      deliveredMessageKeys.add(_messageKey(recovered))) {
                    yield recovered;
                  }
                }
                yield const RunCompleted();
                return;
              case 'error':
                if (_decodeField(event.data, 'error_code') == 'SSE_TIMEOUT') {
                  // 서버는 생성을 계속한다. 실패 UI 대신 즉시 단건 조회로 복구한다.
                  fallbackRequested = true;
                  break;
                }
                yield await _failureFromRun(runId, event.data);
                return;
            }
            if (fallbackRequested) break;
          }
          // 이벤트 스트림이 서버 측에서 종료됨 - 재연결.
          shouldDelayBeforeReconnect = !fallbackRequested;
        } on SseIdleTimeoutException {
          // heartbeat까지 끊긴 상태 - 즉시 재연결.
        } catch (_) {
          if (!deadlineReached.isCompleted && !cancellation.consumerCanceled) {
            shouldDelayBeforeReconnect = true;
          }
        } finally {
          cancellation.detach(cancelToken);
          if (!cancelToken.isCancelled) {
            cancelToken.cancel('SSE connection finished');
          }
        }
        if (fallbackRequested ||
            deadlineReached.isCompleted ||
            cancellation.consumerCanceled) {
          break;
        }
        if (shouldDelayBeforeReconnect) {
          await Future.any<void>([
            Future<void>.delayed(_reconnectDelay),
            deadlineReached.future,
          ]);
        }
      }
    } finally {
      deadlineTimer.cancel();
      cancellation.cancelActive('Chat run watcher finished');
    }

    if (cancellation.consumerCanceled) return;

    // 60초 초과: 폴백 단건 조회.
    try {
      final run = await _fetchRun(runId);
      if (run.status == 'succeeded' && run.message != null) {
        final recovered = RunMessageReceived(
          messageId: run.message!.id,
          content: run.message!.content,
        );
        if (deliveredMessageKeys.add(_messageKey(recovered))) {
          yield recovered;
        }
        yield const RunCompleted();
        return;
      }
      if (run.status == 'failed') {
        yield RunFailed(run.errorCode);
        return;
      }
    } catch (_) {
      // 조회 실패도 timeout으로 처리한다.
    }
    yield const RunTimedOut();
  }

  /// SSE 재연결과 GET 복구가 같은 메시지를 다시 전달해도 한 번만 노출한다.
  /// 정상 응답은 DB id가 양수이며, 방어적으로 id가 없는 이벤트는 본문을 쓴다.
  String _messageKey(RunMessageReceived update) => update.messageId > 0
      ? 'id:${update.messageId}'
      : 'content:${update.content}';

  Future<RunMessageReceived?> _recoverFromRun(int runId) async {
    try {
      final run = await _fetchRun(runId);
      final message = run.message;
      if (run.status == 'succeeded' && message != null) {
        return RunMessageReceived(
            messageId: message.id, content: message.content);
      }
    } catch (_) {
      // 보강 실패는 무시하고 done만 전달한다.
    }
    return null;
  }

  Future<RunUpdate> _failureFromRun(int runId, String eventData) async {
    final decoded = _decode(eventData);
    final inlineCode = decoded['error_code'] as String?;
    if (inlineCode != null) return RunFailed(inlineCode);
    try {
      final run = await _fetchRun(runId);
      return RunFailed(run.errorCode);
    } catch (_) {
      return const RunFailed(null);
    }
  }

  Map<String, dynamic> _decode(String data) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // 형식이 어긋난 이벤트 본문은 빈 값으로 취급한다.
    }
    return const {};
  }

  String? _decodeField(String data, String field) =>
      _decode(data)[field] as String?;
}

final chatRunWatcherProvider = Provider<ChatRunWatcher>((ref) {
  final repository = ref.watch(chatRepositoryProvider);
  return ChatRunWatcher(
    sseClient: ref.watch(sseClientProvider),
    fetchRun: repository.getRun,
  );
});
