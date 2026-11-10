import 'package:pmart_api_delivery_dispatch/pmart_api_delivery_dispatch.dart'
    as dsp;
import 'package:pmart_api_mfc_fulfillment/pmart_api_mfc_fulfillment.dart'
    as api;
import 'package:pmart_core/pmart_core.dart';

import '../domain/packing.dart';
import 'packing_repository.dart';

/// 목 구현. 출하 shp-2(task-mock-2 패킹): 그릭요거트 1 + 서울우유 2 를 담는다.
/// 모든 수량이 밀봉되면 출하가 READY 가 된다. 담을 수량을 넘으면 CONTENT_MISMATCH.
base class MockPackingRepository implements PackingRepository {
  MockPackingRepository({this.latency = const Duration(milliseconds: 300)});

  final Duration latency;

  /// 출하 shp-2 가 담아야 할 수량(피킹 확정분).
  static const expected = {'ol-1': 1, 'ol-2': 2};

  final _shipment = <String, Object?>{
    'shipmentId': 'shp-2',
    'fulfillmentId': 'ful-2',
    'orderId': 'order-seed-4',
    'deliveryId': 'dlv-2',
    'version': 1,
    'state': 'PREPARING',
    'packages': <Map<String, Object?>>[],
  };
  final _byKey = <String, String>{};
  final _dispatches = <String, int>{};
  int _seq = 0;

  /// 다음 밀봉 응답을 1회 잃는다(서버는 밀봉함).
  bool loseNextSealResponse = false;

  /// 다음 배차 요청을 주문 취소로 거절한다.
  bool orderCancelled = false;

  Future<void> _wait() => Future<void>.delayed(latency);

  List<Map<String, Object?>> get _packages =>
      (_shipment['packages']! as List).cast<Map<String, Object?>>();

  /// fence 를 걸어 인계 중인 것처럼 만든다(재포장 차단 시연).
  void startHandover(String packageId) {
    _packages.firstWhere((p) => p['packageId'] == packageId)['fence'] = {
      'state': 'HANDOVER_IN_PROGRESS',
      'fenceVersion': 1,
      'riderId': 'rider-mock-1',
    };
  }

  @override
  Future<ShipmentView> shipment(String shipmentId) async {
    await _wait();
    return shipmentFromContract(api.Shipment.fromJson(_shipment));
  }

  Map<String, int> _packed() {
    final m = <String, int>{};
    for (final p in _packages) {
      if (p['state'] != 'SEALED' && p['state'] != 'HANDED_OVER') continue;
      for (final c in (p['contents']! as List).cast<Map<String, Object?>>()) {
        final id = c['orderLineId']! as String;
        m[id] = (m[id] ?? 0) + (c['qty']! as int);
      }
    }
    return m;
  }

  PackOutcome _done(Map<String, Object?> p) =>
      PackDone(packageFromContract(api.Package.fromJson(p)));

  @override
  Future<PackOutcome> seal(
    String shipmentId,
    List<ContentLine> contents, {
    required int bagCount,
    required TemperatureZone zone,
    bool containsAlcohol = false,
    String? packedBy,
    required IdempotencyKey key,
  }) async {
    await _wait();
    final existing = _byKey[key.value];
    if (existing != null) {
      return _done(_packages.firstWhere((p) => p['packageId'] == existing));
    }
    if (_shipment['state'] != 'PREPARING' && _shipment['state'] != 'READY') {
      return packFailureToOutcome(
        const ProblemFailure(
          Problem(status: 409, code: PackProblemCode.invalidState),
        ),
      );
    }
    final packed = _packed();
    for (final c in contents) {
      final room =
          (expected[c.orderLineId] ?? 0) - (packed[c.orderLineId] ?? 0);
      if (c.qty > room) {
        return packFailureToOutcome(
          const ProblemFailure(
            Problem(status: 409, code: PackProblemCode.contentMismatch),
          ),
        );
      }
    }
    final id = 'pkg-${++_seq}';
    final p = <String, Object?>{
      'packageId': id,
      'packageVersion': 1,
      'shipmentId': shipmentId,
      'orderId': _shipment['orderId'],
      'version': 1,
      'state': 'SEALED',
      'qrCode': 'PKG:$id:1',
      'contents': [
        for (final c in contents)
          {
            'orderLineId': c.orderLineId,
            'sku': c.sku,
            'qty': c.qty,
            'lotId': ?c.lotId,
          },
      ],
      'bagCount': bagCount,
      'containsAlcohol': containsAlcohol,
      'temperatureZone': zone.name.toUpperCase(),
      'fence': {'state': 'NONE', 'fenceVersion': 0},
      'sealedAt': '2026-10-24T06:30:00Z',
    };
    _packages.add(p);
    _byKey[key.value] = id;
    _refreshShipment();
    if (loseNextSealResponse) {
      loseNextSealResponse = false;
      return packFailureToOutcome(
        UnknownResultFailure(requestId: key.value, httpStatus: 504),
      );
    }
    return _done(p);
  }

  void _refreshShipment() {
    final packed = _packed();
    final all = expected.entries.every((e) => (packed[e.key] ?? 0) >= e.value);
    _shipment
      ..['state'] = all ? 'READY' : 'PREPARING'
      ..['version'] = (_shipment['version']! as int) + 1;
  }

  @override
  Future<PackOutcome> repack(
    String packageId,
    RepackReason reason, {
    required IdempotencyKey key,
  }) async {
    await _wait();
    final existing = _byKey[key.value];
    if (existing != null) {
      return _done(_packages.firstWhere((p) => p['packageId'] == existing));
    }
    final old = _packages.firstWhere((p) => p['packageId'] == packageId);
    final fence = (old['fence'] as Map?)?['state'];
    if (old['state'] != 'SEALED' || (fence != null && fence != 'NONE')) {
      return packFailureToOutcome(
        const ProblemFailure(
          Problem(status: 409, code: PackProblemCode.invalidState),
        ),
      );
    }
    final version = (old['packageVersion']! as int) + 1;
    old
      ..['state'] = 'INVALIDATED'
      ..['invalidatedReason'] = reason.name;
    final id = 'pkg-${++_seq}';
    final p = {
      ...old,
      'packageId': id,
      'packageVersion': version,
      'state': 'SEALED',
      'qrCode': 'PKG:$id:$version',
      'invalidatedReason': null,
    };
    _packages.add(p);
    _byKey[key.value] = id;
    _refreshShipment();
    return _done(p);
  }

  @override
  Future<String?> requestDispatch({
    required String deliveryId,
    required String mfcId,
    required int packagingMinutes,
    required int bagCount,
    required bool coldChain,
    required List<String> packageIds,
    bool containsAlcohol = false,
    required IdempotencyKey key,
  }) async {
    await _wait();
    if (orderCancelled) {
      throw const ProblemFailure(
        Problem(status: 422, code: PackProblemCode.orderCancelled),
      );
    }
    // 같은 배송에 진행 중 시도가 있으면 그 시도를 돌려준다.
    final existing = _dispatches.keys.firstOrNull;
    if (existing != null) return existing;
    _dispatches[key.value] = 0;
    return key.value;
  }

  @override
  Future<DispatchView> dispatch(String requestId) async {
    await _wait();
    final n = _dispatches[requestId];
    if (n == null) {
      throw const ProblemFailure(
        Problem(status: 404, code: ProblemCode.notFound),
      );
    }
    _dispatches[requestId] = n + 1;
    final state = switch (n) {
      0 => 'SEARCHING',
      1 => 'OFFERING',
      _ => 'ASSIGNED',
    };
    return dispatchFromContract(
      dsp.DispatchAttempt.fromJson({
        'attemptId': 'att-1',
        'requestId': requestId,
        'deliveryId': 'dlv-2',
        'trigger': 'STORE_STAFF',
        'state': state,
        'retryCount': 0,
      }),
    );
  }
}
