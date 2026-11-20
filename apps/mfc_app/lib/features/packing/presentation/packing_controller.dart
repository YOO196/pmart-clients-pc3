import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/codes.dart';
import '../../../shared/product_hints.dart';
import '../../../shared/providers.dart';
import '../../tasks/data/mock_task_repository.dart';
import '../../tasks/domain/task_list.dart';
import '../../tasks/presentation/task_controllers.dart';
import '../data/mock_packing_repository.dart';
import '../data/packing_repository.dart';
import '../domain/packing.dart';

final packingRepositoryProvider = Provider<PackingRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockPackingRepository(
      onShipmentReady: (id) => switch (ref.read(taskRepositoryProvider)) {
        final MockTaskRepository t => t.shipmentReady(id),
        _ => null,
      },
    ),
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
/// notFinished = 끝을 눌렀는데 서버 출고가 아직 READY 아님, finishCheckFailed = 출고를 다시 읽지 못함.
enum PackStepError {
  notStation,
  notCart,
  otherCart,
  notRack,
  notFinished,
  finishCheckFailed,
}

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
    this.rackPending,
    this.stageBusy = false,
    this.stageUnknown = false,
    this.stageRejectCode,
    this.stepError,
  });

  /// 패킹대(포장 위치 `PAK-…`) — 밀봉 본문 packingLocation.
  final String? station;

  /// 확인한 장바구니(`CRT-…`).
  final String? cart;

  /// 올려둔 출하대기 랙(`DSP-…`) — 서버가 모든 밀봉 포장의 랙 위치를 기록했을 때만(fulfillment 0.20.0 staging, BR-52 R20).
  final String? rack;

  /// 찍었지만 아직 서버 확인 전인 랙(보내는 중·결과 모름·거절).
  final String? rackPending;

  /// 랙 올리기를 보내는 중.
  final bool stageBusy;

  /// 랙에 올렸는지 모른다. "다시 확인"은 같은 키로만 보낸다.
  final bool stageUnknown;

  /// 랙 올리기 거절 코드(STAGING_REJECTED·INVALID_STATE 등).
  final String? stageRejectCode;

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
    String? Function()? rackPending,
    bool? stageBusy,
    bool? stageUnknown,
    String? Function()? stageRejectCode,
    PackStepError? Function()? stepError,
  }) => PackingState(
    station: station != null ? station() : this.station,
    cart: cart != null ? cart() : this.cart,
    rack: rack != null ? rack() : this.rack,
    rackPending: rackPending != null ? rackPending() : this.rackPending,
    stageBusy: stageBusy ?? this.stageBusy,
    stageUnknown: stageUnknown ?? this.stageUnknown,
    stageRejectCode: stageRejectCode != null
        ? stageRejectCode()
        : this.stageRejectCode,
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

  /// 랙 올리기 키 — 포장·랙마다 하나. 결과를 모르면 같은 키로만 다시 보낸다.
  final _stageKeys = <String, IdempotencyKey>{};

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
    final line = task.lines.where((l) => l.matchesBarcode(code)).firstOrNull;
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

  /// 5. 출하대기 랙(`DSP-…`) — 찍으면 밀봉한 포장마다 서버에 랙 위치를 보낸다(`POST /packages/{id}/staging`).
  /// 모양이 랙이 아니면 보내지 않는다(랙인지 최종 판정은 서버 — 422 STAGING_REJECTED).
  bool scanRack(String code, ShipmentView s) {
    final c = code.trim();
    final ok = isMfcLocation(c) && c.startsWith('DSP-');
    if (!ok || state.stageBusy) {
      if (!ok) state = state.copyWith(stepError: () => PackStepError.notRack);
      return ok;
    }
    // 이미 올린 같은 랙을 또 찍으면(스캐너 두 번 읽기 등) 그대로 둔다 — 지우고 다시 보내면 "패킹 끝내기"가
    // 꺼졌다 켜지며 깜빡였다(에뮬레이터 확인 2026-11-20).
    if (c == state.rack) return true;
    state = state.copyWith(
      rack: () => null,
      rackPending: () => c,
      stepError: () => null,
    );
    stage(s);
    return true;
  }

  /// 찍은 랙(또는 결과를 모르는 랙)을 밀봉한 포장마다 보낸다. 모두 서버가 기록해야 [PackingState.rack] 이 정해진다.
  Future<void> stage(ShipmentView s) async {
    final rack = state.rackPending;
    if (rack == null || state.stageBusy) return;
    state = state.copyWith(
      stageBusy: true,
      stageUnknown: false,
      stageRejectCode: () => null,
    );
    final targets = [
      for (final p in s.packages)
        if (p.state == PackageState.sealed && p.stagingLocation != rack)
          p.packageId,
    ];
    var unknown = false;
    String? rejected;
    for (final id in targets) {
      final key = _stageKeys['$id|$rack'] ??= IdempotencyKey.generate();
      final outcome = await _repo.stage(id, rack, key: key);
      if (!ref.mounted) return;
      switch (outcome) {
        case StageDone():
          _stageKeys.remove('$id|$rack');
        case StageRejected(:final code):
          _stageKeys.remove('$id|$rack');
          rejected ??= code;
        case StageUnknown():
          unknown = true;
      }
      if (rejected != null) break;
    }
    final done = !unknown && rejected == null;
    state = state.copyWith(
      stageBusy: false,
      stageUnknown: unknown,
      stageRejectCode: () => rejected,
      rack: () => done ? rack : null,
      rackPending: () => rejected != null ? null : (done ? null : rack),
    );
    ref.invalidate(shipmentProvider(s.shipmentId));
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

  /// 결과를 모르는 나누기 — 같은 포장·같은 나눔이면 같은 키로만 다시 보낸다.
  ({String sig, IdempotencyKey key})? _pendingSplit;
  ({String sig, IdempotencyKey key})? _pendingRepack;

  /// 밀봉한 봉투 [p] 를 둘로 나눈다([moved] 만큼 새 봉투로). 봉투가 무겁거나 너무 찼을 때.
  Future<RegroupOutcome> split(
    String shipmentId,
    PackageView p,
    Map<String, int> moved,
  ) async {
    final parts = splitContents(p, moved);
    if (parts == null) {
      return const RegroupRejected(PackProblemCode.contentMismatch);
    }
    final sig = [
      p.packageId,
      for (final e
          in (moved.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
        '${e.key}=${e.value}',
    ].join('|');
    final pending = _pendingSplit;
    final key = pending != null && pending.sig == sig
        ? pending.key
        : IdempotencyKey.generate();
    _pendingSplit = (sig: sig, key: key);
    final outcome = await _repo.regroup(shipmentId, p.packageId, [
      parts.keep,
      parts.move,
    ], key: key);
    if (outcome is! RegroupUnknown) _pendingSplit = null;
    if (ref.mounted) ref.invalidate(shipmentProvider(shipmentId));
    return outcome;
  }

  /// 밀봉하지 않고 남은 수량(지시 − 밀봉 − 지금 봉투) 합.
  int leftAfterBag(TaskDetailView task, ShipmentView s) =>
      task.lines.fold(0, (n, l) => n + room(l, s).clamp(0, 1 << 30));

  Future<PackOutcome> repack(
    String shipmentId,
    PackageView p,
    RepackReason reason,
  ) async {
    // 결과를 모르면 같은 포장·같은 사유는 같은 키로만 다시 보낸다(새 포장이 두 번 생기지 않게).
    final sig = '${p.packageId}|${reason.name}';
    final key =
        (_pendingRepack?.sig == sig ? _pendingRepack!.key : null) ??
        IdempotencyKey.generate();
    _pendingRepack = (sig: sig, key: key);
    final outcome = await _repo.repack(p.packageId, reason, key: key);
    if (outcome is! PackUnknown) _pendingRepack = null;
    if (ref.mounted) {
      if (outcome is PackDone) {
        state = state.copyWith(lastSealed: outcome.package);
      }
      ref.invalidate(shipmentProvider(shipmentId));
    }
    return outcome;
  }

  /// 패킹 끝 — 서버 상태로만 판단한다(PACK 실행은 보내지 않는다).
  ///
  /// 집은 수량이 다 밀봉되면 fulfillment 가 PACK 을 스스로 COMPLETED 로, 출고를 READY 로 바꾼다.
  /// PACK 실행(`POST /tasks/{id}/executions` executionType PACK)은 계약상 422(포장 밀봉으로 대신).
  /// 그래서 출고를 다시 읽어 READY(또는 이미 인계 중·인계됨)일 때만 끝으로 보인다.
  Future<void> finish(TaskDetailView task, ShipmentView s) async {
    if (state.busy) return;
    state = state.copyWith(busy: true, stepError: () => null);
    try {
      ref.invalidate(shipmentProvider(s.shipmentId));
      final fresh = await ref.read(shipmentProvider(s.shipmentId).future);
      if (!ref.mounted) return;
      final done = switch (fresh.state) {
        ShipmentState.ready ||
        ShipmentState.partiallyHandedOver ||
        ShipmentState.handedOver => true,
        _ => false,
      };
      state = state.copyWith(
        busy: false,
        packingFinished: done,
        stepError: () => done ? null : PackStepError.notFinished,
      );
      ref
        ..invalidate(taskQueueProvider(taskId))
        ..invalidate(taskDetailProvider(taskId));
    } on PmartFailure {
      if (!ref.mounted) return;
      // 조회 실패를 끝(또는 안 끝남)으로 바꾸지 않는다 — 다시 눌러 확인.
      state = state.copyWith(
        busy: false,
        stepError: () => PackStepError.finishCheckFailed,
      );
    }
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
        // 다음 단계(담기)는 다시 읽은 출고로 정해진다 — 다 읽을 때까지 단추를 막아 둔다. 먼저 풀면 옛 출고로
        // "배차 요청" 단추가 잠깐 다시 눌릴 수 있게 보였다(에뮬레이터 확인 2026-11-20).
        await _reloadShipment(shipmentId);
        if (!ref.mounted) return;
        state = state.copyWith(dispatchBusy: false, dispatchUnknown: false);
      case DispatchRejected(:final code):
        _pendingDispatch = null;
        await _reloadShipment(shipmentId);
        if (!ref.mounted) return;
        state = state.copyWith(
          dispatchBusy: false,
          dispatchUnknown: false,
          dispatchRejectCode: () => code,
        );
      case DispatchUnknown():
        state = state.copyWith(dispatchBusy: false, dispatchUnknown: true);
    }
  }

  /// 출고를 다시 읽고 끝날 때까지 기다린다(조회 실패는 화면이 오류로 보인다).
  Future<void> _reloadShipment(String shipmentId) async {
    ref.invalidate(shipmentProvider(shipmentId));
    try {
      await ref.read(shipmentProvider(shipmentId).future);
    } catch (_) {}
  }

  /// 결과를 모르는 요청을 다시 확인한다(같은 키·같은 분).
  Future<void> recheckDispatch(String shipmentId) async {
    final p = _pendingDispatch;
    if (p == null) return;
    await requestDispatch(shipmentId, p.minutes);
  }
}
