import 'package:pmart_core/pmart_core.dart';

import '../domain/chat.dart';
import 'chat_repository.dart';

/// 목이 질문마다 고르는 결과.
enum MockChatScenario {
  answered,
  noGrounding,
  realtime,
  outOfScope,

  /// 첫 전송만 202 처리 중. 같은 키로 다시 보내면 완료.
  processingOnce,

  /// 서버는 답을 만들었는데 응답이 유실(첫 전송만).
  lostOnce,
  rateLimited,
  configRequired,
}

/// ⚠ 화면 개발·시험용 목. 실제 AI 상담이 아니다 — 답변 문장은 지어낸 예시다.
/// 계약의 뜻만 흉내 낸다: 같은 키 = 같은 답(다시 세지 않음), 주문을 고르면 ORDER_STATUS,
/// 근거 없음·실행 요청은 문의 남기기 연결(handoff), 요청 제한 429.
final class MockChatRepository implements ChatRepository {
  MockChatRepository({
    this.latency = const Duration(milliseconds: 500),
    MockChatScenario Function(String question)? script,
  }) : _script = script ?? tagScript;

  final Duration latency;
  final MockChatScenario Function(String question) _script;

  /// 목 모드에서 질문에 넣어 결과를 고르는 꼬리표.
  static const tags = <String, MockChatScenario>{
    '#근거없음': MockChatScenario.noGrounding,
    '#주문': MockChatScenario.realtime,
    '#취소': MockChatScenario.outOfScope,
    '#처리중': MockChatScenario.processingOnce,
    '#응답유실': MockChatScenario.lostOnce,
    '#제한': MockChatScenario.rateLimited,
    '#색인없음': MockChatScenario.configRequired,
  };

  static MockChatScenario tagScript(String question) {
    for (final e in tags.entries) {
      if (question.contains(e.key)) return e.value;
    }
    return MockChatScenario.answered;
  }

  static const _orders = [
    ChatOrder(
      orderId: 'order-seed-4',
      statusLabel: '상품 준비 중',
      itemCount: 3,
      totalAmount: 18900,
      arrivalDate: '2026-11-15',
      arrivalStart: '14:00',
      arrivalEnd: '15:00',
    ),
    ChatOrder(
      orderId: 'order-seed-1',
      statusLabel: '배송 완료',
      itemCount: 2,
      totalAmount: 9800,
    ),
  ];

  static const _handoff = ChatHandoff(
    message: '고객센터에 문의를 남겨 주시면 담당자가 확인한 뒤 답변드릴게요. 답변은 고객센터의 내 문의에서 확인할 수 있어요.',
    buttonLabel: '고객센터에 문의 남기기',
  );

  final _byKey = <String, ChatAnswer>{};
  final _lostOnce = <String>{};
  var _seq = 0;

  /// 서버가 처리한 질문 수(같은 키 재전송은 세지 않는다)와 보낸 키.
  int answered = 0;
  final sentKeys = <String>[];
  final sentOrderIds = <String?>[];

  Future<void> _wait() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  @override
  Future<ChatAnswer> ask(
    String question, {
    String? orderId,
    required IdempotencyKey key,
  }) async {
    await _wait();
    sentKeys.add(key.value);
    sentOrderIds.add(orderId);
    final saved = _byKey[key.value];
    if (saved != null) return saved; // 같은 키 = 같은 답(다시 세지 않는다)
    final scenario = _script(question);
    switch (scenario) {
      case MockChatScenario.rateLimited:
        throw const ProblemFailure(
          Problem(
            status: 429,
            code: ChatProblemCode.rateLimited,
            detail: '[목] 질문이 너무 빨라요. 잠시 뒤에 다시 물어봐 주세요.',
          ),
        );
      case MockChatScenario.configRequired:
        throw const ProblemFailure(
          Problem(status: 422, code: ChatProblemCode.configRequired),
        );
      default:
    }
    _seq += 1;
    answered += 1;
    final id = 'cans-mock-$_seq';
    final ChatAnswer made;
    if (orderId != null) {
      final order = _orders.firstWhere(
        (o) => o.orderId == orderId,
        orElse: () => throw const ProblemFailure(
          Problem(status: 422, code: ChatProblemCode.orderNotFound),
        ),
      );
      made = ChatAnswer(
        answerId: id,
        state: ChatAnswerState.orderStatus,
        answer: '[목] 고르신 주문은 지금 "${order.statusLabel}" 상태예요.',
        order: order,
        handoff: ChatHandoff(
          message: _handoff.message,
          buttonLabel: _handoff.buttonLabel,
          orderId: orderId,
        ),
      );
    } else {
      made = switch (scenario) {
        MockChatScenario.noGrounding => ChatAnswer(
          answerId: id,
          state: ChatAnswerState.noGrounding,
          answer: '[목] 이 문의는 지금 바로 답변드리기 어려워요.',
          handoff: _handoff,
        ),
        MockChatScenario.realtime => ChatAnswer(
          answerId: id,
          state: ChatAnswerState.realtimeDataRequired,
          answer: '[목] 어떤 주문이 궁금하신가요?',
          recentOrders: _orders,
        ),
        MockChatScenario.outOfScope => ChatAnswer(
          answerId: id,
          state: ChatAnswerState.outOfScope,
          answer: '[목] AI 상담은 취소·환불을 직접 처리하지 않아요.',
          handoff: _handoff,
        ),
        _ => ChatAnswer(
          answerId: id,
          state: ChatAnswerState.answered,
          answer: '[목 답변] 상품 준비가 시작된 뒤에는 앱에서 취소할 수 없어요.',
          citations: const [
            ChatCitation(
              title: '[목] 주문 취소',
              section: '상품 준비가 시작된 뒤 취소 문의를 하면요?',
              excerpt: '[목 근거] 이미 상품 준비가 시작되어 앱에서는 취소할 수 없어요.',
            ),
          ],
        ),
      };
    }
    _byKey[key.value] = made;
    if (scenario == MockChatScenario.processingOnce) {
      // 이번만 처리 중으로 답한다. 같은 키로 다시 보내면 완료된 답이 간다.
      return ChatAnswer(
        answerId: id,
        state: ChatAnswerState.processing,
        answer: '',
      );
    }
    if (scenario == MockChatScenario.lostOnce && _lostOnce.add(key.value)) {
      throw UnknownResultFailure(requestId: key.value);
    }
    return made;
  }
}
