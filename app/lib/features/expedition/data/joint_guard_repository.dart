import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_providers.dart';
import '../../../core/error/api_exception.dart';
import '../domain/expedition_combat_models.dart';
import '../domain/joint_guard_models.dart';

/// 합동 수호전 API.
///
/// 판을 **만드는** 요청은 헤더의 `Idempotency-Key`가, 판 **안에서** 일어나는
/// 행동은 `client_action_id`가 지킨다. 서버의 다른 쓰기 경로와 같은 계약이다.
class JointGuardRepository {
  JointGuardRepository(this._dio);

  final Dio _dio;

  Future<JointGuardEntry> getEntry() => guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/adventure/joint-guard',
        );
        return JointGuardEntry.fromJson(response.data ?? const {});
      });

  Future<JointGuardRun?> getActive() => guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/adventure/joint-guard/active',
        );
        final data = response.data;
        if (data == null || data['run'] == null) return null;
        return JointGuardRun.fromJson(data);
      });

  Future<JointGuardRun> start({
    required String beastCode,
    required String difficulty,
    required List<Map<String, Object?>> formation,
    required String idempotencyKey,
  }) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/adventure/joint-guard',
          data: {
            'beast_code': beastCode,
            'difficulty': difficulty,
            'formation': formation,
          },
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        );
        return JointGuardRun.fromJson(response.data ?? const {});
      });

  Future<JointGuardRun> submitTurn({
    required int runId,
    required ExpeditionCombatCommand command,
    required int expectedRevision,
    required String clientActionId,
  }) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/adventure/joint-guard/$runId/turns',
          data: {
            'command': {
              'member_id': command.memberId,
              'action': command.action,
              if (command.choice != null) 'choice': command.choice,
            },
            'expected_revision': expectedRevision,
            'client_action_id': clientActionId,
          },
        );
        return JointGuardRun.fromJson(response.data ?? const {});
      });

  Future<JointGuardRun> swap({
    required int runId,
    required int outMemberId,
    required int inMemberId,
    required int expectedRevision,
    required String clientActionId,
  }) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/adventure/joint-guard/$runId/swap',
          data: {
            'out_member_id': outMemberId,
            'in_member_id': inMemberId,
            'expected_revision': expectedRevision,
            'client_action_id': clientActionId,
          },
        );
        return JointGuardRun.fromJson(response.data ?? const {});
      });
}

final jointGuardRepositoryProvider = Provider<JointGuardRepository>(
  (ref) => JointGuardRepository(ref.watch(dioProvider)),
);
