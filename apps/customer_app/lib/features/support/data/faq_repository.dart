import 'package:dio/dio.dart';
import 'package:pmart_api_customer_assistant/pmart_api_customer_assistant.dart'
    as api;
import 'package:pmart_core/pmart_core.dart';

import '../domain/faq.dart';

/// 자주 묻는 질문 조회(customer-assistant 0.2.0). 실패는 [PmartFailure] 로 던진다(빈 목록으로 바꾸지 않는다).
abstract interface class FaqRepository {
  /// `GET /customer-assistant/faqs?q=&category=`.
  Future<FaqList> list({String? q, String? category});

  /// `GET /customer-assistant/faqs/{faqId}`.
  Future<Faq> get(String faqId);
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
}

Faq faqFromContract(api.FaqItem f) => Faq(
  faqId: f.faqId,
  category: f.category,
  categoryTitle: f.categoryTitle,
  question: f.question,
  answer: f.answer,
);

FaqList faqListFromContract(api.FaqList l) => FaqList(
  items: [for (final f in l.items) faqFromContract(f)],
  categories: [
    for (final c in l.categories)
      FaqCategory(category: c.category, title: c.title, count: c.count),
  ],
);
