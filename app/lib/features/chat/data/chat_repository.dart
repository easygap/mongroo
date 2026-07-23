import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_providers.dart';
import '../../../core/error/api_exception.dart';
import '../domain/chat_models.dart';

class ChatRepository {
  ChatRepository(this._dio);

  final Dio _dio;

  Future<StartSessionResult> startSession({int? plantId}) => guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/chat/sessions',
          data: {if (plantId != null) 'plant_id': plantId},
        );
        return StartSessionResult.fromJson(response.data!);
      });

  Future<List<ChatMessage>> getMessages(int sessionId, {String? cursor}) =>
      guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/chat/sessions/$sessionId/messages',
          queryParameters: {if (cursor != null) 'cursor': cursor},
        );
        return ((response.data?['items'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ChatMessage.fromJson)
            .toList();
      });

  Future<SendMessageResult> sendMessage({
    required int sessionId,
    required String content,
    required String clientMessageId,
    required String idempotencyKey,
    bool retryFailed = false,
  }) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/chat/sessions/$sessionId/messages',
          data: {
            'content': content,
            'client_message_id': clientMessageId,
            if (retryFailed) 'retry_failed': true,
          },
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        );
        return SendMessageResult.fromJson(response.data!);
      });

  Future<ChatRun> getRun(int runId) => guardApi(() async {
        final response =
            await _dio.get<Map<String, dynamic>>('/chat/runs/$runId');
        return ChatRun.fromJson(response.data!);
      });
}

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(ref.watch(dioProvider)),
);
