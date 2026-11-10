import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/field_outcome.dart';
import '../../../shared/field_repositories.dart';
import '../../inbound/presentation/inbound_controller.dart'
    show applyPollPolicyProvider;
import '../../packing/presentation/packing_controller.dart'
    show mfcClockProvider;
import '../../stock_move/domain/stock_move.dart';
import '../../tasks/presentation/task_controllers.dart';
import '../domain/quality.dart';

// ───────────────────────── 입고 품질검사 ─────────────────────────

/// 결과 한 줄 입력값(화면).
@immutable
class InspectRow {
  const InspectRow({
    this.id = 0,
    this.quarantined = false,
    this.qty = 0,
    this.lotRef = '',
    this.noLot = false,
    this.expiry = '',
    this.manufacture = '',
  });

  /// 화면 입력칸 식별(줄을 지워도 다른 줄 입력이 섞이지 않게).
  final int id;
  final bool quarantined;
  final int qty;

  /// 제조사 LOT 원문 — 포장에 찍힌 값을 스캔으로 읽는다. LOT 번호(lotId)는 시스템이 정한다.
  final String lotRef;

  /// 포장에 LOT 표기가 없다고 작업자가 확인했다.
  final bool noLot;
  final String expiry;
  final String manufacture;

  InspectRow copyWith({
    bool? quarantined,
    int? qty,
    String? lotRef,
    bool? noLot,
    String? expiry,
    String? manufacture,
  }) => InspectRow(
    id: id,
    quarantined: quarantined ?? this.quarantined,
    qty: qty ?? this.qty,
    lotRef: lotRef ?? this.lotRef,
    noLot: noLot ?? this.noLot,
    expiry: expiry ?? this.expiry,
    manufacture: manufacture ?? this.manufacture,
  );
}

/// 입력 오류(화면 문구는 화면이 정한다). 최종 판정은 서버(400·409).
enum InspectIssue {
  /// 수량이 0 인 줄.
  zeroQty,

  /// 합계가 잔량보다 많다.
  overRemaining,

  /// 정상 판정인데 소비기한이 없다 — LOT 를 나누는 기준이라 필수로 둔다(가정).
  needExpiry,

  /// 날짜 형식(yyyy-MM-dd)이 틀렸다.
  badDate,

  /// 제조일이 오늘 이후거나 소비기한 이후다.
  badManufacture,

  /// 같은 판정·같은 LOT 표기·같은 소비기한 줄이 둘 이상 — 같은 배치라 한 줄로 합친다.
  duplicateExpiry,

  /// 정상 판정인데 LOT 표기를 스캔하지도, "표기 없음"을 누르지도 않았다(지침 G-06 — 동일 배치 판정에 쓴다).
  needLot,
}

final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

bool _isDate(String s) =>
    _datePattern.hasMatch(s) && DateTime.tryParse(s) != null;

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// 줄마다의 문제(없으면 빈 집합).
Set<InspectIssue> inspectRowIssues(InspectRow r, DateTime today) {
  final out = <InspectIssue>{};
  if (r.qty < 1) out.add(InspectIssue.zeroQty);
  if (!r.quarantined && r.expiry.isEmpty) out.add(InspectIssue.needExpiry);
  if (!r.quarantined && r.lotRef.isEmpty && !r.noLot) {
    out.add(InspectIssue.needLot);
  }
  if ((r.expiry.isNotEmpty && !_isDate(r.expiry)) ||
      (r.manufacture.isNotEmpty && !_isDate(r.manufacture))) {
    out.add(InspectIssue.badDate);
  } else if (r.manufacture.isNotEmpty &&
      (r.manufacture.compareTo(_ymd(today)) > 0 ||
          (r.expiry.isNotEmpty && r.manufacture.compareTo(r.expiry) > 0))) {
    out.add(InspectIssue.badManufacture);
  }
  return out;
}

enum InspectPhase { loading, editing, applied, notFound, loadError }

@immutable
class InspectState {
  const InspectState({
    this.phase = InspectPhase.loading,
    this.task,
    this.rows = const [],
    this.busy = false,
    this.unknown = false,
    this.code,
    this.result,
  });

  final InspectPhase phase;
  final InboundTaskView? task;
  final List<InspectRow> rows;
  final bool busy;
  final bool unknown;
  final String? code;
  final InboundTaskExecutionView? result;

