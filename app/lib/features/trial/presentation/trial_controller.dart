import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/trial_progress_store.dart';
import '../domain/trial_progress.dart';

class TrialUiState {
  const TrialUiState({
    this.loading = true,
    this.progress = const TrialProgress(),
    this.storageAvailable = true,
  });

  final bool loading;
  final TrialProgress progress;
  final bool storageAvailable;

  TrialUiState copyWith({
    bool? loading,
    TrialProgress? progress,
    bool? storageAvailable,
  }) =>
      TrialUiState(
        loading: loading ?? this.loading,
        progress: progress ?? this.progress,
        storageAvailable: storageAvailable ?? this.storageAvailable,
      );
}

class TrialController extends Notifier<TrialUiState> {
  @override
  TrialUiState build() {
    Future.microtask(_load);
    return const TrialUiState();
  }

  Future<void> _load() async {
    final progress = await ref.read(trialProgressStoreProvider).load();
    state = state.copyWith(loading: false, progress: progress);
  }

  Future<void> start() => _update(
        state.progress.copyWith(stage: TrialStage.diary),
      );

  Future<void> saveDiary({
    required String text,
    required String emotionCode,
  }) =>
      _update(
        state.progress.copyWith(
          stage: TrialStage.growth,
          diaryText: text.trim(),
          emotionCode: emotionCode,
        ),
      );

  Future<void> openExploration() => _update(
        state.progress.copyWith(
          stage: TrialStage.exploration,
          explorationStep: 0,
        ),
      );

  Future<void> choosePath(String path) => _update(
        state.progress.copyWith(
          selectedPath: path,
          explorationStep: 1,
        ),
      );

  Future<void> resolveEvent(String choice) => _update(
        state.progress.copyWith(
          stage: TrialStage.complete,
          selectedChoice: choice,
          explorationStep: 2,
        ),
      );

  Future<void> reset() async {
    final available = await ref.read(trialProgressStoreProvider).clear();
    state = TrialUiState(
      loading: false,
      progress: const TrialProgress(),
      storageAvailable: state.storageAvailable && available,
    );
  }

  Future<void> _update(TrialProgress progress) async {
    state = state.copyWith(progress: progress);
    final available = await ref.read(trialProgressStoreProvider).save(progress);
    if (!available) state = state.copyWith(storageAvailable: false);
  }
}

final trialControllerProvider =
    NotifierProvider<TrialController, TrialUiState>(TrialController.new);
