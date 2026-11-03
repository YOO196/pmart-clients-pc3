import 'package:pmart_api_claim/pmart_api_claim.dart' as api;
import 'package:pmart_core/pmart_core.dart';

import '../../orders/data/mock_orders_repository.dart';
import '../domain/claims.dart';
import 'claims_repository.dart';

/// 목 구현. 취소는 조회할 때마다 접수 → 출고 중지 확인(고객에게는 "확인 중") → 환불 진행 → 종결로 나아간다.
/// 배송이 시작된 주문은 취소를 받지 않는다(ORDER_NOT_CANCELLABLE).
base class MockClaimsRepository implements ClaimsRepository {
  MockClaimsRepository({
    this.orders,
    this.latency = const Duration(milliseconds: 300),
  });

  final MockOrdersRepository? orders;
  final Duration latency;

  final claims = <String, Map<String, Object?>>{};
  final _byKey = <String, String>{};
  final _withdrawals = <String, int>{};
  int _seq = 0;

  /// 다음 접수 응답을 1회 잃는다(같은 키 재전송 확인).
  bool loseNextCreateResponse = false;

  /// 접수 뒤 자동 진행을 멈춘다(철회 시연).
  bool holdAtOpened = false;

  /// 클레임 상세 조회 횟수(시험용: 끝 상태 뒤 조회가 멈추는지).
  int getCalls = 0;

  Future<void> _wait() => Future<void>.delayed(latency);

  ClaimView _out(Map<String, Object?> json) =>
      claimFromContract(api.Claim.fromJson(json));

  @override
  Future<ClaimView> requestCancel(
    String orderId,
    List<CancelLine> lines,
    CancelReason reason, {
    String? detail,
    required IdempotencyKey key,
  }) async {
    await _wait();
    final existing = _byKey[key.value];
    if (existing != null) return _out(claims[existing]!);
    final order = orders?.orderJson(orderId);
    final status = order?['status'];
    if (status == 'IN_DELIVERY' ||
        status == 'PARTIALLY_DELIVERED' ||
        status == 'COMPLETED' ||
        status == 'CANCELLED') {
      throw const ProblemFailure(
        Problem(status: 422, code: ClaimProblemCode.orderNotCancellable),
      );
    }
    // 서버처럼 주문 전체(모든 행 × 미이행 수량)만 받는다.
    final unfulfilled = {
      for (final l
          in (order?['lines'] as List? ?? const [])
              .cast<Map<String, Object?>>())
        if ((l['unfulfilledQty'] as int? ?? 0) > 0)
          l['orderLineId']: l['unfulfilledQty'] as int,
    };
    final requested = {for (final l in lines) l.orderLineId: l.qty};
    if (order != null &&
        (requested.length != unfulfilled.length ||
            unfulfilled.entries.any((e) => requested[e.key] != e.value))) {
      throw const ProblemFailure(
        Problem(status: 422, code: ClaimProblemCode.partialCancelNotAllowed),
      );
    }
    final id = 'claim-${++_seq}';
    final priceByLine = {
      for (final l
          in (order?['lines'] as List? ?? const [])
              .cast<Map<String, Object?>>())
        l['orderLineId']: l['unitPrice'] as int? ?? 0,
    };
    final json = <String, Object?>{
      'claimId': id,
      'version': 1,
      'orderId': orderId,
      'type': 'CANCEL',
      'state': 'OPENED',
      'openedAt': orders?.now().toUtc().toIso8601String(),
      'reason': 'CHANGE_OF_MIND',
      'lines': [
        for (final l in lines)
          {
            'claimLineId': '$id-${l.orderLineId}',
            'orderLineId': l.orderLineId,
            'requestedQty': l.qty,
            'decision': 'PENDING',
            'refundAmount': (priceByLine[l.orderLineId] ?? 0) * l.qty,
          },
      ],
      'refunds': <Object?>[],
    };
    claims[id] = json;
    _byKey[key.value] = id;
    // 서버처럼 주문 상세의 `claims` 는 비워 둔다. 처리 내역은 [listForOrder] 로 보인다.
    if (loseNextCreateResponse) {
      loseNextCreateResponse = false;
      throw UnknownResultFailure(requestId: key.value, httpStatus: 504);
    }
    return _out(json);
  }

  void _advance(Map<String, Object?> c) {
    final lines = (c['lines']! as List).cast<Map<String, Object?>>();
    final amount = lines.fold<int>(
      0,
      (s, l) => s + (l['refundAmount'] as int? ?? 0),
    );
    switch (c['state']) {
      case 'OPENED' when !holdAtOpened:
        c['state'] = 'STOP_PENDING';
      case 'STOP_PENDING':
        c['state'] = 'IN_PROGRESS';
        for (final l in lines) {
          l
            ..['decision'] = 'APPROVED'
            ..['approvedQty'] = l['requestedQty'];
        }
        c['refunds'] = [
          {
            'refundIntentId': 'rf-${c['claimId']}',
            'state': 'PG_PENDING',
            'amount': amount,
            'pgResult': 'UNKNOWN',
          },
        ];
      case 'IN_PROGRESS':
        c['state'] = 'CLOSED';
        final orderId = c['orderId']! as String;
        final order = orders?.orderJson(orderId);
        if (order != null) {
          orders!.overrides[orderId] = {
            ...order,
            'status': 'CANCELLED',
            'lines': [
              for (final l
                  in (order['lines'] as List? ?? const [])
                      .cast<Map<String, Object?>>())
                {
                  ...l,
                  'unfulfilledQty': 0,
                  'cancelledBeforeShipQty': l['originalQty'],
                },
            ],
            'payment': {'state': 'REFUNDED', 'refundedAmount': amount},
          };
        }
        c['refunds'] = [
          {
            'refundIntentId': 'rf-${c['claimId']}',
            'state': 'COMPLETED',
            'amount': amount,
            'pgResult': 'SUCCESS',
            'completedAt': '2026-10-24T04:00:00Z',
          },
        ];
    }
    c['version'] = (c['version']! as int) + 1;
  }

  @override
  Future<ClaimView> get(String claimId) async {
    await _wait();
    getCalls++;
    final c = claims[claimId];
    if (c == null) {
      throw const ProblemFailure(
        Problem(status: 404, code: ProblemCode.notFound),
      );
    }
    final view = _out(c);
    _advance(c);
    return view;
  }

  @override
  Future<List<ClaimSummaryView>> listForOrder(String orderId) async {
    await _wait();
    final mine = [
      for (final c in claims.values)
        if (c['orderId'] == orderId) _out(c),
    ];
    // 서버는 최근 순으로 준다.
    return [
      for (final v in mine.reversed)
        ClaimSummaryView(
          claimId: v.claimId,
          orderId: v.orderId,
          type: v.type,
          state: v.state,
          openedAt: switch (claims[v.claimId]!['openedAt']) {
            final String s => DateTime.parse(s),
            _ => null,
          },
        ),
    ];
  }

  @override
  Future<ClaimView?> findActiveCancel(String orderId) async {
    await _wait();
    final c = claims.values.lastWhere(
      (c) =>
          c['orderId'] == orderId &&
          c['type'] == 'CANCEL' &&
          c['state'] != 'WITHDRAWN' &&
          c['state'] != 'REJECTED',
      orElse: () => const {},
    );
    return c.isEmpty ? null : _out(c);
  }

  @override
  Future<void> withdraw(
    String claimId, {
    required int expectedVersion,
    required IdempotencyKey key,
  }) async {
    await _wait();
    final c = claims[claimId]!;
    if (c['state'] != 'OPENED') {
      throw const ProblemFailure(
        Problem(status: 409, code: ClaimProblemCode.invalidState),
      );
    }
    _withdrawals[key.value] = 0;
  }

  @override
  Future<RequestState> withdrawal(String claimId, IdempotencyKey key) async {
    await _wait();
    final n = _withdrawals[key.value];
    if (n == null) return RequestState.unknown;
    _withdrawals[key.value] = n + 1;
    if (n == 0) return RequestState.pending;
    claims[claimId]!['state'] = 'WITHDRAWN';
    return RequestState.confirmed;
  }
}
