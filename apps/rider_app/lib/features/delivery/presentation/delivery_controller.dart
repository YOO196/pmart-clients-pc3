import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart';
import '../data/delivery_repository.dart';
import '../data/mock_delivery_repository.dart';
import '../domain/delivery.dart';

final _mockDelivery = Provider<MockDeliveryRepository>(
  (_) => MockDeliveryRepository(),
);

final deliveryRepositoryProvider = Provider<DeliveryRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => ref.watch(_mockDelivery),
    PmartEnv.local => ApiDeliveryRepository(ref.watch(dioProvider)),
  },
);

final handoverRepositoryProvider = Provider<HandoverRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => ref.watch(_mockDelivery),
    PmartEnv.local => ApiHandoverRepository(ref.watch(dioProvider)),
  },
);

final evidenceUploaderProvider = Provider<EvidenceUploader>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => ref.watch(_mockDelivery),
    PmartEnv.local => const UnavailableEvidenceUploader(),
  },
);

/// 라이더 ID. BR-02(라이더 로그인) 전에는 목 라이더다.
final currentRiderIdProvider = Provider<String>(
  (_) => MockDeliveryRepository.riderId,
);

/// 라이더 현장 큐(수행 명령). 앱이 꺼져도 남고 같은 키로 다시 보낸다.
final riderQueueProvider = Provider<FieldQueue>(
  (ref) => FieldQueue(ref.watch(secureStoreProvider), name: 'rider'),
);

final deliveryProvider = FutureProvider.autoDispose
    .family<DeliveryView, String>(
      (ref, id) => ref.watch(deliveryRepositoryProvider).get(id),
    );

final myActiveDeliveriesProvider =
    FutureProvider.autoDispose<List<DeliveryView>>(
      (ref) => ref.watch(deliveryRepositoryProvider).myActive(),
    );

final dropInfoProvider = FutureProvider.autoDispose.family<DropInfo?, String>(
  (ref, id) => ref.watch(deliveryRepositoryProvider).dropInfo(id),
);

final deliveryQueueProvider = FutureProvider.autoDispose
    .family<List<QueueItem>, String>(
      (ref, id) async => [
        for (final i in await ref.watch(riderQueueProvider).items())
          if (i.targetId == id) i,
      ],
    );

@immutable
class DeliveryFlowState {
  const DeliveryFlowState({
    this.packages = const {},
    this.lastScan,
    this.lastRejectCode,
    this.photoRef,
    this.uploading = false,
    this.uploadFailed = false,
  });

  final Map<String, PackageHandover> packages;
  final ScanVerdict? lastScan;
  final String? lastRejectCode;

  /// 업로드에 성공한 사진 참조. 이것이 있어야 전달 완료를 누를 수 있다.
  final String? photoRef;
  final bool uploading;
  final bool uploadFailed;

  PackageHandover phaseOf(String packageId) =>
      packages[packageId] ??
      PackageHandover(packageId: packageId, phase: HandoverPhase.waiting);

  List<String> get handoverIds => [
    for (final p in packages.values)
      if (p.phase == HandoverPhase.handedOver && p.handoverId != null)
        p.handoverId!,
  ];

  DeliveryFlowState copyWith({
    Map<String, PackageHandover>? packages,
    ScanVerdict? lastScan,
    String? Function()? lastRejectCode,
    String? photoRef,
    bool? uploading,
    bool? uploadFailed,
  }) => DeliveryFlowState(
    packages: packages ?? this.packages,
    lastScan: lastScan ?? this.lastScan,
    lastRejectCode: lastRejectCode != null
        ? lastRejectCode()
        : this.lastRejectCode,
    photoRef: photoRef ?? this.photoRef,
    uploading: uploading ?? this.uploading,
    uploadFailed: uploadFailed ?? this.uploadFailed,
  );
}

final deliveryFlowProvider = NotifierProvider.autoDispose
    .family<DeliveryFlowController, DeliveryFlowState, String>(
      DeliveryFlowController.new,
    );

