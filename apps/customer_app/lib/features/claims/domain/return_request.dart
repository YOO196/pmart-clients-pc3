import 'package:flutter/foundation.dart';

import '../../checkout/domain/checkout.dart' show ShippingAddress;

// 고객 앱 반품·교환 신청(레퍼런스 12, 사용자 2026-11-24 "1번 — 목으로 화면 구현 + BR 요청").
// 지금 계약은 인계 뒤 반품을 고객센터만 접수한다(claim 0.2.0, ADR-0060 결정 2) — 고객 접수·신청 자격 조회가
// 계약에 생기기 전까지 목에서만 쓴다. BR-95.

/// 반품(돌려받고 환불) / 교환(돌려받고 같은 상품 다시 배달).
enum ReturnRequestType { returnItems, exchange }

/// 이유 묶음 — 레퍼런스 탭 [변심·실수] [상품문제] [배달문제].
enum ReturnReasonGroup { changeOfMind, product, delivery }

/// 이유(레퍼런스 5-1·5-2·5-3 문구 순서).
enum ReturnReason {
  dislike(ReturnReasonGroup.changeOfMind),
  wrongOrder(ReturnReasonGroup.changeOfMind),
  wrongAddress(ReturnReasonGroup.changeOfMind),
  notAsDescribed(ReturnReasonGroup.product),
  malfunction(ReturnReasonGroup.product),
  spoiled(ReturnReasonGroup.product),
  foreignObject(ReturnReasonGroup.product),
  expired(ReturnReasonGroup.product),
  damaged(ReturnReasonGroup.delivery),
  partlyWrong(ReturnReasonGroup.delivery),
  allWrong(ReturnReasonGroup.delivery),
  partlyMissing(ReturnReasonGroup.delivery),
  notArrived(ReturnReasonGroup.delivery);

  const ReturnReason(this.group);

  final ReturnReasonGroup group;

  /// 교환 이유로 고를 수 있는지. "일부 안 왔어요"·"배달완료인데 안 왔어요"는 교환할 실물이 없어 빼고
  /// 오배송·누락 문의로 보낸다(BR-95 회신 2026-11-25 Q3).
  bool get exchangeable =>
      this != ReturnReason.partlyMissing && this != ReturnReason.notArrived;
}

/// 고를 수 있는 주문 품목 한 줄. 수량·기한·변심 가능 여부는 서버 판정(BR-95) — 앱은 표시·막기에만 쓴다.
@immutable
class ReturnableLine {
  const ReturnableLine({
    required this.orderLineId,
    required this.title,
    required this.orderedQty,
    required this.requestableQty,
    this.productId,
    this.imageUrl,
    this.unitPrice,
    this.lineAmount,
    this.changeOfMindAllowed = true,
    this.freshGuarantee = false,
  });

  final String orderLineId;
  final String? productId;
  final String title;
  final String? imageUrl;
  final int? unitPrice;
  final int? lineAmount;

  /// 받은 수량(전달 완료).
  final int orderedQty;

  /// 지금 신청할 수 있는 수량(받은 수량 − 진행·완료 클레임).
  final int requestableQty;

  /// 단순 변심·실수로 신청할 수 있는지(신선식품·냉동 등은 안 됨 — 서버 값). false 면 "교환 제한" 표시.
  final bool changeOfMindAllowed;

  /// 신선보장 상품 — "신선하지 않으면 교환해드립니다".
  final bool freshGuarantee;
}

/// 신청할 수 없는 품목(품절 취소·이미 신청·판매 중지 등) — "교환 불가 상품" 펼치기에 흐리게.
@immutable
class UnavailableLine {
  const UnavailableLine({
    required this.orderLineId,
    required this.title,
    required this.qty,
    this.imageUrl,
    this.unitPrice,
    this.lineAmount,
  });

  final String orderLineId;
  final String title;
  final String? imageUrl;
  final int? unitPrice;
  final int? lineAmount;
  final int qty;
}

/// 한 주문의 반품·교환 신청 자격(서버 판정 — BR-95).
@immutable
class ReturnEligibility {
  const ReturnEligibility({
    required this.orderId,
    required this.returnAllowed,
    required this.exchangeAllowed,
    required this.lines,
    required this.unavailable,
    this.changeOfMindFee,
    this.pickupAddress,
  });

  final String orderId;

  /// 앱에서 반품·교환을 신청할 수 있는 주문인지. false 면 그 칸을 흐리게 하고 고객센터 안내.
  final bool returnAllowed;
  final bool exchangeAllowed;

  final List<ReturnableLine> lines;
  final List<UnavailableLine> unavailable;

  /// 단순 변심·실수일 때 내는 배달팁(서버 값 — 지금 정책 9,000원). null 이면 모름(금액을 지어내지 않는다).
  final int? changeOfMindFee;

  /// 회수·재배달 주소(원주문 주소 고정 — 정책).
  final ShippingAddress? pickupAddress;
}

/// 신청 본문.
@immutable
class ReturnRequestDraft {
  const ReturnRequestDraft({
    required this.orderId,
    required this.type,
    required this.lines,
    required this.reason,
    this.detail,
    this.photos = const [],
    this.pickupNote,
    this.redeliveryNote,
  });

  final String orderId;
  final ReturnRequestType type;
  final List<({String orderLineId, int qty})> lines;
  final ReturnReason reason;
  final String? detail;

  /// 첨부 사진(목은 개수만 쓴다 — 올리기 API 는 BR-95).
  final List<Uint8List> photos;

  /// 라이더 요청사항(회수할 때·재배달할 때).
  final String? pickupNote;
  final String? redeliveryNote;
}

/// 상세 이유 글자 상한(레퍼런스 0/200).
const returnDetailMax = 200;

/// 사진 장수 상한(레퍼런스 0/3).
const returnPhotosMax = 3;

/// 신청 화면 입력이 서버로 보낼 만한지 — 앱 쪽 미리 막기만(최종 판정은 서버).
/// 문제(상품·배달) 사유는 상세 이유·사진이 필수, 변심 사유는 변심 불가 품목을 고를 수 없다.
enum ReturnDraftProblem {
  noLines,
  noReason,
  changeOfMindRestricted,
  needDetail,
  needPhoto,
}

List<ReturnDraftProblem> returnDraftProblems({
  required List<ReturnableLine> picked,
  required ReturnReason? reason,
  required String detail,
  required int photos,
}) => [
  if (picked.isEmpty) ReturnDraftProblem.noLines,
  if (reason == null) ReturnDraftProblem.noReason,
  if (reason?.group == ReturnReasonGroup.changeOfMind &&
      picked.any((l) => !l.changeOfMindAllowed))
    ReturnDraftProblem.changeOfMindRestricted,
  if (reason != null &&
      reason.group != ReturnReasonGroup.changeOfMind &&
      detail.trim().isEmpty)
    ReturnDraftProblem.needDetail,
  if (reason != null &&
      reason.group != ReturnReasonGroup.changeOfMind &&
      photos == 0)
    ReturnDraftProblem.needPhoto,
];
