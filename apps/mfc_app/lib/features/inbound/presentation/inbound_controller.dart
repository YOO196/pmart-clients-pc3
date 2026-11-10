import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart';
import '../../packing/presentation/packing_controller.dart'
    show mfcClockProvider;
import '../../tasks/presentation/task_controllers.dart';
import '../data/inbound_repository.dart';
import '../data/mock_inbound_repository.dart';
import '../domain/inbound.dart';

final inboundRepositoryProvider = Provider<InboundRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockInboundRepository(),
    PmartEnv.local => ApiInboundRepository(ref.watch(dioProvider)),
  },
);

/// 재고 반영 조회 간격·횟수. 다 돌아도 안 끝나면 "반영 대기"로 두고 다시 확인한다.
final applyPollPolicyProvider = Provider<({Duration interval, int attempts})>(
  (_) => (interval: const Duration(seconds: 1), attempts: 5),
);

enum InboundPhase {
  loading,

  /// 1단계: 도착 등록·하차.
  arrival,

  /// 2단계: 상품별 수령 계수.
  counting,

  /// 3단계: 확인 후 수령 등록.
  review,

  /// 4단계: 접수됨, 재고 반영 기다림.
  applying,

  /// 반영 완료(TIN_POSTED / APPLIED).
  applied,

  /// 재고 반영이 거절됐다.
  applyRejected,
  cancelled,
  loadError,
}

/// 스캔 결과.
enum InboundScan { counted, otherLine, unknownCode }

@immutable
class InboundState {
  const InboundState({
    this.phase = InboundPhase.loading,
    this.promise,
    this.counts = const {},
    this.index = 0,
    this.busy = false,
    this.unknown = false,
    this.code,
    this.receiptId,
    this.lastScan,
  });

  final InboundPhase phase;
  final InboundPromiseView? promise;

  /// 행 key → 현장 계수.
  final Map<String, ReceiptCount> counts;

  /// 계수 중인 행.
  final int index;
  final bool busy;

  /// 보낸 명령의 결과를 모른다 — "다시 확인"은 같은 키로만.
  final bool unknown;

  /// 거절 코드 등 안내용.
  final String? code;
  final String? receiptId;
  final InboundScan? lastScan;

  InboundLine? get line {
    final ls = promise?.lines ?? const <InboundLine>[];
    return index < ls.length ? ls[index] : null;
  }

  ReceiptCount countOf(InboundLine l) => counts[l.key] ?? const ReceiptCount();

  InboundState copyWith({
    InboundPhase? phase,
    InboundPromiseView? promise,
    Map<String, ReceiptCount>? counts,
    int? index,
    bool? busy,
    bool? unknown,
    String? Function()? code,
    String? Function()? receiptId,
    InboundScan? Function()? lastScan,
  }) => InboundState(
    phase: phase ?? this.phase,
    promise: promise ?? this.promise,
    counts: counts ?? this.counts,
    index: index ?? this.index,
    busy: busy ?? this.busy,
    unknown: unknown ?? this.unknown,
    code: code != null ? code() : this.code,
    receiptId: receiptId != null ? receiptId() : this.receiptId,
    lastScan: lastScan != null ? lastScan() : this.lastScan,
  );
}

/// 입고 1건(TRF). 서버가 준 입고 작업을 단계별로 진행한다.
final inboundFlowProvider = NotifierProvider.autoDispose
    .family<InboundFlowController, InboundState, String>(
      InboundFlowController.new,
    );

class InboundFlowController extends Notifier<InboundState> {
  InboundFlowController(this.trfId);

  final String trfId;
  IdempotencyKey? _arrivalKey;
  IdempotencyKey? _receiptKey;

  InboundRepository get _repo => ref.read(inboundRepositoryProvider);
  String get _me => ref.read(currentWorkerIdProvider);
  DateTime _now() => ref.read(mfcClockProvider)();

  @override
  InboundState build() {
    Future.microtask(load);
    return const InboundState();
  }

  /// 서버 상태로 단계를 정한다. 계수는 화면에만 있으므로 유지한다.
  Future<void> load() async {
    InboundPromiseView p;
    try {
      p = await _repo.promise(trfId);
    } on PmartFailure {
      if (ref.mounted) state = state.copyWith(phase: InboundPhase.loadError);
      return;
    }
    if (!ref.mounted) return;
    final open = p.receipts.where((r) => !r.applyStatus.finished).lastOrNull;
    final phase = switch (p.state) {
      PromiseState.expected => InboundPhase.arrival,
      PromiseState.receiving when open != null => InboundPhase.applying,
      PromiseState.receiving =>
        state.phase == InboundPhase.review
            ? InboundPhase.review
            : InboundPhase.counting,
      PromiseState.tinPosted => InboundPhase.applied,
      PromiseState.cancelled => InboundPhase.cancelled,
      PromiseState.unknown => InboundPhase.loadError,
    };
    state = state.copyWith(
      phase: phase,
      promise: p,
      receiptId: open == null ? null : () => open.receiptId,
    );
  }