class DeliveryFlowController extends Notifier<DeliveryFlowState> {
  DeliveryFlowController(this.deliveryId);

  final String deliveryId;

  /// 포장별 승인·커밋 키. 결과가 확정될 때까지 같은 키로만 다시 보낸다.
  final _authKeys = <String, IdempotencyKey>{};
  final _commitKeys = <String, IdempotencyKey>{};
  final _auths = <String, HandoverAuthorized>{};

  @override
  DeliveryFlowState build() => const DeliveryFlowState();

  HandoverRepository get _handovers => ref.read(handoverRepositoryProvider);

  void _setPhase(
    String pkg,
    HandoverPhase phase, {
    String? handoverId,
    String? code,
  }) {
    if (!ref.mounted) return;
    state = state.copyWith(
      packages: {
        ...state.packages,
        pkg: PackageHandover(
          packageId: pkg,
          phase: phase,
          handoverId: handoverId,
          rejectCode: code,
        ),
      },
    );
  }

  /// 재진입 시 포장마다 서버 판정을 조회해 화면을 맞춘다.
  Future<void> hydrate(DeliveryView d) async {
    for (final pkg in d.packageIds) {
      if (state.packages.containsKey(pkg)) continue;
      await resolve(pkg, fromHydrate: true);
    }
  }

  /// 포장 QR 스캔. 다른 배송·중복·읽기 실패는 서버에 보내기 전에 막고 사유를 보인다.
  Future<ScanVerdict> scan(DeliveryView d, String code) async {
    final pkg = packageIdFromQr(code);
    final ScanVerdict verdict;
    if (pkg == null) {
      verdict = ScanVerdict.unreadable;
    } else if (!d.packageIds.contains(pkg)) {
      verdict = ScanVerdict.otherDelivery;
    } else if (state.phaseOf(pkg).phase != HandoverPhase.waiting &&
        state.phaseOf(pkg).phase != HandoverPhase.rejected) {
      // 진행 중·확인 중·완료인 포장을 다시 찍어 새 인계를 만들지 않는다.
      verdict = ScanVerdict.duplicate;
    } else {
      verdict = ScanVerdict.accepted;
    }
    state = state.copyWith(lastScan: verdict, lastRejectCode: () => null);
    if (verdict == ScanVerdict.accepted) await _handover(d, pkg!, code.trim());
    return verdict;
  }

  Future<void> _handover(DeliveryView d, String pkg, String code) async {
    final rider = ref.read(currentRiderIdProvider);
    _setPhase(pkg, HandoverPhase.authorizing);
    final authKey = _authKeys[pkg] ??= IdempotencyKey.generate();
    HandoverStep step = const HandoverUnknown();
    for (var i = 0; i < 3 && step is HandoverUnknown; i++) {
      step = await _handovers.authorize(
        pkg,
        riderId: rider,
        deliveryId: d.deliveryId,
        scannedCode: code,
        key: authKey,
      );
    }
    switch (step) {
      case HandoverAuthorized():
        _auths[pkg] = step;
      case HandoverRejected(:final code):
        _authKeys.remove(pkg);
        _setPhase(pkg, HandoverPhase.rejected, code: code);
        if (ref.mounted) state = state.copyWith(lastRejectCode: () => code);
        return;
      default:
        // 승인 여부를 모른다. 판정 조회로 확인한다.
        _setPhase(pkg, HandoverPhase.checking);
        await resolve(pkg);
        return;
    }
    await _commit(pkg);
  }

  Future<void> _commit(String pkg) async {
    final auth = _auths[pkg];
    if (auth == null) return;
    _setPhase(pkg, HandoverPhase.committing);
    final key = _commitKeys[pkg] ??= IdempotencyKey.generate();
    HandoverStep step = const HandoverUnknown();
    for (var i = 0; i < 3 && step is HandoverUnknown; i++) {
      step = await _handovers.commit(
        pkg,
        authorizationId: auth.authorizationId,
        fenceVersion: auth.fenceVersion,
        riderId: ref.read(currentRiderIdProvider),
        key: key,
      );
    }
    switch (step) {
      case HandoverCommitted(:final handoverId):
        _setPhase(pkg, HandoverPhase.handedOver, handoverId: handoverId);
      case HandoverRejected(:final code):
        _setPhase(pkg, HandoverPhase.rejected, code: code);
        if (ref.mounted) state = state.copyWith(lastRejectCode: () => code);
      default:
        _setPhase(pkg, HandoverPhase.checking);
        await resolve(pkg);
    }
  }

