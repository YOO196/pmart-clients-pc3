import 'package:dio/dio.dart';
import 'package:pmart_api_delivery_capacity/pmart_api_delivery_capacity.dart'
    as cap;
import 'package:pmart_api_order/pmart_api_order.dart' as api;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/order_status.dart';
import '../../../shared/providers.dart' show sourceSystem;
import '../../payment/domain/payment.dart' show PaymentEntry;
import '../../address/domain/address.dart' show EntranceMethod;
import '../domain/checkout.dart';

/// 배송 방식·슬롯·주문 초안·결제 진입. 조회 실패는 [PmartFailure] 로 던진다.
abstract interface class CheckoutRepository {
  /// 배송 방식별 가능 여부·사유·예상시간·배달팁·가장 빠른 슬롯(`GET /delivery-options`, BR-13).
  /// [itemAmount] 는 서버 값(장바구니 selectedItemAmount)만 넘긴다. 주면 무료 사유를 적용한 배달팁도 온다.
  Future<List<DeliveryOption>> options(String mfcId, {int? itemAmount});

  /// 날짜(Asia/Seoul `YYYY-MM-DD`)의 예약 슬롯.
  Future<List<Slot>> slots(String mfcId, String date);

  /// `POST /order-drafts`. 같은 키·같은 본문 재전송은 기존 초안을 돌려준다.
  /// 결과 불명은 [UnknownResultFailure] 로 던진다(같은 키 재전송으로 해소).
  Future<OrderDraft> createDraft(
    DraftRequest request, {
    required IdempotencyKey key,
  });

  Future<OrderDraft> getDraft(String draftId);

  /// `POST /order-drafts/{id}/checkouts`.
  Future<CheckoutStart> startCheckout(
    String draftId, {
    required int expectedVersion,
    required int acceptedQuoteVersion,
    required IdempotencyKey key,
  });
}

final class ApiCheckoutRepository implements CheckoutRepository {
  ApiCheckoutRepository(Dio dio)
    : _slots = cap.PmartApiDeliveryCapacity(dio: dio).getSlotsApi(),
      _drafts = api.PmartApiOrder(dio: dio).getDraftsApi();

  final cap.SlotsApi _slots;
  final api.DraftsApi _drafts;

  @override
  Future<List<DeliveryOption>> options(String mfcId, {int? itemAmount}) async {
    final res = await pmartGuard(
      () => _drafts.getDeliveryOptions(mfcId: mfcId, itemAmount: itemAmount),
    );
    return optionsFromContract(
      res.data ?? (throw const ContractViolationFailure('배송 방식 본문 없음')),
    );
  }

  @override
  Future<List<Slot>> slots(String mfcId, String date) async {
    final res = await pmartGuard(
      () => _slots.listSlots(mfcId: mfcId, date: date),
    );
    return slotsFromContract(
      res.data ?? (throw const ContractViolationFailure('슬롯 본문 없음')),
    );
  }

  @override
  Future<OrderDraft> createDraft(
    DraftRequest r, {
    required IdempotencyKey key,
  }) async {
    final res = await pmartGuard(
      () => _drafts.createOrderDraft(
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        createDraftRequest: draftRequestToContract(r),
        extra: commandOptions(key).extra,
      ),
    );
    return draftFromContract(
      // 2xx 인데 본문이 없으면 만들어졌는지 모른다.
      res.data ?? (throw UnknownResultFailure(requestId: key.value)),
    );
  }

  @override
  Future<OrderDraft> getDraft(String draftId) async {
    final res = await pmartGuard(() => _drafts.getOrderDraft(draftId: draftId));
    return draftFromContract(
      res.data ?? (throw const ContractViolationFailure('초안 본문 없음')),
    );
  }

