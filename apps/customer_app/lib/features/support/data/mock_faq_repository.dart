import 'package:pmart_core/pmart_core.dart';

import '../domain/faq.dart';
import 'faq_repository.dart';

/// ⚠ 화면 개발·시험용 목. 실제 FAQ 원문이 아니다(서버는 고객 AI 상담의 안내 문서에서 만든다).
final class MockFaqRepository implements FaqRepository {
  MockFaqRepository({this.latency = const Duration(milliseconds: 200)});

  final Duration latency;

  /// 조회에 쓴 조건(순서대로).
  final queries = <({String? q, String? category})>[];

  /// 다음 조회에 던질 실패(시험용).
  PmartFailure? failNext;

  static const items = <Faq>[
    Faq(
      faqId: 'faq-cancel-1',
      category: 'CANCEL',
      categoryTitle: '취소',
      question: '주문을 취소하고 싶어요',
      answer:
          '## 취소할 수 있는 때\n\n'
          '- **상품 준비 전**에는 주문 상세에서 바로 취소할 수 있어요.\n'
          '- 상품 준비가 시작되면 취소할 수 없어요.\n\n'
          '| 상태 | 취소 |\n|---|---|\n| 주문 확인 | 가능 |\n| 상품 준비 중 | 불가 |\n',
    ),
    Faq(
      faqId: 'faq-delivery-1',
      category: 'DELIVERY',
      categoryTitle: '배달',
      question: '배달이 늦어지고 있어요',
      answer:
          '배달 현황에서 **도착 예정 시간**을 확인해 주세요.\n\n'
          '1. 주문 상세 → 문의하기\n2. "배달이 늦어지고 있어요"를 골라 남겨 주세요.\n',
    ),
    Faq(
      faqId: 'faq-refund-1',
      category: 'REFUND',
      categoryTitle: '환불',
      question: '환불은 언제 되나요?',
      answer: '결제 수단에 따라 **3~5일** 걸릴 수 있어요.',
    ),
  ];

  Future<void> _wait() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  void _maybeFail() {
    final f = failNext;
    if (f != null) {
      failNext = null;
      throw f;
    }
  }

  @override
  Future<FaqList> list({String? q, String? category}) async {
    await _wait();
    queries.add((q: q, category: category));
    _maybeFail();
    final needle = q?.trim().toLowerCase();
    final hits = [
      for (final f in items)
        if ((category == null || f.category == category) &&
            (needle == null ||
                needle.isEmpty ||
                f.question.toLowerCase().contains(needle) ||
                f.answer.toLowerCase().contains(needle)))
          f,
    ];
    final cats = <String, FaqCategory>{};
    for (final f in items) {
      final c = cats[f.category];
      cats[f.category] = FaqCategory(
        category: f.category,
        title: f.categoryTitle,
        count: (c?.count ?? 0) + 1,
      );
    }
    return FaqList(items: hits, categories: cats.values.toList());
  }

  @override
  Future<Faq> get(String faqId) async {
    await _wait();
    _maybeFail();
    return items.firstWhere(
      (f) => f.faqId == faqId,
      orElse: () => throw const ProblemFailure(
        Problem(status: 404, code: ProblemCode.notFound),
      ),
    );
  }
}