  int get total => rows.fold(0, (s, r) => s + r.qty);

  InspectState copyWith({
    InspectPhase? phase,
    InboundTaskView? task,
    List<InspectRow>? rows,
    bool? busy,
    bool? unknown,
    String? Function()? code,
    InboundTaskExecutionView? result,
  }) => InspectState(
    phase: phase ?? this.phase,
    task: task ?? this.task,
    rows: rows ?? this.rows,
    busy: busy ?? this.busy,
    unknown: unknown ?? this.unknown,
    code: code != null ? code() : this.code,
    result: result ?? this.result,
  );
}

final inspectFlowProvider = NotifierProvider.autoDispose
    .family<InspectController, InspectState, String>(InspectController.new);

/// 입고 품질검사 1건(입고 작업 INSPECT). 서버가 준 작업 → 결과 줄 입력 → 등록 → 반영(APPLIED)이면 끝.
class InspectController extends Notifier<InspectState> {
  InspectController(this.taskId);

  final String taskId;
  IdempotencyKey? _key;
  int _rowSeq = 0;

  @override
  InspectState build() {
    Future.microtask(load);
    return const InspectState();
  }

  DateTime get today => ref.read(mfcClockProvider)();

  Future<void> load() async {
    final repo = ref.read(qualityRepositoryProvider);
    final mfc = ref.read(currentMfcIdProvider);
    try {
      // 단건 조회가 계약에 없어 목록에서 찾는다.
      final open = await repo.inboundTasks(mfc, kind: InboundTaskKind.inspect);
      final t = open.where((t) => t.taskId == taskId).firstOrNull;
      if (!ref.mounted) return;
      if (t != null) {
        state = state.copyWith(
          phase: InspectPhase.editing,
          task: t,
          rows: state.rows.isEmpty
              ? [InspectRow(id: ++_rowSeq, qty: t.remainingQty)]
              : state.rows,
        );
        return;
      }
      final done = await repo.inboundTasks(
        mfc,
        kind: InboundTaskKind.inspect,
        completed: true,
      );
      if (!ref.mounted) return;
      final d = done.where((t) => t.taskId == taskId).firstOrNull;
      state = d == null
          ? state.copyWith(phase: InspectPhase.notFound)
          : state.copyWith(phase: InspectPhase.applied, task: d);
    } on PmartFailure {
      if (ref.mounted) state = state.copyWith(phase: InspectPhase.loadError);
    }
  }

  void setRow(int i, InspectRow r) {
    if (state.unknown) return; // 결과를 모르는 동안은 보낸 내용을 바꾸지 않는다.
    state = state.copyWith(rows: [...state.rows]..[i] = r);
  }

  void addRow() {
    if (state.unknown) return;
    final t = state.task;
    final left = t == null ? 0 : t.remainingQty - state.total;
    state = state.copyWith(
      rows: [
        ...state.rows,
        InspectRow(qty: left > 0 ? left : 0),
      ],
    );
  }

  void removeRow(int i) {
    if (state.unknown || state.rows.length < 2) return;
    state = state.copyWith(rows: [...state.rows]..removeAt(i));
  }

  /// 보낼 수 있는지와 전체 문제.
  Set<InspectIssue> issues() {
    final t = state.task;
    final out = <InspectIssue>{
      for (final r in state.rows) ...inspectRowIssues(r, today),
    };
    if (t != null && state.total > t.remainingQty) {
      out.add(InspectIssue.overRemaining);
    }
    final seen = <String>{};
    for (final r in state.rows) {
      if (r.expiry.isEmpty) continue;
      if (!seen.add('${r.quarantined}|${r.lotRef}|${r.expiry}')) {
        out.add(InspectIssue.duplicateExpiry);
      }
    }
    return out;
  }

