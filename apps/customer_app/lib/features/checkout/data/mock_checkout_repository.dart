import 'package:pmart_api_delivery_capacity/pmart_api_delivery_capacity.dart'
    as cap;
import 'package:pmart_api_delivery_serviceability/pmart_api_delivery_serviceability.dart'
    as svc;
import 'package:pmart_api_order/pmart_api_order.dart' as api;
import 'package:pmart_core/pmart_core.dart';

import '../../catalog/data/mock_catalog_repository.dart' show mockProducts;
import '../domain/checkout.dart';
import 'checkout_repository.dart';

/// 목 초안 한 건(계약 OrderDraft JSON 을 직접 들고 있다).
final class MockDraft {
  MockDraft(this.json, this.request, this.createdAt);

  final Map<String, Object?> json;
  final DraftRequest request;
  final DateTime createdAt;
  int polls = 0;
}

/// 목 구현. 서버 규칙(최소주문 15,000원·배달팁·봉투값·10분 동결)을 흉내 내서 견적을 만든다.
/// 앱 화면은 이 값을 표시만 한다(앱은 계산하지 않는다).
base class MockCheckoutRepository implements CheckoutRepository {
  MockCheckoutRepository({
    this.latency = const Duration(milliseconds: 300),
    DateTime Function()? now,
    this.waitPolls = 1,
  }) : now = now ?? DateTime.now;

  final Duration latency;
  final DateTime Function() now;

  /// 초안 생성 뒤 몇 번 조회해야 자원 확보(nextAction=PAY)가 끝나는지.
  final int waitPolls;

  /// BR-13 시연: 지금 안 되는 방식과 사유.
  Map<DeliveryMode, String> unavailable = {};

  /// 첫 구매 무료 대상인지(서버 판정 흉내).
  bool firstPurchase = false;

  /// 다음 결제 진입을 가격 변경(RE_QUOTE_REQUIRED)으로 만든다.
  bool priceChangesOnCheckout = false;

  /// 다음 초안 생성을 "만들어졌지만 응답 잃음"으로 만든다.
  bool loseNextDraftResponse = false;

  final drafts = <String, MockDraft>{};
  final _byKey = <String, String>{};
  final checkoutKeys = <String>[];
  int _seq = 0;

  Future<void> _wait() => Future<void>.delayed(latency);

  @override
  Future<List<DeliveryOption>> options(String mfcId) async {
    await _wait();
    final base = optionsFromContract(
      svc.DeliveryConditions.fromJson({
        'mfcId': mfcId,
        'policyVersion': 1,
        'deliveryModes': ['SINGLE', 'BUNDLED', 'SCHEDULED'],
        'timeRestriction': {
          'state': 'WINDOW',
          'start': '00:00',
          'end': '08:00',
        },
      }),
    );
    // BR-13: 계약에는 방식별 가능 여부가 없다. 목에서만 사유를 붙인다.
    return [
      for (final o in base)
        DeliveryOption(o.mode, unavailableReason: unavailable[o.mode]),
    ];
  }

  @override
  Future<List<Slot>> slots(String mfcId, String date) async {
    await _wait();
    final current = now().toUtc();
    final slots = <Map<String, Object?>>[];
    // 09~22시 도착 1시간 구간(00~08시 도착 슬롯 없음). 마감은 시작 1시간 전(서울).
    for (var h = 9; h < 22; h++) {
      final start = DateTime.parse(
        '${date}T${h.toString().padLeft(2, '0')}:00:00+09:00',
      );
      final cutoff = start.subtract(const Duration(hours: 1));
      final closed = !current.isBefore(cutoff);
      final availability = closed
          ? 'CLOSED'
          : h == 13
          ? 'FULL'
          : h == 21
          ? 'CONFIG_REQUIRED'
          : 'AVAILABLE';
      slots.add({
        'slotId': 'slot-$date-$h',
        'window': {
          'date': date,
          'start': '${h.toString().padLeft(2, '0')}:00',
          'end': '${(h + 1).toString().padLeft(2, '0')}:00',
        },
        'capacity': h == 21
            ? {'state': 'NOT_SET'}
            : {'state': 'VALUE', 'value': 20},
        'remaining': h == 21 ? null : (h == 13 ? 0 : 7),
        'availability': availability,
        'cutoffAt': cutoff.toUtc().toIso8601String(),
      });
    }
    return slotsFromContract(
      cap.ListSlots200Response.fromJson({
        'mfcId': mfcId,
        'date': date,
        'slots': slots,
      }),
    );
  }

  static int priceOf(String sku) {
    for (final p in mockProducts) {
      if (p.sku == sku) return p.price;
      if (p.bundleSku == sku) return p.bundlePrice!;
    }
    throw ArgumentError(sku);
  }

  Map<String, Object?> _quote(
    DraftRequest r,
    int version,
    DateTime created, {
    int priceDelta = 0,
  }) {
    var items = priceDelta;
    for (final l in r.lines) {
      items += priceOf(l.sku) * l.quantity;
    }
    final (tip, reason) = items >= 30000
        ? (0, 'OVER_30000')
        : firstPurchase
        ? (0, 'FIRST_PURCHASE')
        : (r.mode == DeliveryMode.single ? 4000 : 3000, 'STANDARD');
    return {
      'quoteVersion': version,
      'quoteExpiresAt': created
          .add(const Duration(minutes: 10))
          .toUtc()
          .toIso8601String(),
      'priceVersion': version,
      'itemAmount': items,
      'deliveryTip': tip,
      'deliveryTipReason': reason,
      'bagFee': 100,
      'totalAmount': items + tip + 100,
      'minOrderSatisfied': items >= 15000,
      'weightG': 3000,
      'plannedShipments': 1,
    };
  }

  OrderDraft _out(MockDraft d) =>
      draftFromContract(api.OrderDraft.fromJson(d.json));

  @override
  Future<OrderDraft> createDraft(
    DraftRequest request, {
    required IdempotencyKey key,
  }) async {
    await _wait();
    final existing = _byKey[key.value];
    if (existing != null) return _out(drafts[existing]!);
    final id = 'draft-${++_seq}';
    final created = now();
    final d = MockDraft(
      {
        'draftId': id,
        'purchaseIntentId': request.purchaseIntentId,
        'version': 1,
        'status': 'RESOURCE_PENDING',
        'mfcId': request.expectedMfcId,
        'quote': _quote(request, 1, created),
        'resources': {
          'inventoryReservation': 'NOT_REQUESTED',
          'capacityHold': 'NOT_REQUESTED',
          'slotHold': request.mode == DeliveryMode.scheduled
              ? 'NOT_REQUESTED'
              : 'NOT_REQUIRED',
          'payment': 'NOT_STARTED',
        },
        'nextAction': 'WAIT',
      },
      request,
      created,
    );
    drafts[id] = d;
    _byKey[key.value] = id;
    if (waitPolls == 0) _settle(d);
    if (loseNextDraftResponse) {
      loseNextDraftResponse = false;
      throw UnknownResultFailure(requestId: key.value, httpStatus: 504);
    }
    return _out(d);
  }

  /// 자원 확보 결과를 반영한다(최소주문 미달이면 결제로 가지 않는다).
  void _settle(MockDraft d) {
    final quote = d.json['quote']! as Map<String, Object?>;
    final ok = quote['minOrderSatisfied'] == true;
    d.json
      ..['status'] = 'DRAFT'
      ..['version'] = (d.json['version']! as int) + 1
      ..['nextAction'] = ok ? 'PAY' : 'REVIEW'
      ..['resources'] = {
        'inventoryReservation': ok ? 'HELD' : 'NOT_REQUESTED',
        'capacityHold': ok ? 'HELD' : 'NOT_REQUESTED',
        'slotHold': d.request.mode == DeliveryMode.scheduled
            ? (ok ? 'HELD' : 'NOT_REQUESTED')
            : 'NOT_REQUIRED',
        'payment': 'NOT_STARTED',
        'reservationExpiresAt': d.createdAt
            .add(const Duration(minutes: 9))
            .toUtc()
            .toIso8601String(),
      };
  }

  @override
  Future<OrderDraft> getDraft(String draftId) async {
    await _wait();
    final d = drafts[draftId];
    if (d == null) {
      throw const ProblemFailure(
        Problem(status: 404, code: ProblemCode.notFound),
      );
    }
    if (d.json['nextAction'] == 'WAIT' &&
        d.json['status'] == 'RESOURCE_PENDING') {
      d.polls++;
      if (d.polls >= waitPolls) _settle(d);
    }
    final quote = d.json['quote']! as Map<String, Object?>;
    final expires = DateTime.parse(quote['quoteExpiresAt']! as String);
    if (!now().isBefore(expires) && d.json['nextAction'] == 'PAY') {
      d.json['nextAction'] = 'RE_QUOTE';
    }
    return _out(d);
  }

  @override
  Future<CheckoutStart> startCheckout(
    String draftId, {
    required int expectedVersion,
    required int acceptedQuoteVersion,
    required IdempotencyKey key,
  }) async {
    await _wait();
    checkoutKeys.add(key.value);
    final d = drafts[draftId]!;
    final quote = d.json['quote']! as Map<String, Object?>;
    final current = quote['quoteVersion']! as int;
    final expires = DateTime.parse(quote['quoteExpiresAt']! as String);
    final expired = !now().isBefore(expires);
    if (priceChangesOnCheckout || expired) {
      priceChangesOnCheckout = false;
      // 새 견적(가격 500원 인상)을 만들고 다시 동의를 요구한다.
      d.json
        ..['quote'] = _quote(d.request, current + 1, now(), priceDelta: 500)
        ..['version'] = (d.json['version']! as int) + 1
        ..['nextAction'] = 'PAY';
      return checkoutFailureToStart(
        const ProblemFailure(
          Problem(status: 422, code: CheckoutProblemCode.reQuoteRequired),
        ),
      );
    }
    if (acceptedQuoteVersion != current) {
      return checkoutFailureToStart(
        const ProblemFailure(
          Problem(status: 422, code: CheckoutProblemCode.reQuoteRequired),
        ),
      );
    }
    d.json
      ..['status'] = 'PAYMENT_PENDING'
      ..['nextAction'] = 'WAIT'
      ..['version'] = (d.json['version']! as int) + 1;
    (d.json['resources']! as Map<String, Object?>)['payment'] = 'STARTED';
    return CheckoutAccepted(key.value);
  }
}
