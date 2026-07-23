import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_providers.dart';
import '../../../core/error/api_exception.dart';
import '../domain/plant.dart';

class PlantRepository {
  PlantRepository(this._dio);

  final Dio _dio;

  Future<ActivePlant?> getActivePlant() => guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>('/plants/me');
        final plantJson = response.data?['plant'];
        if (plantJson is! Map<String, dynamic>) return null;
        return ActivePlant.fromJson(plantJson);
      });

  Future<List<PlantSpecies>> getSpecies() => guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>('/plant-species');
        return ((response.data?['items'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(PlantSpecies.fromJson)
            .toList();
      });

  /// 수확. 성공 시 활성 식물은 비게 되고(active_plant: null),
  /// 새 식물은 POST /plants로 따로 심는다.
  Future<void> harvest({
    required int plantId,
    required String idempotencyKey,
  }) =>
      guardApi(() async {
        await _dio.post<Map<String, dynamic>>(
          '/plants/$plantId/harvest',
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        );
      });

  Future<ActivePlant> createPlant({int? speciesId, String? name}) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/plants',
          data: {
            if (speciesId != null) 'species_id': speciesId,
            if (name != null && name.isNotEmpty) 'name': name,
          },
        );
        return ActivePlant.fromJson(response.data!);
      });
}

final plantRepositoryProvider = Provider<PlantRepository>(
  (ref) => PlantRepository(ref.watch(dioProvider)),
);
