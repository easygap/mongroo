import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_providers.dart';
import '../../../core/error/api_exception.dart';
import '../domain/skill_book_models.dart';

class SkillBookRepository {
  SkillBookRepository(this._dio);

  final Dio _dio;

  Future<SkillBookLibrary> getLibrary() => guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>('/skill-books');
        return SkillBookLibrary.fromJson(response.data ?? const {});
      });

  Future<SkillLoadout> getLoadout({
    required int plantId,
    required String presetCode,
  }) =>
      guardApi(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/skill-books/loadouts/$plantId',
          queryParameters: {'preset_code': presetCode},
        );
        return SkillLoadout.fromJson(response.data ?? const {});
      });

  /// 장착을 저장한다.
  ///
  /// [expectedRevision]은 읽을 때 받은 값을 그대로 돌려보낸다. 다른 화면이
  /// 먼저 바꿨으면 서버가 409로 되돌리고, 호출부는 다시 읽어 보여 준다.
  Future<SkillLoadout> saveLoadout({
    required int plantId,
    required String presetCode,
    required String? slotB1Code,
    required String? slotB2Code,
    required int expectedRevision,
  }) =>
      guardApi(() async {
        final response = await _dio.put<Map<String, dynamic>>(
          '/skill-books/loadouts/$plantId',
          data: {
            'preset_code': presetCode,
            'slot_b1_code': slotB1Code,
            'slot_b2_code': slotB2Code,
            'expected_revision': expectedRevision,
          },
        );
        return SkillLoadout.fromJson(response.data ?? const {});
      });
}

final skillBookRepositoryProvider = Provider<SkillBookRepository>(
  (ref) => SkillBookRepository(ref.watch(dioProvider)),
);