  @override
  Future<CheckoutStart> startCheckout(
    String draftId, {
    required int expectedVersion,
    required int acceptedQuoteVersion,
    required IdempotencyKey key,
  }) async {
    try {
      final res = await pmartGuard(
        () => _drafts.startCheckout(
          draftId: draftId,
          idempotencyKey: key.value,
          xSourceSystem: sourceSystem,
          xExpectedVersion: expectedVersion,
          startCheckoutRequest: api.StartCheckoutRequest(
            acceptedQuoteVersion: acceptedQuoteVersion,
            paymentMethod:
                api.StartCheckoutRequestPaymentMethodEnum.TOSS_PAYMENTS,
          ),
          extra: commandOptions(key, expectedVersion: expectedVersion).extra,
        ),
      );
      return switch (res.data?.status) {
        api.StartCheckout202ResponseStatusEnum.ACCEPTED ||
        api.StartCheckout202ResponseStatusEnum.APPLIED => CheckoutAccepted(
          res.data!.requestId,
        ),
        api.StartCheckout202ResponseStatusEnum.REJECTED => CheckoutRejected(
          res.data!.nextAction ?? ProblemCode.domainRejected,
        ),
        _ => const CheckoutUnknown(),
      };
    } on PmartFailure catch (f) {
      return checkoutFailureToStart(f);
    }
  }
}

CheckoutStart checkoutFailureToStart(PmartFailure f) => switch (f) {
  // 501 UNSUPPORTED_ACTION 은 "아직 지원하지 않음"이 확정된 응답이다(결제 진입은 ⑥ 전까지 501).
  // 변경 요청의 5xx 라도 결과 불명으로 두지 않는다.
  UnknownResultFailure(:final problem)
      when problem?.code == CheckoutProblemCode.unsupported =>
    const CheckoutRejected(CheckoutProblemCode.unsupported),
  UnknownResultFailure() => const CheckoutUnknown(),
  ProblemFailure(:final problem)
      when problem.code == CheckoutProblemCode.reQuoteRequired =>
    const CheckoutReQuote(),
  ProblemFailure(:final problem)
      when problem.code == CheckoutProblemCode.draftExpired =>
    const CheckoutDraftExpired(),
  ProblemFailure(:final problem) => CheckoutRejected(problem.code),
  _ => throw f,
};

List<DeliveryOption> optionsFromContract(api.DeliveryOptions c) => [
  for (final o in c.options ?? const <api.DeliveryOption>[])
    DeliveryOption(
      switch (o.mode) {
        api.DeliveryOptionModeEnum.SINGLE => DeliveryMode.single,
        api.DeliveryOptionModeEnum.BUNDLED => DeliveryMode.bundled,
        api.DeliveryOptionModeEnum.SCHEDULED => DeliveryMode.scheduled,
      },
      availability: switch (o.availability) {
        api.DeliveryOptionAvailabilityEnum.AVAILABLE =>
          OptionAvailability.available,
        api.DeliveryOptionAvailabilityEnum.UNAVAILABLE =>
          OptionAvailability.unavailable,
        api.DeliveryOptionAvailabilityEnum.CONFIG_REQUIRED =>
          OptionAvailability.configRequired,
        api.DeliveryOptionAvailabilityEnum.UNKNOWN =>
          OptionAvailability.unknown,
      },
      reason: switch (o.unavailableReason) {
        null => null,
        api.DeliveryOptionUnavailableReasonEnum.NIGHT_TIME =>
          UnavailableReason.nightTime,
        api.DeliveryOptionUnavailableReasonEnum.CENTER_CLOSED =>
          UnavailableReason.centerClosed,
        api.DeliveryOptionUnavailableReasonEnum.NO_SLOT =>
          UnavailableReason.noSlot,
        api.DeliveryOptionUnavailableReasonEnum.CONFIG_REQUIRED =>
          UnavailableReason.configRequired,
        api.DeliveryOptionUnavailableReasonEnum.LOOKUP_FAILED =>
          UnavailableReason.lookupFailed,
      },
      eta: switch (o.eta) {
        null => null,
        final e when e.state == api.DeliveryOptionEtaStateEnum.VALUE =>
          switch (e.value) {
            final Map<String, dynamic> v => Eta(
              minMinutes: (v['minMinutes'] as num?)?.toInt(),
              maxMinutes: (v['maxMinutes'] as num?)?.toInt(),
            ),
            // 값 모양이 다르면 모르는 것으로(0분으로 만들지 않는다).
            _ => null,
          },
        final e when e.state == api.DeliveryOptionEtaStateEnum.NOT_SET =>
          const Eta.notSet(),
        _ => null,
      },
      tip: switch (o.deliveryTip) {
        null => null,
        final t => OptionTip(
          base: t.base_,
          applied: t.applied,
          reason: switch (t.reason) {
            api.DeliveryOptionDeliveryTipReasonEnum.STANDARD =>
              TipReason.standard,
            api.DeliveryOptionDeliveryTipReasonEnum.OVER_30000 =>
              TipReason.over30000,
            api.DeliveryOptionDeliveryTipReasonEnum.FIRST_PURCHASE =>
              TipReason.firstPurchase,
            _ => TipReason.unknown,
          },
        ),
      },
      earliestSlot: switch (o.earliestSlot) {
        final w? => ArrivalWindow(date: w.date, start: w.start, end: w.end),
        null => null,
      },
      // order 0.22.0(BR-96): 최소 주문(PolicyValue — NOT_SET 이면 null, 0 으로 바꾸지 않는다)·배달팁 구간·운영 시간.
      minOrderAmount: switch (o.minOrderAmount) {
        final m?
            when m.state == api.DeliveryOptionMinOrderAmountStateEnum.VALUE =>
          switch (m.value) {
            final num v => v.toInt(),
            _ => null,
          },
        _ => null,
      },
      tipTiers: switch (o.deliveryTip?.tiers) {
        final ts? when ts.isNotEmpty => [
          for (final t in ts) (fromAmount: t.fromAmount, tip: t.tip),
        ],
        _ => null,
      },
      serviceHours: switch (c.serviceHours) {
        final h? => (start: h.start, end: h.end),
        null => null,
      },
    ),
];

