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

/// 계약 `InquiryStatus`. 닫기는 `POST /inquiries/{id}/closures`(case 0.19.0, 다시 열기 없음).
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

/// 배송 신고 종류(case 0.16.0 `deliveryIssue`, 지연은 0.23.0). 문의 종류 DELIVERY + 주문과 함께 보낸다.
enum DeliveryIssue {
  /// 늦어요 — 확정 뒤 ~ 배송 완료 전만(그 밖 422 `ORDER_NOT_IN_PROGRESS`).
  delayed('DELAYED'),

  /// 못 받았어요(완료 뒤).
  notReceived('NOT_RECEIVED'),

  /// 다른 곳에 왔어요.
  misdelivered('MISDELIVERED');

  const DeliveryIssue(this.wire);

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
    this.deliveryIssue,
    this.deliveryId,
    this.photoIds = const [],
  });

  /// 먼저 `POST /inquiry-photos` 로 올린 사진(case 0.14.0, 문의 하나에 [inquiryPhotosMax] 장).
  final List<String> photoIds;

  final InquiryCategory category;
  final String body;
  final String? orderId;
  final String? title;
  final InquiryOrigin origin;

  /// 배송 신고면 그 종류(종류 DELIVERY·주문 필수).
  final DeliveryIssue? deliveryIssue;

  /// 배송 신고의 배송 ID(선택, 참고값).
  final String? deliveryId;
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

/// 남긴 만족도(case 0.15.0 — 답변 뒤 한 번, 고치기 없음).
@immutable
class InquirySatisfactionView {
  const InquirySatisfactionView({required this.score, this.comment});

  final int score;
  final String? comment;
}

@immutable
class InquiryDetail {
  const InquiryDetail({
    required this.summary,
    required this.body,
    required this.replies,
    this.photoIds = const [],
    this.satisfaction,
    this.closedAt,
  });

  final InquirySummary summary;
  final String body;
  final List<InquiryReply> replies;

  /// 붙은 사진(본문은 `GET /inquiry-photos/{id}` — 본인 토큰).
  final List<String> photoIds;
  final InquirySatisfactionView? satisfaction;
  final DateTime? closedAt;

  bool get closed => summary.status == InquiryStatus.closed;

  /// 만족도를 남길 수 있다: 답변을 받았고 아직 안 남겼다. 최종 판정은 서버(409).
  bool get canRate => replies.isNotEmpty && satisfaction == null;
}

/// 문의 하나에 붙일 수 있는 사진 수(계약).
const inquiryPhotosMax = 5;

/// 만족도 의견 한도(계약).
const inquiryCommentMax = 200;

@immutable
class InquiryPage {
  const InquiryPage({required this.items, this.nextCursor});

  final List<InquirySummary> items;
  final String? nextCursor;
}

abstract final class InquiryProblemCode {
  /// 남의·없는 주문(422).
  static const orderNotFound = 'ORDER_NOT_FOUND';

  /// 지연 신고인데 진행 중 주문이 아님(422, case 0.23.0).
  static const orderNotInProgress = 'ORDER_NOT_IN_PROGRESS';

  /// 내가 올린 사진이 아니거나 이미 다른 문의에 붙음(422) — 문의도 남지 않는다.
  static const photoNotFound = 'PHOTO_NOT_FOUND';

  /// 사진 형식·크기(422).
  static const photoInvalid = 'PHOTO_INVALID';

  /// 닫힌 문의(409).
  static const inquiryClosed = 'INQUIRY_CLOSED';

  /// 답변 전 만족도(409).
  static const notAnswered = 'INQUIRY_NOT_ANSWERED';

  /// 이미 만족도를 남김(409).
  static const alreadyRated = 'ALREADY_RATED';
}
