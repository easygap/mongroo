import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

/// text/event-stream 이벤트 하나. event 필드가 없으면 기본값 "message".
class SseEvent {
  const SseEvent({required this.event, required this.data});

  final String event;
  final String data;

  @override
  String toString() => 'SseEvent($event)';
}

/// 25초 동안 아무 데이터(heartbeat 포함)가 없을 때 던지는 예외.
class SseIdleTimeoutException implements Exception {
  const SseIdleTimeoutException();

  @override
  String toString() => 'SSE idle timeout';
}

/// 청크 단위로 들어오는 SSE 텍스트를 이벤트로 조립하는 파서.
///
/// - `event:` / `data:` 필드를 해석하고 빈 줄에서 이벤트를 확정한다.
/// - `:`로 시작하는 주석(`:hb` heartbeat)은 무시한다.
/// - 줄이 청크 경계에서 잘려 들어와도 버퍼에 모아 조립한다.
class SseParser {
  String _pending = '';
  String? _eventName;
  final List<String> _dataLines = [];

  List<SseEvent> addChunk(String chunk) {
    final events = <SseEvent>[];
    _pending += chunk;
    while (true) {
      final newline = _pending.indexOf('\n');
      if (newline < 0) break;
      var line = _pending.substring(0, newline);
      _pending = _pending.substring(newline + 1);
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      final event = _processLine(line);
      if (event != null) events.add(event);
    }
    return events;
  }

  SseEvent? _processLine(String line) {
    if (line.isEmpty) {
      if (_eventName == null && _dataLines.isEmpty) return null;
      final event = SseEvent(
        event: _eventName ?? 'message',
        data: _dataLines.join('\n'),
      );
      _eventName = null;
      _dataLines.clear();
      return event;
    }
    if (line.startsWith(':')) return null; // 주석(heartbeat)

    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);

    switch (field) {
      case 'event':
        _eventName = value;
      case 'data':
        _dataLines.add(value);
      default:
        // id, retry 등은 사용하지 않는다.
        break;
    }
    return null;
  }
}

/// dio 스트림 응답 기반 SSE 클라이언트.
///
/// heartbeat 주석을 포함한 어떤 수신이든 idle 타이머를 초기화하고,
/// [idleTimeout] 동안 완전히 조용하면 [SseIdleTimeoutException]으로 끊는다.
/// 재연결과 전체 timeout 정책은 호출부(예: ChatRunWatcher)가 담당한다.
class SseClient {
  SseClient(this._dio);

  // 서버 heartbeat(15초)에 네트워크 지연 여유 10초를 더한다.
  static const Duration idleTimeout = Duration(seconds: 25);

  final Dio _dio;

  Stream<SseEvent> connect(String path, {CancelToken? cancelToken}) {
    final controller = StreamController<SseEvent>();
    StreamSubscription<String>? subscription;
    Timer? idleTimer;

    void stop() {
      idleTimer?.cancel();
      subscription?.cancel();
      if (cancelToken != null && !cancelToken.isCancelled) {
        cancelToken.cancel('SSE consumer canceled');
      }
    }

    Future<void> open() async {
      try {
        final response = await _dio.get<ResponseBody>(
          path,
          options: Options(
            responseType: ResponseType.stream,
            receiveTimeout: Duration.zero,
            headers: {'Accept': 'text/event-stream'},
          ),
          cancelToken: cancelToken,
        );
        final body = response.data;
        if (body == null) {
          controller.addError(StateError('SSE 응답 본문이 비어 있음'));
          await controller.close();
          return;
        }

        final parser = SseParser();

        void resetIdle() {
          idleTimer?.cancel();
          idleTimer = Timer(idleTimeout, () {
            subscription?.cancel();
            if (!controller.isClosed) {
              controller.addError(const SseIdleTimeoutException());
              controller.close();
            }
            if (cancelToken != null && !cancelToken.isCancelled) {
              cancelToken.cancel('SSE idle timeout');
            }
          });
        }

        resetIdle();
        subscription =
            body.stream.cast<List<int>>().transform(utf8.decoder).listen(
          (chunk) {
            resetIdle();
            for (final event in parser.addChunk(chunk)) {
              if (!controller.isClosed) controller.add(event);
            }
          },
          onError: (Object error, StackTrace stack) {
            idleTimer?.cancel();
            if (!controller.isClosed) {
              controller.addError(error, stack);
              controller.close();
            }
          },
          onDone: () {
            idleTimer?.cancel();
            if (!controller.isClosed) controller.close();
          },
          cancelOnError: true,
        );
      } catch (error, stack) {
        if (!controller.isClosed) {
          controller.addError(error, stack);
          await controller.close();
        }
      }
    }

    controller.onListen = open;
    controller.onCancel = stop;
    return controller.stream;
  }
}