List<Slot> slotsFromContract(cap.ListSlots200Response r) => [
  for (final s in r.slots ?? const <cap.Slot>[])
    if (s.window case final w?)
      Slot(
        slotId: s.slotId,
        window: ArrivalWindow(date: w.date, start: w.start, end: w.end),
        availability: switch (s.availability) {
          cap.SlotAvailabilityEnum.AVAILABLE => SlotAvailability.available,
          cap.SlotAvailabilityEnum.FULL => SlotAvailability.full,
          cap.SlotAvailabilityEnum.CLOSED => SlotAvailability.closed,
          cap.SlotAvailabilityEnum.CONFIG_REQUIRED =>
            SlotAvailability.configRequired,
          _ => SlotAvailability.unavailable,
        },
        // 정원 미설정이면 남은 수를 0 으로 보이지 않는다.
        remaining: s.capacity?.state == cap.SlotCapacityStateEnum.VALUE
            ? s.remaining
            : null,
        cutoffAt: s.cutoffAt,
      ),
];

api.CreateDraftRequest draftRequestToContract(DraftRequest r) =>
    api.CreateDraftRequest(
      purchaseIntentId: r.purchaseIntentId,
      items: [
        for (final l in r.lines)
          api.CreateDraftRequestItemsInner(
            cartItemId: l.cartItemId,
            sku: l.sku,
            quantity: l.quantity,
          ),
      ],
      shoppingAddressId: r.shoppingAddressId,
      expectedMfcId: r.expectedMfcId,
      deliveryMode: switch (r.mode) {
        DeliveryMode.single => api.CreateDraftRequestDeliveryModeEnum.SINGLE,
        DeliveryMode.bundled => api.CreateDraftRequestDeliveryModeEnum.BUNDLED,
        DeliveryMode.scheduled =>
          api.CreateDraftRequestDeliveryModeEnum.SCHEDULED,
      },
      arrivalWindow: switch (r.window) {
        final w? => api.ArrivalWindow(date: w.date, start: w.start, end: w.end),
        null => null,
      },
      outOfStockPreference: switch (r.outOfStock) {
        OutOfStockPreference.cancelOutOfStockOnly =>
          api.CreateDraftRequestOutOfStockPreferenceEnum.CANCEL_OOS_ONLY,
        OutOfStockPreference.cancelAll =>
          api.CreateDraftRequestOutOfStockPreferenceEnum.CANCEL_ALL,
      },
      deliveryNote: r.deliveryNote,
      couponId: r.couponId,
    );

