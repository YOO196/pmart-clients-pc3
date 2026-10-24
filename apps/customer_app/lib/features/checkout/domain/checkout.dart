import 'package:flutter/foundation.dart';

import '../../../shared/order_status.dart';

/// 한집(SINGLE) / 알뜰(BUNDLED) / 예약(SCHEDULED). 이름은 잠정("한집/알뜰/예약" 유지).
enum DeliveryMode { single, bundled, scheduled }

/// 배송 방식 선택지. [unavailableReason] 은 계약에 없어서 목에서만 채운다(BR-13).
@immutable
class DeliveryOption {
  const DeliveryOption(this.mode, {this.unavailableReason});

  final DeliveryMode mode;

  /// BR-13: 지금 이 방식이 안 되는 이유(심야·휴무 등). 실서버에서는 아직 항상 null.
  final String? unavailableReason;

  bool get available => unavailableReason == null;
}

/// 도착 구간. 날짜는 Asia/Seoul `YYYY-MM-DD`, 시각은 `HH:mm`.
@immutable
class ArrivalWindow {
  const ArrivalWindow({
    required this.date,
    required this.start,
    required this.end,
  });

  final String date;
  final String start;
  final String end;

  @override
  bool operator ==(Object other) =>
      other is ArrivalWindow &&
      other.date == date &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(date, start, end);
}

/// 슬롯 상태. CONFIG_REQUIRED(정원 미설정)는 0도 무제한도 아니고 선택 불가다.
enum SlotAvailability { available, full, closed, configRequired, unavailable }

@immutable
class Slot {
  const Slot({
    required this.window,
    required this.availability,
    this.slotId,
    this.remaining,
    this.cutoffAt,
  });

  final String? slotId;
  final ArrivalWindow window;
  final SlotAvailability availability;

  /// 남은 정원 사본(선택 성공 보장 아님). 미설정이면 null.
  final int? remaining;
  final DateTime? cutoffAt;

  bool get selectable => availability == SlotAvailability.available;
}

enum OutOfStockPreference { cancelOutOfStockOnly, cancelAll }

/// 배달팁 사유. 서버 값만 표시한다(앱이 무료 여부를 계산하지 않는다).
enum TipReason { standard, over30000, firstPurchase, none, unknown }

@immutable
class Quote {
  const Quote({
    required this.version,
    required this.tipReason,
    this.expiresAt,
    this.itemAmount,
    this.deliveryTip,
    this.bagFee,
    this.totalAmount,
    this.minOrderSatisfied,
    this.plannedShipments,
  });

  final int version;

  /// 가격 동결 만료(초안 생성 + 10분). 재고 예약 만료와 별개다.
  final DateTime? expiresAt;
  final int? itemAmount;
  final int? deliveryTip;
  final TipReason tipReason;
  final int? bagFee;
  final int? totalAmount;

  /// 최소 주문금액 충족 여부(서버 판정). 모르면 null. 부족액은 계약에 없다(BR-14).
  final bool? minOrderSatisfied;

  /// 2 이상이면 분할배송(10,000g 초과).
  final int? plannedShipments;
}

enum HoldState { notNeeded, held, failed, released, unknown, other }

enum PaymentProgress {
  notStarted,
  started,
  approved,
  failed,
  unknown,
  mismatch,
}

@immutable
class DraftResources {
  const DraftResources({
    required this.inventory,
    required this.capacity,
    required this.slot,
    required this.payment,
    this.reservationExpiresAt,
  });

  final HoldState inventory;
  final HoldState capacity;
  final HoldState slot;
  final PaymentProgress payment;

  /// 재고 예약 만료. 가격 동결과 별개다.
  final DateTime? reservationExpiresAt;
}

/// 서버가 알려 준 다음 행동. 결제 버튼은 [pay] 일 때만 연다.
enum DraftNext { review, reQuote, pay, wait, done, expired, unknown }

@immutable
class OrderDraft {
  const OrderDraft({
    required this.draftId,
    required this.version,
    required this.status,
    required this.next,
    this.quote,
    this.resources,
    this.orderId,
  });

  final String draftId;
  final int version;
  final OrderStatus status;
  final Quote? quote;
  final DraftResources? resources;
  final DraftNext next;

  /// 확정 시에만 있다. 이것과 확정 상태가 있어야 "주문 완료"다.
  final String? orderId;

  /// 가격 동결·재고 예약 중 더 이른 만료(안내용). 앱 타이머로 확보를 풀지 않는다.
  DateTime? get earliestExpiry {
    final a = quote?.expiresAt;
    final b = resources?.reservationExpiresAt;
    if (a == null) return b;
    if (b == null) return a;
    return a.isBefore(b) ? a : b;
  }
}

@immutable
class DraftLine {
  const DraftLine({
    required this.cartItemId,
    required this.sku,
    required this.quantity,
  });

  final String cartItemId;
  final String sku;
  final int quantity;
}

@immutable
class DraftRequest {
  const DraftRequest({
    required this.purchaseIntentId,
    required this.lines,
    required this.shoppingAddressId,
    required this.mode,
    required this.outOfStock,
    this.expectedMfcId,
    this.window,
    this.deliveryNote,
    this.bagOptOut = false,
  });

  /// 같은 주문 의도 식별. "주문하기" 한 번에 하나.
  final String purchaseIntentId;
  final List<DraftLine> lines;
  final String shoppingAddressId;
  final String? expectedMfcId;
  final DeliveryMode mode;
  final ArrivalWindow? window;
  final OutOfStockPreference outOfStock;
  final String? deliveryNote;
  final bool bagOptOut;
}

/// 결제 진입 요청 결과. ACCEPTED 는 사가 시작일 뿐 재고·슬롯·결제 성공이 아니다.
@immutable
sealed class CheckoutStart {
  const CheckoutStart();
}

final class CheckoutAccepted extends CheckoutStart {
  const CheckoutAccepted(this.requestId);

  final String requestId;
}

/// 가격 동결이 끝났거나 가격이 바뀌었다. 새 견적을 받아 전후 비교·재동의한다.
final class CheckoutReQuote extends CheckoutStart {
  const CheckoutReQuote();
}

final class CheckoutDraftExpired extends CheckoutStart {
  const CheckoutDraftExpired();
}

final class CheckoutRejected extends CheckoutStart {
  const CheckoutRejected(this.code);

  final String code;
}

/// 시작됐는지 모른다. 초안 조회로 확인한다(결제를 다시 누르게 하지 않는다).
final class CheckoutUnknown extends CheckoutStart {
  const CheckoutUnknown();
}

abstract final class CheckoutProblemCode {
  static const reQuoteRequired = 'RE_QUOTE_REQUIRED';
  static const draftExpired = 'DRAFT_EXPIRED';
  static const minOrderAmount = 'MIN_ORDER_AMOUNT';
  static const outOfServiceArea = 'OUT_OF_SERVICE_AREA';
  static const weightUnsplittable = 'WEIGHT_UNSPLITTABLE';
}
