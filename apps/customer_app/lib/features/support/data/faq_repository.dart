import 'package:dio/dio.dart';
import 'package:pmart_api_customer_assistant/pmart_api_customer_assistant.dart'
    as api;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;
import '../domain/faq.dart';

/// 자주 묻는 질문 조회(customer-assistant 0.2.0). 실패는 [PmartFailure] 로 던진다(빈 목록으로 바꾸지 않는다).
abstract interface class FaqRepository {
  /// `GET /customer-assistant/faqs?q=&category=`.
  Future<FaqList> list({String? q, String? category});

  /// `GET /customer-assistant/faqs/{faqId}`.
  Future<Faq> get(String faqId);

  /// 답 의견(`POST /customer-assistant/faqs/{faqId}/feedback`, 0.4.0 BR-91) — 회원만, 한 FAQ 에 하나(마지막 값).
  /// 같은 요청을 다시 보내도 안전 — 결과를 모르면 같은 [key] 로 다시. 서버가 준 지금 내 값을 돌려준다.
  Future<bool> sendFeedback(
    String faqId, {
    required bool helpful,
    required IdempotencyKey key,
  });
}

final class ApiFaqRepository implements FaqRepository {
  ApiFaqRepository(Dio dio)
    : _api = api.PmartApiCustomerAssistant(dio: dio).getFaqsApi();

  final api.FaqsApi _api;

  @override
  Future<FaqList> list({String? q, String? category}) async {
    final res = await pmartGuard(
      () => _api.listCustomerFaqs(q: q, category: category),
    );
    return faqListFromContract(
      res.data ?? (throw const ContractViolationFailure('FAQ 목록 본문 없음')),
    );
  }

  @override
  Future<Faq> get(String faqId) async {
    final res = await pmartGuard(() => _api.getCustomerFaq(faqId: faqId));
    return faqFromContract(
      res.data ?? (throw const ContractViolationFailure('FAQ 본문 없음')),
    );
  }

  @override
  Future<bool> sendFeedback(
    String faqId, {
    required bool helpful,
    required IdempotencyKey key,
  }) async {
    final res = await pmartGuard(
      () => _api.sendFaqFeedback(
        faqId: faqId,
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        extra: commandOptions(key).extra,
        sendFaqFeedbackRequest: api.SendFaqFeedbackRequest(helpful: helpful),
      ),
    );
    // 본문이 없으면 반영됐는지 모른다 — 같은 키로 다시.
    return (res.data ?? (throw UnknownResultFailure(requestId: key.value)))
        .helpful;
  }
}

Faq faqFromContract(api.FaqItem f) => Faq(
  faqId: f.faqId,
  category: f.category,
  categoryTitle: f.categoryTitle,
  question: f.question,
  answer: f.answer,
  myFeedback: f.myFeedback,
);

FaqList faqListFromContract(api.FaqList l) => FaqList(
  items: [for (final f in l.items) faqFromContract(f)],
  categories: [
    for (final c in l.categories)
      FaqCategory(category: c.category, title: c.title, count: c.count),
  ],
);
