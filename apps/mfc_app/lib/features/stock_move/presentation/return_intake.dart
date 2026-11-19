// 회수품 반입 — 반납 도착 대기에서 골라 반품 칸에 반입(mfc-inbound 0.13.0, 백엔드 요청
// clients/mfc-app/2026-11-19-request-return-arrivals MI-1·MI-2).
// 대기 목록(종류·도착 시각·상품 × 수량, 시스템 ID 없음 — ADR-0070) → 반품 칸 스캔 → 상품 확인(스캔·수량) → 반입.
// claimId·회수 ID·주문 줄 번호는 서버가 대기 건에서 채운다. 받은 수량이 대기와 같으면 줄을 보내지 않는다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/codes.dart';
import '../../../shared/field_outcome.dart';
import '../../../shared/field_repositories.dart';
import '../../../shared/field_widgets.dart';
import '../../../shared/pda_theme.dart';
import '../../../shared/product_hints.dart';
import '../../../shared/scanner/scan_input.dart';
import '../../../shared/scanner/scanner.dart';
import '../../../shared/ui_state_of.dart';
import '../../tasks/presentation/task_controllers.dart';
import '../domain/stock_move.dart';

/// 반납 종류 이름.
String arrivalPurposeText(AppLocalizations l10n, String p) => switch (p) {
  'CLAIM_RETURN' => l10n.rhPurposeClaim,
  'MISDELIVERY_RECOVERY' => l10n.rhPurposeMisdelivery,
  'FAILED_DELIVERY_RETURN' => l10n.rhPurposeFailed,
  _ => l10n.rhPurposeOther,
};

/// 반품 칸(`RTN-{온도}-{번호}`)인가.
bool isReturnLocation(String code) {
  final c = code.trim();
  return c.startsWith('RTN-') && isMfcLocation(c);
}

final returnArrivalsProvider = FutureProvider.autoDispose<List<ReturnArrival>>(
  (ref) => ref
      .watch(stockMoveRepositoryProvider)
      .returnArrivals(ref.watch(currentMfcIdProvider)),
);

enum IntakePhase { editing, sending, done, unknown, rejected }

@immutable
class IntakeState {
  const IntakeState({
    this.location,
    this.counts = const {},
    this.phase = IntakePhase.editing,
    this.rejectCode,
    this.scanError,
  });

  /// 찍은 반품 칸.
  final String? location;

  /// SKU → 받은 수량(스캔·수기).
  final Map<String, int> counts;
  final IntakePhase phase;
  final String? rejectCode;
  final String? scanError;

  int countOf(String sku) => counts[sku] ?? 0;

  IntakeState copyWith({
    String? Function()? location,
    Map<String, int>? counts,
    IntakePhase? phase,
    String? Function()? rejectCode,
    String? Function()? scanError,
  }) => IntakeState(
    location: location != null ? location() : this.location,
    counts: counts ?? this.counts,
    phase: phase ?? this.phase,
    rejectCode: rejectCode != null ? rejectCode() : this.rejectCode,
    scanError: scanError != null ? scanError() : this.scanError,
  );
}

final returnIntakeProvider = NotifierProvider.autoDispose
    .family<ReturnIntakeController, IntakeState, String>(
      ReturnIntakeController.new,
    );

class ReturnIntakeController extends Notifier<IntakeState> {
  ReturnIntakeController(this.arrivalId);

  final String arrivalId;

  /// 반입 키 — 결과를 모르면 같은 키·같은 본문으로만 다시 보낸다.
  ({IdempotencyKey key, String sig})? _pending;

  @override
  IntakeState build() => const IntakeState();

  /// 틀린 스캔 안내(화면 문구 종류) — 'location' 반품 칸 아님, 'item' 이 반납의 상품 아님.
  bool scanLocation(String code) {
    if (!isReturnLocation(code)) {
      state = state.copyWith(scanError: () => 'location');
      return false;
    }
    state = state.copyWith(location: () => code.trim(), scanError: () => null);
    return true;
  }

  /// 상품 바코드 — 이 반납의 상품이면 +1. 아니면 false.
  bool scanItem(ReturnArrival a, String code) {
    final hit = ref.read(productHintsProvider).byBarcode(code.trim());
    final sku = hit?.$1 ?? code.trim();
    final line = a.lines.where((l) => l.sku == sku).firstOrNull;
    if (line == null) {
      state = state.copyWith(scanError: () => 'item');
      return false;
    }
    setCount(line.sku, state.countOf(line.sku) + 1);
    state = state.copyWith(scanError: () => null);
    return true;
  }

  void setCount(String sku, int n) {
    if (state.phase == IntakePhase.sending) return;
    state = state.copyWith(
      counts: {...state.counts, sku: n < 0 ? 0 : n},
      phase: IntakePhase.editing,
    );
  }

  /// 대기 수량 그대로 받음.
  void receiveAll(ReturnArrival a) => state = state.copyWith(
    counts: {for (final l in a.lines) l.sku: l.qty},
    phase: IntakePhase.editing,
  );

