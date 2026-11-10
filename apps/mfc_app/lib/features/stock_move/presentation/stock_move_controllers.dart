import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/codes.dart';
import '../../../shared/field_outcome.dart';
import '../../../shared/field_repositories.dart';
import '../../quality/domain/quality.dart';
import '../../tasks/presentation/task_controllers.dart';
import '../domain/stock_move.dart';

/// 위치 스캔 결과.
enum LocScan { ok, wrongPlace, notLocation }

// ───────────────────────── 이동·보충 지시 ─────────────────────────

enum MovePhase { loading, pickUp, drop, done, cancelled, loadError }

@immutable
class MoveFlowState {
  const MoveFlowState({
    this.phase = MovePhase.loading,
    this.move,
    this.atFrom = false,
    this.atTo = false,
    this.cart,
    this.qty = 0,
    this.busy = false,
    this.unknown = false,
    this.code,
    this.lastScan,
  });

  final MovePhase phase;
  final MoveOrderView? move;

  /// 출발 칸 바코드를 찍었다.
  final bool atFrom;

  /// 도착 칸(취소 뒤에는 출발 칸) 바코드를 찍었다.
  final bool atTo;

  /// 찍은 카트(`CRT-…`).
  final String? cart;
  final int qty;
  final bool busy;
  final bool unknown;
  final String? code;
  final LocScan? lastScan;

  MoveFlowState copyWith({
    MovePhase? phase,
    MoveOrderView? move,
    bool? atFrom,
    bool? atTo,
    String? Function()? cart,
    int? qty,
    bool? busy,
    bool? unknown,
    String? Function()? code,
    LocScan? Function()? lastScan,
  }) => MoveFlowState(
    phase: phase ?? this.phase,
    move: move ?? this.move,
    atFrom: atFrom ?? this.atFrom,
    atTo: atTo ?? this.atTo,
    cart: cart != null ? cart() : this.cart,
    qty: qty ?? this.qty,
    busy: busy ?? this.busy,
    unknown: unknown ?? this.unknown,
    code: code != null ? code() : this.code,
    lastScan: lastScan != null ? lastScan() : this.lastScan,
  );
}

final moveFlowProvider = NotifierProvider.autoDispose
    .family<MoveController, MoveFlowState, String>(MoveController.new);

/// 이동·보충 지시 1건: 출발 칸 확인 → 수량 → 카트 스캔 → 집어 올리기 → 도착 칸 확인 → 내려놓기.
class MoveController extends Notifier<MoveFlowState> {
  MoveController(this.moveId);

  final String moveId;
  IdempotencyKey? _key;

  @override
  MoveFlowState build() {
    Future.microtask(load);
    return const MoveFlowState();
  }

  MoveFlowState _phaseFor(MoveOrderView m, MoveFlowState s) {
    if (m.state == MoveState.completed) {
      return s.copyWith(phase: MovePhase.done, move: m);
    }
    if (m.state == MoveState.cancelled) {
      return s.copyWith(phase: MovePhase.cancelled, move: m);
    }
    if (m.onCartQty > 0) {
      return s.copyWith(
        phase: MovePhase.drop,
        move: m,
        qty: m.onCartQty,
        cart: () => m.cartLocation ?? s.cart,
      );
    }
    if (m.toPick > 0) {
      return s.copyWith(phase: MovePhase.pickUp, move: m, qty: m.toPick);
    }
    return s.copyWith(phase: MovePhase.done, move: m);
  }

  Future<void> load() async {
    try {
      final m = await ref.read(stockMoveRepositoryProvider).move(moveId);
      if (ref.mounted) state = _phaseFor(m, state);
    } on PmartFailure {
      if (ref.mounted) state = state.copyWith(phase: MovePhase.loadError);
    }
  }

  /// 위치 스캔. 집기 단계는 출발 칸, 내려놓기 단계는 도착 칸이어야 한다.
  /// 카트 코드면 카트로 받는다.
  LocScan scan(String code) {
    final m = state.move;
    final c = code.trim();
    if (m == null || state.unknown) return LocScan.notLocation;
    final LocScan r;
    if (state.phase == MovePhase.pickUp && isCartLocation(c)) {
      state = state.copyWith(cart: () => c);
      r = LocScan.ok;
    } else if (!isMfcLocation(c)) {
      r = LocScan.notLocation;
    } else if (state.phase == MovePhase.pickUp && c == m.fromLocation) {
      state = state.copyWith(atFrom: true);
      r = LocScan.ok;
    } else if (state.phase == MovePhase.drop && c == m.dropTarget) {
      state = state.copyWith(atTo: true);
      r = LocScan.ok;
    } else {
      r = LocScan.wrongPlace;
    }
    state = state.copyWith(lastScan: () => r);
    return r;
  }

  void setQty(int q) {
    if (!state.unknown) state = state.copyWith(qty: q);
  }

  bool get canPickUp =>
      state.atFrom && state.cart != null && state.qty > 0 || state.unknown;

  bool get canDrop => state.atTo && state.qty > 0 || state.unknown;

