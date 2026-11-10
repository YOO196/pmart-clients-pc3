import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/codes.dart';
import '../../../shared/field_outcome.dart';
import '../../../shared/field_repositories.dart';
import '../../../shared/product_hints.dart';
import '../../quality/domain/quality.dart';
import '../../tasks/presentation/task_controllers.dart';
import '../domain/stock_move.dart';

/// 스캔 결과. 칸·카트·상품을 한 입력칸에서 받는다.
/// needFrom = 출발 칸을 먼저, wrongItem = 지시 상품이 아님, over = 옮길 양을 넘음.
enum LocScan { ok, wrongPlace, notLocation, needFrom, wrongItem, over }

// ───────────────────────── 이동·보충 지시 ─────────────────────────

enum MovePhase { loading, pickUp, drop, done, cancelled, reported, loadError }

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

  MoveFlowState get current => state;

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
      // 수량은 상품을 스캔해 센다(0부터). 상품 바코드를 모르면 직접 넣는다.
      return s.copyWith(
        phase: MovePhase.pickUp,
        move: m,
        qty: s.phase == MovePhase.pickUp ? s.qty : 0,
      );
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

  /// 지시 상품 바코드(상품 정보). 모르면 null — 상품 확인 없이 수량을 직접 넣는다.
  String? get productBarcode {
    final m = state.move;
    return m == null
        ? null
        : ref.read(productHintsProvider).bySku(m.sku)?.barcode;
  }

  String? get productName {
    final m = state.move;
    return m == null ? null : ref.read(productHintsProvider).bySku(m.sku)?.name;
  }

  /// 스캔. 집기 단계는 출발 칸 → 상품(1개씩) → 카트, 내려놓기 단계는 도착 칸.
  LocScan scan(String code) {
    final m = state.move;
    final c = code.trim();
    if (m == null || state.unknown) return LocScan.notLocation;
    final bc = productBarcode;
    final LocScan r;
    if (state.phase == MovePhase.pickUp && bc != null && !isMfcLocation(c)) {
      if (!state.atFrom) {
        r = LocScan.needFrom;
      } else if (c != bc) {
        r = LocScan.wrongItem;
      } else if (state.qty >= m.toPick) {
        r = LocScan.over;
      } else {
        state = state.copyWith(qty: state.qty + 1);
        r = LocScan.ok;
      }
    } else if (state.phase == MovePhase.pickUp && isCartLocation(c)) {
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

  /// 문제를 보고했다 — 이 지시는 관리자가 처리한다(서버 처리 방식은 R19 7 회신 대기).
  void reported() => state = state.copyWith(phase: MovePhase.reported);

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

enum PutawayPhase { loading, editing, done, reported, notFound, loadError }

@immutable
class PutawayState {
  const PutawayState({
    this.phase = PutawayPhase.loading,
    this.task,
    this.to,
    this.atFrom = false,
    this.qty = 0,
    this.busy = false,
    this.unknown = false,
    this.code,
    this.lastScan,
  });

  final PutawayPhase phase;
  final InboundTaskView? task;

  /// 출발 위치(입고 구역)를 찍었다.
  final bool atFrom;

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
    bool? atFrom,
    int? qty,
    bool? busy,
    bool? unknown,
    String? Function()? code,
    LocScan? Function()? lastScan,
  }) => PutawayState(
    phase: phase ?? this.phase,
    task: task ?? this.task,
    to: to != null ? to() : this.to,
    atFrom: atFrom ?? this.atFrom,
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

  PutawayState get current => state;

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
          : state.copyWith(phase: PutawayPhase.editing, task: t, qty: 0);
    } on PmartFailure {
      if (ref.mounted) state = state.copyWith(phase: PutawayPhase.loadError);
    }
  }

  String? get productBarcode {
    final t = state.task;
    if (t == null) return null;
    return t.barcode ?? ref.read(productHintsProvider).bySku(t.sku)?.barcode;
  }

  /// 출발 위치 → 상품(1개씩) → 도착 칸. 추천 칸이 아니어도 받는다(진열 판정은 서버).
  LocScan scan(String code) {
    final t = state.task;
    final c = code.trim();
    if (state.unknown || t == null) return LocScan.notLocation;
    final bc = productBarcode;
    final LocScan r;
    if (!state.atFrom) {
      r = c == t.locationCode
          ? LocScan.ok
          : isMfcLocation(c)
          ? LocScan.wrongPlace
          : LocScan.needFrom;
      if (r == LocScan.ok) state = state.copyWith(atFrom: true);
    } else if (bc != null && !isMfcLocation(c)) {
      if (c != bc) {
        r = LocScan.wrongItem;
      } else if (state.qty >= t.remainingQty) {
        r = LocScan.over;
      } else {
        state = state.copyWith(qty: state.qty + 1);
        r = LocScan.ok;
      }
    } else if (isMfcLocation(c) && !isCartLocation(c) && c != t.locationCode) {
      state = state.copyWith(to: () => c);
      r = LocScan.ok;
    } else {
      r = LocScan.notLocation;
    }
    state = state.copyWith(lastScan: () => r);
    return r;
  }

  void reported() => state = state.copyWith(phase: PutawayPhase.reported);

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
                qty: 0,
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
