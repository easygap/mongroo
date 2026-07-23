import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/api_exception.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../home/presentation/home_controller.dart';
import '../data/quest_repository.dart';
import '../domain/daily_quest.dart';

class QuestUiState {
  const QuestUiState({
    this.feed = const AsyncLoading(),
    this.busyQuestIds = const {},
    this.actionError,
  });

  final AsyncValue<DailyQuestFeed> feed;
  final Set<int> busyQuestIds;
  final String? actionError;

  QuestUiState copyWith({
    AsyncValue<DailyQuestFeed>? feed,
    Set<int>? busyQuestIds,
    Object? actionError = _unset,
  }) =>
      QuestUiState(
        feed: feed ?? this.feed,
        busyQuestIds: busyQuestIds ?? this.busyQuestIds,
        actionError:
            actionError == _unset ? this.actionError : actionError as String?,
      );
}

const _unset = Object();

class QuestController extends Notifier<QuestUiState> {
  static const _uuid = Uuid();
  final Map<int, String> _completionKeys = {};

  @override
  QuestUiState build() {
    Future.microtask(load);
    return const QuestUiState();
  }

  Future<void> load() async {
    state = state.copyWith(feed: const AsyncLoading(), actionError: null);
    try {
      final feed = await ref.read(questRepositoryProvider).getToday();
      state = state.copyWith(feed: AsyncData(feed));
    } on ApiException catch (error, stack) {
      state = state.copyWith(feed: AsyncError(error, stack));
    }
  }

  Future<QuestCompletionResult?> complete(int userQuestId) async {
    if (state.busyQuestIds.contains(userQuestId)) return null;
    _setBusy(userQuestId, true);
    try {
      final key = _completionKeys.putIfAbsent(userQuestId, () => _uuid.v4());
      final result = await ref.read(questRepositoryProvider).complete(
            userQuestId: userQuestId,
            idempotencyKey: key,
          );
      _completionKeys.remove(userQuestId);
      final balance = result.reward?.seedBalance;
      if (balance != null) {
        ref.read(authControllerProvider.notifier).updateSeedBalance(balance);
      }
      if (result.reward != null) {
        // 퀘스트 경험치는 서버의 활성 식물에 즉시 반영된다. 홈 캐시도
        // 무효화해야 탭을 돌아갔을 때 성장도와 단계가 오래된 값으로 남지 않는다.
        ref.invalidate(homeControllerProvider);
      }
      final feed = state.feed.valueOrNull;
      if (feed != null) {
        state = state.copyWith(
          feed: AsyncData(
            feed.replace(result.userQuest, journey: result.journey),
          ),
        );
      }
      _setBusy(userQuestId, false);
      return result;
    } on ApiException catch (error) {
      _setBusy(userQuestId, false, error: error.message);
      return null;
    }
  }

  Future<bool> skip(int userQuestId) async {
    if (state.busyQuestIds.contains(userQuestId)) return false;
    _setBusy(userQuestId, true);
    try {
      final updated = await ref.read(questRepositoryProvider).skip(userQuestId);
      final feed = state.feed.valueOrNull;
      if (feed != null) {
        state = state.copyWith(feed: AsyncData(feed.replace(updated)));
      }
      _setBusy(userQuestId, false);
      return true;
    } on ApiException catch (error) {
      _setBusy(userQuestId, false, error: error.message);
      return false;
    }
  }

  void clearActionError() => state = state.copyWith(actionError: null);

  void _setBusy(int id, bool busy, {String? error}) {
    final ids = {...state.busyQuestIds};
    busy ? ids.add(id) : ids.remove(id);
    state = state.copyWith(
      busyQuestIds: ids,
      actionError: error,
    );
  }
}

final questControllerProvider =
    NotifierProvider<QuestController, QuestUiState>(QuestController.new);
