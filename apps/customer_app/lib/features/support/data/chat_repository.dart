import 'package:dio/dio.dart';
import 'package:pmart_api_customer_assistant/pmart_api_customer_assistant.dart'
    as api;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;
import '../domain/chat.dart';

/// 고객센터 AI 상담(게이트웨이 `/api/v1/customer-assistant/**`). 실패는 [PmartFailure] 로 던진다.
/// 질문·답변을 로그에 남기지 않는다.
abstract interface class ChatRepository {
  /// `POST /customer-assistant/questions`. 200 완료 또는 202 처리 중(`PROCESSING`)을 돌려준다.
  /// 같은 키·같은 본문으로 다시 보내면 같은 답이다(요청 제한에 세지 않는다) — 응답을 잃었을 때 그렇게 다시 확인한다.
  /// 403(비회원), 409 `IDEMPOTENCY_CONFLICT`, 422 `ORDER_NOT_FOUND`·`CONFIG_REQUIRED`, 429 `RATE_LIMITED`, 503.
  Future<ChatAnswer> ask(
    String question, {
    String? orderId,
    required IdempotencyKey key,
  });
}

final class ApiChatRepository implements ChatRepository {
  ApiChatRepository(Dio dio)
    : _api = api.PmartApiCustomerAssistant(dio: dio).getCustomerAssistantApi();

  final api.CustomerAssistantApi _api;

  @override
  Future<ChatAnswer> ask(
    String question, {
    String? orderId,
    required IdempotencyKey key,
  }) async {
    final res = await pmartGuard(
      () => _api.askCustomerQuestion(
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        customerQuestion: api.CustomerQuestion(
          question: question,
          orderId: orderId,
        ),
        extra: commandOptions(key).extra,
      ),
    );
    return chatAnswerFromContract(
      res.data ?? (throw UnknownResultFailure(requestId: key.value)),
    );
  }
}

ChatOrder chatOrderFromContract(api.OrderBrief o) => ChatOrder(
  orderId: o.orderId,
  statusLabel: o.statusLabel,
  orderedAt: o.orderedAt,
  itemCount: o.itemCount,
  totalAmount: o.totalAmount,
  arrivalDate: o.arrivalWindow?.date,
  arrivalStart: o.arrivalWindow?.start,
  arrivalEnd: o.arrivalWindow?.end,
);

ChatAnswer chatAnswerFromContract(api.CustomerAnswer a) => ChatAnswer(
  answerId: a.answerId,
  state:
      ChatAnswerState.fromWire(a.state.value) ??
      (throw ContractViolationFailure('state 값 이상: ${a.state.value}')),
  answer: a.answer,
  citations: [
    for (final c in a.citations)
      ChatCitation(title: c.title, section: c.section, excerpt: c.excerpt),
  ],
  order: switch (a.order) {
    final api.OrderBrief o => chatOrderFromContract(o),
    null => null,
  },
  recentOrders: [
    for (final o in a.recentOrders ?? const <api.OrderBrief>[])
      chatOrderFromContract(o),
  ],
  handoff: switch (a.handoff) {
    final api.Handoff h => ChatHandoff(
      message: h.message,
      buttonLabel: h.buttonLabel,
      orderId: h.orderId,
    ),
    null => null,
  },
  extractive: a.answerMode == api.AnswerMode.BASELINE_EXTRACTIVE,
);
