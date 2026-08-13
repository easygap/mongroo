import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/api_exception.dart';
import '../data/skill_book_repository.dart';
import '../domain/skill_book_models.dart';

class SkillBookState {
  const SkillBookState({
    this.loading = true,
    this.library,
    this.loadout,
    this.presetCode = 'guard',
    this.saving = false,
    this.error,
    this.notice,
  });

  final bool loading;
  final SkillBookLibrary? library;
  final SkillLoadout? loadout;
  final String presetCode;
  final bool saving;

  /// 저장이 거부된 이유. 고르는 순간에 왜 안 되는지 알려 준다.
  final String? error;

  /// 저장이 끝났거나 선택이 되돌려졌다는 안내.
  final String? notice;

  bool get ready => !loading && library != null && loadout != null;

  SkillBookState copyWith({
    bool? loading,
    SkillBookLibrary? library,
    SkillLoadout? loadout,
    String? presetCode,
    bool? saving,
    Object? error = _unset,
    Object? notice = _unset,
  }) =>
      SkillBookState(
        loading: loading ?? this.loading,
        library: library ?? this.library,
        loadout: loadout ?? this.loadout,
        presetCode: presetCode ?? this.presetCode,
        saving: saving ?? this.saving,
        error: error == _unset ? this.error : error as String?,
        notice: notice == _unset ? this.notice : notice as String?,
      );
}

const _unset = Object();

/// 서고와 한 캐릭터의 장착을 함께 다룬다.
///
/// 저장은 서버가 판정한다. 앱은 규칙을 다시 계산하지 않고, 거부되면 서버가 준
/// 문장을 그대로 보여 준다. 규칙이 두 곳에 있으면 반드시 어긋나기 때문이다.
class SkillBookController extends FamilyNotifier<SkillBookState, int> {
  int get _plantId => arg;

  @override
  SkillBookState build(int plantId) {
    Future.microtask(load);
    return const SkillBookState();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, error: null);
    final repository = ref.read(skillBookRepositoryProvider);
    try {
      final results = await Future.wait([
        repository.getLibrary(),
        repository.getLoadout(
          plantId: _plantId,
          presetCode: state.presetCode,
        ),
      ]);
      final loadout = results[1] as SkillLoadout;
      state = state.copyWith(
        loading: false,
        library: results[0] as SkillBookLibrary,
        loadout: loadout,
        notice: _fallbackNotice(loadout),
      );
    } on ApiException catch (error) {
      state = state.copyWith(loading: false, error: error.message);
    }
  }

  /// 저장한 선택이 그대로 쓰이지 못했으면 조용히 넘어가지 않고 알려 준다.
  static String? _fallbackNotice(SkillLoadout loadout) {
    for (final slot in const ['B1', 'B2']) {
      final decision = loadout.slot(slot);
      if (decision != null && decision.fellBack && decision.lockReason != null) {
        return '$slot 칸: ${decision.lockReason}';
      }
    }
    return null;
  }

  Future<void> selectPreset(String presetCode) async {
    if (presetCode == state.presetCode) return;
    state = state.copyWith(presetCode: presetCode, error: null, notice: null);
    await load();
  }

  /// 슬롯 하나를 바꿔 저장한다. [code]가 null이면 비운다.
  Future<bool> equip({required String slot, required String? code}) async {
    final loadout = state.loadout;
    if (loadout == null || state.saving) return false;
    state = state.copyWith(saving: true, error: null, notice: null);
    try {
      final saved = await ref.read(skillBookRepositoryProvider).saveLoadout(
            plantId: _plantId,
            presetCode: state.presetCode,
            slotB1Code: slot == 'B1' ? code : loadout.storedB1,
            slotB2Code: slot == 'B2' ? code : loadout.storedB2,
            expectedRevision: loadout.revision,
          );
      state = state.copyWith(
        saving: false,
        loadout: saved,
        notice: _fallbackNotice(saved) ?? '기록서를 정리했어요.',
      );
      return true;
    } on ApiException catch (error) {
      // 다른 화면이 먼저 바꿨으면 덮어쓰지 않고 최신 상태를 다시 읽는다.
      if (error.code == 'LOADOUT_REVISION_CONFLICT') {
        state = state.copyWith(saving: false, error: error.message);
        await load();
        return false;
      }
      state = state.copyWith(saving: false, error: error.message);
      return false;
    }
  }
}

final skillBookControllerProvider =
    NotifierProvider.family<SkillBookController, SkillBookState, int>(
  SkillBookController.new,
);
