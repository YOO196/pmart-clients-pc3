import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/codes.dart';
import '../../../shared/product_hints.dart';
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

final shipmentProvider = FutureProvider.autoDispose
    .family<ShipmentView, String>(
      (ref, id) => ref.watch(packingRepositoryProvider).shipment(id),
    );

/// 패킹대·장바구니·랙 스캔 오류.
/// notStation = 패킹대(PAK) 아님, notCart = 장바구니(CRT) 아님,
/// otherCart = 이 주문을 피킹한 장바구니가 아님, notRack = 출하대기(DSP) 아님.
enum PackStepError { notStation, notCart, otherCart, notRack }

/// otherZone = 지금 봉투와 다른 온도대 상품(WK-07 온도별 포장).
enum PackScan { matched, wrongItem, overExpected, otherZone }

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
    this.dispatchBusy = false,
    this.dispatchUnknown = false,
    this.dispatchRejectCode,
    this.station,
    this.cart,
    this.rack,
    this.stepError,
  });

  /// 패킹대(포장 위치 `PAK-…`) — 밀봉 본문 packingLocation.
  final String? station;

  /// 확인한 장바구니(`CRT-…`).
  final String? cart;

  /// 올려둔 출하대기 랙(`DSP-…`). 보낼 곳이 계약에 없다(BR-52 R20) — 화면 확인만.
  final String? rack;

  /// 패킹대·장바구니·랙 스캔 오류.
  final PackStepError? stepError;

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
  final bool dispatchBusy;

  /// 배차 요청이 됐는지 모른다. "다시 확인"은 같은 키·같은 분으로만 보낸다.
  final bool dispatchUnknown;
  final String? dispatchRejectCode;

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
    bool? dispatchBusy,
    bool? dispatchUnknown,
    String? Function()? dispatchRejectCode,
    String? Function()? station,
    String? Function()? cart,
    String? Function()? rack,
    PackStepError? Function()? stepError,
  }) => PackingState(
    station: station != null ? station() : this.station,
    cart: cart != null ? cart() : this.cart,
    rack: rack != null ? rack() : this.rack,
    stepError: stepError != null ? stepError() : this.stepError,
    bag: bag ?? this.bag,
    zone: zone ?? this.zone,
    lastScan: lastScan ?? this.lastScan,
    busy: busy ?? this.busy,
    sealUnknown: sealUnknown ?? this.sealUnknown,
    rejectCode: rejectCode != null ? rejectCode() : this.rejectCode,
    lastSealed: lastSealed ?? this.lastSealed,
    packingFinished: packingFinished ?? this.packingFinished,
    dispatchBusy: dispatchBusy ?? this.dispatchBusy,
    dispatchUnknown: dispatchUnknown ?? this.dispatchUnknown,
    dispatchRejectCode: dispatchRejectCode != null
        ? dispatchRejectCode()
        : this.dispatchRejectCode,
  );
}

/// 패킹 1건(작업 ID 기준).
final packingProvider = NotifierProvider.autoDispose
    .family<PackingController, PackingState, String>(PackingController.new);

class PackingController extends Notifier<PackingState> {
  PackingController(this.taskId);

  final String taskId;
  IdempotencyKey? _sealKey;

  /// 결과를 모르는 배차 요청의 키·분. 확인될 때까지 이 값으로만 다시 보낸다.
  ({IdempotencyKey key, int minutes})? _pendingDispatch;
  late final DateTime _startedAt = ref.read(mfcClockProvider)();

  @override
  PackingState build() => const PackingState();

  PackingRepository get _repo => ref.read(packingRepositoryProvider);

  /// 담을 수 있는 남은 수량 = 지시(피킹 확정) − 이미 밀봉 − 지금 봉투. 안내용이고 최종은 서버(CONTENT_MISMATCH).
  /// 상품 보관 온도대(상품 정보). 모르면 null(BR-52 R19 2).
  StorageZone? zoneOf(TaskLineView line) =>
      ref.read(productHintsProvider).bySku(line.sku)?.zone;

