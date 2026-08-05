import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_providers.dart';
import '../../../core/error/api_exception.dart';
import '../domain/adventure_models.dart';

class AdventureRepository {
  AdventureRepository(this._dio);

  final Dio _dio;

  Future<AdventureState> getState() => guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>('/adventure');
        return AdventureState.fromJson(response.data ?? const {});
      });

  Future<AdventureActionResult> startPatrol({
    required String routeCode,
    required String idempotencyKey,
  }) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/adventure/patrols',
          data: {'route_code': routeCode},
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        );
        return AdventureActionResult.fromJson(response.data ?? const {});
      });

  Future<AdventureActionResult> claimPatrol({
    required int patrolId,
    required String idempotencyKey,
  }) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/adventure/patrols/$patrolId/claim',
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        );
        return AdventureActionResult.fromJson(response.data ?? const {});
      });

  Future<AdventureActionResult> runDungeon({
    required String dungeonCode,
    required String approachCode,
    required String idempotencyKey,
  }) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/adventure/dungeons/$dungeonCode/run',
          data: {'approach_code': approachCode},
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        );
        return AdventureActionResult.fromJson(response.data ?? const {});
      });

  Future<AdventureActionResult> completeResearch({
    required String projectCode,
    required String idempotencyKey,
  }) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/adventure/research/$projectCode/complete',
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        );
        return AdventureActionResult.fromJson(response.data ?? const {});
      });

  Future<AdventureActionResult> claimWeeklyGoal({
    required String goalCode,
    required String idempotencyKey,
  }) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/adventure/weekly-goals/$goalCode/claim',
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        );
        return AdventureActionResult.fromJson(response.data ?? const {});
      });

  Future<AdventureActionResult> donateItem({
    required String itemCode,
    required String idempotencyKey,
  }) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/adventure/donations',
          data: {'item_code': itemCode},
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        );
        return AdventureActionResult.fromJson(response.data ?? const {});
      });
}

final adventureRepositoryProvider = Provider<AdventureRepository>(
  (ref) => AdventureRepository(ref.watch(dioProvider)),
);
