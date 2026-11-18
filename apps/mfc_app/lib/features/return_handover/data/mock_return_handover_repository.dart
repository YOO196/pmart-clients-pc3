import 'package:pmart_core/pmart_core.dart';

import '../domain/return_handover.dart';
import 'return_handover_repository.dart';

/// 목 구현.
/// - dlv-ret-1: 고객 반품 회수, 라이더 r-7, 번호 4821
/// - dlv-ret-2: 전달 실패 반납, 5번 틀려 잠김
base class MockReturnHandoverRepository implements ReturnHandoverRepository {
  MockReturnHandoverRepository({
    this.latency = const Duration(milliseconds: 300),
  }) {
    for (final h in _seed) {
      _byId[h.deliveryId] = h;
    }
  }

  final Duration latency;
  final _byId = <String, ReturnHandoverView>{};
  final _byKey = <String, ReissueOutcome>{};
  var _next = 0;

  /// 다음 새 번호 응답을 1회 잃는다(서버는 반영함).
  bool loseNextReissueResponse = false;

  int reissueCalls = 0;

  static final _seed = [
    ReturnHandoverView(
      deliveryId: 'dlv-ret-1',
      deliveryNumber: 'D-1118-0042',
      purpose: ReturnPurpose.claimReturn,
      state: 'RETURN_PICKED_UP',
      riderId: 'r-7',
      code: '4821',
      failedAttempts: 1,
      locked: false,
      issuedAt: DateTime.utc(2026, 11, 18, 5, 2),
    ),
    ReturnHandoverView(
      deliveryId: 'dlv-ret-2',
      deliveryNumber: 'D-1118-0051',
      purpose: ReturnPurpose.failedDeliveryReturn,
      state: 'ASSIGNED',
      riderId: 'r-9',
      code: '0397',
      failedAttempts: 5,
      locked: true,
      issuedAt: DateTime.utc(2026, 11, 18, 4, 40),
    ),
  ];

  Future<void> _wait() => Future<void>.delayed(latency);

  /// 라이더가 번호를 넣어 반납이 끝난 것처럼 목록에서 뺀다(테스트용).
  void returned(String deliveryId) => _byId.remove(deliveryId);

  @override
  Future<List<ReturnHandoverView>> waiting(String mfcId) async {
    await _wait();
    return _byId.values.toList();
  }

  @override
  Future<ReissueOutcome> reissue(
    String deliveryId, {
    required IdempotencyKey key,
  }) async {
    await _wait();
    reissueCalls++;
    final out = _byKey[key.value] ??= _apply(deliveryId);
    if (loseNextReissueResponse) {
      loseNextReissueResponse = false;
      return const ReissueUnknown();
    }
    return out;
  }

  ReissueOutcome _apply(String deliveryId) {
    final h = _byId[deliveryId];
    if (h == null) return const ReissueRejected(ProblemCode.invalidState);
    _next++;
    final fresh = ReturnHandoverView(
      deliveryId: h.deliveryId,
      deliveryNumber: h.deliveryNumber,
      purpose: h.purpose,
      state: h.state,
      riderId: h.riderId,
      code: (1000 + (_next * 1379) % 9000).toString(),
      failedAttempts: 0,
      locked: false,
      issuedAt: DateTime.utc(2026, 11, 18, 6, _next),
    );
    _byId[deliveryId] = fresh;
    return Reissued(fresh);
  }
}