  Future<void> submit() async {
    final m = state.move;
    if (m == null || state.busy) return;
    final picking = state.phase == MovePhase.pickUp;
    if (picking ? !canPickUp : !canDrop) return;
    state = state.copyWith(busy: true, code: () => null);
    final key = _key ??= IdempotencyKey.generate();
    final repo = ref.read(stockMoveRepositoryProvider);
    final outcome = picking
        ? await repo.pickUp(
            moveId,
            cartLocation: state.cart!,
            qty: state.qty,
            key: key,
          )
        : await repo.drop(
            moveId,
            toLocation: m.dropTarget,
            qty: state.qty,
            key: key,
          );
    if (!ref.mounted) return;
    switch (outcome) {
      case FieldDone(:final value):
        _key = null;
        state = _phaseFor(
          value,
          state.copyWith(
            busy: false,
            unknown: false,
            atFrom: false,
            atTo: false,
            lastScan: () => null,
          ),
        );
      case FieldRejected(:final code):
        _key = null;
        state = state.copyWith(busy: false, unknown: false, code: () => code);
      case FieldUnknown():
        state = state.copyWith(busy: false, unknown: true);
    }
  }
}

// ───────────────────────── 적치 ─────────────────────────

enum PutawayPhase { loading, editing, done, notFound, loadError }

@immutable
class PutawayState {
  const PutawayState({
    this.phase = PutawayPhase.loading,
    this.task,
    this.to,
    this.qty = 0,
    this.busy = false,
    this.unknown = false,
    this.code,
    this.lastScan,
  });

  final PutawayPhase phase;
  final InboundTaskView? task;

  /// 찍은 도착 선반.
  final String? to;
  final int qty;
  final bool busy;
  final bool unknown;
  final String? code;
  final LocScan? lastScan;

  PutawayState copyWith({
    PutawayPhase? phase,
    InboundTaskView? task,
    String? Function()? to,
    int? qty,
    bool? busy,
    bool? unknown,
    String? Function()? code,
    LocScan? Function()? lastScan,
  }) => PutawayState(
    phase: phase ?? this.phase,
    task: task ?? this.task,
    to: to != null ? to() : this.to,
    qty: qty ?? this.qty,
    busy: busy ?? this.busy,
    unknown: unknown ?? this.unknown,
    code: code != null ? code() : this.code,
    lastScan: lastScan != null ? lastScan() : this.lastScan,
  );
}

final putawayFlowProvider = NotifierProvider.autoDispose
    .family<PutawayController, PutawayState, String>(PutawayController.new);

/// 적치 1건(입고 작업 PUTAWAY): 도착 선반 스캔 → 수량 → 적치. 나눠 놓으면 남은 양으로 다시.
/// 목적지 검사(등록·온도대·구역)는 서버(mfc-inventory)가 한다.
class PutawayController extends Notifier<PutawayState> {
  PutawayController(this.taskId);

  final String taskId;
  IdempotencyKey? _key;

  @override
  PutawayState build() {
    Future.microtask(load);
    return const PutawayState();
  }

  Future<void> load() async {
    try {
      final list = await ref
          .read(qualityRepositoryProvider)
          .inboundTasks(
            ref.read(currentMfcIdProvider),
            kind: InboundTaskKind.putaway,
          );
      if (!ref.mounted) return;
      final t = list.where((t) => t.taskId == taskId).firstOrNull;
      state = t == null
          ? state.copyWith(phase: PutawayPhase.notFound)
          : state.copyWith(
              phase: PutawayPhase.editing,
              task: t,
              qty: t.remainingQty,
            );
    } on PmartFailure {
      if (ref.mounted) state = state.copyWith(phase: PutawayPhase.loadError);
    }
  }

  LocScan scan(String code) {
    final c = code.trim();
    if (state.unknown) return LocScan.notLocation;
    final r = isMfcLocation(c) ? LocScan.ok : LocScan.notLocation;
    state = state.copyWith(
      to: r == LocScan.ok ? () => c : null,
      lastScan: () => r,
    );
    return r;
  }

  void setQty(int q) {
    if (!state.unknown) state = state.copyWith(qty: q);
  }

  Future<void> submit() async {
    final t = state.task;
    if (t == null || state.busy) return;
    if (!state.unknown && (state.to == null || state.qty < 1)) return;
    state = state.copyWith(busy: true, code: () => null);
    final key = _key ??= IdempotencyKey.generate();
    final outcome = await ref
        .read(qualityRepositoryProvider)
        .putaway(taskId, toLocationCode: state.to!, qty: state.qty, key: key);
    if (!ref.mounted) return;
    switch (outcome) {
      case FieldDone(:final value):
        _key = null;
        final next = value.task;
        state = next == null || next.completed || next.remainingQty <= 0
            ? state.copyWith(
                phase: PutawayPhase.done,
                busy: false,
                unknown: false,
              )
            : state.copyWith(
                task: next,
                qty: next.remainingQty,
                to: () => null,
                busy: false,
                unknown: false,
                lastScan: () => null,
              );
      case FieldRejected(:final code):
        _key = null;
        state = state.copyWith(busy: false, unknown: false, code: () => code);
      case FieldUnknown():
        state = state.copyWith(busy: false, unknown: true);
    }
  }
}