  /// 1단계: 도착 등록. 접수 뒤 예정 상태를 다시 읽어 RECEIVING 이어야 다음 단계다.
  Future<void> arrive() async {
    final p = state.promise;
    if (p == null || state.busy) return;
    state = state.copyWith(busy: true, code: () => null);
    final key = _arrivalKey ??= IdempotencyKey.generate();
    final outcome = await _repo.recordArrival(
      trfId,
      version: p.version,
      arrivedAt: _now(),
      recordedBy: _me,
      key: key,
    );
    if (!ref.mounted) return;
    switch (outcome) {
      case InboundAccepted():
        _arrivalKey = null;
        state = state.copyWith(busy: false, unknown: false);
        await load();
      case InboundRejected(:final code):
        _arrivalKey = null;
        state = state.copyWith(busy: false, unknown: false, code: () => code);
        // 이미 도착 등록됐을 수 있다 — 서버 상태로 다시 정한다.
        await load();
      case InboundUnknown():
        state = state.copyWith(busy: false, unknown: true);
    }
  }

  /// 상품 스캔: 지금 행의 바코드면 정상 +1.
  InboundScan scan(String code) {
    final l = state.line;
    final c = code.trim();
    final InboundScan r;
    if (l != null && l.barcode != null && l.barcode == c) {
      _set(l, state.countOf(l).copyWith(normal: state.countOf(l).normal + 1));
      r = InboundScan.counted;
    } else if (state.promise?.lines.any((x) => x.barcode == c) ?? false) {
      r = InboundScan.otherLine;
    } else {
      r = InboundScan.unknownCode;
    }
    state = state.copyWith(lastScan: () => r);
    return r;
  }

  void setCount(InboundLine l, ReceiptCount c) => _set(l, c);

  void _set(InboundLine l, ReceiptCount c) =>
      state = state.copyWith(counts: {...state.counts, l.key: c});

  void next() {
    final p = state.promise;
    final l = state.line;
    if (p == null || l == null || !state.countOf(l).complete) return;
    state = state.index + 1 < p.lines.length
        ? state.copyWith(index: state.index + 1, lastScan: () => null)
        : state.copyWith(phase: InboundPhase.review, lastScan: () => null);
  }

  void back() {
    if (state.phase == InboundPhase.review) {
      state = state.copyWith(phase: InboundPhase.counting);
    } else if (state.index > 0) {
      state = state.copyWith(index: state.index - 1, lastScan: () => null);
    }
  }

  /// 3단계: 수령 등록. 접수(202) ≠ 반영 — 반영은 수령 결과 조회로 확인한다.
  Future<void> submit() async {
    final p = state.promise;
    if (p == null || state.busy) return;
    state = state.copyWith(busy: true, code: () => null);
    final key = _receiptKey ??= IdempotencyKey.generate();
    final outcome = await _repo.recordReceipt(
      trfId,
      version: p.version,
      counts: [for (final l in p.lines) (l, state.countOf(l))],
      receivedAt: _now(),
      receivedBy: _me,
      key: key,
    );
    if (!ref.mounted) return;
    switch (outcome) {
      case InboundAccepted(:final resultId):
        _receiptKey = null;
        state = state.copyWith(
          busy: false,
          unknown: false,
          phase: InboundPhase.applying,
          receiptId: () => resultId,
        );
        await pollApply();
      case InboundRejected(:final code):
        _receiptKey = null;
        state = state.copyWith(busy: false, unknown: false, code: () => code);
        if (code == InboundProblemCode.versionConflict ||
            code == InboundProblemCode.invalidState) {
          await load();
        }
      case InboundUnknown():
        state = state.copyWith(busy: false, unknown: true);
    }
  }

  /// 4단계: 재고 반영 확인. 끝나지 않으면 "반영 대기"로 두고 다시 확인한다.
  Future<void> pollApply() async {
    final id = state.receiptId;
    if (id == null) {
      // 접수 응답에 receiptId 가 없으면 예정의 수령 목록으로 확인한다.
      await load();
      return;
    }
    state = state.copyWith(busy: true);
    final policy = ref.read(applyPollPolicyProvider);
    ReceiptView? last;
    for (var i = 0; i < policy.attempts; i++) {
      if (i > 0) await Future<void>.delayed(policy.interval);
      if (!ref.mounted) return;
      try {
        last = await _repo.receipt(trfId, id);
      } on PmartFailure {
        continue;
      }
      if (last.applyStatus.finished) break;
    }
    if (!ref.mounted) return;
    state = state.copyWith(
      busy: false,
      phase: switch (last?.applyStatus) {
        ApplyStatus.applied => InboundPhase.applied,
        ApplyStatus.rejected => InboundPhase.applyRejected,
        _ => InboundPhase.applying,
      },
    );
  }
}
