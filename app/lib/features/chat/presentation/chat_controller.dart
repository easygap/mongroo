import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/api_exception.dart';
import '../../home/domain/plant.dart';
import '../../home/domain/reward_result.dart';
import '../../home/presentation/home_controller.dart';
import '../../quest/presentation/quest_controller.dart';
import '../../safety/domain/safety_action.dart';
import '../data/chat_repository.dart';
import '../data/chat_run_watcher.dart';
import '../domain/chat_models.dart';

enum BubbleStatus { sent, failed }

class ChatBubble {
  const ChatBubble({
    required this.localId,
    required this.role,
    required this.content,
    this.status = BubbleStatus.sent,
  });

  final String localId;
  final String role; // "user" | "plant"
  final String content;
  final BubbleStatus status;

  ChatBubble withStatus(BubbleStatus next) =>
      ChatBubble(localId: localId, role: role, content: content, status: next);
}

class _ChatSendAttempt {
  const _ChatSendAttempt({
    required this.content,
    required this.clientMessageId,
    required this.idempotencyKey,
    this.retryFailedRun = false,
  });

  final String content;
  final String clientMessageId;
  final String idempotencyKey;
  final bool retryFailedRun;
}

const _unset = Object();

class ChatUiState {
  const ChatUiState({
    this.session,
    this.character,
    this.bubbles = const [],
    this.starting = false,
    this.thinking = false,
    this.closed = false,
    this.userTurns = 0,
    this.failedContent,
    this.errorMessage,
    this.closureMessage,
    this.pendingSafety,
    this.sessionReward,
  });

  final ChatSession? session;
  final ChatCharacterSnapshot? character;
  final List<ChatBubble> bubbles;
  final bool starting;
  final bool thinking;
  final bool closed;
  final int userTurns;

  /// 응답 생성에 실패한 마지막 사용자 입력. "다시 시도"가 이 내용을 재전송한다.
  final String? failedContent;
  final String? errorMessage;
  final String? closureMessage;
  final SafetyAction? pendingSafety;
  final RewardResult? sessionReward;

  bool get hasSession => session != null;
  int get remainingTurns => (ChatController.maxUserTurns - userTurns)
      .clamp(0, ChatController.maxUserTurns)
      .toInt();
  double get turnProgress =>
      (userTurns / ChatController.maxUserTurns).clamp(0, 1).toDouble();
  List<String> get suggestedStarters => userTurns == 0 && !closed
      ? character?.suggestedStarters ?? const []
      : const [];

  ChatUiState copyWith({
    Object? session = _unset,
    Object? character = _unset,
    List<ChatBubble>? bubbles,
    bool? starting,
    bool? thinking,
    bool? closed,
    int? userTurns,
    Object? failedContent = _unset,
    Object? errorMessage = _unset,
    Object? closureMessage = _unset,
    Object? pendingSafety = _unset,
    Object? sessionReward = _unset,
  }) {
    return ChatUiState(
      session: session == _unset ? this.session : session as ChatSession?,
      character: character == _unset
          ? this.character
          : character as ChatCharacterSnapshot?,
      bubbles: bubbles ?? this.bubbles,
      starting: starting ?? this.starting,
      thinking: thinking ?? this.thinking,
      closed: closed ?? this.closed,
      userTurns: userTurns ?? this.userTurns,
      failedContent: failedContent == _unset
          ? this.failedContent
          : failedContent as String?,
      errorMessage:
          errorMessage == _unset ? this.errorMessage : errorMessage as String?,
      closureMessage: closureMessage == _unset
          ? this.closureMessage
          : closureMessage as String?,
      pendingSafety: pendingSafety == _unset
          ? this.pendingSafety
          : pendingSafety as SafetyAction?,
      sessionReward: sessionReward == _unset
          ? this.sessionReward
          : sessionReward as RewardResult?,
    );
  }
}

/// 대화 세션의 시작·전송·run 구독·종료를 담당한다.
class ChatController extends Notifier<ChatUiState> {
  static const _uuid = Uuid();
  static const maxUserTurns = 10;

  StreamSubscription<RunUpdate>? _runSubscription;
  _ChatSendAttempt? _retryAttempt;
  final Set<String> _countedClientMessageIds = {};
  final Set<int> _runsWithAssistantMessage = {};
  int _watchEpoch = 0;
  int _sessionEpoch = 0;

  @override
  ChatUiState build() {
    ref.onDispose(() {
      _sessionEpoch++;
      _retireRunWatcher();
    });
    return const ChatUiState();
  }

