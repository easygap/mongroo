import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/features/gallery/data/gallery_repository.dart';
import 'package:mongroo/features/gallery/domain/harvested_plant.dart';

class _FakeHttpAdapter implements HttpClientAdapter {
  _FakeHttpAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body, {int status = 200}) => ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  test('최근 박물관은 mode와 최대 10 limit을 보내고 감정 스냅샷을 읽는다', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://fake.local/api/v1'));
    late RequestOptions request;
    dio.httpClientAdapter = _FakeHttpAdapter((options) async {
      request = options;
      return _json('''
        {
          "items": [{
            "id": 3,
            "name": "달이",
            "species": {"id": 2, "code": "cactus", "name": "선인장"},
            "exp": 1100,
            "final_form": "moonlit",
            "museum_featured": false,
            "emotion_profile": {
              "version": 1,
              "total": 2,
              "counts": {"anxiety": 2},
              "ratios": {"anxiety": 1.0}
            }
          }],
          "mode": "recent",
          "limit": 10,
          "max_featured": 10
        }
      ''');
    });

    final page = await GalleryRepository(dio).getMuseum(limit: 99);

    expect(request.path, '/plants/museum');
    expect(request.queryParameters, {'mode': 'recent', 'limit': 10});
    expect(page.items, hasLength(1));
    expect(page.items.single.finalForm, PlantFinalForm.moonlit);
    expect(
      page.items.single.emotionProfile.ratioFor(PlantEmotion.anxiety),
      1,
    );
  });

  test('대표 전시 변경은 PATCH 계약과 서버 저장 결과를 그대로 반영한다', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://fake.local/api/v1'));
    late RequestOptions request;
    dio.httpClientAdapter = _FakeHttpAdapter((options) async {
      request = options;
      return _json('''
        {
          "plant": {
            "id": 3,
            "name": "달이",
            "species": {"id": 2, "code": "cactus", "name": "선인장"},
            "exp": 1100,
            "final_form": "moonlit",
            "museum_featured": true,
            "emotion_profile": {"version": 1, "total": 0, "counts": {}, "ratios": {}}
          },
          "featured_count": 1,
          "max_featured": 10
        }
      ''');
    });

    final result = await GalleryRepository(dio).setFeatured(
      plantId: 3,
      isFeatured: true,
    );

    expect(request.method, 'PATCH');
    expect(request.path, '/plants/3/museum');
    expect(request.data, {'is_featured': true});
    expect(result.plant?.museumFeatured, isTrue);
    expect(result.featuredCount, 1);
    expect(result.maxFeatured, 10);
  });

  test('박물관 API가 없는 이전 서버에서는 수확 목록으로 안전하게 대체한다', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://fake.local/api/v1'));
    final paths = <String>[];
    dio.httpClientAdapter = _FakeHttpAdapter((options) async {
      paths.add(options.path);
      if (options.path == '/plants/museum') {
        return _json(
          '{"code":"NOT_FOUND","message":"없음","details":{}}',
          status: 404,
        );
      }
      return _json('''
        {
          "items": [{
            "id": 9,
            "name": "옛 식물",
            "species": {"id": 1, "code": "sunflower", "name": "해바라기"},
            "exp": 1000
          }],
          "next_cursor": null
        }
      ''');
    });

    final page = await GalleryRepository(dio).getMuseum();

    expect(paths, ['/plants/museum', '/plants']);
    expect(page.items.single.name, '옛 식물');
    expect(page.items.single.finalForm, PlantFinalForm.mosaic);
  });

  test('전체 수확 목록은 cursor를 보내고 다음 cursor를 돌려준다', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://fake.local/api/v1'));
    late RequestOptions request;
    dio.httpClientAdapter = _FakeHttpAdapter((options) async {
      request = options;
      return _json('''
        {
          "items": [{
            "id": 12,
            "name": "가시꽃",
            "species": {"id": 2, "code": "cactus", "name": "가시니"},
            "exp": 1300,
            "final_form": "ember"
          }],
          "next_cursor": "40"
        }
      ''');
    });

    final page = await GalleryRepository(dio).getHarvested(cursor: '20');

    expect(request.path, '/plants');
    expect(request.queryParameters, {'status': 'harvested', 'cursor': '20'});
    expect(page.items.single.species.code, 'cactus');
    expect(page.items.single.finalForm, PlantFinalForm.ember);
    expect(page.nextCursor, '40');
  });
}
