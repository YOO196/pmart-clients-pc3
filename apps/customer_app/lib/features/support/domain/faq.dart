import 'package:flutter/foundation.dart';

/// 자주 묻는 질문(customer-assistant 0.2.0 `GET /customer-assistant/faqs`). 고객 AI 상담과 같은 원문이다.
/// 회원 고객만(비회원 403). 답([answer])은 마크다운이다.
@immutable
class Faq {
  const Faq({
    required this.faqId,
    required this.category,
    required this.categoryTitle,
    required this.question,
    required this.answer,
  });

  final String faqId;
  final String category;
  final String categoryTitle;
  final String question;

  /// 마크다운(목록·굵게·표·소제목).
  final String answer;
}

@immutable
class FaqCategory {
  const FaqCategory({
    required this.category,
    required this.title,
    required this.count,
  });

  final String category;
  final String title;
  final int count;
}

@immutable
class FaqList {
  const FaqList({required this.items, required this.categories});

  final List<Faq> items;
  final List<FaqCategory> categories;
}

/// FAQ 조회 조건. 둘 다 없으면 전체.
@immutable
class FaqQuery {
  const FaqQuery({this.q, this.category});

  final String? q;
  final String? category;

  @override
  bool operator ==(Object other) =>
      other is FaqQuery && other.q == q && other.category == category;

  @override
  int get hashCode => Object.hash(q, category);
}

abstract final class FaqProblemCode {
  /// 서버 FAQ 색인이 아직 없음(422 — LAN 배포·색인 전).
  static const configRequired = 'CONFIG_REQUIRED';
}