  Future<void> submit() async {
    if (state.busy || state.task == null) return;
    if (!state.unknown && issues().isNotEmpty) return;
    state = state.copyWith(busy: true, code: () => null);
    final key = _key ??= IdempotencyKey.generate();
    final outcome = await ref.read(qualityRepositoryProvider).inspect(taskId, [
      for (final r in state.rows)
        InspectionResult(
          qty: r.qty,
          quarantined: r.quarantined,
          // LOT 번호(lotId)는 시스템이 정한다. 보내는 것은 포장에 찍힌 제조사 LOT 원문뿐(지침 G-06).
          sourceLotRef: r.lotRef.isEmpty ? null : r.lotRef,
          expiryDate: r.expiry.isEmpty ? null : r.expiry,
          manufactureDate: r.manufacture.isEmpty ? null : r.manufacture,
        ),
    ], key: key);
    if (!ref.mounted) return;
    switch (outcome) {
      case FieldDone(:final value):
        _key = null;
        state = state.copyWith(
          busy: false,
          unknown: false,
          phase: InspectPhase.applied,
          result: value,
          task: value.task,
        );
      case FieldRejected(:final code):
        _key = null;
        state = state.copyWith(busy: false, unknown: false, code: () => code);
      case FieldUnknown():
        state = state.copyWith(busy: false, unknown: true);
    }
  }
}

// ───────────────────────── 회수품 검수 ─────────────────────────

/// 회수품 한 줄 판정 입력값.
@immutable
class ReturnDecision {
  const ReturnDecision({
    this.zone,
    this.fresh = false,
    this.opened = false,
    this.verdict,
    this.disposeReason,
  });

  /// 온도대 — 반입 조회에 없어 작업자가 고른다(BR-52 R12).
  final TempZone? zone;
  final bool fresh;
  final bool opened;
  final ReturnVerdict? verdict;
  final DisposeReason? disposeReason;

  /// 재판매는 상온·신선 아님·미개봉일 때만(화면 안내 — 최종은 서버 422).
  bool get resaleAllowed => zone == TempZone.ambient && !fresh && !opened;

  /// 폐기 사유 기본값: 조건에서 바로 나오는 것.
  DisposeReason? get suggestedReason => switch (this) {
    ReturnDecision(zone: TempZone.chilled || TempZone.frozen) =>
      DisposeReason.temperatureZone,
    ReturnDecision(fresh: true) => DisposeReason.fresh,
    ReturnDecision(opened: true) => DisposeReason.opened,
    _ => null,
  };

  bool get complete =>
      zone != null &&
      switch (verdict) {
        ReturnVerdict.resale => resaleAllowed,
        ReturnVerdict.dispose => disposeReason != null,
        null => false,
      };

  ReturnDecision copyWith({
    TempZone? zone,
    bool? fresh,
    bool? opened,
    ReturnVerdict? Function()? verdict,
    DisposeReason? Function()? disposeReason,
  }) {
    var next = ReturnDecision(
      zone: zone ?? this.zone,
      fresh: fresh ?? this.fresh,
      opened: opened ?? this.opened,
      verdict: verdict != null ? verdict() : this.verdict,
      disposeReason: disposeReason != null
          ? disposeReason()
          : this.disposeReason,
    );
    // 조건이 바뀌어 재판매가 안 되면 판정을 폐기로 돌리고 사유를 채운다.
    if (next.verdict == ReturnVerdict.resale && !next.resaleAllowed) {
      next = ReturnDecision(
        zone: next.zone,
        fresh: next.fresh,
        opened: next.opened,
        verdict: ReturnVerdict.dispose,
        disposeReason: next.suggestedReason,
      );
    }
    return next;
  }
}

enum ReturnPhase {
  loading,
  editing,

  /// 접수됨, 재고 반영 기다림.
  applying,
  applied,
  alreadyInspected,
  loadError,
}

@immutable
class ReturnInspectState {
  const ReturnInspectState({
    this.phase = ReturnPhase.loading,
    this.receipt,
    this.decisions = const [],
    this.busy = false,
    this.unknown = false,
    this.code,
    this.inspectionId,
  });

  final ReturnPhase phase;
  final ReturnReceiptView? receipt;
  final List<ReturnDecision> decisions;
  final bool busy;
  final bool unknown;
  final String? code;
  final String? inspectionId;

  bool get complete =>
      decisions.isNotEmpty && decisions.every((d) => d.complete);

  ReturnInspectState copyWith({
    ReturnPhase? phase,
    ReturnReceiptView? receipt,
    List<ReturnDecision>? decisions,
    bool? busy,
    bool? unknown,
    String? Function()? code,
    String? Function()? inspectionId,
  }) => ReturnInspectState(
    phase: phase ?? this.phase,
    receipt: receipt ?? this.receipt,
    decisions: decisions ?? this.decisions,
    busy: busy ?? this.busy,
    unknown: unknown ?? this.unknown,
    code: code != null ? code() : this.code,
    inspectionId: inspectionId != null ? inspectionId() : this.inspectionId,
  );
}

