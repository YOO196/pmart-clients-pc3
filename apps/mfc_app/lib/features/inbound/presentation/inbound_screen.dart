import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/field_widgets.dart';
import '../../../shared/pda_theme.dart';
import '../../../shared/printer/reprint.dart';
import '../../../shared/scanner/scan_input.dart';
import '../../../shared/scanner/scanner.dart';
import '../../work/domain/work.dart';
import '../../work/presentation/work_screens.dart' show backToSession;
import '../domain/inbound.dart';
import 'inbound_controller.dart';

/// 입고(받기): 도착 등록·하차 → 상품별 수령 계수(정상/격리/미판정) → 확인·수령 등록 → 재고 반영 확인.
class InboundReceiveScreen extends ConsumerWidget {
  const InboundReceiveScreen({super.key, required this.trfId});

  final String trfId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(inboundFlowProvider(trfId));
    final ctl = ref.read(inboundFlowProvider(trfId).notifier);
    // 박스 목록이 있으면 도착 → 박스 → 낱개 → 확인 → 반영, 없으면 도착 → 수령 → 확인 → 반영.
    final boxes = s.usesBoxes;
    final step = switch (s.phase) {
      InboundPhase.arrival => 0,
      InboundPhase.boxCheck || InboundPhase.counting => 1,
      InboundPhase.boxInspect => 2,
      InboundPhase.review => boxes ? 3 : 2,
      InboundPhase.applying ||
      InboundPhase.applied ||
      InboundPhase.applyRejected => boxes ? 4 : 3,
      _ => -1,
    };
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: Text(l10n.inboundTitle(trfId))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (step >= 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _Steps(current: step, boxes: boxes),
                ),
              Expanded(
                child: switch (s.phase) {
                  InboundPhase.loading => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  InboundPhase.loadError => _Message(
                    text: l10n.inboundLoadError,
                    action: l10n.retry,
                    onAction: ctl.load,
                  ),
                  InboundPhase.cancelled => _Message(
                    text: l10n.inboundCancelled,
                    action: l10n.nextTask,
                    onAction: () async =>
                        backToSession(context, WorkArea.inbound),
                  ),
                  InboundPhase.arrival => _ArrivalStep(trfId: trfId),
                  InboundPhase.boxCheck => _BoxCheckStep(trfId: trfId),
                  InboundPhase.boxInspect => _BoxInspectStep(trfId: trfId),
                  InboundPhase.counting => _CountStep(trfId: trfId),
                  InboundPhase.review => _ReviewStep(trfId: trfId),
                  InboundPhase.applying => _Message(
                    key: const ValueKey('inbound-applying'),
                    text: l10n.inboundApplying,
                    busy: s.busy,
                    action: l10n.checkAgain,
                    onAction: ctl.pollApply,
                  ),
                  InboundPhase.applied => _Message(
                    key: const ValueKey('inbound-applied'),
                    icon: Icons.check_circle,
                    text: l10n.inboundApplied,
                    action: l10n.nextTask,
                    onAction: () async =>
                        backToSession(context, WorkArea.inbound),
                  ),
                  InboundPhase.applyRejected => _Message(
                    key: const ValueKey('inbound-apply-rejected'),
                    icon: Icons.error_outline,
                    text: l10n.inboundApplyRejected,
                    action: l10n.nextTask,
                    onAction: () async =>
                        backToSession(context, WorkArea.inbound),
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.current, this.boxes = false});

  final int current;
  final bool boxes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final names = [
      l10n.inboundStepArrival,
      if (boxes) ...[
        l10n.inboundStepBox,
        l10n.inboundStepUnits,
      ] else
        l10n.inboundStepCount,
      l10n.inboundStepReview,
      l10n.inboundStepApply,
    ];
    return KeyedSubtree(
      key: ValueKey('inbound-step-$current'),
      child: StepHeader(names: names, current: current),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    super.key,
    required this.text,
    required this.action,
    required this.onAction,
    this.icon,
    this.busy = false,
  });

