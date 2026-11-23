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

  void chooseGeneral() => _settle(const ChatTopicGeneral());

  void chooseOrder() => state = const ChatTopicPickingOrder();

  void pickOrder(ChatOrder order) => _settle(ChatTopicOrder(order));

  /// 최근 2일 안의 주문이 없다 — 주문을 고르는 중일 때만 넘어간다.
  void noRecentOrder() {
    if (state is ChatTopicPickingOrder) _settle(const ChatTopicNoRecentOrder());
  }

  void reset() => state = null;

  /// 정해진 종류는 대화 기록에도 남긴다 — 그때까지의 질문 수 자리에(한 줄 시간순으로 그린다).
  /// [ChatLoggedTopic.fromChooser] = "주문 건에 대한 문의"를 눌러 고른 주문(답 안의 주문 카드로 고른 것과 구분).
  void _settle(ChatTopic topic) {
    ref.read(chatTopicLogProvider.notifier).add((
      topic: topic,
      at: ref.read(chatProvider).length,
      fromChooser:
          topic is ChatTopicGeneral ||
          topic is ChatTopicNoRecentOrder ||
          state is ChatTopicPickingOrder,
    ));
    state = topic;
  }
}

/// 대화 중 고른 상담 종류·주문(시간순). [at] = 고를 때까지 있던 질문 수 — 그 질문들 뒤에 그린다.
/// 지금 고르는 중인 선택지는 기록이 아니라 대화 맨 끝에 그린다. 계정이 바뀌면 비운다.
typedef ChatLoggedTopic = ({ChatTopic topic, int at, bool fromChooser});

class ChatTopicLog extends Notifier<List<ChatLoggedTopic>> {
  @override
  List<ChatLoggedTopic> build() {
    ref.watch(sessionProvider);
    return const [];
  }

  void add(ChatLoggedTopic entry) => state = [...state, entry];
}

final chatTopicLogProvider =
    NotifierProvider<ChatTopicLog, List<ChatLoggedTopic>>(ChatTopicLog.new);

final chatTopicProvider = NotifierProvider<ChatTopicController, ChatTopic?>(
  ChatTopicController.new,
);

/// "주문 건에 대한 문의"에서 고를 최근 주문. 실패는 오류로 남는다(빈 목록으로 바꾸지 않는다).
/// "주문 건에 대한 문의"에서 고를 주문 — 서버가 준 최근 주문 중 **주문한 지 2일(48시간) 안**인 것만
/// (레퍼런스 고객센터 2-4·2-4-1 "최근 2일 내 주문", 사용자 2026-11-23). 주문 시각을 모르면 빼지 않는다.
final chatRecentOrdersProvider = FutureProvider.autoDispose<List<ChatOrder>>((
  ref,
) async {
  final all = await ref.watch(chatRepositoryProvider).recentOrders();
  final now = ref.watch(chatClockProvider)();
  return [
    for (final o in all)
      if (o.orderedAt == null ||
          now.difference(o.orderedAt!) <= chatRecentOrderWindow)
        o,
  ];
});

const chatRecentOrderWindow = Duration(days: 2);

final chatClockProvider = Provider<DateTime Function()>((_) => DateTime.now);
