import 'package:flutter/foundation.dart' show mapEquals;
import 'package:pmart_api_mfc_fulfillment/pmart_api_mfc_fulfillment.dart'
    as api;
import 'package:pmart_core/pmart_core.dart';

import '../domain/packing.dart';
import 'packing_repository.dart';

/// 목 구현.
/// - 출하 shp-1(task-mock-1 피킹 → shp-1-PACK): 요거트 1·우유 2(냉장) + 왕만두 1(냉동) + 감자칩 1(상온).
/// - 출하 shp-2(task-mock-2 패킹 시연): 요거트 1·우유 2(냉장) + 왕만두 1(냉동).
/// 모든 수량이 밀봉되면 출하가 READY 가 된다. 담을 수량을 넘으면 CONTENT_MISMATCH.
/// 배차는 직원 요청만 쓴다(2026-11-10 사용자 결정) — READY 가 돼도 자동 요청을 만들지 않는다.
base class MockPackingRepository implements PackingRepository {
  MockPackingRepository({
    this.latency = const Duration(milliseconds: 300),
    DateTime Function()? now,
    this.onShipmentReady,
  }) : _now = now ?? DateTime.now;

  final Duration latency;

  /// 출고가 READY 가 됐을 때(서버는 이때 PACK 을 COMPLETED 로 바꾼다). 목 작업 저장소에 잇는다.
  final void Function(String shipmentId)? onShipmentReady;
  final DateTime Function() _now;

  /// 출하마다 담아야 할 수량(피킹 확정분).
  static const expectedOf = {
    'shp-1': {'ol-1': 1, 'ol-2': 2, 'ol-4': 1, 'ol-3': 1},
    'shp-2': {'ol-1': 1, 'ol-2': 2, 'ol-4': 1},
  };

  /// 패킹대 칸(포장 위치).
  static const stations = ['PAK-C-01', 'PAK-C-02', 'PAK-C-03'];

  final _shipments = <String, Map<String, Object?>>{
    for (final (id, n) in const [('shp-1', 1), ('shp-2', 4)])
      id: <String, Object?>{
        'shipmentId': id,
        'fulfillmentId': 'ful-${id.substring(4)}',
        'orderId': 'order-seed-$n',
        'orderNumber': '1000000$n',
        'deliveryId': 'dlv-${id.substring(4)}',
        'version': 1,
        'state': 'PREPARING',
        'packages': <Map<String, Object?>>[],
      },
  };

  /// 밀봉 때 받은 포장 위치(패킹대).
  final sealedAt = <String, String?>{};
  final _byKey = <String, String>{};

  /// 받은 배차 요청 횟수(같은 키 재전송 포함).
  int dispatchCalls = 0;
  int _seq = 0;

  /// 다음 밀봉 응답을 1회 잃는다(서버는 밀봉함).
  bool loseNextSealResponse = false;

  /// 출고가 취소된 것처럼 배차 요청을 409 INVALID_STATE 로 거절한다.
  bool shipmentCancelled = false;

  /// 다음 배차 요청 응답을 1회 잃는다(서버는 요청을 남김).
  bool loseNextDispatchResponse = false;

  /// 랙 올리기 요청(포장 ID·랙·키) — 시험이 본문·키를 본다.
  final stageCalls = <({String packageId, String rack, String key})>[];

  /// 다음 랙 올리기 응답을 1회 잃는다(서버는 기록함).
  bool loseNextStageResponse = false;

  /// 목 인계 숫자 6자리(서버는 무작위 — 목은 순번으로 겹치지 않게).
  static String _code(int seq) => '${(318204 + seq * 7919) % 900000 + 100000}';

  Future<void> _wait() => Future<void>.delayed(latency);

  /// 출하 — 목에 없는 출하(인계 화면의 다른 포장 등)는 빈 출하로 만든다.
  Map<String, Object?> _ship(String id) => _shipments.putIfAbsent(
    id,
    () => <String, Object?>{
      'shipmentId': id,
      'orderId': 'order-$id',
      'deliveryId': 'dlv-$id',
      'version': 1,
      'state': 'PREPARING',
      'packages': <Map<String, Object?>>[],
    },
  );

  List<Map<String, Object?>> _packagesOf(String shipmentId) =>
      (_ship(shipmentId)['packages']! as List).cast<Map<String, Object?>>();

  Iterable<Map<String, Object?>> get _allPackages =>
      _shipments.keys.expand(_packagesOf);

  /// fence 를 걸어 인계 중인 것처럼 만든다(재포장 차단 시연).
  void startHandover(String packageId) {
    _allPackages.firstWhere((p) => p['packageId'] == packageId)['fence'] = {
      'state': 'HANDOVER_IN_PROGRESS',
      'fenceVersion': 1,
      'riderId': 'rider-mock-1',
    };
  }

  @override
  Future<ShipmentView> shipment(String shipmentId) async {
    await _wait();
    return shipmentFromContract(api.Shipment.fromJson(_ship(shipmentId)));
  }

  Map<String, int> _packed(String shipmentId) {
    final m = <String, int>{};
    for (final p in _packagesOf(shipmentId)) {
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
    String? packingLocation,
    required IdempotencyKey key,
  }) async {
    await _wait();
    final existing = _byKey[key.value];
    if (existing != null) {
      return _done(_allPackages.firstWhere((p) => p['packageId'] == existing));
    }
    final shipment = _ship(shipmentId);
    final expected = (expectedOf[shipmentId] ?? const <String, int>{});
    if (shipment['state'] != 'PREPARING' && shipment['state'] != 'READY') {
      return packFailureToOutcome(
        const ProblemFailure(
          Problem(status: 409, code: PackProblemCode.invalidState),
        ),
      );
    }
    final packed = _packed(shipmentId);
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
      'orderId': shipment['orderId'],
      'version': 1,
      'state': 'SEALED',
      'qrCode': 'PKG:$id:1',
      'handoverCode': _code(_seq),
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
    _packagesOf(shipmentId).add(p);
    _byKey[key.value] = id;
    sealedAt[id] = packingLocation;
    _refreshShipment(shipmentId);
    if (loseNextSealResponse) {
      loseNextSealResponse = false;
      return packFailureToOutcome(
        UnknownResultFailure(requestId: key.value, httpStatus: 504),
      );
    }
    return _done(p);
  }

  void _refreshShipment(String shipmentId) {
    final packed = _packed(shipmentId);
    final all = (expectedOf[shipmentId] ?? const <String, int>{}).entries.every(
      (e) => (packed[e.key] ?? 0) >= e.value,
    );
    final shipment = _ship(shipmentId);
    shipment
      ..['state'] = all ? 'READY' : 'PREPARING'
      ..['version'] = (shipment['version']! as int) + 1;
    if (all) onShipmentReady?.call(shipmentId);
  }

  Map<String, Object?> _dispatchJson(String shipmentId, int minutes) {
    final now = _now().toUtc();
    return {
      'shipmentId': shipmentId,
      'trigger': 'MANUAL',
      'estimatedPackMinutes': minutes,
      'estimatedReadyAt': now.add(Duration(minutes: minutes)).toIso8601String(),
      'requestedAt': now.toIso8601String(),
      'requestedBy': 'OP-mock-1',
    };
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
      return _done(_allPackages.firstWhere((p) => p['packageId'] == existing));
    }
    final old = _allPackages.firstWhere((p) => p['packageId'] == packageId);
    final shipmentId = old['shipmentId']! as String;
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
      'handoverCode': _code(_seq),
      'invalidatedReason': null,
    };
    _packagesOf(shipmentId).add(p);
    _byKey[key.value] = id;
    _refreshShipment(shipmentId);
    if (loseNextRepackResponse) {
      loseNextRepackResponse = false;
      return packFailureToOutcome(
        UnknownResultFailure(requestId: key.value, httpStatus: 504),
      );
    }
    return _done(p);
  }

  /// 다음 재포장 응답을 잃는다(서버는 반영) — 같은 키 재전송 시험용.
  bool loseNextRepackResponse = false;

  /// 받은 나누기 요청 횟수(같은 키 재전송 포함).
  int regroupCalls = 0;

  /// 다음 나누기 응답을 1회 잃는다(서버는 나눔).
  bool loseNextRegroupResponse = false;
  final _regroupByKey = <String, List<String>>{};

  @override
  Future<RegroupOutcome> regroup(
    String shipmentId,
    String packageId,
    List<List<ContentLine>> groups, {
    required IdempotencyKey key,
  }) async {
    await _wait();
    regroupCalls++;
    List<Map<String, Object?>> byIds(List<String> ids) => [
      for (final id in ids)
        _allPackages.firstWhere((p) => p['packageId'] == id),
    ];
    RegroupOutcome done(List<String> ids) => RegroupDone([
      for (final p in byIds(ids)) packageFromContract(api.Package.fromJson(p)),
    ]);
    final existing = _regroupByKey[key.value];
    if (existing != null) return done(existing);
    final old = _allPackages.firstWhere((p) => p['packageId'] == packageId);
    final fence = (old['fence'] as Map?)?['state'];
    if (old['state'] != 'SEALED' || (fence != null && fence != 'NONE')) {
      return const RegroupRejected(PackProblemCode.invalidState);
    }
    // 합계가 같아야 한다(주문 줄별).
    Map<String, int> sum(Iterable<({String ol, int qty})> xs) {
      final m = <String, int>{};
      for (final x in xs) {
        m[x.ol] = (m[x.ol] ?? 0) + x.qty;
      }
      return m;
    }

    final before = sum([
      for (final c in (old['contents']! as List).cast<Map<String, Object?>>())
        (ol: c['orderLineId']! as String, qty: c['qty']! as int),
    ]);
    final after = sum([
      for (final g in groups)
        for (final c in g) (ol: c.orderLineId, qty: c.qty),
    ]);
    if (!mapEquals(before, after) || groups.any((g) => g.isEmpty)) {
      return const RegroupRejected(PackProblemCode.contentMismatch);
    }
    final version = (old['packageVersion']! as int) + 1;
    old
      ..['state'] = 'INVALIDATED'
      ..['invalidatedReason'] = 'contentChange';
    final ids = <String>[];
    for (final g in groups) {
      final id = 'pkg-${++_seq}';
      _packagesOf(shipmentId).add({
        ...old,
        'packageId': id,
        'packageVersion': version,
        'state': 'SEALED',
        'qrCode': 'PKG:$id:$version',
        'handoverCode': _code(_seq),
        'invalidatedReason': null,
        'contents': [
          for (final c in g)
            {
              'orderLineId': c.orderLineId,
              'sku': c.sku,
              'qty': c.qty,
              'lotId': ?c.lotId,
            },
        ],
        'bagCount': 1,
      });
      ids.add(id);
    }
    _regroupByKey[key.value] = ids;
    _refreshShipment(shipmentId);
    if (loseNextRegroupResponse) {
      loseNextRegroupResponse = false;
      return const RegroupUnknown();
    }
    return done(ids);
  }

  @override
  Future<StageOutcome> stage(
    String packageId,
    String stagingLocation, {
    required IdempotencyKey key,
  }) async {
    await _wait();
    stageCalls.add((
      packageId: packageId,
      rack: stagingLocation,
      key: key.value,
    ));
    final p = _allPackages
        .where((x) => x['packageId'] == packageId)
        .firstOrNull;
    if (p == null || p['state'] != 'SEALED') {
      return stageFailureToOutcome(
        const ProblemFailure(
          Problem(status: 409, code: PackProblemCode.invalidState),
        ),
      );
    }
    // 랙인지는 서버(inventory 위치 종류)가 판정 — 목은 DSP- 칸만 랙으로 본다.
    if (!stagingLocation.startsWith('DSP-')) {
      return stageFailureToOutcome(
        const ProblemFailure(
          Problem(status: 422, code: PackProblemCode.stagingRejected),
        ),
      );
    }
    p['stagingLocation'] = stagingLocation;
    if (loseNextStageResponse) {
      loseNextStageResponse = false;
      return stageFailureToOutcome(
        UnknownResultFailure(requestId: key.value, httpStatus: 504),
      );
    }
    return StageDone(stagingLocation);
  }

  @override
  Future<DispatchOutcome> requestDispatch(
    String shipmentId, {
    required int estimatedPackMinutes,
    required IdempotencyKey key,
  }) async {
    await _wait();
    dispatchCalls++;
    if (shipmentCancelled) {
      return const DispatchRejected(PackProblemCode.invalidState);
    }
    // 출고당 한 번 — 이미 있으면 그 요청을 돌려준다.
    final d = _ship(shipmentId)['dispatchRequest'] ??= _dispatchJson(
      shipmentId,
      estimatedPackMinutes,
    );
    if (loseNextDispatchResponse) {
      loseNextDispatchResponse = false;
      return const DispatchUnknown();
    }
    return DispatchDone(
      dispatchRequestFromContract(
        api.DispatchRequest.fromJson((d as Map).cast<String, Object?>()),
      ),
    );
  }
}
