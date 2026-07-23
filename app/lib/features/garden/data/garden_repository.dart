import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_providers.dart';
import '../../../core/error/api_exception.dart';
import '../domain/garden_models.dart';

class GardenRepository {
  GardenRepository(this._dio);

  final Dio _dio;

  Future<ShopCatalog> getShopItems() => guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>('/shop/items');
        return ShopCatalog.fromJson(response.data ?? const {});
      });

  Future<ShopPurchaseResult> purchase({
    required int itemId,
    required String idempotencyKey,
  }) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/shop/items/$itemId/purchase',
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        );
        return ShopPurchaseResult.fromJson(response.data ?? const {});
      });

  Future<ShopPurchaseResult> claim({
    required int itemId,
    required String idempotencyKey,
  }) =>
      guardApi(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/shop/items/$itemId/claim',
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        );
        return ShopPurchaseResult.fromJson(response.data ?? const {});
      });

  Future<GardenCollection> getCollection() => guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>('/collection');
        return GardenCollection.fromJson(response.data ?? const {});
      });

  Future<FarmData> getFarm() => guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>('/farm');
        return FarmData.fromJson(response.data ?? const {});
      });

  Future<FarmLayout> updateFarm(FarmLayout layout) => guardApi(() async {
        final response = await _dio.put<Map<String, dynamic>>(
          '/farm/layout',
          data: layout.toUpdateJson(),
        );
        return FarmLayout.fromJson(
          (response.data?['layout'] as Map<String, dynamic>?) ?? const {},
        );
      });
}

final gardenRepositoryProvider = Provider<GardenRepository>(
  (ref) => GardenRepository(ref.watch(dioProvider)),
);
