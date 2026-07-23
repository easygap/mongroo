import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_providers.dart';
import '../../../core/error/api_exception.dart';
import '../domain/daily_quest.dart';

class QuestRepository {
  QuestRepository(this._dio);

  final Dio _dio;

  Future<DailyQuestFeed> getToday() => guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>('/quests/today');
        return DailyQuestFeed.fromJson(response.data ?? const {});
      });

  Future<QuestCompletionResult> complete({
    required int userQuestId,
    required String idempotencyKey,
  }) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/user-quests/$userQuestId/complete',
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        );
        return QuestCompletionResult.fromJson(response.data ?? const {});
      });

  Future<DailyQuest> skip(int userQuestId) => guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/user-quests/$userQuestId/skip',
        );
        return DailyQuest.fromJson(
          (response.data?['user_quest'] as Map<String, dynamic>?) ?? const {},
        );
      });
}

final questRepositoryProvider = Provider<QuestRepository>(
  (ref) => QuestRepository(ref.watch(dioProvider)),
);
