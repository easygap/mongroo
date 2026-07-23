import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_providers.dart';
import '../../../core/error/api_exception.dart';
import '../domain/report.dart';

class ReportRepository {
  ReportRepository(this._dio);

  final Dio _dio;

  /// 같은 입력이면 200 기존 리포트, 새 입력이면 202 pending 리포트.
  Future<Report> create({
    required String periodType,
    required String periodStart,
    required String idempotencyKey,
  }) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/reports',
          data: {'period_type': periodType, 'period_start': periodStart},
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        );
        return _unwrap(response.data!);
      });

  Future<Report> getById(int id) => guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>('/reports/$id');
        return _unwrap(response.data!);
      });

  /// 202 응답이 {report: {...}}로 감싸져 올 수 있어 양쪽 모두 허용한다.
  Report _unwrap(Map<String, dynamic> body) {
    final inner = body['report'];
    if (inner is Map<String, dynamic>) return Report.fromJson(inner);
    return Report.fromJson(body);
  }
}

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(ref.watch(dioProvider)),
);
