import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/field_widgets.dart';
import '../../../shared/location_guide.dart';
import '../../../shared/pda_theme.dart';
import '../../../shared/providers.dart';
import '../../../shared/scanner/scan_input.dart';
import '../../../shared/scanner/scanner.dart';
import '../data/cdc_task_repository.dart';
import '../domain/cdc_task.dart';
import 'cdc_home.dart';
import 'cdc_widgets.dart';

final cdcTaskRepositoryProvider = Provider<CdcTaskRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockCdcTaskRepository(),
    PmartEnv.local => ApiCdcTaskRepository(ref.watch(dioProvider)),
  },
);

/// DC 피킹 — MFC 피킹과 같은 흐름(사용자 2026-11-26 "mfc 쪽 업무화면 참고해봐").
/// 작업 받기(서버 자동 배정·들고 있던 작업 이어감) → 착수 → 줄마다 [위치 스캔 → 상품 스캔(+1)·수량, 부족 보고]
/// → 모든 줄이 차면 한 번에 실피킹 결과(202) → 작업을 다시 읽어 DONE·PARTIAL 이면 완료 화면 → 10초 뒤 다음 작업.
/// 끝남 표시는 서버 상태만 따른다. 같은 보내기의 재전송은 같은 멱등 키.
class CdcPickScreen extends ConsumerStatefulWidget {
  const CdcPickScreen({super.key});

  @override
  ConsumerState<CdcPickScreen> createState() => _CdcPickScreenState();
}

enum _Phase { pulling, noTask, failed, working, done }

class _CdcPickScreenState extends ConsumerState<CdcPickScreen> with CdcCommand {
  _Phase _phase = _Phase.pulling;
  CdcTask? _task;
  IdempotencyKey? _pullKey;

  /// 줄 → 집은 수(이번에 보낼 것)
  final _picked = <String, int>{};

  /// 줄 → 부족 사유(남은 수량 − 집은 수 = 부족)
  final _short = <String, String>{};
  bool _locOk = false;
  String? _scanError;

  String get _cdcId => cdcCenterOf(ref);
  CdcTaskRepository get _repo => ref.read(cdcTaskRepositoryProvider);

  @override
  void initState() {
    super.initState();
    if (_cdcId.isNotEmpty) Future.microtask(_pull);
  }

  void _setTask(CdcTask t) {
    _task = t;
    _picked.clear();
    _short.clear();
    _locOk = false;
    _scanError = null;
    _phase = t.finished ? _Phase.done : _Phase.working;
  }

  /// 다음 작업 받기 → 받기만 한 작업(ACCEPTED)이면 바로 착수
  Future<void> _pull() async {
    setState(() {
      _phase = _Phase.pulling;
      failText = null;
    });
    final key = _pullKey ??= IdempotencyKey.generate();
    try {
      final r = await _repo.nextPick(
        cdcId: _cdcId,
        workerId: cdcWorkerOf(ref),
        key: key,
      );
      _pullKey = null;
      switch (r) {
        case CdcNoTask():
          _phase = _Phase.noTask;
        case CdcGotTask(:final task):
          var t = task;
          if (t.accepted) {
            t = await _repo.start(
              cdcId: _cdcId,
              task: t,
              key: IdempotencyKey.generate(),
            );
          }
          _setTask(t);
      }
    } on PmartFailure {
      _phase = _Phase.failed;
    }
    if (mounted) setState(() {});
  }

  /// 아직 처리하지 않은 줄(서버 남은 수량 > 0 이고 이번에 다 채우지 않은 줄)
  CdcTaskLine? get _current => _task?.lines
      .where((l) => l.remaining > 0)
      .where((l) => !_short.containsKey(l.key))
      .where((l) => (_picked[l.key] ?? 0) < l.remaining)
      .firstOrNull;