  /// 인계 판정 조회(`handover-resolution`). 시간이 지났다고 원상복구하지 않는다.
  Future<void> resolve(String pkg, {bool fromHydrate = false}) async {
    try {
      final r = await _handovers.resolution(pkg);
      switch (r.verdict) {
        case HandoverVerdict.handedOver:
          _setPhase(pkg, HandoverPhase.handedOver, handoverId: r.handoverId);
        case HandoverVerdict.stopped:
          _setPhase(pkg, HandoverPhase.stopped);
        case HandoverVerdict.inProgress:
          _setPhase(pkg, HandoverPhase.checking);
        case HandoverVerdict.unknown:
          if (!fromHydrate) _setPhase(pkg, HandoverPhase.checking);
      }
    } on PmartFailure {
      if (!fromHydrate) _setPhase(pkg, HandoverPhase.checking);
    }
  }

  /// "다시 확인": 먼저 판정을 조회하고, 아직 진행 중이면 같은 키로 커밋을 다시 보낸다(새 인계를 만들지 않는다).
  Future<void> checkAgain(String pkg) async {
    await resolve(pkg);
    if (state.phaseOf(pkg).phase == HandoverPhase.checking &&
        _auths.containsKey(pkg) &&
        _commitKeys.containsKey(pkg)) {
      await _commit(pkg);
    }
  }

  // -------------------------------------------------------------- 수행 명령

  Future<void> _send(String kind, Map<String, Object?> payload) async {
    final queue = ref.read(riderQueueProvider);
    await queue.enqueue(
      kind: kind,
      targetId: deliveryId,
      payload: {
        'occurredAt': DateTime.now().toUtc().toIso8601String(),
        ...payload,
      },
    );
    await sync();
  }

  /// 전송 대기·확인 중을 같은 키로 보내고, 접수분은 배송 상태로 확정을 확인한다.
  Future<void> sync() async {
    final repo = ref.read(deliveryRepositoryProvider);
    final queue = ref.read(riderQueueProvider);
    await queue.flush(repo.send);
    await queue.confirm((item) async {
      try {
        final d = await repo.get(item.targetId);
        return _reached(item.kind, d.state)
            ? ConfirmResult.applied
            : ConfirmResult.pending;
      } on PmartFailure {
        return ConfirmResult.unknown;
      }
    });
    if (!ref.mounted) return;
    ref
      ..invalidate(deliveryProvider(deliveryId))
      ..invalidate(deliveryQueueProvider(deliveryId));
  }

  static bool _reached(String kind, ExecutionState s) {
    const order = [
      ExecutionState.assigned,
      ExecutionState.arrivedAtStore,
      ExecutionState.pickedUp,
      ExecutionState.arrivedAtCustomer,
      ExecutionState.completed,
    ];
    final target = switch (kind) {
      DeliveryCommandKind.storeArrival => ExecutionState.arrivedAtStore,
      DeliveryCommandKind.pickup => ExecutionState.pickedUp,
      DeliveryCommandKind.customerArrival => ExecutionState.arrivedAtCustomer,
      DeliveryCommandKind.completion => ExecutionState.completed,
      _ => ExecutionState.failed,
    };
    if (target == ExecutionState.failed) return s == ExecutionState.failed;
    final i = order.indexOf(s);
    return i >= 0 && i >= order.indexOf(target);
  }

  Future<void> arriveAtStore() =>
      _send(DeliveryCommandKind.storeArrival, const {});

