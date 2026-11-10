import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/field_outcome.dart';
import '../../../shared/field_repositories.dart';
import '../../tasks/presentation/task_controllers.dart';
import '../domain/stock_count.dart';

enum CountPhase {
  loading,

  /// 칸으로 가서 칸 바코드를 찍는다.
  goTo,

  /// 칸의 상품을 센다(장부 수량은 보이지 않는다).
  counting,

  /// 다 세고 제출 전 확인.
  review,

  /// 제출 뒤 서버 결과(일치·재계수 필요·승인 대기).
  result,

  /// 이 작업자는 셀 수 없다(재계수는 다른 사람).
  notMine,
  loadError,
}

@immutable
class CountFlowState {
  const CountFlowState({
    this.phase = CountPhase.loading,
    this.session,
    this.locIndex = 0,
    this.counts = const {},
    this.busy = false,
    this.unknown = false,
    this.code,
    this.wrongPlace = false,
  });

  final CountPhase phase;
  final CountSessionView? session;

  /// 지금 세는 칸 순서.
  final int locIndex;

  /// 줄 key → 센 수량. 없으면 아직 안 셈.
  final Map<String, int> counts;
  final bool busy;
  final bool unknown;
  final String? code;
  final bool wrongPlace;

  List<String> get locations => session?.locationCodes ?? const [];
  String? get location =>
      locIndex < locations.length ? locations[locIndex] : null;

  List<CountSheetLine> linesAt(String loc) => [
    for (final l in session?.sheet ?? const <CountSheetLine>[])
      if (l.locationCode == loc) l,
  ];

  /// 지금 칸의 줄을 모두 셌는지(0 도 직접 넣어야 센 것).
  bool get locationDone {
    final loc = location;
    return loc != null && linesAt(loc).every((l) => counts.containsKey(l.key));
  }

  CountFlowState copyWith({
    CountPhase? phase,
    CountSessionView? session,
    int? locIndex,
    Map<String, int>? counts,
    bool? busy,
    bool? unknown,
    String? Function()? code,
    bool? wrongPlace,
  }) => CountFlowState(
    phase: phase ?? this.phase,
    session: session ?? this.session,
    locIndex: locIndex ?? this.locIndex,
    counts: counts ?? this.counts,
    busy: busy ?? this.busy,
    unknown: unknown ?? this.unknown,
    code: code != null ? code() : this.code,
    wrongPlace: wrongPlace ?? this.wrongPlace,
  );
}

final countFlowProvider = NotifierProvider.autoDispose
    .family<CountController, CountFlowState, String>(CountController.new);

/// 실사 1회(세션): 칸마다 칸 확인 → 줄별 수량(장부 비공개) → 전부 세면 확인 → 제출 → 서버 판정.
class CountController extends Notifier<CountFlowState> {
  CountController(this.sessionId);

  final String sessionId;
  IdempotencyKey? _key;

  @override
  CountFlowState build() {
    Future.microtask(load);
    return const CountFlowState();
  }

  String get _mfc => ref.read(currentMfcIdProvider);

  Future<void> load() async {
    try {
      final s = await ref
          .read(stockCountRepositoryProvider)
          .session(_mfc, sessionId);
      if (!ref.mounted) return;
      final me = ref.read(currentWorkerIdProvider);
      state = state.copyWith(
        session: s,
        phase: switch (s.state) {
          CountState.counting ||
          CountState.recountRequired when s.canCount(me) => CountPhase.goTo,
          CountState.counting ||
          CountState.recountRequired => CountPhase.notMine,
          _ => CountPhase.result,
        },
      );
    } on PmartFailure {
      if (ref.mounted) state = state.copyWith(phase: CountPhase.loadError);
    }
  }

  /// 칸 바코드. 지금 칸이면 세기 시작.
  bool scanLocation(String code) {
    final ok = code.trim() == state.location;
    state = state.copyWith(
      wrongPlace: !ok,
      phase: ok ? CountPhase.counting : state.phase,
    );
    return ok;
  }

  void setCount(CountSheetLine l, int qty) {
    if (state.unknown) return;
    state = state.copyWith(counts: {...state.counts, l.key: qty});
  }

  /// 다음 칸 또는 확인으로.
  void nextLocation() {
    if (!state.locationDone) return;
    state = state.locIndex + 1 < state.locations.length
        ? state.copyWith(
            locIndex: state.locIndex + 1,
            phase: CountPhase.goTo,
            wrongPlace: false,
          )
        : state.copyWith(phase: CountPhase.review);
  }

  void back() {
    if (state.unknown) return;
    state = state.copyWith(phase: CountPhase.counting);
  }

  Future<void> submit() async {
    final s = state.session;
    if (s == null || state.busy) return;
    state = state.copyWith(busy: true, code: () => null);
    final key = _key ??= IdempotencyKey.generate();
    final outcome = await ref.read(stockCountRepositoryProvider).submit(
      _mfc,
      sessionId,
      [
        for (final l in s.sheet)
          CountedLine(line: l, countedQty: state.counts[l.key] ?? 0),
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
          session: value,
          phase: CountPhase.result,
        );
      case FieldRejected(:final code):
        _key = null;
        state = state.copyWith(
          busy: false,
          unknown: false,
          code: () => code,
          phase: code == CountProblemCode.sameCounter
              ? CountPhase.notMine
              : state.phase,
        );
      case FieldUnknown():
        state = state.copyWith(busy: false, unknown: true);
    }
  }
}
