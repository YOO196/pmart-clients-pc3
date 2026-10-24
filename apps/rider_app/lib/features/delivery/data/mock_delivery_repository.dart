import 'package:dio/dio.dart';
import 'package:pmart_api_delivery_execution/pmart_api_delivery_execution.dart'
    as ex;
import 'package:pmart_core/pmart_core.dart';

import '../domain/delivery.dart';
import 'delivery_repository.dart';

/// 인계 커밋 응답 시연.
enum MockCommit { applied, unknownButApplied, unknownStillInProgress }

/// 목 구현. 배송 dlv-1(포장 2개)의 가게 도착 → 포장별 QR 인계 → 픽업 → 고객 도착 → 전달 완료를 흉내 낸다.
/// 인계는 fence(승인) → 커밋 두 단계이고, 커밋이 끝난 포장만 인계 완료다.
base class MockDeliveryRepository
    implements DeliveryRepository, HandoverRepository, EvidenceUploader {
  /// [seeded] 가 false 면 진행 중 배송 없이 시작한다(제안 화면 테스트용).
  MockDeliveryRepository({
    this.latency = const Duration(milliseconds: 300),
    bool seeded = true,
  }) {
    if (!seeded) _deliveries.clear();
  }

  final Duration latency;
  static const riderId = 'rider-mock-1';

  static String qrFor(String packageId, {int version = 1}) =>
      'PMART-PKG:$packageId:v$version';

  final _deliveries = <String, Map<String, Object?>>{
    'dlv-1': {
      'deliveryId': 'dlv-1',
      'version': 1,
      'type': 'FORWARD',
      'orderId': 'order-seed-4',
      'riderId': riderId,
      'mfcId': 'MFC-MOCK-01',
      'state': 'ASSIGNED',
      'packageIds': ['pkg-1', 'pkg-2'],
      'handoverIds': <String>[],
    },
  };

  /// packageId → {state: SEALED|HANDED_OVER, fence: auth id?, handoverId?}
  final _packages = <String, Map<String, Object?>>{
    'pkg-1': {'state': 'SEALED'},
    'pkg-2': {'state': 'SEALED'},
    'pkg-x': {'state': 'SEALED', 'otherDelivery': true},
  };
  final _results = <String, HandoverStep>{};
  final _sent = <String>{};
  int _seq = 0;
  int _photo = 0;

  MockCommit commitMode = MockCommit.applied;

  /// 재포장으로 무효가 된 라벨(구 버전 QR).
  final invalidatedQrs = <String>{};

  /// 연결이 끊긴 상태(수행 명령이 서버에 닿지 않는다).
  bool offline = false;

  /// 다음 사진 업로드를 실패시킨다.
  bool uploadFails = false;

  /// 주문 취소로 출고가 중지된 포장.
  final stoppedPackages = <String>{};

  final sentKeys = <String>[];
  final commitKeys = <String>[];

  Future<void> _wait() => Future<void>.delayed(latency);

  Map<String, Object?> deliveryJson(String id) => _deliveries[id]!;

  @override
  Future<DeliveryView> get(String deliveryId) async {
    await _wait();
    final d = _deliveries[deliveryId];
    if (d == null) {
      throw const ProblemFailure(
        Problem(status: 404, code: ProblemCode.notFound),
      );
    }
    return deliveryFromContract(ex.DeliveryExecution.fromJson(d));
  }

  @override
  Future<List<DeliveryView>> myActive() async {
    await _wait();
    return [
      for (final d in _deliveries.values)
        deliveryFromContract(ex.DeliveryExecution.fromJson(d)),
    ].where((d) => isActive(d.state)).toList();
  }

  @override
  Future<DropInfo?> dropInfo(String deliveryId) async {
    await _wait();
    // BR-24: 실제 계약에는 라이더용 전달지 조회가 없다.
    return const DropInfo(
      addressSummary: '목동 1단지 101동',
      requestNote: '문 앞에 두고 벨을 눌러 주세요',
    );
  }

  // ---------------------------------------------------------------- 인계

  @override
  Future<HandoverStep> authorize(
    String packageId, {
    required String riderId,
    required String deliveryId,
    required String scannedCode,
    required IdempotencyKey key,
  }) async {
    await _wait();
    final previous = _results[key.value];
    if (previous != null) return previous;
    final p = _packages[packageId];
    final delivery = _deliveries[deliveryId]!;
    final HandoverStep step;
    if (p == null) {
      step = const HandoverRejected(ProblemCode.notFound);
    } else if (invalidatedQrs.contains(scannedCode)) {
      step = const HandoverRejected(HandoverProblemCode.packageInvalidated);
    } else if (!(delivery['packageIds']! as List).contains(packageId)) {
      step = const HandoverRejected(HandoverProblemCode.deliveryMismatch);
    } else if (p['state'] == 'HANDED_OVER') {
      step = const HandoverRejected(HandoverProblemCode.alreadyHandedOver);
    } else if (stoppedPackages.contains(packageId)) {
      step = const HandoverRejected('INVALID_STATE');
    } else {
      final auth = 'hoa-${++_seq}';
      p['fence'] = auth;
      step = HandoverAuthorized(authorizationId: auth, fenceVersion: 1);
    }
    _results[key.value] = step;
    return step;
  }

  @override
  Future<HandoverStep> commit(
    String packageId, {
    required String authorizationId,
    required int fenceVersion,
    required String riderId,
    required IdempotencyKey key,
  }) async {
    await _wait();
    commitKeys.add(key.value);
    final previous = _results[key.value];
    if (previous != null) return previous;
    final p = _packages[packageId]!;
    if (p['fence'] != authorizationId) {
      return const HandoverRejected('FENCE_VERSION_MISMATCH');
    }
    if (commitMode == MockCommit.unknownStillInProgress) {
      // 재고 응답 불명: fence 유지, 결과 모름.
      return const HandoverUnknown();
    }
    final handoverId = 'hof-$packageId';
    p
      ..['state'] = 'HANDED_OVER'
      ..['handoverId'] = handoverId
      ..remove('fence');
    final step = HandoverCommitted(handoverId);
    _results[key.value] = step;
    if (commitMode == MockCommit.unknownButApplied) {
      commitMode = MockCommit.applied;
      return const HandoverUnknown();
    }
    return step;
  }

  /// 불명이던 커밋을 서버가 나중에 확정했다.
  void settleInProgress() {
    for (final e in _packages.entries) {
      if (e.value['fence'] != null) {
        e.value
          ..['state'] = 'HANDED_OVER'
          ..['handoverId'] = 'hof-${e.key}'
          ..remove('fence');
      }
    }
    commitMode = MockCommit.applied;
  }

  @override
  Future<HandoverResolutionView> resolution(String packageId) async {
    await _wait();
    final p = _packages[packageId]!;
    if (stoppedPackages.contains(packageId)) {
      return const HandoverResolutionView(verdict: HandoverVerdict.stopped);
    }
    if (p['state'] == 'HANDED_OVER') {
      return HandoverResolutionView(
        verdict: HandoverVerdict.handedOver,
        handoverId: p['handoverId'] as String?,
      );
    }
    if (p['fence'] != null) {
      return const HandoverResolutionView(verdict: HandoverVerdict.inProgress);
    }
    return const HandoverResolutionView(verdict: HandoverVerdict.unknown);
  }

  // ---------------------------------------------------------------- 수행 명령

  @override
  Future<SendResult> send(QueueItem item) async {
    await _wait();
    sentKeys.add(item.id);
    if (offline) {
      return transitionFailureToSend(
        const UnknownResultFailure(transport: DioExceptionType.connectionError),
      );
    }
    if (_sent.contains(item.id)) return const SendAccepted();
    final d = _deliveries[item.targetId]!;
    String? reject;
    String? next;
    switch (item.kind) {
      case DeliveryCommandKind.storeArrival:
        next = d['state'] == 'ASSIGNED' ? 'ARRIVED_AT_STORE' : null;
      case DeliveryCommandKind.pickup:
        final ids = (item.payload['handoverIds']! as List)
            .cast<String>()
            .toSet();
        final need = {
          for (final pid in (d['packageIds']! as List).cast<String>())
            _packages[pid]?['handoverId'],
        };
        if (need.contains(null) || !ids.containsAll(need)) {
          reject = HandoverProblemCode.handoverNotConfirmed;
        } else {
          next = 'PICKED_UP';
          d['handoverIds'] = ids.toList();
        }
      case DeliveryCommandKind.customerArrival:
        next = d['state'] == 'PICKED_UP' ? 'ARRIVED_AT_CUSTOMER' : null;
      case DeliveryCommandKind.completion:
        final refs = (item.payload['photoRefs'] as List?) ?? const [];
        if (refs.isEmpty) {
          reject = HandoverProblemCode.evidenceRequired;
        } else {
          next = d['state'] == 'ARRIVED_AT_CUSTOMER' ? 'COMPLETED' : null;
        }
      case DeliveryCommandKind.failure:
        next = 'FAILED';
    }
    if (reject != null) {
      return transitionFailureToSend(
        ProblemFailure(Problem(status: 422, code: reject)),
      );
    }
    if (next == null) {
      return transitionFailureToSend(
        const ProblemFailure(
          Problem(status: 409, code: ProblemCode.invalidState),
        ),
      );
    }
    _sent.add(item.id);
    d
      ..['state'] = next
      ..['version'] = (d['version']! as int) + 1;
    return const SendAccepted();
  }

  // ---------------------------------------------------------------- 도움요청

  final _help = <String, int>{};

  /// 다음 도움요청 응답을 1회 잃는다(서버는 접수함).
  bool loseNextHelpResponse = false;

  @override
  Future<void> requestHelp(
    String deliveryId,
    HelpCategory category, {
    String? detail,
    required IdempotencyKey key,
  }) async {
    await _wait();
    _help.putIfAbsent(key.value, () => 0);
    if (loseNextHelpResponse) {
      loseNextHelpResponse = false;
      throw UnknownResultFailure(requestId: key.value, httpStatus: 504);
    }
  }

  /// 조회할 때마다 접수 → 처리 중 → 해결로 나아간다.
  @override
  Future<HelpState> helpStatus(String deliveryId, IdempotencyKey key) async {
    await _wait();
    final n = _help[key.value];
    if (n == null) return HelpState.unknown;
    _help[key.value] = n + 1;
    return helpStateFromWire(switch (n) {
      0 => 'OPEN',
      1 => 'IN_PROGRESS',
      _ => 'RESOLVED',
    });
  }

  // ---------------------------------------------------------------- 사진(BR-07)

  @override
  Future<String> upload(String localPhotoId) async {
    await _wait();
    if (uploadFails) {
      uploadFails = false;
      throw const NetworkFailure(DioExceptionType.connectionTimeout);
    }
    return 'photo-${++_photo}';
  }
}
