import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart';
import '../../tasks/data/task_repository.dart' show packPayload;
import '../../tasks/domain/task_list.dart';
import '../../tasks/presentation/task_controllers.dart';
import '../data/mock_packing_repository.dart';
import '../data/packing_repository.dart';
import '../domain/packing.dart';

final packingRepositoryProvider = Provider<PackingRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockPackingRepository(),
    PmartEnv.local => ApiPackingRepository(ref.watch(dioProvider)),
  },
);

/// 지금 시각(패킹 소요시간 계산용). 테스트에서 바꾼다.
final mfcClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// 배차 결과 조회 간격·횟수.
final dispatchPollPolicyProvider =
    Provider<({Duration interval, int attempts})>(
      (_) => (interval: const Duration(seconds: 3), attempts: 5),
    );

final shipmentProvider = FutureProvider.autoDispose
    .family<ShipmentView, String>(
      (ref, id) => ref.watch(packingRepositoryProvider).shipment(id),
    );

enum PackScan { matched, wrongItem, overExpected }

@immutable
class PackingState {
  const PackingState({
    this.bag = const {},
    this.zone = TemperatureZone.chilled,
    this.lastScan,
    this.busy = false,
    this.sealUnknown = false,
    this.rejectCode,
    this.lastSealed,
    this.packingFinished = false,
    this.dispatch,
    this.dispatchRequestId,
  });

  /// 지금 담고 있는 포장의 수량(밀봉 전). orderLineId → 수량.
  final Map<String, int> bag;
  final TemperatureZone zone;
  final PackScan? lastScan;
  final bool busy;

  /// 밀봉됐는지 모른다. "다시 확인"은 같은 키로만 보낸다.
  final bool sealUnknown;
  final String? rejectCode;
  final PackageView? lastSealed;
  final bool packingFinished;
  final DispatchView? dispatch;
  final String? dispatchRequestId;

  int inBag(String orderLineId) => bag[orderLineId] ?? 0;

  PackingState copyWith({
    Map<String, int>? bag,
    TemperatureZone? zone,
    PackScan? lastScan,
    bool? busy,
    bool? sealUnknown,
    String? Function()? rejectCode,
    PackageView? lastSealed,
    bool? packingFinished,
    DispatchView? dispatch,
    String? dispatchRequestId,
  }) => PackingState(
    bag: bag ?? this.bag,
    zone: zone ?? this.zone,
    lastScan: lastScan ?? this.lastScan,
    busy: busy ?? this.busy,
    sealUnknown: sealUnknown ?? this.sealUnknown,
    rejectCode: rejectCode != null ? rejectCode() : this.rejectCode,
    lastSealed: lastSealed ?? this.lastSealed,
    packingFinished: packingFinished ?? this.packingFinished,
    dispatch: dispatch ?? this.dispatch,
    dispatchRequestId: dispatchRequestId ?? this.dispatchRequestId,
  );
}

/// 패킹 1건(작업 ID 기준).
final packingProvider = NotifierProvider.autoDispose
    .family<PackingController, PackingState, String>(PackingController.new);

class PackingController extends Notifier<PackingState> {
  PackingController(this.taskId);

  final String taskId;
  IdempotencyKey? _sealKey;
  late final DateTime _startedAt = ref.read(mfcClockProvider)();

  @override
  PackingState build() => const PackingState();

  PackingRepository get _repo => ref.read(packingRepositoryProvider);

  /// 담을 수 있는 남은 수량 = 지시(피킹 확정) − 이미 밀봉 − 지금 봉투. 안내용이고 최종은 서버(CONTENT_MISMATCH).
  int room(TaskLineView line, ShipmentView s) =>
      line.plannedQty -
      (s.packedByLine[line.orderLineId] ?? 0) -
      state.inBag(line.orderLineId);

  PackScan scan(TaskDetailView task, ShipmentView s, String code) {
    final line = task.lines.where((l) => l.barcode == code.trim()).firstOrNull;
    final PackScan result;
    if (line == null) {
      result = PackScan.wrongItem;
    } else if (room(line, s) <= 0) {
      result = PackScan.overExpected;
    } else {
      state = state.copyWith(
        bag: {
          ...state.bag,
          line.orderLineId: state.inBag(line.orderLineId) + 1,
        },
        lastScan: PackScan.matched,
        rejectCode: () => null,
      );
      return PackScan.matched;
    }
    state = state.copyWith(lastScan: result);
    return result;
  }

  void setZone(TemperatureZone z) => state = state.copyWith(zone: z);