  /// 모든 줄의 온도대를 알면 봉투 온도대를 작업자가 고르지 않는다.
  bool zonesKnown(TaskDetailView task) =>
      task.lines.every((l) => zoneOf(l) != null);

  /// 지금 봉투의 온도대(담은 상품으로 정해짐). 비었으면 null.
  StorageZone? bagZone(TaskDetailView task) {
    for (final l in task.lines) {
      if (state.inBag(l.orderLineId) > 0) {
        final z = zoneOf(l);
        if (z != null) return z;
      }
    }
    return null;
  }

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
    } else if (zoneOf(line) case final z?
        when bagZone(task) != null && bagZone(task) != z) {
      result = PackScan.otherZone;
    } else {
      final z = zoneOf(line);
      state = state.copyWith(
        zone: z == null ? null : TemperatureZone.values.byName(z.name),
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

  PackingState get current => state;

  /// 1. 패킹대 칸(`PAK-…`).
  bool scanStation(String code) {
    final c = code.trim();
    final ok = isMfcLocation(c) && c.startsWith('PAK-');
    state = state.copyWith(
      station: ok ? () => c : null,
      stepError: () => ok ? null : PackStepError.notStation,
    );
    return ok;
  }

  /// 2. 장바구니 — 이 주문을 피킹한 장바구니를 이 기기가 알면 같은지 본다.
  bool scanCart(String code, {String? expected}) {
    final c = code.trim();
    final PackStepError? err = !isCartLocation(c)
        ? PackStepError.notCart
        : expected != null && expected != c
        ? PackStepError.otherCart
        : null;
    state = state.copyWith(
      cart: err == null ? () => c : null,
      stepError: () => err,
    );
    return err == null;
  }

  /// 5. 출하대기 랙(`DSP-…`).
  bool scanRack(String code) {
    final c = code.trim();
    final ok = isMfcLocation(c) && c.startsWith('DSP-');
    state = state.copyWith(
      rack: ok ? () => c : null,
      stepError: () => ok ? null : PackStepError.notRack,
    );
    return ok;
  }

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
        packingLocation: state.station,
        key: key,
      );
      if (!ref.mounted) return;
    }
    switch (outcome) {
      case PackDone(:final package):
        _sealKey = null;
        state = PackingState(
          zone: state.zone,
          lastSealed: package,
          station: state.station,
          cart: state.cart,
        );
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

  /// 배차 요청(D-5) — 예상 포장 시간(분)과 함께. 요청 ≠ 배정.
  /// 결과를 모르면 같은 키·같은 분으로만 다시 보낸다(출고당 한 번이라 서버가 그 요청을 돌려준다).
  Future<void> requestDispatch(String shipmentId, int minutes) async {
    if (state.dispatchBusy) return;
    final pending = _pendingDispatch ??= (
      key: IdempotencyKey.generate(),
      minutes: minutes,
    );
    state = state.copyWith(dispatchBusy: true, dispatchRejectCode: () => null);
    final outcome = await _repo.requestDispatch(
      shipmentId,
      estimatedPackMinutes: pending.minutes,
      key: pending.key,
    );
    if (!ref.mounted) return;
    switch (outcome) {
      case DispatchDone():
        _pendingDispatch = null;
        state = state.copyWith(dispatchBusy: false, dispatchUnknown: false);
        ref.invalidate(shipmentProvider(shipmentId));
      case DispatchRejected(:final code):
        _pendingDispatch = null;
        state = state.copyWith(
          dispatchBusy: false,
          dispatchUnknown: false,
          dispatchRejectCode: () => code,
        );
        ref.invalidate(shipmentProvider(shipmentId));
      case DispatchUnknown():
        state = state.copyWith(dispatchBusy: false, dispatchUnknown: true);
    }
  }

  /// 결과를 모르는 요청을 다시 확인한다(같은 키·같은 분).
  Future<void> recheckDispatch(String shipmentId) async {
    final p = _pendingDispatch;
    if (p == null) return;
    await requestDispatch(shipmentId, p.minutes);
  }
}
