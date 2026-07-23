import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/core/api/sse_client.dart';

void main() {
  group('SseParser', () {
    test('빈 줄로 구분된 이벤트를 순서대로 분리한다', () {
      final parser = SseParser();
      final events = parser.addChunk(
        'event: status\n'
        'data: {"run_id": 7, "status": "generating"}\n'
        '\n'
        'event: message\n'
        'data: {"message_id": 42, "content": "안녕"}\n'
        '\n',
      );

      expect(events, hasLength(2));
      expect(events[0].event, 'status');
      expect(events[0].data, '{"run_id": 7, "status": "generating"}');
      expect(events[1].event, 'message');
      expect(events[1].data, '{"message_id": 42, "content": "안녕"}');
    });

    test('event 필드가 없으면 기본 이벤트명 message를 쓴다', () {
      final parser = SseParser();
      final events = parser.addChunk('data: hello\n\n');

      expect(events, hasLength(1));
      expect(events.single.event, 'message');
      expect(events.single.data, 'hello');
    });

    test('heartbeat 주석(:hb)은 이벤트를 만들지 않는다', () {
      final parser = SseParser();
      final events = parser.addChunk(':hb\n\n:hb\n');

      expect(events, isEmpty);
    });

    test('이벤트 사이에 낀 주석을 무시하고 이벤트만 조립한다', () {
      final parser = SseParser();
      final events = parser.addChunk(
        'event: status\n'
        ':hb\n'
        'data: {"status": "queued"}\n'
        '\n',
      );

      expect(events, hasLength(1));
      expect(events.single.event, 'status');
      expect(events.single.data, '{"status": "queued"}');
    });

    test('청크 경계에서 잘린 줄을 버퍼에 모아 조립한다', () {
      final parser = SseParser();
      final collected = <SseEvent>[
        ...parser.addChunk('eve'),
        ...parser.addChunk('nt: done\nda'),
        ...parser.addChunk('ta: {"run_id"'),
        ...parser.addChunk(': 7}\n'),
      ];
      expect(collected, isEmpty, reason: '빈 줄 전에는 이벤트가 확정되지 않는다');

      collected.addAll(parser.addChunk('\n'));
      expect(collected, hasLength(1));
      expect(collected.single.event, 'done');
      expect(collected.single.data, '{"run_id": 7}');
    });

    test('data가 여러 줄이면 개행으로 잇는다', () {
      final parser = SseParser();
      final events = parser.addChunk(
        'event: message\n'
        'data: 첫 줄\n'
        'data: 둘째 줄\n'
        '\n',
      );

      expect(events.single.data, '첫 줄\n둘째 줄');
    });

    test('CRLF 줄바꿈도 처리한다', () {
      final parser = SseParser();
      final events = parser.addChunk(
        'event: status\r\ndata: ok\r\n\r\n',
      );

      expect(events, hasLength(1));
      expect(events.single.event, 'status');
      expect(events.single.data, 'ok');
    });

    test('연속된 빈 줄은 빈 이벤트를 만들지 않는다', () {
      final parser = SseParser();
      final events = parser.addChunk('\n\n\ndata: x\n\n\n\n');

      expect(events, hasLength(1));
      expect(events.single.data, 'x');
    });
  });
}