HoldState _hold(String? wire) => switch (wire) {
  null => HoldState.unknown,
  'NOT_REQUESTED' || 'NOT_REQUIRED' => HoldState.notNeeded,
  'HELD' => HoldState.held,
  'FAILED' => HoldState.failed,
  'RELEASED' => HoldState.released,
  'UNKNOWN' => HoldState.unknown,
  _ => HoldState.other,
};

/// 주문 당시 배송지 사본(BR-37). 없거나(배포 전 초안·주문) 도로명이 비면 null — 현재 주소로 대신하지 않는다.
/// 받는 분·연락처는 없을 수 있다(order 0.14.0 — BR-60 R2·R4).
ShippingAddress? shippingAddressFromContract(api.ShippingAddress? s) {
  if (s == null) return null;
  final road = s.roadAddress;
  if (road == null) return null;
  String? text(String? v) => (v == null || v.trim().isEmpty) ? null : v;
  final name = text(s.receiverName);
  final phone = text(s.receiverPhone);
  return ShippingAddress(
    roadAddress: road,
    detailAddress: s.detailAddress ?? '',
    postalCode: s.postalCode,
    receiverName: name,
    receiverPhone: phone,
    entranceMethod: switch (s.entranceMethod) {
      api.ShippingAddressEntranceMethodEnum.FREE => EntranceMethod.free,
      api.ShippingAddressEntranceMethodEnum.PASSWORD => EntranceMethod.password,
      api.ShippingAddressEntranceMethodEnum.CALL => EntranceMethod.call,
      api.ShippingAddressEntranceMethodEnum.OTHER => EntranceMethod.other,
      _ => null,
    },
    entranceNote: s.entranceNote,
    lat: s.geo?.lat?.toDouble(),
    lng: s.geo?.lng?.toDouble(),
    capturedAt: s.capturedAt,
  );
}

OrderDraft draftFromContract(api.OrderDraft d) {
  final q = d.quote;
  final r = d.resources;
  return OrderDraft(
    draftId: d.draftId ?? (throw const ContractViolationFailure('draftId 없음')),
    version:
        d.version ?? (throw const ContractViolationFailure('초안 version 없음')),
    status: OrderStatus.fromWire(d.status?.value),
    orderId: d.orderId,
    next: switch (d.nextAction) {
      api.OrderDraftNextActionEnum.REVIEW => DraftNext.review,
      api.OrderDraftNextActionEnum.RE_QUOTE => DraftNext.reQuote,
      api.OrderDraftNextActionEnum.PAY => DraftNext.pay,
      api.OrderDraftNextActionEnum.WAIT => DraftNext.wait,
      api.OrderDraftNextActionEnum.DONE => DraftNext.done,
      api.OrderDraftNextActionEnum.EXPIRED => DraftNext.expired,
      null => DraftNext.unknown,
    },
    quote: q?.quoteVersion == null ? null : quoteFromContract(q!),
    shippingAddress: shippingAddressFromContract(d.delivery?.shippingAddress),
    lines: [
      for (final l in d.lines ?? const <api.DraftLine>[])
        if (l.sku case final sku?)
          DraftLineView(
            sku: sku,
            cartItemId: l.cartItemId,
            productName: l.productName,
            optionLabel: l.optionLabel,
            quantity: l.quantity,
            unitPrice: l.unitPrice,
          ),
    ],
    payment: switch (d.payment) {
      api.OrderDraftPayment(
        clientKey: final String clientKey,
        pgOrderId: final String pgOrderId,
        amount: final int amount,
      ) =>
        PaymentEntry(
          clientKey: clientKey,
          pgOrderId: pgOrderId,
          amount: amount,
          orderName: d.payment!.orderName ?? '',
          paymentAttemptId: d.payment!.paymentAttemptId,
          expiresAt: d.payment!.expiresAt,
        ),
      // 결제창에 필요한 값이 빠졌으면 결제창을 열지 않는다(대기로 둔다).
      _ => null,
    },
    checkoutFailure: switch (d.checkoutFailure) {
      api.OrderDraftCheckoutFailure(code: final String code) => CheckoutFailure(
        code: code,
        step: d.checkoutFailure!.step,
      ),
      _ => null,
    },
    blockers: [
      for (final b in d.blockers ?? const <api.DraftBlocker>[])
        switch (b.code) {
          api.DraftBlockerCodeEnum.MIN_ORDER_AMOUNT =>
            DraftBlocker.minOrderAmount,
          api.DraftBlockerCodeEnum.DELIVERY_MODE_UNAVAILABLE =>
            DraftBlocker.deliveryModeUnavailable,
          api.DraftBlockerCodeEnum.SLOT_REQUIRED => DraftBlocker.slotRequired,
          api.DraftBlockerCodeEnum.SLOT_UNAVAILABLE =>
            DraftBlocker.slotUnavailable,
          api.DraftBlockerCodeEnum.CONTACT_REQUIRED =>
            DraftBlocker.contactRequired,
          api.DraftBlockerCodeEnum.COUPON_NOT_APPLICABLE =>
            DraftBlocker.couponNotApplicable,
        },
    ],
    resources: r == null
        ? null
        : DraftResources(
            inventory: _hold(r.inventoryReservation?.value),
            capacity: _hold(r.capacityHold?.value),
            slot: _hold(r.slotHold?.value),
            payment: switch (r.payment?.value) {
              'NOT_STARTED' => PaymentProgress.notStarted,
              'STARTED' => PaymentProgress.started,
              'APPROVED' => PaymentProgress.approved,
              'FAILED' => PaymentProgress.failed,
              'MISMATCH' => PaymentProgress.mismatch,
              _ => PaymentProgress.unknown,
            },
            reservationExpiresAt: r.reservationExpiresAt,
          ),
  );
}

