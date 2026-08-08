import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_providers.dart';
import '../../../core/error/api_exception.dart';
import '../domain/expedition_models.dart';

class ExpeditionRepository {
  ExpeditionRepository(this._dio);

  final Dio _dio;

  Future<ExpeditionCatalog> getCatalog() => guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/adventure/expeditions/catalog',
        );
        return ExpeditionCatalog.fromJson(response.data ?? const {});
      });

  Future<List<ExpeditionRosterItem>> getRoster() => guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/adventure/expeditions/roster',
        );
        final items = response.data?['items'];
        if (items is! List) return const [];
        return items
            .whereType<Map<String, dynamic>>()
            .map(ExpeditionRosterItem.fromJson)
            .toList(growable: false);
      });

  Future<ExpeditionSnapshot?> getActive() => guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/adventure/expeditions/active',
        );
        final expedition = response.data?['expedition'];
        return expedition is Map<String, dynamic>
            ? ExpeditionSnapshot.fromJson(expedition)
            : null;
      });

  Future<ExpeditionStageMap> getStageMap() => guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/adventure/stages',
        );
        return ExpeditionStageMap.fromJson(response.data ?? const {});
      });

  Future<bool> markStageStorySeen({
    required String regionCode,
    required int stageNo,
  }) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/adventure/stages/$regionCode/$stageNo/story-seen',
        );
        return response.data?['story_seen'] == true;
      });

  Future<ExpeditionSnapshot> start({
    required String mode,
    required List<int> plantIds,
    required int guideCount,
    required String idempotencyKey,
    int? stageNo,
  }) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/adventure/expeditions',
          data: {
            'region_code': 'moss_archive',
            'mode': mode,
            'plant_ids': plantIds,
            'guide_count': guideCount,
            if (stageNo != null) 'stage_no': stageNo,
          },
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        );
        return ExpeditionSnapshot.fromJson(response.data ?? const {});
      });

  Future<ExpeditionSnapshot> move({
    required int runId,
    required String nodeCode,
    required int expectedRevision,
    required String clientActionId,
  }) =>
      _action(
        runId: runId,
        path: 'move',
        data: {'node_code': nodeCode},
        expectedRevision: expectedRevision,
        clientActionId: clientActionId,
      );

  Future<ExpeditionSnapshot> choose({
    required int runId,
    required String choiceCode,
    required int memberId,
    required int expectedRevision,
    required String clientActionId,
  }) =>
      _action(
        runId: runId,
        path: 'choices',
        data: {
          'choice_code': choiceCode,
          'acting_member_id': memberId,
        },
        expectedRevision: expectedRevision,
        clientActionId: clientActionId,
      );

  Future<ExpeditionSnapshot> useSkill({
    required int runId,
    required int memberId,
    required String skillType,
    String? modeCode,
    required int expectedRevision,
    required String clientActionId,
  }) =>
      _action(
        runId: runId,
        path: 'skills',
        data: {
          'member_id': memberId,
          'skill_type': skillType,
          if (modeCode != null) 'mode_code': modeCode,
        },
        expectedRevision: expectedRevision,
        clientActionId: clientActionId,
      );

  Future<ExpeditionSnapshot> resolveCombatTurn({
    required int runId,
    required List<ExpeditionCombatCommand> commands,
    bool partial = false,
    required int expectedRevision,
    required String clientActionId,
  }) =>
      _action(
        runId: runId,
        path: 'combat/turns',
        data: {
          'commands': commands
              .map((command) => command.toJson())
              .toList(growable: false),
          // 스테이지 개편의 순차 명령. 대원 한 명의 행동을 즉시 판정한다.
          if (partial) 'partial': true,
        },
        expectedRevision: expectedRevision,
        clientActionId: clientActionId,
      );

  Future<ExpeditionSnapshot> extract({
    required int runId,
    required int expectedRevision,
    required String clientActionId,
  }) =>
      _action(
        runId: runId,
        path: 'extract',
        data: const {},
        expectedRevision: expectedRevision,
        clientActionId: clientActionId,
      );

  Future<ExpeditionSnapshot> retreat({
    required int runId,
    required int expectedRevision,
    required String clientActionId,
  }) =>
      _action(
        runId: runId,
        path: 'retreat',
        data: const {},
        expectedRevision: expectedRevision,
        clientActionId: clientActionId,
      );

  Future<ExpeditionSnapshot> _action({
    required int runId,
    required String path,
    required Map<String, dynamic> data,
    required int expectedRevision,
    required String clientActionId,
  }) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/adventure/expeditions/$runId/$path',
          data: {
            ...data,
            'expected_revision': expectedRevision,
            'client_action_id': clientActionId,
          },
        );
        return ExpeditionSnapshot.fromJson(response.data ?? const {});
      });
}

final expeditionRepositoryProvider = Provider<ExpeditionRepository>(
  (ref) => ExpeditionRepository(ref.watch(dioProvider)),
);