  final String text;
  final String action;
  final Future<void> Function() onAction;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) => StepBody(
    actions: [
      CommandButton(
        key: const ValueKey('inbound-message-action'),
        label: action,
        busy: busy,
        onPressed: onAction,
      ),
    ],
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (busy)
          const Center(child: CircularProgressIndicator())
        else if (icon != null)
          MarkCircle(icon: icon == Icons.check_circle ? Icons.check : icon!),
        const SizedBox(height: 16),
        Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _ArrivalStep extends ConsumerWidget {
  const _ArrivalStep({required this.trfId});

  final String trfId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = ref.watch(inboundFlowProvider(trfId));
    final ctl = ref.read(inboundFlowProvider(trfId).notifier);
    final p = s.promise!;
    return StepBody(
      actions: [
        ScanInput(
          id: 'trf-scan',
          testValues: [
            TestScan(l10n.tsNext, 'TRF:$trfId:1'),
            TestScan(l10n.tsOtherTruck, 'TRF:TRF-OTHER-999:1'),
          ],
          label: l10n.inboundTrfScanHint,
          cameraTitle: l10n.inboundTrfScanHint,
          continuous: false,
          autofocus: false,
          onScan: (code) {
            // 송장 라벨 `TRF:{trfId}:{version}` — trfId 만 비교한다(BR-53 R10).
            if (trfIdFromLabel(code) != trfId) {
              return ScanFeedback.error(l10n.inboundTrfMismatch);
            }
            ctl.arrive();
            return const ScanFeedback.ok();
          },
        ),
        CommandButton(
          key: const ValueKey('inbound-arrive'),
          busy: s.busy,
          label: s.unknown ? l10n.checkAgain : l10n.inboundArrive,
          onPressed: ctl.arrive,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScanPrompt(
            text: l10n.inboundArrivalTitle,
            detail: l10n.inboundArrivalHelp,
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.trfId,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (p.eta ?? p.plannedArrivalAt case final t?)
                    Text(
                      l10n.inboundPlannedAt(formatSeoulTime(t)),
                      style: const TextStyle(
                        color: PdaColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  Text(
                    l10n.inboundLinesSummary(p.lines.length, p.expectedTotal),
                    style: const TextStyle(
                      color: PdaColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (p.boxes case final b?)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        l10n.inboundTruck(p.rollContainers ?? 0, b),
                        key: const ValueKey('inbound-truck'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: PdaColors.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (s.code case final c?)
            Text(
              c == 'VERSION_CONFLICT'
                  ? l10n.inboundVersionConflict
                  : l10n.inboundArrivalRejected,
              key: const ValueKey('inbound-arrival-rejected'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          if (s.unknown)
            Text(
              l10n.inboundArrivalUnknown,
              key: const ValueKey('inbound-unknown'),
            ),
          const SizedBox(height: 10),
          // 입고 예정 상품 전부(박스 수·입수·수량).
          Expanded(
            child: Card(
              margin: EdgeInsets.zero,
              child: ListView.separated(
                key: const ValueKey('arrival-lines'),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: p.lines.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (_, i) {
                  final l = p.lines[i];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      l.productName ?? l.sku,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      [
                        l.sku,
                        if (l.unitsPerBox case final per?) l10n.boxPer(per),
                      ].join(' · '),
                      style: const TextStyle(color: PdaColors.body),
                    ),
                    trailing: Text(
                      [
                        if (l.boxCount case final b?) l10n.boxesUnit(b),
                        l10n.qtyUnit(l.expectedQty),
                      ].join(' · '),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountStep extends ConsumerWidget {
  const _CountStep({required this.trfId});

  final String trfId;

  Future<void> _edit(
    BuildContext context,
    String title,
    int value,
    ValueChanged<int> onSet,
  ) async {
    final v = await showDialog<int>(
      context: context,
      builder: (_) => _QtyDialog(title: title, initial: value),
    );
    if (v != null) onSet(v);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = ref.watch(inboundFlowProvider(trfId));
    final ctl = ref.read(inboundFlowProvider(trfId).notifier);
    final p = s.promise!;
    final l = s.line!;
    final c = s.countOf(l);
    final reason = c.reasonFor(l.expectedQty);
    final diff = c.total != l.expectedQty;

    Widget counter(
      String key,
      String label,
      int value,
      ReceiptCount Function(int) set,
    ) => Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.titleMedium)),
        IconButton.outlined(
          key: ValueKey('$key-minus'),
          onPressed: value > 0 ? () => ctl.setCount(l, set(value - 1)) : null,
          icon: const Icon(Icons.remove),
        ),
        InkWell(
          key: ValueKey('$key-value'),
          onTap: () =>
              _edit(context, label, value, (v) => ctl.setCount(l, set(v))),
          child: SizedBox(
            width: 64,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
          ),
        ),
        IconButton.filledTonal(
          key: ValueKey('$key-plus'),
          onPressed: () => ctl.setCount(l, set(value + 1)),
          icon: const Icon(Icons.add),
        ),
      ],
    );

    return StepBody(
      key: ValueKey('count-${l.key}'),
      actions: [
        ScanInput(
          id: 'inbound-scan',
          reprint: [
            ReprintTarget(sku: l.sku, name: l.productName, barcode: l.barcode),
          ],
          testValues: [
            for (final x in p.lines)
              if (x.barcode case final bc?)
                TestScan(x.productName ?? x.sku, bc),
            TestScan(l10n.tsWrong, '0000000000000'),
          ],
          label: l10n.inboundScanHint,
          cameraTitle: l10n.inboundCameraTitle,
          autofocus: false,
          onScan: (code) => switch (ctl.scan(code)) {
            InboundScan.counted => const ScanFeedback.ok(),
            InboundScan.otherLine => ScanFeedback.error(l10n.inboundOtherLine),
            InboundScan.unknownCode => ScanFeedback.error(
              l10n.inboundUnknownCode,
            ),
          },
        ),
        Row(
          children: [
            if (s.index > 0) ...[
              OutlinedButton(
                key: const ValueKey('inbound-back'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(96, 56),
                ),
                onPressed: ctl.back,
                child: Text(l10n.prev),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: FilledButton(
                key: const ValueKey('inbound-next'),
                onPressed: c.complete ? ctl.next : null,
                child: Text(
                  s.index + 1 < p.lines.length
                      ? l10n.nextProduct
                      : l10n.inboundToReview,
                ),
              ),
            ),
          ],
        ),
      ],
      child: ListView(
        children: [
          StepCaption(l10n.inboundLineOf(s.index + 1, p.lines.length)),
          ScanPrompt(
            text: l.productName ?? l.sku,
            detail: [
              l.sku,
              if (l.lotId case final lot?) l10n.lot(lot),
            ].join(' · '),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(15, 10, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    switch ((l.boxCount, l.unitsPerBox)) {
                      (final b?, final per?) => l10n.inboundExpectedBoxes(
                        b,
                        per,
                        l.expectedQty,
                      ),
                      _ => l10n.inboundExpected(l.expectedQty),
                    },
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: PdaColors.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  counter(
                    'normal',
                    l10n.qtyNormal,
                    c.normal,
                    (v) => c.copyWith(normal: v),
                  ),
                  counter(
                    'quarantined',
                    l10n.qtyQuarantined,
                    c.quarantined,
                    (v) => c.copyWith(quarantined: v),
                  ),
                  counter(
                    'pending',
                    l10n.qtyPending,
                    c.pending,
                    (v) => c.copyWith(pending: v),
                  ),
                  const Divider(),
                  const SizedBox(height: 6),
                  Text(
                    l10n.inboundTotal(c.total, l.expectedQty),
                    key: const ValueKey('inbound-total'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: diff ? theme.colorScheme.error : null,
                    ),
                  ),
                  if (diff && reason != null)
                    Text(
                      reasonText(l10n, reason),
                      key: const ValueKey('inbound-diff-reason'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                ],
              ),
            ),
          ),
          if (s.lastScan case final r? when r != InboundScan.counted)
            Text(
              r == InboundScan.otherLine
                  ? l10n.inboundOtherLine
                  : l10n.inboundUnknownCode,
              key: const ValueKey('inbound-scan-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          if (l.unitsPerBox case final per?)
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                key: const ValueKey('box-plus'),
                onPressed: () => ctl.addBox(l),
                icon: const Icon(Icons.inventory_2_outlined),
                label: Text(l10n.inboundAddBox(per)),
              ),
            ),
          if (c.quarantined > 0) ...[
            const SizedBox(height: 10),
            Text(
              l10n.inboundQuarantineReason,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final r in [
                  DiscrepancyReason.damaged,
                  DiscrepancyReason.temperature,
                ])
                  ChoiceChip(
                    key: ValueKey('reason-${r.name}'),
                    label: Text(reasonText(l10n, r)),
                    selected: c.quarantineReason == r,
                    onSelected: (_) =>
                        ctl.setCount(l, c.copyWith(quarantineReason: () => r)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String reasonText(AppLocalizations l10n, DiscrepancyReason r) => switch (r) {
  DiscrepancyReason.notReceived => l10n.reasonNotReceived,
  DiscrepancyReason.short => l10n.reasonShort,
  DiscrepancyReason.over => l10n.reasonOver,
  DiscrepancyReason.damaged => l10n.reasonDamaged,
  DiscrepancyReason.temperature => l10n.reasonTemperature,
};

class _ReviewStep extends ConsumerWidget {
  const _ReviewStep({required this.trfId});

  final String trfId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = ref.watch(inboundFlowProvider(trfId));
    final ctl = ref.read(inboundFlowProvider(trfId).notifier);
    final p = s.promise!;
    return StepBody(
      actions: [
        Row(
          children: [
            OutlinedButton(
              key: const ValueKey('inbound-back'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(96, 56)),
              onPressed: s.busy || s.unknown ? null : ctl.back,
              child: Text(l10n.prev),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: CommandButton(
                key: const ValueKey('inbound-submit'),
                busy: s.busy,
                label: s.unknown ? l10n.checkAgain : l10n.inboundSubmit,
                // 입고칸(수령 위치)을 다 고르기 전에는 못 보낸다 — 서버 필수(시뮬레이터 C-6)
                onPressed: s.hasReceivingLocations || s.unknown
                    ? ctl.submit
                    : null,
              ),
            ),
          ],
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScanPrompt(text: l10n.inboundReviewTitle),
          // 수령 입고칸 — 내려놓은 입고칸 위치 바코드를 온도대마다 한 번(시뮬레이터 C-6, 위치 라벨)
          for (final z in s.receivingZones)
            Card(
              key: ValueKey('receiving-$z'),
              margin: const EdgeInsets.only(bottom: 10),
              color: (s.receivingAt[z] ?? '').isEmpty ? PdaColors.notice : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                child: (s.receivingAt[z] ?? '').isEmpty
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            l10n.receivingScanTitle(zoneLabel(l10n, z)),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          ScanInput(
                            id: 'receiving-scan-$z',
                            label: l10n.receivingScanHint,
                            cameraTitle: l10n.receivingScanHint,
                            continuous: false,
                            autofocus: false,
                            testValues: [
                              TestScan(
                                l10n.receivingTestValue(zoneLabel(l10n, z)),
                                switch (z) {
                                  'FROZEN' => 'RCV-F-01',
                                  'CHILLED' => 'RCV-C-01',
                                  _ => 'RCV-A-02',
                                },
                              ),
                            ],
                            onScan: (code) {
                              ctl.setReceivingLocation(z, code);
                              return const ScanFeedback.ok();
                            },
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          const Icon(
                            Icons.place_outlined,
                            color: PdaColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.receivingAt(
                                zoneLabel(l10n, z),
                                s.receivingAt[z]!,
                              ),
                              key: ValueKey('receiving-at-$z'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => ctl.clearReceivingLocation(z),
                            child: Text(l10n.receivingChange),
                          ),
                        ],
                      ),
              ),
            ),
          Expanded(
            child: ListView(
              children: [
                for (final l in p.lines)
                  Builder(
                    builder: (context) {
                      final c = s.countOf(l);
                      final r = c.reasonFor(l.expectedQty);
                      final ok = c.total == l.expectedQty;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          key: ValueKey('review-${l.key}'),
                          title: Text(
                            l.productName ?? l.sku,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            [
                              l10n.inboundReviewLine(
                                l.expectedQty,
                                c.normal,
                                c.quarantined,
                                c.pending,
                              ),
                              if (r != null) reasonText(l10n, r),
                            ].join('\n'),
                          ),
                          trailing: ok
                              ? const Icon(
                                  Icons.check,
                                  color: PdaColors.primary,
                                )
                              : Icon(
                                  Icons.warning_amber,
                                  color: theme.colorScheme.error,
                                ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          if (s.code case final c?)
            Text(
              switch (c) {
                'VERSION_CONFLICT' => l10n.inboundVersionConflict,
                'INVALID_STATE' => l10n.inboundReceiptInvalidState,
                _ => l10n.inboundReceiptRejected,
              },
              key: const ValueKey('inbound-receipt-rejected'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          // 거절 이유(서버 detail)를 한 줄로 — 코드만으로는 왜인지 모른다(시뮬레이터 C-6)
          if (s.rejectDetail case final d? when d.isNotEmpty)
            Text(
              d,
              key: const ValueKey('inbound-reject-detail'),
              style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
            ),
          if (s.unknown)
            Text(
              l10n.inboundReceiptUnknown,
              key: const ValueKey('inbound-unknown'),
            ),
        ],
      ),
    );
  }
}

/// 수량 직접 입력. 컨트롤러는 다이얼로그가 닫힌 뒤(애니메이션 끝) 해제한다.
class _QtyDialog extends StatefulWidget {
  const _QtyDialog({required this.title, required this.initial});

  final String title;
  final int initial;

  @override
  State<_QtyDialog> createState() => _QtyDialogState();
}

class _QtyDialogState extends State<_QtyDialog> {
  late final _c = TextEditingController(text: '${widget.initial}');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('qty-input'),
        controller: _c,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('qty-ok'),
          onPressed: () =>
              Navigator.of(context).pop(int.tryParse(_c.text.trim())),
          child: Text(l10n.confirmOk),
        ),
      ],
    );
  }
}

String boxScanText(AppLocalizations l10n, BoxScan r) => switch (r) {
  BoxScan.ok => '',
  BoxScan.already => l10n.boxAlready,
  BoxScan.notThisTruck => l10n.boxNotThisTruck,
};

/// 박스 검수: 이 트럭에 어떤 상품이 몇 박스 와야 하는지 → 박스 바코드로 하나씩 확인, 박스째 파손은 격리.
class _BoxCheckStep extends ConsumerWidget {
  const _BoxCheckStep({required this.trfId});

  final String trfId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = ref.watch(inboundFlowProvider(trfId));
    final ctl = ref.read(inboundFlowProvider(trfId).notifier);
    final p = s.promise!;
    // 박스 = 고유 LPN(한 박스에 상품이 여럿일 수 있다 — 시뮬레이터 C-5)
    final total = s.boxIds.length;
    final last = s.lastBox == null ? null : s.boxById(s.lastBox!);
    return StepBody(
      actions: [
        ScanInput(
          id: 'box-scan',
          testActions: [
            TestAction(
              'all',
              l10n.testScanAllBoxes(total - s.arrived.length),
              () {
                for (final b in p.boxList) {
                  if (!s.arrived.contains(b.boxId)) ctl.scanBox(b.boxId);
                }
              },
            ),
            TestAction('all-but-one', l10n.testScanAllButOne, () {
              final left = [
                for (final id in ctl.current.boxIds)
                  if (!ctl.current.arrived.contains(id)) id,
              ];
              for (final id in left.take(left.length - 1)) {
                ctl.scanBox(id);
              }
            }),
          ],
          testValues: [
            for (final id
                in s.boxIds.where((id) => !s.arrived.contains(id)).take(5))
              TestScan(l10n.tsNext, id),
            if (s.arrived.isNotEmpty) TestScan(l10n.tsAlready, s.arrived.first),
            TestScan(l10n.tsOtherTruck, 'BOX-99999999'),
          ],
          label: l10n.boxScanHint,
          cameraTitle: l10n.boxScanHint,
          autofocus: false,
          onScan: (code) => switch (ctl.scanBox(code)) {
            BoxScan.ok => const ScanFeedback.ok(),
            final r => ScanFeedback.error(boxScanText(l10n, r)),
          },
        ),
        FilledButton(
          key: const ValueKey('box-check-done'),
          onPressed: s.arrived.isEmpty ? null : ctl.finishBoxCheck,
          child: Text(l10n.boxCheckDone),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScanPrompt(text: l10n.boxCheckTitle),
          // 한 줄에 함께 — 파손 표시로 줄이 늘어 아래 목록이 밀리지 않게.
          Text.rich(
            TextSpan(
              text: l10n.boxCheckProgress(s.arrived.length, total),
              children: [
                if (s.damaged.isNotEmpty)
                  TextSpan(
                    text: '  ${l10n.boxDamagedCount(s.damaged.length)}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
              ],
            ),
            key: const ValueKey('box-progress'),
            style: theme.textTheme.titleMedium?.copyWith(
              color: PdaColors.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
          // 안내 줄 자리는 늘 잡아 둔다 — 오류가 나타나도 아래 목록이 밀리지 않게.
          SizedBox(
            height: 20,
            child: switch (s.lastBoxScan) {
              final r? when r != BoxScan.ok => Text(
                boxScanText(l10n, r),
                key: const ValueKey('box-scan-error'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              _ => null,
            },
          ),
          // 자리를 늘 잡아 둔다 — 박스를 확인할 때 아래 목록이 밀려 잘못 누르지 않게.
          if (last != null && s.arrived.contains(last.boxId))
            Card(
              key: const ValueKey('last-box'),
              child: ListTile(
                title: Text(last.boxId),
                subtitle: Text(
                  s.entriesOf(last.boxId).length > 1
                      ? l10n.boxMixed(
                          s.entriesOf(last.boxId).length,
                          s.unitsOf(last.boxId),
                        )
                      : l10n.boxOf(
                          p.lines
                                  .where((l) => l.key == last.lineKey)
                                  .firstOrNull
                                  ?.productName ??
                              last.lineKey.split('|').first,
                          last.unitsPerBox,
                        ),
                ),
                trailing: FilterChip(
                  key: const ValueKey('box-damaged'),
                  label: Text(l10n.boxDamaged),
                  selected: s.damaged.contains(last.boxId),
                  onSelected: (_) => ctl.toggleDamaged(last.boxId),
                ),
              ),
            )
          else
            Card(
              child: ListTile(
                title: Text(l10n.boxLastPlaceholder),
                subtitle: const Text(' '),
              ),
            ),
          Expanded(
            child: ListView(
              children: [
                for (final l in p.lines)
                  Builder(
                    builder: (context) {
                      final boxes = p.boxesOf(l);
                      final got = boxes
                          .where((b) => s.arrived.contains(b.boxId))
                          .length;
                      final bad = boxes
                          .where((b) => s.damaged.contains(b.boxId))
                          .length;
                      final done = got == boxes.length;
                      final open = s.expandedLine == l.key;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ListTile(
                            key: ValueKey('box-line-${l.key}'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            onTap: () => ctl.toggleLine(l.key),
                            leading: Icon(
                              done
                                  ? Icons.check_circle
                                  : Icons.inventory_2_outlined,
                              color: done ? theme.colorScheme.primary : null,
                            ),
                            title: Text(l.productName ?? l.sku),
                            subtitle: Text(
                              [
                                if (l.unitsPerBox case final per?)
                                  l10n.boxPer(per),
                                if (bad > 0) l10n.boxDamagedCount(bad),
                              ].join(' · '),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  l10n.boxLineProgress(got, boxes.length),
                                  style: theme.textTheme.titleMedium,
                                ),
                                Icon(
                                  open ? Icons.expand_less : Icons.expand_more,
                                ),
                              ],
                            ),
                          ),
                          if (open)
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                for (final b in boxes)
                                  FilterChip(
                                    key: ValueKey('box-chip-${b.boxId}'),
                                    label: Text(b.boxId.substring(4)),
                                    selected: s.arrived.contains(b.boxId),
                                    // 보기 전용 — 확인은 스캔으로만(안드로이드).
                                    onSelected: null,
                                  ),
                              ],
                            ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
          // 목록 아래 빨간 한 줄이 잘린 목록 끝과 겹쳐 보였다 — 노란 주의 띠로 떼어 놓는다.
          if (s.arrived.length < total)
            NoticeBox(
              warning: true,
              textKey: const ValueKey('box-missing'),
              text: l10n.boxMissingWarn(total - s.arrived.length),
            ),
        ],
      ),
    );
  }
}

/// 박스별 낱개 검수: 확인한 박스를 하나씩 열어 정상·격리·미판정을 센다(박스째 파손은 이미 격리).
class _BoxInspectStep extends ConsumerWidget {
  const _BoxInspectStep({required this.trfId});

  final String trfId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = ref.watch(inboundFlowProvider(trfId));
    final ctl = ref.read(inboundFlowProvider(trfId).notifier);
    final p = s.promise!;
    InboundLine? lineOf(InboundBox b) =>
        p.lines.where((l) => l.key == b.lineKey).firstOrNull;
    String nameOf(InboundBox b) =>
        lineOf(b)?.productName ?? b.lineKey.split('|').first;

    if (s.selectedBox case final id?) {
      final entries = s.entriesOf(id);
      final mixed = entries.length > 1;
      final counts = [for (final e in entries) ctl.boxCountOf(e.entryKey)];
      final sum = counts.fold(0, (a, c) => a + c.total);
      return StepBody(
        key: ValueKey('box-open-$id'),
        actions: [
          // 낱개는 0부터 — 상품 바코드 1번 = 그 상품 정상 +1(섞인 박스면 바코드로 상품을 찾는다).
          ScanInput(
            id: 'box-item-scan',
            reprint: [
              for (final e in entries)
                if (lineOf(e) case final l?)
                  ReprintTarget(
                    sku: l.sku,
                    name: nameOf(e),
                    barcode: l.barcode,
                  ),
            ],
            testValues: [
              for (final e in entries)
                if (lineOf(e)?.barcode case final bc?) TestScan(nameOf(e), bc),
              TestScan(l10n.tsWrong, '0000000000000'),
            ],
            testActions: [
              TestAction('fill', l10n.testFillBox(s.unitsOf(id)), () {
                for (final e in entries) {
                  final c = ctl.boxCountOf(e.entryKey);
                  ctl.setBoxCount(
                    e.entryKey,
                    c.copyWith(normal: e.unitsPerBox - c.pending),
                  );
                }
              }),
            ],
            label: l10n.scanItemBtn,
            cameraTitle: l10n.boxItemScan,
            autofocus: false,
            onScan: (code) => ctl.scanBoxItem(code)
                ? const ScanFeedback.ok()
                : ScanFeedback.error(l10n.inboundOtherLine),
          ),
          Row(
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(96, 56),
                ),
                onPressed: ctl.closeBox,
                child: Text(l10n.prev),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('box-save'),
                  onPressed: sum > 0 ? ctl.saveBox : null,
                  child: Text(l10n.boxSave),
                ),
              ),
            ],
          ),
        ],
        child: ListView(
          children: [
            StepCaption(id),
            ScanPrompt(
              text: mixed
                  ? l10n.boxMixed(entries.length, s.unitsOf(id))
                  : l10n.boxOf(
                      nameOf(entries.first),
                      entries.first.unitsPerBox,
                    ),
              detail: mixed ? l10n.boxMixedHelp : l10n.boxCountHelp,
            ),
            for (final (i, e) in entries.indexed)
              Card(
                key: ValueKey('box-entry-${e.lineKey}'),
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(15, 6, 8, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (mixed)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 2),
                          child: Text(
                            l10n.boxEntryTitle(nameOf(e), e.unitsPerBox),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      QtyStepper(
                        // 한 상품 박스는 예전 키 그대로
                        id: mixed ? 'box-normal-$i' : 'box-normal',
                        label: l10n.qtyNormal,
                        value: counts[i].normal,
                        onChanged: (v) => ctl.setBoxCount(
                          e.entryKey,
                          counts[i].copyWith(normal: v),
                        ),
                      ),
                      QtyStepper(
                        id: mixed
                            ? 'box-damaged-units-$i'
                            : 'box-damaged-units',
                        label: l10n.boxLooksDamaged,
                        value: counts[i].pending,
                        onChanged: (v) => ctl.setBoxCount(
                          e.entryKey,
                          counts[i].copyWith(pending: v),
                        ),
                      ),
                      const Divider(),
                      const SizedBox(height: 6),
                      Text(
                        l10n.inboundTotal(counts[i].total, e.unitsPerBox),
                        key: ValueKey(mixed ? 'box-total-$i' : 'box-total'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: counts[i].total == e.unitsPerBox
                              ? null
                              : theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (sum > 0 &&
                entries.indexed.any(
                  (x) => counts[x.$1].total != x.$2.unitsPerBox,
                ))
              NoticeBox(text: l10n.boxCountDiff, warning: true),
          ],
        ),
      );
    }

    final boxes = s.openable;
    final done = boxes.where((b) => s.boxDone(b.boxId)).length;
    return StepBody(
      actions: [
        ScanInput(
          id: 'box-open-scan',
          testActions: [
            TestAction('all-normal', l10n.testOpenAllNormal, () {
              for (final b in ctl.current.openable) {
                if (ctl.current.boxDone(b.boxId)) continue;
                ctl.openBox(b.boxId);
                for (final e in ctl.current.entriesOf(b.boxId)) {
                  ctl.setBoxCount(
                    e.entryKey,
                    ReceiptCount(normal: e.unitsPerBox),
                  );
                }
                ctl.saveBox();
              }
            }),
          ],
          testValues: [
            for (final b
                in s.openable.where((b) => !s.boxDone(b.boxId)).take(5))
              TestScan(l10n.tsNext, b.boxId),
            TestScan(l10n.tsOtherTruck, 'BOX-99999999'),
          ],
          label: l10n.boxOpenScan,
          cameraTitle: l10n.boxOpenScan,
          continuous: false,
          autofocus: false,
          onScan: (code) => ctl.openBox(code)
              ? const ScanFeedback.ok()
              : ScanFeedback.error(l10n.boxNotThisTruck),
        ),
        Row(
          children: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(96, 56)),
              onPressed: ctl.backToBoxCheck,
              child: Text(l10n.prev),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                key: const ValueKey('box-to-review'),
                onPressed: s.allBoxesInspected ? ctl.boxesToReview : null,
                child: Text(l10n.inboundToReview),
              ),
            ),
          ],
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScanPrompt(
            text: l10n.boxInspectTitle,
            detail: s.damaged.isEmpty
                ? null
                : l10n.boxDamagedQuarantined(s.damaged.length),
          ),
          if (s.handover case final h?)
            NoticeBox(
              textKey: const ValueKey('handover-result'),
              warning: h is! InboundAccepted,
              text: switch (h) {
                InboundAccepted() => l10n.handoverRecorded(s.arrived.length),
                InboundUnknown() => l10n.handoverUnknown,
                InboundRejected(code: 'STOP_NOT_FOUND') => l10n.handoverNoStop,
                // 하차 화면에서 이미 정차 인계함(정차당 한 번)
                InboundRejected(code: 'HANDOVER_RECORDED') =>
                  l10n.handoverAlready,
                InboundRejected(code: 'INVALID_STATE') =>
                  l10n.handoverNotArrived,
                InboundRejected() => l10n.handoverRejected,
              },
            ),
          if (s.handover
              case InboundUnknown() ||
                  InboundRejected(code: != 'HANDOVER_RECORDED'))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('handover-retry'),
                onPressed: s.busy ? null : ctl.sendHandover,
                child: Text(l10n.handoverRetry),
              ),
            ),
          Text(
            l10n.boxInspectProgress(done, boxes.length),
            key: const ValueKey('box-inspect-progress'),
            style: theme.textTheme.titleMedium?.copyWith(
              color: PdaColors.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: ListView(
              children: [
                for (final b in boxes)
                  ListTile(
                    key: ValueKey('box-${b.boxId}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      s.boxDone(b.boxId)
                          ? Icons.check_circle
                          : Icons.inventory_2_outlined,
                    ),
                    title: Text(
                      s.entriesOf(b.boxId).length > 1
                          ? '${b.boxId} · ${l10n.boxMixedShort(s.entriesOf(b.boxId).length)}'
                          : '${b.boxId} · ${nameOf(b)}',
                    ),
                    trailing: Text(
                      s.boxDone(b.boxId)
                          ? l10n.boxInspected(
                              [
                                for (final e in s.entriesOf(b.boxId))
                                  s.boxCounts[e.entryKey]!.normal,
                              ].fold(0, (a, n) => a + n),
                              [
                                for (final e in s.entriesOf(b.boxId))
                                  s.boxCounts[e.entryKey]!.quarantined +
                                      s.boxCounts[e.entryKey]!.pending,
                              ].fold(0, (a, n) => a + n),
                            )
                          : l10n.boxNotInspected,
                    ),
                    onTap: () => ctl.openBox(b.boxId),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 입고칸 고를 온도대 이름(모르면 "입고칸")
String zoneLabel(AppLocalizations l10n, String zone) => switch (zone) {
  'FROZEN' => l10n.zoneFrozen,
  'CHILLED' => l10n.zoneChilled,
  'AMBIENT' => l10n.zoneAmbient,
  _ => l10n.receivingAnyZone,
};