/// 견적(주문 초안·주문 공통). 값은 그대로 옮기고 계산하지 않는다.
Quote quoteFromContract(api.Quote q) => Quote(
  version: q.quoteVersion ?? 0,
  expiresAt: q.quoteExpiresAt,
  itemAmount: q.itemAmount,
  baseItemAmount: q.baseItemAmount,
  promotionDiscount: q.promotionDiscount,
  couponDiscount: q.couponDiscount,
  coupon: switch (q.coupon) {
    final c? => QuoteCoupon(
      couponId: c.couponId,
      applicable: c.applicable,
      reason: c.reason,
      name: switch (c.name?.trim()) {
        null || '' => null,
        final n => n,
      },
    ),
    null => null,
  },
  deliveryTip: q.deliveryTip,
  tipReason: switch (q.deliveryTipReason) {
    api.QuoteDeliveryTipReasonEnum.STANDARD => TipReason.standard,
    api.QuoteDeliveryTipReasonEnum.OVER_30000 => TipReason.over30000,
    api.QuoteDeliveryTipReasonEnum.FIRST_PURCHASE => TipReason.firstPurchase,
    api.QuoteDeliveryTipReasonEnum.NONE => TipReason.none,
    null => TipReason.unknown,
  },
  bagFee: q.bagFee,
  totalAmount: q.totalAmount,
  minOrderSatisfied: q.minOrderSatisfied,
  plannedShipments: q.plannedShipments,
  minOrderAmount: q.minOrderAmount,
  minOrderShortfall: q.minOrderShortfall,
  deliveryTipBase: q.deliveryTipBase,
  firstPurchase: switch (q.firstPurchaseBenefit) {
    api.QuoteFirstPurchaseBenefitEnum.EXPECTED => FirstPurchaseBenefit.expected,
    api.QuoteFirstPurchaseBenefitEnum.CHECKING_OTHER_ORDER =>
      FirstPurchaseBenefit.checkingOtherOrder,
    api.QuoteFirstPurchaseBenefitEnum.CONFIRMED =>
      FirstPurchaseBenefit.confirmed,
    api.QuoteFirstPurchaseBenefitEnum.NOT_ELIGIBLE =>
      FirstPurchaseBenefit.notEligible,
    _ => FirstPurchaseBenefit.unknown,
  },
);