  Future<void> submit(ReturnArrival a) async {
    final to = state.location;
    if (to == null || state.phase == IntakePhase.sending) return;
    final same =
        a.lines.every((l) => state.countOf(l.sku) == l.qty) &&
        state.counts.keys.every((k) => a.lines.any((l) => l.sku == k));
    final lines = same
        ? null
        : [
            for (final e in state.counts.entries)
              if (e.value > 0) ReturnReceiptLine(sku: e.key, qty: e.value),
          ];
    final sig =
        '$to|${lines?.map((l) => '${l.sku}:${l.qty}').join(',') ?? 'ALL'}';
    final key =
        (_pending?.sig == sig ? _pending!.key : null) ??
        IdempotencyKey.generate();
    _pending = (key: key, sig: sig);
    state = state.copyWith(phase: IntakePhase.sending, rejectCode: () => null);
    final outcome = await ref
        .read(stockMoveRepositoryProvider)
        .receiveReturn(
          mfcId: ref.read(currentMfcIdProvider),
          arrivalId: arrivalId,
          toLocationCode: to,
          receivedBy: ref.read(currentWorkerIdProvider),
          receivedAt: DateTime.now().toUtc(),
          lines: lines,
          key: key,
        );
    if (!ref.mounted) return;
    switch (outcome) {
      case FieldDone():
        _pending = null;
        state = state.copyWith(phase: IntakePhase.done);
        ref.invalidate(returnArrivalsProvider);
      case FieldRejected(:final code):
        _pending = null;
        state = state.copyWith(
          phase: IntakePhase.rejected,
          rejectCode: () => code,
        );
        if (code == 'ARRIVAL_ALREADY_RECEIVED' ||
            code == 'RETURN_ARRIVAL_NOT_FOUND') {
          ref.invalidate(returnArrivalsProvider);
        }
      case FieldUnknown():
        state = state.copyWith(phase: IntakePhase.unknown);
    }
  }
}