  /// 밀봉 → 포장 QR. 결과를 모르면 같은 키로만 다시 보낸다(포장이 두 개 생기지 않게).
  Future<void> seal(TaskDetailView task, ShipmentView s) async {
    if (state.busy || (state.bag.isEmpty && !state.sealUnknown)) return;
    state = state.copyWith(busy: true, rejectCode: () => null);
    final key = _sealKey ??= IdempotencyKey.generate();
    final contents = [
      for (final e in state.bag.entries)
        if (e.value > 0)
          ContentLine(
            orderLineId: e.key,
            sku: task.lines.firstWhere((l) => l.orderLineId == e.key).sku,
            qty: e.value,
          ),
    ];
    PackOutcome outcome = const PackUnknown();
    for (var i = 0; i < 3 && outcome is PackUnknown; i++) {
      outcome = await _repo.seal(
        s.shipmentId,
        contents,
        bagCount: 1,
        zone: state.zone,
        packedBy: ref.read(currentWorkerIdProvider),
        key: key,
      );
      if (!ref.mounted) return;
    }
    switch (outcome) {
      case PackDone(:final package):
        _sealKey = null;
        state = PackingState(zone: state.zone, lastSealed: package);
      case PackRejected(:final code):
        _sealKey = null;
        state = state.copyWith(busy: false, rejectCode: () => code);
      case PackUnknown():
        state = state.copyWith(busy: false, sealUnknown: true);
    }
    ref.invalidate(shipmentProvider(s.shipmentId));
  }

  Future<PackOutcome> repack(
    String shipmentId,
    PackageView p,
    RepackReason reason,
  ) async {
    final outcome = await _repo.repack(
      p.packageId,
      reason,
      key: IdempotencyKey.generate(),
    );
    if (ref.mounted) {
      if (outcome is PackDone) {
        state = state.copyWith(lastSealed: outcome.package);
      }
      ref.invalidate(shipmentProvider(shipmentId));
    }
    return outcome;
  }

  /// 패킹 완료 실적(PACK 실행)을 큐에 넣고 보낸다. 담은 수량은 유효 포장 기준이다.
  Future<void> finish(TaskDetailView task, ShipmentView s) async {
    final packed = s.packedByLine;
    final queue = ref.read(fieldQueueProvider);
    final now = ref.read(mfcClockProvider)();
    await queue.enqueue(
      kind: FieldCommandKind.packExecution,
      targetId: taskId,
      payload: packPayload(
        workerId: ref.read(currentWorkerIdProvider),
        assignmentVersion: task.assignmentVersion,
        lines: [
          for (final l in task.lines)
            if ((packed[l.orderLineId] ?? 0) > 0)
              (
                orderLineId: l.orderLineId,
                sku: l.sku,
                qty: packed[l.orderLineId]!,
              ),
        ],
        durationSec: now.difference(_startedAt).inSeconds,
      ),
    );
    final repo = ref.read(taskRepositoryProvider);
    await queue.flush(repo.sendExecution);
    await queue.confirm(
      (item) => item.resultId == null
          ? Future.value(ConfirmResult.unknown)
          : repo.execution(item.targetId, item.resultId!),
    );
    if (!ref.mounted) return;
    state = state.copyWith(packingFinished: true);
    ref
      ..invalidate(taskQueueProvider(taskId))
      ..invalidate(taskDetailProvider(taskId));
  }

  /// 배차 요청 → 결과 조회. 배차 요청 ≠ 배정(라이더 수락은 dispatch 판정).
  Future<void> requestDispatch(ShipmentView s) async {
    final deliveryId = s.deliveryId;
    if (deliveryId == null || state.busy) return;
    state = state.copyWith(busy: true, rejectCode: () => null);
    final key = IdempotencyKey.generate();
    String? requestId;
    try {
      requestId = await _repo.requestDispatch(
        deliveryId: deliveryId,
        mfcId: ref.read(currentMfcIdProvider),
        packagingMinutes:
            (ref.read(mfcClockProvider)().difference(_startedAt).inSeconds / 60)
                .ceil(),
        bagCount: s.packages
            .where((p) => p.state == PackageState.sealed)
            .length,
        coldChain: s.packages.any((p) => p.temperatureZone != 'AMBIENT'),
        packageIds: [
          for (final p in s.packages)
            if (p.state == PackageState.sealed) p.packageId,
        ],
        key: key,
      );
    } on UnknownResultFailure {
      // 같은 배송의 진행 중 시도는 서버가 기존 것을 돌려준다. 결과는 조회로 확인한다.
      requestId = key.value;
    } on ProblemFailure catch (f) {
      if (ref.mounted) {
        state = state.copyWith(busy: false, rejectCode: () => f.problem.code);
      }
      return;
    }
    final policy = ref.read(dispatchPollPolicyProvider);
    DispatchView? last;
    for (var i = 0; i < policy.attempts; i++) {
      if (i > 0) await Future<void>.delayed(policy.interval);
      if (!ref.mounted) return;
      try {
        last = await _repo.dispatch(requestId!);
      } on PmartFailure {
        continue;
      }
      if (last.state == DispatchState.assigned ||
          last.state == DispatchState.failed) {
        break;
      }
    }
    if (!ref.mounted) return;
    state = state.copyWith(
      busy: false,
      dispatch: last,
      dispatchRequestId: requestId,
    );
  }
}
