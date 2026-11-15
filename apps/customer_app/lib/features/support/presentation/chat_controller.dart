import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/chat_repository.dart';
import '../data/mock_chat_repository.dart';
import '../domain/chat.dart';

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockChatRepository(),
    PmartEnv.local => ApiChatRepository(ref.watch(dioProvider)),
  },
);

/// 202 처리 중일 때 같은 키로 다시 물어보는 간격·횟수. 넘으면 "확인 중"으로 두고 사용자가 다시 확인한다.
final chatProcessingPolicyProvider =
    Provider<({Duration interval, int attempts})>(
      (_) => (interval: const Duration(seconds: 2), attempts: 3),
    );

/// AI 상담 대화(이 앱 실행 동안, 기기에 저장하지 않는다). 계정이 바뀌면 비운다.
/// - 새 질문 = 새 Idempotency-Key. 결과를 모르면 그 질문의 키로만 다시 보낸다(같은 답, 요청 제한에 세지 않음).
/// - 주문을 고르면 같은 질문을 `orderId` 와 함께 **새 키로** 보낸다(계약: 같은 키에 다른 주문은 409).
class ChatController extends Notifier<List<ChatTurn>> {
  @override
  List<ChatTurn> build() {
    ref.watch(sessionProvider); // 로그인·로그아웃·계정 변경 → 대화를 비운다
    return const [];
  }

  bool get busy => state.any((t) => t.status == ChatTurnStatus.sending);

  /// 질문을 보낸다. 보내는 중인 질문이 있으면 받지 않는다.
  Future<void> ask(String question, {String? orderId}) async {
    final q = question.trim();
    if (q.isEmpty || busy) return;
    final key = IdempotencyKey.generate();
    state = [
      ...state,
      ChatTurn(
        id: key.value,
        question: q,
        orderId: orderId,
        status: ChatTurnStatus.sending,
      ),
    ];
    await _send(key.value);
  }

  /// 결과를 모르는 질문을 같은 키로 다시 확인한다.
  Future<void> recheck(String turnId) async {
    final turn = _turn(turnId);
    if (turn == null || turn.status != ChatTurnStatus.unknown || busy) return;
    _replace(turn.copyWith(status: ChatTurnStatus.sending));
    await _send(turnId);
  }

  ChatTurn? _turn(String id) {
    for (final t in state) {
      if (t.id == id) return t;
    }
    return null;
  }

  void _replace(ChatTurn next) {
    state = [for (final t in state) t.id == next.id ? next : t];
  }

  Future<void> _send(String turnId) async {
    final turn = _turn(turnId);
    if (turn == null) return;
    final repo = ref.read(chatRepositoryProvider);
    final policy = ref.read(chatProcessingPolicyProvider);
    final key = IdempotencyKey(turnId);
    ChatTurn result;
    try {
      var answer = await repo.ask(
        turn.question,
        orderId: turn.orderId,
        key: key,
      );
      for (
        var i = 0;
        answer.state == ChatAnswerState.processing && i < policy.attempts;
        i++
      ) {
        await Future<void>.delayed(policy.interval);
        if (!ref.mounted) return;
        answer = await repo.ask(turn.question, orderId: turn.orderId, key: key);
      }
      result = answer.state == ChatAnswerState.processing
          ? turn.copyWith(status: ChatTurnStatus.unknown)
          : turn.copyWith(status: ChatTurnStatus.answered, answer: answer);
    } on ProblemFailure catch (f) {
      result = turn.copyWith(
        status: ChatTurnStatus.rejected,
        rejectCode: f.problem.code,
        rejectStatus: f.problem.status,
        serverDetail: f.problem.detail,
      );
    } on PmartFailure {
      result = turn.copyWith(status: ChatTurnStatus.unknown);
    }
    if (!ref.mounted) return;
    _replace(result);
  }
}

final chatProvider = NotifierProvider<ChatController, List<ChatTurn>>(
  ChatController.new,
);

/// 상담 종류. null = 아직 고르지 않음(입력 칸을 막고 두 버튼을 보인다). 계정이 바뀌면 처음으로.
class ChatTopicController extends Notifier<ChatTopic?> {
  @override
  ChatTopic? build() {
    ref.watch(sessionProvider);
    return null;
  }

  void chooseGeneral() => state = const ChatTopicGeneral();

  void chooseOrder() => state = const ChatTopicPickingOrder();

  void pickOrder(ChatOrder order) => state = ChatTopicOrder(order);

  void reset() => state = null;
}

final chatTopicProvider = NotifierProvider<ChatTopicController, ChatTopic?>(
  ChatTopicController.new,
);

/// "주문 건에 대한 문의"에서 고를 최근 주문. 실패는 오류로 남는다(빈 목록으로 바꾸지 않는다).
final chatRecentOrdersProvider = FutureProvider.autoDispose<List<ChatOrder>>(
  (ref) => ref.watch(chatRepositoryProvider).recentOrders(),
);
