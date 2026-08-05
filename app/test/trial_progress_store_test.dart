import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/features/trial/data/trial_progress_store.dart';
import 'package:mongroo/features/trial/domain/trial_progress.dart';

class _MemoryTrialStorage implements TrialProgressStorage {
  String? value;
  bool failWrites = false;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    if (failWrites) throw StateError('storage disabled');
    this.value = value;
  }
}

void main() {
  test('체험 진행은 기기 저장소에 직렬화하고 다시 이어서 읽는다', () async {
    final storage = _MemoryTrialStorage();
    final store = TrialProgressStore(storage);
    const progress = TrialProgress(
      stage: TrialStage.exploration,
      diaryText: '오늘은 따뜻한 차를 마셔 마음이 편안했다.',
      emotionCode: 'sunny',
      explorationStep: 1,
      selectedPath: 'labels',
    );

    expect(await store.save(progress), isTrue);
    final restored = await store.load();

    expect(restored.stage, TrialStage.exploration);
    expect(restored.diaryText, progress.diaryText);
    expect(restored.emotionCode, 'sunny');
    expect(restored.selectedPath, 'labels');
  });

  test('손상되거나 다른 스키마의 캐시는 새 체험으로 안전하게 복구한다', () async {
    final storage = _MemoryTrialStorage()..value = '{broken';
    final store = TrialProgressStore(storage);

    expect((await store.load()).stage, TrialStage.welcome);

    storage.value = '{"schema_version":99,"stage":"complete"}';
    expect((await store.load()).stage, TrialStage.welcome);
  });

  test('저장소가 막혀도 체험 진행을 실패로 처리하지 않는다', () async {
    final storage = _MemoryTrialStorage()..failWrites = true;
    final store = TrialProgressStore(storage);

    expect(
      await store.save(const TrialProgress(stage: TrialStage.diary)),
      isFalse,
    );
  });
}