final returnInspectFlowProvider = NotifierProvider.autoDispose
    .family<ReturnInspectController, ReturnInspectState, String>(
      ReturnInspectController.new,
    );

/// 회수품 검수 1건(반입 ID). 반입 조회 → 줄별 판정 → 등록(202) → 재고 반영 확인.
class ReturnInspectController extends Notifier<ReturnInspectState> {
  ReturnInspectController(this.returnReceiptId);

  final String returnReceiptId;
  IdempotencyKey? _key;

  @override
  ReturnInspectState build() {
    Future.microtask(load);
    return const ReturnInspectState();
  }

  Future<void> load() async {
    try {
      final r = await ref
          .read(stockMoveRepositoryProvider)
          .returnReceipt(returnReceiptId);
      if (!ref.mounted) return;
      state = state.copyWith(
        phase: r.inspected ? ReturnPhase.alreadyInspected : ReturnPhase.editing,
        receipt: r,
        decisions: state.decisions.length == r.lines.length
            ? state.decisions
            : [for (final _ in r.lines) const ReturnDecision()],
      );
    } on PmartFailure {
      if (ref.mounted) state = state.copyWith(phase: ReturnPhase.loadError);
    }
  }

  void decide(int i, ReturnDecision d) {
    if (state.unknown) return;
    state = state.copyWith(decisions: [...state.decisions]..[i] = d);
  }

  Future<void> submit() async {
    final r = state.receipt;
    if (r == null || state.busy) return;
    if (!state.unknown && !state.complete) return;
    final claimId = r.claimId;
    if (claimId == null) {
      state = state.copyWith(code: () => 'CLAIM_MISSING');
      return;
    }
    state = state.copyWith(busy: true, code: () => null);
    final key = _key ??= IdempotencyKey.generate();
    final outcome = await ref
        .read(qualityRepositoryProvider)
        .inspectReturn(
          mfcId: ref.read(currentMfcIdProvider),
          claimId: claimId,
          returnReceiptId: returnReceiptId,
          inspectedBy: ref.read(currentWorkerIdProvider),
          lines: [
            for (final (i, l) in r.lines.indexed)
              ReturnInspectionLine(
                sku: l.sku,
                orderLineId: l.orderLineId,
                lotId: l.lotId,
                qty: l.qty,
                verdict: state.decisions[i].verdict!,
                zone: state.decisions[i].zone!,
                fresh: state.decisions[i].fresh,
                opened: state.decisions[i].opened,
                disposeReason:
                    state.decisions[i].verdict == ReturnVerdict.dispose
                    ? state.decisions[i].disposeReason
                    : null,
              ),
          ],
          key: key,
        );
    if (!ref.mounted) return;
    switch (outcome) {
      case FieldDone(:final value):
        _key = null;
        state = state.copyWith(
          busy: false,
          unknown: false,
          phase: ReturnPhase.applying,
          inspectionId: () => value,
        );
        await pollApply();
      case FieldRejected(:final code):
        _key = null;
        state = state.copyWith(busy: false, unknown: false, code: () => code);
      case FieldUnknown():
        state = state.copyWith(busy: false, unknown: true);
    }
  }

  /// 접수(202) ≠ 반영. 검수 조회의 재고 반영 상태가 APPLIED 여야 끝.
  Future<void> pollApply() async {
    final id = state.inspectionId;
    if (id == null) return;
    state = state.copyWith(busy: true);
    final policy = ref.read(applyPollPolicyProvider);
    String? status;
    for (var i = 0; i < policy.attempts; i++) {
      if (i > 0) await Future<void>.delayed(policy.interval);
      if (!ref.mounted) return;
      try {
        status =
            (await ref.read(qualityRepositoryProvider).returnInspection(id))
                .applyStatus;
      } on PmartFailure {
        continue;
      }
      if (status == 'APPLIED' || status == 'REJECTED') break;
    }
    if (!ref.mounted) return;
    state = state.copyWith(
      busy: false,
      phase: status == 'APPLIED' ? ReturnPhase.applied : ReturnPhase.applying,
      code: status == 'REJECTED' ? () => 'APPLY_REJECTED' : null,
    );
  }
}