  /// cancel 완료 전에 늦은 이벤트가 와도 새 세션 상태를 건드리지 못하게 epoch를
  /// 먼저 바꾸고 구독을 폐기한다.
  void _retireRunWatcher() {
    _watchEpoch++;
    final subscription = _runSubscription;
    _runSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  Future<void> startSession({ActivePlant? plant}) async {
    if (state.starting) return;
    final character =
        plant == null ? null : ChatCharacterSnapshot.fromPlant(plant);
    final sessionEpoch = ++_sessionEpoch;
    _retireRunWatcher();
    state = state.copyWith(starting: true, errorMessage: null);
    try {
      final result = await ref
          .read(chatRepositoryProvider)
          .startSession(plantId: character?.plantId);
      if (sessionEpoch != _sessionEpoch) return;
      _retryAttempt = null;
      _countedClientMessageIds.clear();
      _runsWithAssistantMessage.clear();
      if (result.reward != null) {
        // 하루 첫 대화 보상으로 바뀐 식물 경험치를 홈에 즉시 연결한다.
        ref.invalidate(homeControllerProvider);
      }
      state = ChatUiState(
        session: result.session,
        character: character,
        bubbles: [
          if (result.greeting.isNotEmpty)
            ChatBubble(
              localId: _uuid.v4(),
              role: 'plant',
              content: result.greeting,
            ),
        ],
        closed: result.session.isClosed,
        closureMessage: result.session.isClosed ? '이 대화는 이미 마무리되었어요.' : null,
        sessionReward: result.reward,
      );
    } on ApiException catch (e) {
      if (sessionEpoch != _sessionEpoch) return;
      state = state.copyWith(starting: false, errorMessage: e.message);
    }
  }

  Future<void> send(String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    // 마지막 전송의 처리 결과가 비어 있는 동안 새 턴을 열면 서버 순서가
    // 어긋난다. 사용자는 기존 메시지를 재시도하거나 세션을 끝낸 뒤 진행한다.
    if (state.failedContent != null) return;
    if (state.remainingTurns <= 0) {
      state = state.copyWith(
        closed: true,
        closureMessage: '오늘 나눌 수 있는 10번의 이야기를 모두 마쳤어요.',
      );
      return;
    }
    await _sendAttempt(
      _ChatSendAttempt(
        content: trimmed,
        clientMessageId: _uuid.v4(),
        idempotencyKey: _uuid.v4(),
      ),
      addBubble: true,
    );
  }

  Future<void> _sendAttempt(
    _ChatSendAttempt attempt, {
    required bool addBubble,
  }) async {
    final session = state.session;
    if (session == null || state.thinking || state.closed) {
      return;
    }
    final sessionEpoch = _sessionEpoch;
    final bubble = addBubble
        ? ChatBubble(
            localId: _uuid.v4(),
            role: 'user',
            content: attempt.content,
          )
        : null;
    state = state.copyWith(
      bubbles: bubble == null ? state.bubbles : [...state.bubbles, bubble],
      thinking: true,
      failedContent: null,
      errorMessage: null,
    );
    try {
      final result = await ref.read(chatRepositoryProvider).sendMessage(
            sessionId: session.id,
            content: attempt.content,
            clientMessageId: attempt.clientMessageId,
            idempotencyKey: attempt.idempotencyKey,
            retryFailed: attempt.retryFailedRun,
          );
      if (sessionEpoch != _sessionEpoch) return;
      _retryAttempt = null;
      final firstAcknowledgement =
          _countedClientMessageIds.add(attempt.clientMessageId);
      final turns = state.userTurns + (firstAcknowledgement ? 1 : 0);
      if (result.safetyAction != null) {
        // 안전 경로: LLM 미호출. 지원 화면으로 안내한다.
        ref.invalidate(questControllerProvider);
        state = state.copyWith(
          thinking: false,
          userTurns: turns,
          closed: turns >= maxUserTurns,
          closureMessage:
              turns >= maxUserTurns ? '오늘 나눌 수 있는 10번의 이야기를 모두 마쳤어요.' : null,
          pendingSafety: result.safetyAction,
        );
        return;
      }
      final runId = result.runId;
      if (runId == null) {
        state = state.copyWith(
          thinking: false,
          userTurns: turns,
          closed: turns >= maxUserTurns,
          closureMessage:
              turns >= maxUserTurns ? '오늘 나눌 수 있는 10번의 이야기를 모두 마쳤어요.' : null,
        );
        return;
      }
      state = state.copyWith(userTurns: turns);
      _watchRun(runId, attempt);
    } on ApiException catch (e) {
      if (sessionEpoch != _sessionEpoch) return;
      if (e.code == 'CHAT_RETRY_STALE' ||
          e.code == 'CHAT_RETRY_SAFETY_BLOCKED' ||
          e.code == 'CHAT_RUN_NOT_FAILED') {
        // 서버가 재시도 불가를 확정한 오류에는 같은 버튼을 다시 노출하지 않는다.
        _retryAttempt = null;
        state = state.copyWith(
          thinking: false,
          failedContent: null,
          errorMessage: e.code == 'CHAT_RETRY_SAFETY_BLOCKED'
              ? '안전 안내가 필요한 대화에서는 이전 AI 답변을 다시 만들지 않아요.'
              : '이후 대화가 있어 이전 답변은 다시 만들 수 없어요.',
        );
        return;
      }
      if (e.code == 'CHAT_SESSION_CLOSED') {
        _retryAttempt = null;
        state = state.copyWith(
          bubbles: bubble == null
              ? state.bubbles
              : state.bubbles
                  .where((b) => b.localId != bubble.localId)
                  .toList(),
          thinking: false,
          closed: true,
          errorMessage: null,
          closureMessage: '대화 시간이 끝났어요. 새 대화에서 다시 이야기할 수 있어요.',
        );
        return;
      }
      // 전송 자체가 실패: 말풍선을 실패 상태로 남기고 재시도를 안내한다.
      _retryAttempt = attempt;
      state = state.copyWith(
        bubbles: [
          for (final b in state.bubbles)
            bubble != null && b.localId == bubble.localId
                ? b.withStatus(BubbleStatus.failed)
                : b,
        ],
        thinking: false,
        failedContent: attempt.content,
        errorMessage: e.message,
      );
    }
  }

  void _watchRun(int runId, _ChatSendAttempt attempt) {
    _retireRunWatcher();
    final epoch = _watchEpoch;
    _runSubscription =
        ref.read(chatRunWatcherProvider).watch(runId).listen((update) {
      if (epoch != _watchEpoch) return;
      switch (update) {
        case RunGenerating():
          state = state.copyWith(thinking: true);
        case RunMessageReceived(:final content):
          // watcher가 잘못된 두 번째 message_id까지 내보내더라도 한 run의 식물
          // 답변은 UI에 하나만 추가한다.
          if (!_runsWithAssistantMessage.add(runId)) return;
          _retryAttempt = null;
          state = state.copyWith(
            bubbles: [
              ...state.bubbles,
              ChatBubble(localId: _uuid.v4(), role: 'plant', content: content),
            ],
            thinking: false,
            closed: state.userTurns >= maxUserTurns,
            closureMessage: state.userTurns >= maxUserTurns
                ? '오늘 나눌 수 있는 10번의 이야기를 모두 마쳤어요.'
                : null,
          );
        case RunCompleted():
          _retryAttempt = null;
          final reachedLimit = state.userTurns >= maxUserTurns;
          state = state.copyWith(
            thinking: false,
            closed: state.closed || reachedLimit,
            errorMessage: null,
            closureMessage: reachedLimit
                ? '오늘 나눌 수 있는 10번의 이야기를 모두 마쳤어요.'
                : state.closureMessage,
          );
        case RunFailed(:final errorCode):
          // 전송 응답 유실과 달리 서버가 failed를 확정한 run은 같은 멱등
          // 응답을 재생하면 영원히 실패한다. 사용자 메시지 ID는 유지해 대화
          // 본문을 중복시키지 않고, 새 멱등 키로 서버 재큐잉을 명시한다.
          _retryAttempt = _ChatSendAttempt(
            content: attempt.content,
            clientMessageId: attempt.clientMessageId,
            idempotencyKey: _uuid.v4(),
            retryFailedRun: true,
          );
          state = state.copyWith(
            thinking: false,
            failedContent: attempt.content,
            errorMessage: _failureMessage(errorCode),
          );
        case RunTimedOut():
          _retryAttempt = attempt;
          state = state.copyWith(
            thinking: false,
            failedContent: attempt.content,
            errorMessage: '응답이 늦어지고 있어요. 잠시 후 다시 시도해 주세요.',
          );
      }
    });
  }

  String _failureMessage(String? errorCode) {
    switch (errorCode) {
      case 'LLM_TIMEOUT':
        return '식물이 답을 만드는 데 시간이 너무 걸렸어요. 다시 시도해 주세요.';
      case 'LLM_UNAVAILABLE':
        return 'AI 응답 기능이 잠시 멈춰 있어요. 잠시 후 다시 시도해 주세요.';
      case 'GUARD_REJECTED':
        return '안전 기준을 통과한 답변을 만들지 못했어요. 다시 시도해 주세요.';
      default:
        return '답변을 만들지 못했어요. 다시 시도해 주세요.';
    }
  }

  /// "다시 시도": 같은 논리 전송의 ID를 재사용해 응답 유실 때 중복을 막는다.
  Future<void> retryFailed() async {
    final attempt = _retryAttempt;
    if (attempt == null) return;
    // 전송 실패로 남은 실패 말풍선은 제거 후 새로 보낸다.
    final bubbles = [...state.bubbles];
    final transportFailure = bubbles.isNotEmpty &&
        bubbles.last.role == 'user' &&
        bubbles.last.status == BubbleStatus.failed;
    if (transportFailure) {
      bubbles.removeLast();
    }
    state = state.copyWith(
        bubbles: bubbles, failedContent: null, errorMessage: null);
    await _sendAttempt(attempt, addBubble: transportFailure);
  }

  /// 사용자가 대화를 접는다. 서버 세션은 10턴/30분 규칙으로 자체 종료된다.
  void endSession() {
    _sessionEpoch++;
    _retireRunWatcher();
    _retryAttempt = null;
    _countedClientMessageIds.clear();
    _runsWithAssistantMessage.clear();
    state = const ChatUiState();
  }

  void clearSafety() => state = state.copyWith(pendingSafety: null);

  void clearSessionReward() => state = state.copyWith(sessionReward: null);
}

final chatControllerProvider =
    NotifierProvider<ChatController, ChatUiState>(ChatController.new);
