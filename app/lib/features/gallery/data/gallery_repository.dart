import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_providers.dart';
import '../../../core/error/api_exception.dart';
import '../domain/harvested_plant.dart';

enum MuseumMode { recent, featured, archive }

extension MuseumModeApi on MuseumMode {
  String get apiValue => name;
}

class HarvestedPage {
  const HarvestedPage({required this.items, required this.nextCursor});

  final List<HarvestedPlant> items;
  final String? nextCursor;
}

class MuseumPage {
  const MuseumPage({
    required this.items,
    required this.mode,
    this.limit = 10,
    this.maxFeatured = 10,
  });

  final List<HarvestedPlant> items;
  final MuseumMode mode;
  final int limit;
  final int maxFeatured;
}

class MuseumFeatureResult {
  const MuseumFeatureResult({
    this.plant,
    this.featuredCount,
    this.maxFeatured = 10,
  });

  final HarvestedPlant? plant;
  final int? featuredCount;
  final int maxFeatured;
}

class GalleryRepository {
  GalleryRepository(this._dio);

  final Dio _dio;

  /// 최신 박물관 API를 우선 사용하고, 아직 배포되지 않은 서버에서는 기존 수확
  /// 목록을 읽기 전용으로 보여 준다. 선택 저장은 최신 API에서만 가능하다.
  Future<MuseumPage> getMuseum({
    MuseumMode mode = MuseumMode.recent,
    int limit = 10,
  }) async {
    final safeLimit = limit.clamp(1, 10).toInt();
    try {
      return await guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/plants/museum',
          queryParameters: {'mode': mode.apiValue, 'limit': safeLimit},
        );
        final body = response.data ?? const <String, dynamic>{};
        return MuseumPage(
          items: _plantItems(body['items']).take(safeLimit).toList(),
          mode: _mode(body['mode'], fallback: mode),
          limit: _int(body['limit'], fallback: safeLimit),
          maxFeatured: _int(body['max_featured'], fallback: 10),
        );
      });
    } on ApiException catch (error) {
      if (error.statusCode != 404 && error.statusCode != 405) rethrow;
      final legacy = await getHarvested();
      final filtered = mode == MuseumMode.featured
          ? legacy.items.where((plant) => plant.museumFeatured)
          : legacy.items;
      return MuseumPage(
        items: filtered.take(safeLimit).toList(),
        mode: mode,
        limit: safeLimit,
      );
    }
  }

  Future<MuseumFeatureResult> setFeatured({
    required int plantId,
    required bool isFeatured,
  }) =>
      guardApi(() async {
        final response = await _dio.patch<Map<String, dynamic>>(
          '/plants/$plantId/museum',
          data: {'is_featured': isFeatured},
        );
        final body = response.data ?? const <String, dynamic>{};
        final rawPlant = body['plant'];
        final plantJson = rawPlant is Map
            ? rawPlant.map(
                (key, value) => MapEntry(key.toString(), value),
              )
            : const <String, dynamic>{};
        return MuseumFeatureResult(
          plant: plantJson.containsKey('id') &&
                  plantJson.containsKey('name') &&
                  plantJson.containsKey('species')
              ? HarvestedPlant.fromJson(plantJson)
              : null,
          featuredCount: body['featured_count'] == null
              ? null
              : _int(body['featured_count']),
          maxFeatured: _int(body['max_featured'], fallback: 10),
        );
      });

  /// 이전 화면·fixture와의 호환을 위해 남겨 둔 수확 목록 API.
  Future<HarvestedPage> getHarvested({String? cursor}) => guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/plants',
          queryParameters: {
            'status': 'harvested',
            if (cursor != null) 'cursor': cursor,
          },
        );
        final body = response.data ?? const <String, dynamic>{};
        return HarvestedPage(
          items: _plantItems(body['items']).toList(),
          nextCursor: body['next_cursor'] as String?,
        );
      });
}

Iterable<HarvestedPlant> _plantItems(Object? value) sync* {
  if (value is! List) return;
  for (final item in value) {
    if (item is Map) {
      yield HarvestedPlant.fromJson(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
  }
}

MuseumMode _mode(Object? value, {required MuseumMode fallback}) =>
    value?.toString() == MuseumMode.featured.apiValue
        ? MuseumMode.featured
        : value?.toString() == MuseumMode.recent.apiValue
            ? MuseumMode.recent
            : fallback;

int _int(Object? value, {int fallback = 0}) => switch (value) {
      int number => number,
      num number => number.toInt(),
      String text => int.tryParse(text) ?? fallback,
      _ => fallback,
    };

final galleryRepositoryProvider = Provider<GalleryRepository>(
  (ref) => GalleryRepository(ref.watch(dioProvider)),
);
