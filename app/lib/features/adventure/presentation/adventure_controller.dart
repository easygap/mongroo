import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/api_exception.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../home/presentation/home_controller.dart';
import '../data/adventure_repository.dart';
import '../domain/adventure_models.dart';

class AdventureUiState {
  const AdventureUiState({
    this.data = const AsyncLoading(),
    this.busyAction,
    this.actionError,
    this.actionMessage,
  });

  final AsyncValue<AdventureState> data;
  final String? busyAction;
  final String? actionError;
  final String? actionMessage;

  AdventureUiState copyWith({
    AsyncValue<AdventureState>? data,
    Object? busyAction = _unset,
    Object? actionError = _unset,
    Object? actionMessage = _unset,
  }) =>
      AdventureUiState(
        data: data ?? this.data,
        busyAction:
            busyAction == _unset ? this.busyAction : busyAction as String?,
        actionError:
            actionError == _unset ? this.actionError : actionError as String?,
        actionMessage: actionMessage == _unset
            ? this.actionMessage
            : actionMessage as String?,
      );
}

const _unset = Object();

class AdventureController extends Notifier<AdventureUiState> {
  static const _uuid = Uuid();
  final Map<String, String> _keys = {};

  @override
  AdventureUiState build() {
    Future.microtask(load);
    return const AdventureUiState();
  }

  Future<void> load() async {
    state = state.copyWith(data: const AsyncLoading(), actionError: null);
    try {
      final value = await ref.read(adventureRepositoryProvider).getState();
      state = state.copyWith(data: AsyncData(value));
    } on ApiException catch (error, stack) {
      state = state.copyWith(data: AsyncError(error, stack));
    }
  }

  Future<bool> startPatrol(String routeCode) => _perform(
        action: 'patrol:$routeCode',
        request: (key) => ref.read(adventureRepositoryProvider).startPatrol(
              routeCode: routeCode,
              idempotencyKey: key,
            ),
      );

  Future<bool> claimPatrol(int patrolId) => _perform(
        action: 'claim:$patrolId',
        request: (key) => ref.read(adventureRepositoryProvider).claimPatrol(
              patrolId: patrolId,
              idempotencyKey: key,
            ),
      );

  Future<bool> runDungeon(String dungeonCode, String approachCode) => _perform(
        action: 'dungeon:$dungeonCode:$approachCode',
        request: (key) => ref.read(adventureRepositoryProvider).runDungeon(
              dungeonCode: dungeonCode,
              approachCode: approachCode,
              idempotencyKey: key,
            ),
      );

  Future<bool> completeResearch(String projectCode) => _perform(
        action: 'research:$projectCode',
        request: (key) =>
            ref.read(adventureRepositoryProvider).completeResearch(
                  projectCode: projectCode,
                  idempotencyKey: key,
                ),
      );

  Future<bool> claimWeeklyGoal(String goalCode) => _perform(
        action: 'weekly:$goalCode',
        request: (key) => ref.read(adventureRepositoryProvider).claimWeeklyGoal(
              goalCode: goalCode,
              idempotencyKey: key,
            ),
      );

  Future<bool> donateItem(String itemCode) => _perform(
        action: 'donation:$itemCode',
        request: (key) => ref.read(adventureRepositoryProvider).donateItem(
              itemCode: itemCode,
              idempotencyKey: key,
            ),
      );

  Future<bool> _perform({
    required String action,
    required Future<AdventureActionResult> Function(String key) request,
  }) async {
    if (state.busyAction != null) return false;
    state = state.copyWith(
      busyAction: action,
      actionError: null,
      actionMessage: null,
    );
    try {
      final key = _keys.putIfAbsent(action, () => _uuid.v4());
      final result = await request(key);
      _keys.remove(action);
      if (result.seedBalance != null) {
        ref
            .read(authControllerProvider.notifier)
            .updateSeedBalance(result.seedBalance!);
      }
      ref.invalidate(homeControllerProvider);
      state = state.copyWith(
        data: AsyncData(result.state),
        busyAction: null,
        actionMessage: result.outcomeMessage,
      );
      return true;
    } on ApiException catch (error) {
      state = state.copyWith(busyAction: null, actionError: error.message);
      return false;
    }
  }

  void clearActionError() => state = state.copyWith(actionError: null);
}

final adventureControllerProvider =
    NotifierProvider<AdventureController, AdventureUiState>(
  AdventureController.new,
);