/// 대기 목록.
class ReturnArrivalsScreen extends ConsumerWidget {
  const ReturnArrivalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.riTitle)),
      body: UiStateView<List<ReturnArrival>>(
        state: uiStateOf(
          ref.watch(returnArrivalsProvider),
          isEmpty: (l) => l.isEmpty,
        ),
        onRetry: () => ref.invalidate(returnArrivalsProvider),
        empty: (_) => Center(
          key: const ValueKey('ri-empty'),
          child: Text(l10n.riEmpty, style: theme.textTheme.titleMedium),
        ),
        ready: (context, list) => RefreshIndicator(
          onRefresh: () => ref.refresh(returnArrivalsProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                l10n.riIntro,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: PdaColors.body,
                ),
              ),
              for (final a in list)
                Card(
                  key: ValueKey('ri-${a.arrivalId}'),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(13),
                    onTap: () =>
                        context.push('/return-arrivals/${a.arrivalId}'),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  arrivalPurposeText(l10n, a.purpose),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Text(
                                l10n.riArrivedAt(formatSeoulTime(a.arrivedAt)),
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: PdaColors.body,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          for (final l in a.lines)
                            Text(
                              l10n.riLine(l.productName ?? l.sku, l.qty),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: PdaColors.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 한 건 반입: 반품 칸 → 상품 확인 → 반입.
class ReturnIntakeScreen extends ConsumerWidget {
  const ReturnIntakeScreen({super.key, required this.arrivalId});

  final String arrivalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final list = ref.watch(returnArrivalsProvider);
    final s = ref.watch(returnIntakeProvider(arrivalId));
    final ctl = ref.read(returnIntakeProvider(arrivalId).notifier);
    if (s.phase == IntakePhase.done) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.riTitle)),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ResultView(
            key: const ValueKey('ri-done'),
            icon: Icons.check_circle,
            text: l10n.riDone,
            detail: l10n.riDoneDetail(s.location ?? '-'),
            action: l10n.riBackToList,
            onAction: () async => context.pop(),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.riTitle)),
      body: UiStateView<List<ReturnArrival>>(
        state: uiStateOf(list),
        onRetry: () => ref.invalidate(returnArrivalsProvider),
        ready: (context, items) {
          final a = items.where((x) => x.arrivalId == arrivalId).firstOrNull;
          if (a == null) {
            return Center(
              key: const ValueKey('ri-gone'),
              child: Text(l10n.riGone, style: theme.textTheme.titleMedium),
            );
          }
          // 한 화면(사용자 2026-11-20 "반품 칸이랑 상품 확인을 나누면 안 되지 — 무거운데 넘길 시간이 어딨냐"):
          // 반품 칸 줄 + 상품 목록을 같이 보이고, 스캔 단추 하나가 반품 칸(RTN-…)이면 칸으로, 아니면 상품으로 받는다.
          // 순서는 자유 — 상품을 먼저 찍어도 되고, 반입 단추는 칸을 찍어야 켜진다.
          final total = s.counts.values.fold(0, (x, y) => x + y);
          final located = s.location != null;
          final body = <Widget>[
            // 어떤 반납인지 — 옅은 보라 상자(종류 굵게·도착 시각).
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: PdaColors.softer,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: PdaColors.lilac),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      arrivalPurposeText(l10n, a.purpose),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    l10n.riArrivedAt(formatSeoulTime(a.arrivedAt)),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: PdaColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            // 클레임이 없는 반납은 검수 결과가 환불로 이어지지 않는다(요청 3).
            if (!a.hasClaim)
              NoticeBox(
                textKey: const ValueKey('ri-no-claim'),
                text: l10n.riNoClaim,
              ),
            const SizedBox(height: 4),
            ScanPrompt(text: l10n.riOneTitle, detail: l10n.riOneHelp),
            // 반품 칸 — 찍었으면 ✓ 상자, 아직이면 노란 "반품 칸을 찍어요" 상자.
            Container(
              key: ValueKey(
                located ? 'ri-location-confirmed' : 'ri-location-needed',
              ),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: located ? Colors.white : PdaColors.warning,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: located
                      ? PdaColors.line
                      : PdaColors.onWarning.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: located
                  ? TargetLine(
                      label: l10n.riStepLocation,
                      code: s.location!,
                      confirmed: true,
                    )
                  : Row(
                      children: [
                        const Icon(
                          Icons.place_outlined,
                          color: PdaColors.onWarning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.riLocationNeeded,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: PdaColors.onWarning,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            if (s.scanError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  s.scanError == 'location'
                      ? l10n.riNotReturnLocation
                      : l10n.riNotThisReturn,
                  key: const ValueKey('ri-scan-error'),
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  children: [
                    for (final (i, l) in a.lines.indexed) ...[
                      if (i > 0) const Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l.productName ?? l.sku,
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  Text(
                                    l10n.riExpected(l.qty),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: PdaColors.body,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              key: ValueKey('ri-less-${l.sku}'),
                              onPressed: s.countOf(l.sku) > 0
                                  ? () => ctl.setCount(
                                      l.sku,
                                      s.countOf(l.sku) - 1,
                                    )
                                  : null,
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            SizedBox(
                              width: 36,
                              child: Text(
                                '${s.countOf(l.sku)}',
                                key: ValueKey('ri-count-${l.sku}'),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: s.countOf(l.sku) == l.qty
                                      ? PdaColors.primary
                                      : PdaColors.ink,
                                ),
                              ),
                            ),
                            IconButton(
                              key: ValueKey('ri-more-${l.sku}'),
                              onPressed: () =>
                                  ctl.setCount(l.sku, s.countOf(l.sku) + 1),
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const ValueKey('ri-all'),
                onPressed: () => ctl.receiveAll(a),
                child: Text(l10n.riReceiveAll),
              ),
            ),
            if (s.phase == IntakePhase.unknown)
              NoticeBox(
                warning: true,
                textKey: const ValueKey('ri-unknown'),
                text: l10n.riUnknown,
              ),
            if (s.phase == IntakePhase.rejected)
              NoticeBox(
                warning: true,
                textKey: const ValueKey('ri-rejected'),
                text: switch (s.rejectCode) {
                  'ARRIVAL_ALREADY_RECEIVED' => l10n.riAlreadyReceived,
                  'RETURN_ARRIVAL_NOT_FOUND' => l10n.riGone,
                  final c => l10n.riRejected(c ?? '-'),
                },
              ),
          ];
          final actions = <Widget>[
            ScanInput(
              id: 'ri-scan',
              testValues: [
                TestScan(l10n.riTestLocation, 'RTN-A-01'),
                for (final l in a.lines)
                  if (ref.read(productHintsProvider).bySku(l.sku)?.barcode
                      case final bc?)
                    TestScan(l.productName ?? l.sku, bc),
                TestScan(l10n.tsWrong, 'C-S1-01-1-01'),
              ],
              label: l10n.riScanBoth,
              cameraTitle: l10n.riTitle,
              autofocus: false,
              onScan: (c) {
                // 반품 칸 모양이면 칸으로, 아니면 상품으로.
                if (isReturnLocation(c)) {
                  ctl.scanLocation(c);
                  return const ScanFeedback.ok();
                }
                if (isMfcLocation(c)) {
                  ctl.scanLocation(c); // 반품 칸이 아닌 칸 — 안내만
                  return ScanFeedback.error(l10n.riNotReturnLocation);
                }
                return ctl.scanItem(a, c)
                    ? const ScanFeedback.ok()
                    : ScanFeedback.error(l10n.riNotThisReturn);
              },
            ),
            CommandButton(
              key: const ValueKey('ri-submit'),
              busy: s.phase == IntakePhase.sending,
              label: !located
                  ? l10n.riNeedLocationBtn
                  : s.phase == IntakePhase.unknown
                  ? l10n.checkAgain
                  : l10n.riSubmit(total),
              onPressed: located && total > 0 ? () => ctl.submit(a) : null,
            ),
          ];
          return StepBody(
            actions: actions,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              children: body,
            ),
          );
        },
      ),
    );
  }
}
