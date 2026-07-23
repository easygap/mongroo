import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_providers.dart';
import '../../../core/error/api_exception.dart';
import '../domain/mood_entry.dart';

/// 기분 기록 API. 위젯 테스트에서 fake로 바꿔 끼우기 위해 인터페이스로 둔다.
abstract class MoodRepository {
  Future<MoodCalendar> getCalendar({required int year, required int month});

  Future<List<MoodEntry>> getByDate(String date);

  Future<List<MoodEntry>> getByIds(List<int> ids);

  Future<MoodEntry> getById(int id);

  Future<MoodSaveResult> create({
    required int moodLevel,
    required List<String> emotionTags,
    required String? content,
    required String idempotencyKey,
  });

  /// PATCH /moods/{id}. changes에는 mood_level / emotion_tags / content /
  /// ai_emotion_override / ai_label_hidden 중 바꿀 필드만 담는다. 서버가
  /// edit_version을 제공한 기록은 expected_version도 함께 보내 충돌을 감지한다.
  Future<MoodSaveResult> patch(int id, Map<String, dynamic> changes);

  Future<void> delete(int id);
}

class ApiMoodRepository implements MoodRepository {
  ApiMoodRepository(this._dio);

  final Dio _dio;

  @override
  Future<MoodCalendar> getCalendar({required int year, required int month}) =>
      guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/moods/calendar',
          queryParameters: {'year': year, 'month': month},
        );
        return MoodCalendar.fromJson(response.data!);
      });

  @override
  Future<List<MoodEntry>> getByDate(String date) => guardApi(() async {
        final entries = <MoodEntry>[];
        String? cursor;
        // 하루 기록은 많지 않으므로 페이지를 끝까지 모은다. 상한은 방어용.
        for (var page = 0; page < 10; page++) {
          final response = await _dio.get<Map<String, dynamic>>(
            '/moods',
            queryParameters: {
              'date': date,
              if (cursor != null) 'cursor': cursor,
            },
          );
          final body = response.data!;
          entries.addAll(((body['items'] as List<dynamic>?) ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(MoodEntry.fromJson));
          cursor = body['next_cursor'] as String?;
          if (cursor == null) break;
        }
        return entries;
      });

  @override
  Future<List<MoodEntry>> getByIds(List<int> ids) async {
    final entries = <MoodEntry>[];
    for (final id in ids) {
      try {
        entries.add(await getById(id));
      } on ApiException catch (e) {
        // 삭제된 기록은 건너뛴다.
        if (e.statusCode == 404) continue;
        rethrow;
      }
    }
    return entries;
  }

  @override
  Future<MoodEntry> getById(int id) => guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>('/moods/$id');
        return MoodEntry.fromJson(response.data!);
      });

  @override
  Future<MoodSaveResult> create({
    required int moodLevel,
    required List<String> emotionTags,
    required String? content,
    required String idempotencyKey,
  }) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/moods',
          data: {
            'mood_level': moodLevel,
            if (emotionTags.isNotEmpty) 'emotion_tags': emotionTags,
            if (content != null && content.isNotEmpty) 'content': content,
          },
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        );
        return MoodSaveResult.fromJson(response.data!);
      });

  Future<MoodSaveResult> createDiary({
    required String content,
    required String idempotencyKey,
  }) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/moods',
          data: {'content': content},
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        );
        return MoodSaveResult.fromJson(response.data!);
      });

  @override
  Future<MoodSaveResult> patch(int id, Map<String, dynamic> changes) =>
      guardApi(() async {
        final response = await _dio.patch<Map<String, dynamic>>(
          '/moods/$id',
          data: changes,
        );
        return MoodSaveResult.fromJson(response.data!);
      });

  @override
  Future<void> delete(int id) => guardApi(() async {
        await _dio.delete<void>('/moods/$id');
      });
}

/// 기존 repository fake와의 하위 호환을 유지하면서 새 기록은 본문만
/// 저장한다. 실제 API 구현은 mood_level/emotion_tags를 전송하지 않는다.
extension DiaryMoodRepository on MoodRepository {
  Future<MoodSaveResult> createDiary({
    required String content,
    required String idempotencyKey,
  }) {
    final repository = this;
    if (repository is ApiMoodRepository) {
      return repository.createDiary(
        content: content,
        idempotencyKey: idempotencyKey,
      );
    }
    return repository.create(
      moodLevel: 3,
      emotionTags: const [],
      content: content,
      idempotencyKey: idempotencyKey,
    );
  }
}

final moodRepositoryProvider = Provider<MoodRepository>(
  (ref) => ApiMoodRepository(ref.watch(dioProvider)),
);
