import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_providers.dart';
import '../../../core/error/api_exception.dart';
import '../domain/journey_models.dart';

/// 장거리 개척 API.
///
/// 개척을 **만드는** 요청과 구간을 **여는** 요청 모두 헤더의
/// `Idempotency-Key`가 지킨다. 구간 안에서 걷고 싸우는 것은 지금까지의 탐험
/// 경로 그대로라 여기에 없다.
class JourneyRepository {
  JourneyRepository(this._dio);

  final Dio _dio;

  Future<JourneyEntry> getEntry() => guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/adventure/journeys',
        );
        return JourneyEntry.fromJson(response.data ?? const {});
      });

  Future<Journey?> getActive() => guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/adventure/journeys/active',
        );
        final data = response.data;
        if (data == null || data['id'] == null) return null;
        return Journey.fromJson(data);
      });

  Future<Journey> start({
    required String directionCode,
    required String mode,
    required String idempotencyKey,
  }) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/adventure/journeys',
          data: {'direction_code': directionCode, 'mode': mode},
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        );
        return Journey.fromJson(response.data ?? const {});
      });

  /// 다음 구간을 연다. 돌아온 개척 상태만 쓴다 — 구간 run 자체는 기존 탐험
  /// 화면이 `/adventure/expeditions/active`로 다시 읽는다.
  Future<Journey> createLeg({
    required int journeyId,
    required String routeCode,
    required List<int> plantIds,
    required int guideCount,
    required int expectedRevision,
    required String idempotencyKey,
  }) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/adventure/journeys/$journeyId/legs',
          data: {
            'route_choice_code': routeCode,
            'plant_ids': plantIds,
            'guide_count': guideCount,
            'expected_revision': expectedRevision,
          },
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        );
        final data = response.data ?? const <String, dynamic>{};
        final journey = data['journey'];
        return Journey.fromJson(
          journey is Map<String, dynamic> ? journey : data,
        );
      });

  Future<Journey> returnHome({
    required int journeyId,
    required int expectedRevision,
    required String idempotencyKey,
  }) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/adventure/journeys/$journeyId/return',
          data: {'expected_revision': expectedRevision},
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        );
        return Journey.fromJson(response.data ?? const {});
      });
}

final journeyRepositoryProvider = Provider<JourneyRepository>(
  (ref) => JourneyRepository(ref.watch(dioProvider)),
);