  ScanFeedback _scanLocation(CdcTaskLine line, String code) {
    final l10n = AppLocalizations.of(context);
    if (code.trim().toUpperCase() != line.locationCode.toUpperCase()) {
      setState(() => _scanError = l10n.cdcPickWrongLocation);
      return ScanFeedback.error(l10n.cdcPickWrongLocation);
    }
    setState(() {
      _locOk = true;
      _scanError = null;
    });
    return const ScanFeedback.ok();
  }

  ScanFeedback _scanItem(CdcTaskLine line, String code) {
    final l10n = AppLocalizations.of(context);
    if (!cdcCodeIsItem(code, line.sku, line.lot)) {
      setState(() => _scanError = l10n.cdcPickWrongItem);
      return ScanFeedback.error(l10n.cdcPickWrongItem);
    }
    _setCount(line, (_picked[line.key] ?? 0) + 1);
    return const ScanFeedback.ok();
  }

  void _setCount(CdcTaskLine line, int n) {
    if (n < 0 || n > line.remaining) return;
    setState(() {
      _picked[line.key] = n;
      _scanError = null;
      if (n == line.remaining) _lineDone();
    });
  }

  /// 줄 하나가 끝났다 — 다음 줄은 다시 위치부터. 다 끝났으면 보낸다.
  void _lineDone() {
    _locOk = false;
    if (_current == null) Future.microtask(_report);
  }

  Future<void> _reportShort(CdcTaskLine line) async {
    final l10n = AppLocalizations.of(context);
    final missing = line.remaining - (_picked[line.key] ?? 0);
    final reason = await showCdcReasonDialog(
      context,
      title: l10n.cdcPickShortTitle(missing),
      keyPrefix: 'cdc-short',
      options: [
        ('NOT_FOUND', Icons.search_off, l10n.cdcShortNotFound),
        ('DAMAGED', Icons.broken_image_outlined, l10n.cdcShortDamaged),
        ('EXPIRED', Icons.event_busy, l10n.cdcShortExpired),
        ('LOCATION_BLOCKED', Icons.block, l10n.cdcShortBlocked),
        ('OTHER', Icons.more_horiz, l10n.cdcShortOther),
      ],
    );
    if (reason == null || !mounted) return;
    setState(() {
      _short[line.key] = reason;
      _lineDone();
    });
  }

