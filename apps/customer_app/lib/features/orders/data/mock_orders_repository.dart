import 'package:dio/dio.dart';
import 'package:pmart_api_delivery_tracking/pmart_api_delivery_tracking.dart'
    as trk;
import 'package:pmart_api_order/pmart_api_order.dart' as api;
import 'package:pmart_core/pmart_core.dart';

import '../../catalog/data/mock_catalog_repository.dart' show mockProducts;
import '../../checkout/data/mock_checkout_repository.dart';
import '../../checkout/domain/checkout.dart' show ArrivalWindow;
import '../../claims/domain/claims.dart' show RequestState;
import '../domain/orders.dart';
import 'orders_repository.dart';

/// 목 구현. 지난 주문 3건(분할배송 진행 중·완료·취소)과, 목 결제로 확정된 주문을 함께 보여 준다.
base class MockOrdersRepository implements OrdersRepository {
  MockOrdersRepository({
    this.checkout,
    this.latency = const Duration(milliseconds: 300),
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final MockCheckoutRepository? checkout;
  final Duration latency;
  final DateTime Function() now;

  /// 배송 위치 조회 실패 시연(주문·배송 상태와 별개).
  bool etaFails = false;

  /// 주문 JSON 을 직접 바꿔 진행을 흉내 낸다(테스트·취소 단계에서 쓴다).
  final overrides = <String, Map<String, Object?>>{};

  Future<void> _wait() => Future<void>.delayed(latency);

  static String _name(String sku) {
    for (final p in mockProducts) {
      if (p.sku == sku) return p.name;
      if (p.bundleSku == sku) return '${p.name} 2개 묶음';
    }
    return sku;
  }

  static const _quoteSeed = {
    'quoteVersion': 1,
    'itemAmount': 31780,
    'deliveryTip': 0,
    'deliveryTipReason': 'OVER_30000',
    'bagFee': 100,
    'totalAmount': 31880,
    'minOrderSatisfied': true,
    'plannedShipments': 2,
  };

  Map<String, Map<String, Object?>> _seeded() => {
    'order-seed-4': {
      'orderId': 'order-seed-4',
      'version': 2,
      'status': 'CONFIRMED',
      'mfcId': 'MFC-MOCK-01',
      'deliveryMode': 'SCHEDULED',
      'arrivalWindow': {'date': '2026-10-24', 'start': '18:00', 'end': '19:00'},
      'quote': {
        ..._quoteSeed,
        'itemAmount': 17940,
        'deliveryTip': 3000,
        'deliveryTipReason': 'STANDARD',
        'totalAmount': 21040,
        'plannedShipments': 1,
      },
      'lines': [
        {
          'orderLineId': 'ol-5',
          'sku': 'E-00000002',
          'productName': '그릭요거트 플레인 400g',
          'unitPrice': 5980,
          'originalQty': 3,
          'handedOverQty': 0,
          'cancelledBeforeShipQty': 0,
          'deliveredQty': 0,
        },
      ],
      'shipments': [
        {
          'shipmentId': 'sh-5',
          'deliveryId': 'dlv-s5',
          'lines': [
            {'orderLineId': 'ol-5', 'qty': 3},
          ],
          'state': 'PLANNED',
        },
      ],
      'payment': {'state': 'APPROVED', 'refundedAmount': 0},
      'claims': <Object?>[],
      'sources': [
        {
          'system': 'order-service',
          'asOf': {'asOf': '2026-10-24T02:58:00Z', 'freshness': 'CURRENT'},
        },
      ],
    },
    'order-seed-1': {
      'orderId': 'order-seed-1',
      'version': 7,
      'status': 'PARTIALLY_DELIVERED',
      'mfcId': 'MFC-MOCK-01',
      'deliveryMode': 'SINGLE',
      'quote': _quoteSeed,
      'lines': [
        {
          'orderLineId': 'ol-1',
          'sku': 'E-00000001',
          'productName': '서울우유 1L',
          'unitsPerSku': 1,
          'unitPrice': 2980,
          'originalQty': 10,
          'handedOverQty': 10,
          'deliveredQty': 10,
          'cancelledBeforeShipQty': 0,
          'returnedQty': 0,
          'unfulfilledQty': 0,
        },
        {
          'orderLineId': 'ol-2',
          'sku': 'E-00000005',
          'productName': '감자칩 오리지널 110g',
          'unitsPerSku': 1,
          'unitPrice': 1980,
          'originalQty': 1,
          'handedOverQty': 1,
          'deliveredQty': 0,
          'cancelledBeforeShipQty': 0,
          'returnedQty': 0,
          'unfulfilledQty': 0,
        },
      ],
      'shipments': [
        {
          'shipmentId': 'sh-1',
          'deliveryId': 'dlv-s1',
          'lines': [
            {'orderLineId': 'ol-1', 'qty': 10},
          ],
          'weightG': 10300,
          'state': 'DELIVERED',
        },
        {
          'shipmentId': 'sh-2',
          'deliveryId': 'dlv-s2',
          'lines': [
            {'orderLineId': 'ol-2', 'qty': 1},
          ],
          'weightG': 110,
          'state': 'IN_DELIVERY',
        },
      ],
      'payment': {
        'paymentAttemptId': 'pa-1',
        'state': 'APPROVED',
        'refundedAmount': 0,
      },
      'claims': [],
      'sources': [
        {
          'system': 'order-service',
          'asOf': {'asOf': '2026-10-24T02:58:00Z', 'freshness': 'CURRENT'},
        },
        {
          'system': 'delivery-execution-service',
          'asOf': {'asOf': '2026-10-24T02:40:00Z', 'freshness': 'STALE'},
        },
      ],
    },
    'order-seed-2': {
      'orderId': 'order-seed-2',
      'version': 9,
      'status': 'COMPLETED',
      'deliveryMode': 'BUNDLED',
      'quote': {
        ..._quoteSeed,
        'itemAmount': 16880,
        'deliveryTip': 3000,
        'deliveryTipReason': 'STANDARD',
        'totalAmount': 19980,
        'plannedShipments': 1,
      },
      'lines': [
        {
          'orderLineId': 'ol-3',
          'sku': 'E-00000002',
          'productName': '그릭요거트 플레인 400g',
          'unitPrice': 5980,
          'originalQty': 2,
          'deliveredQty': 2,
        },
      ],
      'shipments': [
        {
          'shipmentId': 'sh-3',
          'deliveryId': 'dlv-s3',
          'lines': [
            {'orderLineId': 'ol-3', 'qty': 2},
          ],
          'state': 'DELIVERED',
        },
      ],
      'payment': {'state': 'APPROVED', 'refundedAmount': 0},
      'sources': [
        {
          'system': 'order-service',
          'asOf': {'asOf': '2026-10-22T09:00:00Z', 'freshness': 'CURRENT'},
        },
      ],
    },
    'order-seed-3': {
      'orderId': 'order-seed-3',
      'version': 4,
      'status': 'CANCELLED',
      'deliveryMode': 'SCHEDULED',
      'arrivalWindow': {'date': '2026-10-20', 'start': '18:00', 'end': '19:00'},
      'quote': {
        ..._quoteSeed,
        'itemAmount': 15800,
        'deliveryTip': 3000,
        'deliveryTipReason': 'STANDARD',
        'totalAmount': 18900,
        'plannedShipments': 1,
      },
      'lines': [
        {
          'orderLineId': 'ol-4',
          'sku': 'E-00000003',
          'productName': '제주 감귤 1kg',
          'unitPrice': 7900,
          'originalQty': 2,
          'cancelledBeforeShipQty': 2,
        },
      ],
      'shipments': [
        {'shipmentId': 'sh-4', 'state': 'CANCELLED', 'lines': <Object?>[]},
      ],
      'payment': {'state': 'REFUNDED', 'refundedAmount': 18900},
      'claims': [
        {'claimId': 'clm-1', 'type': 'CANCEL', 'state': 'COMPLETED'},
      ],
      'sources': [
        {
          'system': 'order-service',
          'asOf': {'asOf': '2026-10-20T07:00:00Z', 'freshness': 'CURRENT'},
        },
      ],
    },
  };

  static const _orderedAt = {
    'order-seed-4': '2026-10-24T01:00:00Z',
    'order-seed-1': '2026-10-24T02:30:00Z',
    'order-seed-2': '2026-10-22T08:10:00Z',
    'order-seed-3': '2026-10-20T06:00:00Z',
  };

  /// 목 결제로 확정된 주문. 상품 준비 중, 배송 1건.
  Map<String, Object?> _fromCheckout(String orderId, MockDraft d) {
    final quote = d.json['quote']! as Map<String, Object?>;
    var i = 0;
    final lines = [
      for (final l in d.request.lines)
        {
          'orderLineId': '$orderId-l${++i}',
          'sku': l.sku,
          'productName': _name(l.sku),
          'unitPrice': MockCheckoutRepository.priceOf(l.sku),
          'originalQty': l.quantity,
          'handedOverQty': 0,
          'deliveredQty': 0,
          'cancelledBeforeShipQty': 0,
          'returnedQty': 0,
          'unfulfilledQty': 0,
        },
    ];
    return {
      'orderId': orderId,
      'version': 1,
      'status': 'CONFIRMED',
      'mfcId': d.request.expectedMfcId,
      'deliveryMode': d.request.mode.name.toUpperCase(),
      if (d.request.window case final w?)
        'arrivalWindow': {'date': w.date, 'start': w.start, 'end': w.end},
      'quote': quote,
      'lines': lines,
      'shipments': [
        {
          'shipmentId': '$orderId-sh1',
          'deliveryId': 'dlv-$orderId',
          'lines': [
            for (final l in lines)
              {'orderLineId': l['orderLineId'], 'qty': l['originalQty']},
          ],
          'state': 'PLANNED',
        },
      ],
      'payment': {'state': 'APPROVED', 'refundedAmount': 0},
      'claims': [],
      'sources': [
        {
          'system': 'order-service',
          'asOf': {
            'asOf': now().toUtc().toIso8601String(),
            'freshness': 'CURRENT',
          },
        },
      ],
    };
  }

  Map<String, Map<String, Object?>> _all() => {
    for (final e
        in (checkout?.confirmedOrders ?? const <String, MockDraft>{}).entries)
      e.key: _fromCheckout(e.key, e.value),
    ..._seeded(),
    ...overrides,
  };

  /// 현재 주문 JSON(취소 목 등에서 고쳐 쓴다).
  Map<String, Object?>? orderJson(String orderId) => _all()[orderId];

  @override
  Future<OrderPage> list({String? cursor}) async {
    await _wait();
    final all = _all();
    return orderPageFromContract(
      api.ListOrders200Response.fromJson({
        'items': [
          for (final e in all.entries)
            {
              'orderId': e.key,
              'status': e.value['status'],
              'orderedAt': _orderedAt[e.key] ?? now().toUtc().toIso8601String(),
              'totalAmount': (e.value['quote']! as Map)['totalAmount'],
              'itemCount': (e.value['lines']! as List).length,
            },
        ],
        'page': {'nextCursor': null, 'size': 50},
      }),
    );
  }

  @override
  Future<OrderDetail> get(String orderId) async {
    await _wait();
    final json = _all()[orderId];
    if (json == null) {
      throw const ProblemFailure(
        Problem(status: 404, code: ProblemCode.notFound),
      );
    }
    return orderFromContract(api.Order.fromJson(json));
  }

  @override
  Future<DeliveryEtaView> eta(String deliveryId) async {
    await _wait();
    if (etaFails) {
      throw const NetworkFailure(DioExceptionType.connectionTimeout);
    }
    final current = now().toUtc();
    final json = switch (deliveryId) {
      'dlv-s2' => {
        'deliveryId': deliveryId,
        'stage': 'TO_CUSTOMER',
        'dropEta': {
          'status': 'AVAILABLE',
          'etaAt': current.add(const Duration(minutes: 12)).toIso8601String(),
          'remainingSeconds': 720,
          'delayedBySeconds': 300,
          'calculatedAt': current.toIso8601String(),
        },
        'delayAlertTriggered': true,
        'riderLocationQuality': 'GOOD',
        'asOf': {'asOf': current.toIso8601String(), 'freshness': 'CURRENT'},
      },
      'dlv-s1' || 'dlv-s3' => {
        'deliveryId': deliveryId,
        'stage': 'DONE',
        'dropEta': {'status': 'FINAL'},
        'asOf': {'asOf': current.toIso8601String(), 'freshness': 'CURRENT'},
      },
      _ => {
        'deliveryId': deliveryId,
        'stage': 'UNASSIGNED',
        'dropEta': {'status': 'LOCATING'},
        'riderLocationQuality': 'UNKNOWN',
        'asOf': {'asOf': current.toIso8601String(), 'freshness': 'CURRENT'},
      },
    };
    return etaFromContract(deliveryId, trk.DeliveryEta.fromJson(json));
  }

  final _timeChanges =
      <String, ({String orderId, Map<String, String> window, int polls})>{};

  /// 다음 시간 변경을 서버가 거절하게 한다(정원 소진 등).
  bool rejectNextTimeChange = false;

  @override
  Future<void> requestTimeChange(
    String orderId,
    ArrivalWindow window, {
    required int expectedVersion,
    required IdempotencyKey key,
  }) async {
    await _wait();
    if (_timeChanges.containsKey(key.value)) return;
    final order = orderJson(orderId);
    if (order == null) {
      throw const ProblemFailure(
        Problem(status: 404, code: ProblemCode.notFound),
      );
    }
    if (order['status'] != 'CONFIRMED') {
      // 상품 준비에 들어가면 바꿀 수 없다.
      throw const ProblemFailure(
        Problem(status: 409, code: ProblemCode.invalidState),
      );
    }
    if (order['version'] != expectedVersion) {
      throw const ProblemFailure(
        Problem(status: 409, code: ProblemCode.versionConflict),
      );
    }
    _timeChanges[key.value] = (
      orderId: orderId,
      window: {'date': window.date, 'start': window.start, 'end': window.end},
      polls: 0,
    );
  }

  @override
  Future<RequestState> timeChange(String orderId, IdempotencyKey key) async {
    await _wait();
    final r = _timeChanges[key.value];
    if (r == null) return RequestState.unknown;
    if (r.polls == 0) {
      _timeChanges[key.value] = (
        orderId: r.orderId,
        window: r.window,
        polls: 1,
      );
      return RequestState.pending;
    }
    if (rejectNextTimeChange) {
      rejectNextTimeChange = false;
      _timeChanges.remove(key.value);
      return RequestState.rejected;
    }
    final order = orderJson(orderId)!;
    overrides[orderId] = {
      ...order,
      'arrivalWindow': r.window,
      'version': (order['version']! as int) + 1,
    };
    _timeChanges.remove(key.value);
    _confirmed.add(key.value);
    return RequestState.confirmed;
  }

  final _confirmed = <String>{};
}
