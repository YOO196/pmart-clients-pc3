import 'package:pmart_api_claim/pmart_api_claim.dart' as api;
import 'package:pmart_core/pmart_core.dart';

import '../../checkout/data/mock_checkout_repository.dart'
    show MockExternalPayments;
import '../../orders/data/mock_orders_repository.dart';
import '../../payment/domain/payment.dart';
import '../domain/claims.dart';
import 'claims_repository.dart';

/// 목 구현. 취소는 조회할 때마다 접수 → 출고 중지 확인(고객에게는 "확인 중") → 환불 진행 → 종결로 나아간다.
/// 배송이 시작된 주문은 취소를 받지 않는다(ORDER_NOT_CANCELLABLE).
base class MockClaimsRepository
    implements ClaimsRepository, MockExternalPayments {
  MockClaimsRepository({
    this.orders,
    this.latency = const Duration(milliseconds: 300),
    this.now,
  });

  final MockOrdersRepository? orders;
  final Duration latency;

  /// 목 시계(없으면 주문 목의 시계, 그것도 없으면 실제 시각).
  final DateTime Function()? now;

  DateTime get _clock => (now ?? orders?.now ?? DateTime.now)().toUtc();

  /// 목 결제 서비스가 회수비 결제를 승인할 때의 결과: true 승인, false 실패(이번 시도만), null 결과 없음(확인 중).
  bool? feeApproval = true;

  /// 상세를 이만큼 더 읽어야 회수비 결제 시도(paymentAttemptId)가 생긴다(준비 중 시연).
  int feeAttemptReadyAfter = 0;

  /// 받은 회수비 명령(시험용): (claimId, key).
  final feeRetries = <(String, String)>[];
  final _feeKeys = <String, Map<String, Object?>>{};
  final _failedFeeAttempts = <String>{};

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
    // 서버처럼 진행 중인 취소(자동 취소 포함)가 있으면 새로 받지 않는다.
    if (claims.values.any(
      (c) =>
          c['orderId'] == orderId &&
          c['type'] == 'CANCEL' &&
          !const {'WITHDRAWN', 'REJECTED', 'CLOSED'}.contains(c['state']),
    )) {
      throw const ProblemFailure(
        Problem(status: 422, code: ClaimProblemCode.duplicateClaim),
      );
    }
    final order = orders?.orderJson(orderId);
    final status = order?['status'];
    // 서버처럼 고객 취소는 상품 준비 전(CONFIRMED)만(claim 계약, ADR-0060). 주문을 모르면(목 밖) 막지 않는다.
    if (status != null && status != 'CONFIRMED') {
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

  /// 시스템 자동 전체 취소(MFC 작업 거절 뒤)를 만든다. 서버처럼 출고 중지 확인부터 시작한다(백엔드 공지 2026-11-07).
  String seedSystemCancel(String orderId) {
    final order = orders?.orderJson(orderId);
    final id = 'claim-${++_seq}';
    claims[id] = <String, Object?>{
      'claimId': id,
      'version': 1,
      'orderId': orderId,
      'type': 'CANCEL',
      'state': 'STOP_PENDING',
      'openedAt': orders?.now().toUtc().toIso8601String(),
      'reason': 'FULFILLMENT_REJECTED',
      'lines': [
        for (final l
            in (order?['lines'] as List? ?? const [])
                .cast<Map<String, Object?>>())
          if ((l['unfulfilledQty'] as int? ?? 0) > 0)
            {
              'claimLineId': '$id-${l['orderLineId']}',
              'orderLineId': l['orderLineId'],
              'requestedQty': l['unfulfilledQty'],
              'decision': 'PENDING',
              'refundAmount':
                  (l['unitPrice'] as int? ?? 0) *
                  (l['unfulfilledQty'] as int? ?? 0),
            },
      ],
      'refunds': <Object?>[],
    };
    return id;
  }

  /// 고객 사유 반품(회수비 결제 대기)을 만든다 — 고객센터가 접수한 것(앱은 반품을 접수하지 않는다).
  String seedReturnFee(
    String orderId, {
    Duration left = const Duration(hours: 24),
    String state = 'FEE_PENDING',
    String feeState = 'WAITING',
  }) {
    final id = 'claim-${++_seq}';
    final order = orders?.orderJson(orderId);
    final line = (order?['lines'] as List? ?? const [])
        .cast<Map<String, Object?>>()
        .firstOrNull;
    claims[id] = <String, Object?>{
      'claimId': id,
      'version': 1,
      'orderId': orderId,
      'type': 'RETURN',
      'state': state,
      'channel': 'CS',
      'reason': 'CHANGE_OF_MIND',
      'openedAt': _clock.toIso8601String(),
      'returnDeadlineAt': _clock.add(const Duration(days: 7)).toIso8601String(),
      'fees': {'returnPickupFee': 9000},
      'feePayment': {
        'amount': 9000,
        'orderName': '반품 회수비',
        'paymentAttemptId': 'PAY-RET-$id-1',
        'state': feeState,
        'deadlineAt': _clock.add(left).toIso8601String(),
      },
      'lines': [
        if (line != null)
          {
            'claimLineId': '$id-${line['orderLineId']}',
            'orderLineId': line['orderLineId'],
            'requestedQty': 1,
            'decision': 'PENDING',
          },
      ],
      'refunds': <Object?>[],
    };
    return id;
  }

  /// 시험용: 서버 상태를 바로 바꾼다(기한 지남 등).
  void setReturnState(String id, String state, {String? feeState}) {
    final c = claims[id]!;
    c['state'] = state;
    if (feeState != null) {
      c['feePayment'] = <String, Object?>{
        ...(c['feePayment']! as Map).cast<String, Object?>(),
        'state': feeState,
      };
    }
  }

  @override
  Future<ClaimView> retryFeePayment(
    String claimId, {
    required IdempotencyKey key,
  }) async {
    await _wait();
    feeRetries.add((claimId, key.value));
    final prev = _feeKeys[key.value];
    if (prev != null) return _out(prev);
    final c = claims[claimId];
    if (c == null) {
      throw const ProblemFailure(
        Problem(status: 404, code: ProblemCode.notFound),
      );
    }
    final fee = (c['feePayment'] as Map?)?.cast<String, Object?>();
    if (c['state'] != 'FEE_PENDING' || fee?['state'] != 'WAITING') {
      throw const ProblemFailure(
        Problem(status: 409, code: ProblemCode.invalidState),
      );
    }
    final attempt = fee!['paymentAttemptId'] as String?;
    if (attempt != null && _failedFeeAttempts.contains(attempt)) {
      final n = int.parse(attempt.split('-').last) + 1;
      c['feePayment'] = {...fee, 'paymentAttemptId': 'PAY-RET-$claimId-$n'};
      c['version'] = (c['version']! as int) + 1;
    }
    return _out(_feeKeys[key.value] = Map.of(c));
  }

  Map<String, Object?>? _byFeeAttempt(String attemptId) => claims.values
      .where((c) => (c['feePayment'] as Map?)?['paymentAttemptId'] == attemptId)
      .firstOrNull;

  @override
  AuthSubmitResult? submitAuth(PgAuthenticated auth) {
    final c = _byFeeAttempt(auth.pgOrderId);
    if (c == null) return null;
    final fee = (c['feePayment']! as Map).cast<String, Object?>();
    // 서버 검증 흉내: 금액이 다르거나 결제 대기가 아니면 승인하지 않는다.
    if (fee['amount'] != auth.amount ||
        fee['state'] != 'WAITING' ||
        c['state'] != 'FEE_PENDING') {
      return AuthSubmitResult.rejected;
    }
    switch (feeApproval) {
      case true:
        c
          ..['feePayment'] = {
            ...fee,
            'state': 'PAID',
            'paidAt': _clock.toIso8601String(),
          }
          ..['state'] = 'IN_PROGRESS'
          ..['pickup'] = {'state': 'REQUESTED', 'attempts': 1}
          ..['version'] = (c['version']! as int) + 1;
        return AuthSubmitResult.accepted;
      case false:
        _failedFeeAttempts.add(auth.pgOrderId);
        feeApproval = true;
        return AuthSubmitResult.rejected;
      case null:
        return AuthSubmitResult.accepted;
    }
  }

  @override
  bool reportAuthFailure(String pgOrderId, String errorCode) {
    if (_byFeeAttempt(pgOrderId) == null) return false;
    _failedFeeAttempts.add(pgOrderId);
    return true;
  }

  void _advance(Map<String, Object?> c) {
    // 반품은 서버(회수·검수)가 나아가게 한다 — 목은 결제 승인으로만 바뀐다.
    if (c['type'] != 'CANCEL') return;
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
    if (feeAttemptReadyAfter > 0 && c['type'] == 'RETURN') {
      feeAttemptReadyAfter--;
      final fee = (c['feePayment'] as Map?)?.cast<String, Object?>();
      return _out({
        ...c,
        if (fee != null) 'feePayment': {...fee, 'paymentAttemptId': null},
      });
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