  Future<void> _report() async {
    final task = _task;
    if (task == null) return;
    final lines = [
      for (final l in task.lines.where((l) => l.remaining > 0))
        CdcPickLine(
          line: l,
          pickedQty: _picked[l.key] ?? 0,
          shortQty: l.remaining - (_picked[l.key] ?? 0),
          shortReason: _short[l.key],
        ),
    ];
    await send(
      (key) => _repo.reportPick(
        cdcId: _cdcId,
        task: task,
        workerId: cdcWorkerOf(ref),
        lines: lines,
        key: key,
      ),
      reload: () async =>
          _setTask(await _repo.get(cdcId: _cdcId, taskId: task.taskId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final line = _current;
    final stepTitle = switch (_phase) {
      _Phase.done => l10n.cdcPickDone,
      _Phase.working when line == null => l10n.pickSentTitle,
      _Phase.working when !_locOk => l10n.cdcPickStepLocation,
      _Phase.working => l10n.cdcPickStepItem,
      _ => l10n.cdcAreaPick,
    };
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Row(
          children: [
            const CdcBarIcon(area: CdcWorkArea.pick),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _task == null
                        ? l10n.cdcAreaPick
                        : '${l10n.cdcAreaPick} · ${_task!.label}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: PdaColors.onBarMuted,
                    ),
                  ),
                  Text(stepTitle, key: const ValueKey('cdc-pick-step-title')),
                ],
              ),
            ),
          ],
        ),
        bottom: busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
        actions: [
          if (_task case final t?)
            IconButton(
              key: const ValueKey('cdc-task-info'),
              tooltip: l10n.taskInfo,
              icon: const Icon(Icons.info_outline),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (_) => _TaskInfoSheet(task: t),
              ),
            ),
        ],
      ),
      body: SafeArea(child: _body(context, l10n, line)),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n, CdcTaskLine? line) {
    if (_cdcId.isEmpty) {
      return CdcCenterNotice(icon: Icons.block, text: l10n.multipleCenters);
    }
    final task = _task;
    switch (_phase) {
      case _Phase.pulling:
        return CdcCenterNotice(
          icon: Icons.downloading,
          text: l10n.sessionPulling,
        );
      case _Phase.noTask:
        return CdcCenterNotice(
          icon: Icons.hourglass_empty,
          text: l10n.nextNoTask,
          textKey: const ValueKey('cdc-no-task'),
          action: FilledButton(
            key: const ValueKey('cdc-pull'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: _pull,
            child: Text(l10n.nextRetry),
          ),
        );
      case _Phase.failed:
        return CdcCenterNotice(
          icon: Icons.cloud_off,
          text: l10n.cdcPickFailed,
          action: FilledButton(
            key: const ValueKey('cdc-pull'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: _pull,
            child: Text(l10n.retry),
          ),
        );
      case _Phase.done:
        final t = task!;
        final picked = t.lines.fold<int>(0, (a, l) => a + l.pickedQty);
        final short = t.lines.fold<int>(0, (a, l) => a + l.shortQty);
        return TaskDoneView(
          key: const ValueKey('cdc-done'),
          title: l10n.cdcPickDone,
          message: short > 0
              ? l10n.cdcPickDoneShort(short)
              : l10n.cdcPickDoneMessage,
          rows: [
            (l10n.cdcRowTask, t.label),
            if (t.trfNumbers.isNotEmpty)
              (l10n.cdcRowTrf, t.trfNumbers.join(', ')),
            (l10n.cdcRowPicked, '$picked'),
            if (short > 0) (l10n.cdcRowShort, '$short'),
          ],
          onNext: _pull,
        );
      case _Phase.working:
        break;
    }
    final t = task!;
    final total = t.lines.fold<int>(0, (a, l) => a + l.plannedQty);
    final done =
        t.lines.fold<int>(0, (a, l) => a + l.pickedQty + l.shortQty) +
        _picked.values.fold<int>(0, (a, n) => a + n) +
        [
          for (final l in t.lines)
            if (_short.containsKey(l.key)) l.remaining - (_picked[l.key] ?? 0),
        ].fold<int>(0, (a, n) => a + n);
    final body = <Widget>[];
    final actions = <Widget>[];
    if (line != null) {
      body.add(
        StepHeader(
          names: [l10n.cdcPickStepLocationShort, l10n.cdcPickStepItemShort],
          current: _locOk ? 1 : 0,
        ),
      );
    }
    body.add(
      ProgressLine(
        textKey: const ValueKey('cdc-pick-progress'),
        text: l10n.cdcProgress(done, total),
        done: done,
        total: total,
      ),
    );
    if (line == null) {
      // 다 찼다 — 보내는 중이거나, 보냈는데 서버가 아직 끝내지 않음
      body.add(
        ScanPrompt(
          key: const ValueKey('cdc-pick-sending'),
          text: busy ? l10n.cdcSending : l10n.cdcPickWaitServer,
          detail: busy ? null : l10n.cdcPickWaitServerHelp,
        ),
      );
      if (busy) {
        body.add(const Center(child: CircularProgressIndicator()));
      } else if (resend == null) {
        actions.add(
          FilledButton(
            key: const ValueKey('cdc-check'),
            onPressed: () async {
              try {
                final next = await _repo.get(cdcId: _cdcId, taskId: t.taskId);
                if (mounted) setState(() => _setTask(next));
              } on PmartFailure {
                // 그대로 둔다
              }
            },
            child: Text(l10n.checkAgain),
          ),
        );
      }
    } else if (!_locOk) {
      body.add(
        LocationGuide(
          code: line.locationCode,
          codeKey: const ValueKey('cdc-pick-location'),
          detail: l10n.cdcPickLineOf(t.lines.indexOf(line) + 1, t.lines.length),
        ),
      );
      body.add(const SizedBox(height: 12));
      body.add(
        CdcItemCard(
          key: ValueKey('cdc-line-${line.sku}'),
          name: line.productName ?? line.sku,
          sku: line.sku,
          lot: line.lot,
          qty: line.remaining,
          qtyLabel: l10n.cdcQtyUnit,
        ),
      );
      actions.add(
        ScanInput(
          id: 'cdc-loc-scan',
          label: l10n.locScanHint,
          cameraTitle: l10n.cdcCameraLocation,
          continuous: false,
          autofocus: false,
          testValues: [
            TestScan(l10n.tsLocation, line.locationCode),
            TestScan(l10n.tsWrong, 'CDC01-Z-9-99-99-9-9'),
          ],
          onScan: (code) => _scanLocation(line, code),
        ),
      );
    } else {
      final n = _picked[line.key] ?? 0;
      body.add(
        ScanPrompt(
          text: l10n.cdcPickTake(line.remaining - n),
          detail: l10n.pickLocConfirmed(line.locationCode),
        ),
      );
      body.add(
        CdcItemCard(
          key: ValueKey('cdc-line-${line.sku}'),
          name: line.productName ?? line.sku,
          sku: line.sku,
          lot: line.lot,
          qty: line.remaining,
          qtyLabel: l10n.cdcQtyUnit,
          footer: n > 0 ? l10n.cdcPickTaken(n) : null,
          emphasize: true,
        ),
      );
      if (n > 0) {
        body.add(
          CountQtyField(
            id: 'cdc-pick-qty',
            label: l10n.pickQtyLabel,
            help: l10n.pickQtyHelp(line.remaining),
            addLabel: l10n.pickQtyAdd,
            value: n,
            max: line.remaining,
            onAdd: () => _setCount(line, n + 1),
            onSet: (v) => _setCount(line, v),
          ),
        );
      }
      actions.addAll([
        ScanInput(
          id: 'cdc-item-scan',
          label: l10n.cdcScanItem,
          cameraTitle: l10n.cdcCameraItem,
          continuous: false,
          testValues: [
            TestScan(line.productName ?? line.sku, line.sku),
            TestScan(l10n.tsWrong, 'SKU-0000'),
          ],
          onScan: (code) => _scanItem(line, code),
        ),
        OutlinedButton(
          key: const ValueKey('cdc-short'),
          style: OutlinedButton.styleFrom(foregroundColor: PdaColors.danger),
          onPressed: busy ? null : () => _reportShort(line),
          child: Text(l10n.cdcPickShortButton),
        ),
      ]);
    }
    if (_scanError case final e?) {
      actions.insert(0, CdcErrorLine(e, key: const ValueKey('cdc-scan-error')));
    }
    if (failText case final f?) {
      actions.insert(0, CdcErrorLine(f, key: const ValueKey('cdc-message')));
    }
    if (resendButton(context) case final b?) actions.add(b);
    return cdcStepBody(
      step: line == null
          ? 'send'
          : _locOk
          ? 'item-${line.key}'
          : 'loc-${line.key}',
      body: body,
      actions: actions,
    );
  }
}

class _TaskInfoSheet extends StatelessWidget {
  const _TaskInfoSheet({required this.task});

  final CdcTask task;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = task;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MetaPair(label: l10n.cdcRowTask, value: t.label),
            if (t.waveNumber case final w?) MetaPair(label: 'Wave', value: w),
            if (t.trfNumbers.isNotEmpty)
              MetaPair(label: l10n.cdcRowTrf, value: t.trfNumbers.join(', ')),
            if (t.pickMethod case final m?)
              MetaPair(label: l10n.cdcRowMethod, value: m),
            if (t.floor != null || t.zone != null)
              MetaPair(
                label: l10n.cdcRowZone,
                value: [
                  if (t.floor case final f?) l10n.cdcPickFloor(f),
                  if (t.zone case final z?) l10n.cdcPickZone(z),
                ].join(' · '),
              ),
            if (t.dueAt case final d?)
              MetaPair(label: l10n.cdcRowDue, value: formatSeoulDateTime(d)),
          ],
        ),
      ),
    );
  }
}
