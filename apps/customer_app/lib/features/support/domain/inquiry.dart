import 'package:flutter/foundation.dart';

/// 고객센터 문의(case-service 0.2.0 `inquiries`, 백엔드 요청 2026-11-09 customer-inquiry-page).
/// 문의는 접수일 뿐이다 — 취소·환불을 실행하지 않는다. 회원만 쓸 수 있다.

/// 계약 `InquiryCategory`.
enum InquiryCategory {
  order('ORDER'),
  delivery('DELIVERY'),
  payment('PAYMENT'),
  refund('REFUND'),
  product('PRODUCT'),
  account('ACCOUNT'),
  other('OTHER');

  const InquiryCategory(this.wire);

  final String wire;

  /// 모르는 값은 null(화면은 종류를 비워 보인다 — 다른 종류로 바꿔 보이지 않는다).
  static InquiryCategory? fromWire(String? wire) {
    for (final c in values) {
      if (c.wire == wire) return c;
    }
    return null;
  }
}

/// 계약 `InquiryStatus`. 종료(CLOSED) API 는 아직 없다.
enum InquiryStatus {
  received,
  answered,
  closed,
  unknown;

  static InquiryStatus fromWire(String? wire) => switch (wire) {
    'RECEIVED' => received,
    'ANSWERED' => answered,
    'CLOSED' => closed,
    _ => unknown,
  };
}

/// 어디서 남긴 문의인지(계약 `origin`).
enum InquiryOrigin {
  /// 문의 페이지에서 직접.
  inquiryPage('INQUIRY_PAGE'),

  /// AI 상담이 답하지 못해 넘어옴.
  assistantHandoff('ASSISTANT_HANDOFF');

  const InquiryOrigin(this.wire);

  final String wire;
}

/// 계약 한도.
const inquiryTitleMax = 100;
const inquiryBodyMax = 2000;

/// 문의 남기기 본문.
@immutable
class InquiryDraft {
  const InquiryDraft({
    required this.category,
    required this.body,
    this.orderId,
    this.title,
    this.origin = InquiryOrigin.inquiryPage,
  });

  final InquiryCategory category;
  final String body;
  final String? orderId;
  final String? title;
  final InquiryOrigin origin;
}

@immutable
class InquirySummary {
  const InquirySummary({
    required this.inquiryId,
    required this.status,
    required this.createdAt,
    this.category,
    this.orderId,
    this.title,
    this.answeredAt,
  });

  final String inquiryId;
  final InquiryCategory? category;
  final InquiryStatus status;
  final DateTime createdAt;
  final String? orderId;
  final String? title;
  final DateTime? answeredAt;
}

@immutable
class InquiryReply {
  const InquiryReply({required this.body, this.replyId, this.createdAt});

  final String? replyId;
  final String body;
  final DateTime? createdAt;
}

@immutable
class InquiryDetail {
  const InquiryDetail({
    required this.summary,
    required this.body,
    required this.replies,
  });

  final InquirySummary summary;
  final String body;
  final List<InquiryReply> replies;
}

@immutable
class InquiryPage {
  const InquiryPage({required this.items, this.nextCursor});

  final List<InquirySummary> items;
  final String? nextCursor;
}

abstract final class InquiryProblemCode {
  /// 남의·없는 주문(422).
  static const orderNotFound = 'ORDER_NOT_FOUND';
}