  /// 픽업 완료는 서버가 확정한 인계(handoverIds)가 있어야 한다.
  Future<void> pickup() =>
      _send(DeliveryCommandKind.pickup, {'handoverIds': state.handoverIds});

  Future<void> arriveAtCustomer() =>
      _send(DeliveryCommandKind.customerArrival, const {});

  /// 사진 업로드(BR-07 목). 성공해야 전달 완료가 열린다.
  Future<void> uploadPhoto() async {
    state = state.copyWith(uploading: true, uploadFailed: false);
    try {
      final ref0 = await ref
          .read(evidenceUploaderProvider)
          .upload('local-photo');
      if (ref.mounted) state = state.copyWith(uploading: false, photoRef: ref0);
    } on PmartFailure {
      if (ref.mounted) {
        state = state.copyWith(uploading: false, uploadFailed: true);
      }
    }
  }

  Future<void> complete(CompletionMethod method, Placement placement) {
    final photo = state.photoRef;
    if (photo == null) return Future.value();
    return _send(DeliveryCommandKind.completion, {
      'method': method == CompletionMethod.face ? 'FACE' : 'CONTACTLESS',
      'photoRefs': [photo],
      'takenAt': DateTime.now().toUtc().toIso8601String(),
      'placement': switch (placement) {
        Placement.handedToCustomer => 'HANDED_TO_CUSTOMER',
        Placement.frontDoor => 'FRONT_DOOR',
        Placement.securityOffice => 'SECURITY_OFFICE',
        Placement.deliveryBox => 'DELIVERY_BOX',
        Placement.other => 'OTHER',
      },
    });
  }

  Future<void> reportFailure(FailureReason reason) =>
      _send(DeliveryCommandKind.failure, {
        'reason': switch (reason) {
          FailureReason.customerAbsent => 'CUSTOMER_ABSENT',
          FailureReason.addressError => 'ADDRESS_ERROR',
          FailureReason.unreachable => 'UNREACHABLE',
          FailureReason.refused => 'REFUSED',
          FailureReason.damaged => 'DAMAGED',
          FailureReason.riderIncident => 'RIDER_INCIDENT',
          FailureReason.other => 'OTHER',
        },
      });
}

@immutable
class HelpFlowState {
  const HelpFlowState({this.state, this.sending = false, this.key});

  /// 접수 뒤 처리 상태. null 이면 아직 보내지 않았다.
  final HelpState? state;
  final bool sending;
  final IdempotencyKey? key;
}

final helpFlowProvider = NotifierProvider.autoDispose
    .family<HelpFlowController, HelpFlowState, String>(HelpFlowController.new);

/// 도움요청. 접수 결과를 모르면 같은 키로 다시 보낸다(사건이 두 번 생기지 않게).
class HelpFlowController extends Notifier<HelpFlowState> {
  HelpFlowController(this.deliveryId);

  final String deliveryId;

  @override
  HelpFlowState build() => const HelpFlowState();

  Future<void> send(HelpCategory category, {String? detail}) async {
    if (state.sending) return;
    final key = state.key ?? IdempotencyKey.generate();
    state = HelpFlowState(sending: true, key: key);
    final repo = ref.read(deliveryRepositoryProvider);
    var sent = false;
    for (var i = 0; i < 3 && !sent; i++) {
      try {
        await repo.requestHelp(deliveryId, category, detail: detail, key: key);
        sent = true;
      } on UnknownResultFailure {
        continue;
      } on PmartFailure {
        break;
      }
    }
    if (!ref.mounted) return;
    // 접수 응답을 끝내 못 받았어도 상태 조회로 확인한다(새 요청을 만들지 않는다).
    final s = await repo.helpStatus(deliveryId, key);
    if (ref.mounted) state = HelpFlowState(state: s, key: key);
  }

  Future<void> refresh() async {
    final key = state.key;
    if (key == null) return;
    final s = await ref
        .read(deliveryRepositoryProvider)
        .helpStatus(deliveryId, key);
    if (ref.mounted) state = HelpFlowState(state: s, key: key);
  }
}
