import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/pda_theme.dart';
import '../../../shared/providers.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/cdc_task_repository.dart';
import '../domain/cdc_task.dart';

final cdcTaskRepositoryProvider = Provider<CdcTaskRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockCdcTaskRepository(),
    PmartEnv.local => ApiCdcTaskRepository(ref.watch(dioProvider)),
  },
);

/// DC 피킹(사용자 2026-11-26 "피킹부터 붙여줘"). 들어오면 다음 작업을 받는다 — 들고 있던 작업이 있으면 서버가 그 작업을 준다.
/// 받기(ACCEPTED) → 작업 시작(IN_PROGRESS) → 줄마다 집은 수량·부족(사유) → 보내기(202 접수) → 작업 조회로 끝났는지 확인.
/// 끝남 표시는 서버 상태(DONE·PARTIAL)만 따른다. 같은 행위의 재전송은 같은 멱등 키.
class CdcPickScreen extends ConsumerStatefulWidget {
  const CdcPickScreen({super.key});

  @override
  ConsumerState<CdcPickScreen> createState() => _CdcPickScreenState();
}

enum _Phase { loading, noTask, task, failed }

class _CdcPickScreenState extends ConsumerState<CdcPickScreen> {
  _Phase _phase = _Phase.loading;
  CdcTask? _task;
  bool _busy = false;
  String? _message;

  /// 실패 뒤 다시 누르면 같은 키(같은 행위의 재전송)
  IdempotencyKey? _pullKey;
  IdempotencyKey? _startKey;
  IdempotencyKey? _reportKey;
  Future<void> Function()? _retry;

  final _picked = <String, TextEditingController>{};
  final _reason = <String, String>{};

  String get _cdcId {
    final c = ref.read(employeeSessionProvider)?.centers ?? const [];
    return c.length == 1 ? c.single : '';
  }

  String get _workerId => ref.read(employeeSessionProvider)?.operatorId ?? '';

  CdcTaskRepository get _repo => ref.read(cdcTaskRepositoryProvider);

  @override
  void initState() {
    super.initState();
    if (_cdcId.isNotEmpty) Future.microtask(_pull);
  }

  @override
  void dispose() {
    for (final c in _picked.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _setTask(CdcTask t) {
    for (final c in _picked.values) {
      c.dispose();
    }
    _picked
      ..clear()
      ..addAll({
        for (final l in t.lines)
          if (l.remaining > 0)
            l.key: TextEditingController(text: '${l.remaining}'),
      });
    _reason.clear();
    _task = t;
    _phase = _Phase.task;
  }

  Future<void> _run(Future<void> Function() body) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await body();
      _retry = null;
    } on PmartFailure catch (f) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      _retry = () => _run(body);
      _message = switch (f) {
        UnknownResultFailure() || NetworkFailure() => l10n.cdcPickUnknown,
        ProblemFailure(:final problem) => switch (problem.code) {
          'VERSION_CONFLICT' ||
          'INVALID_STATE' ||
          'NOT_ASSIGNEE' => l10n.cdcPickChanged,
          'PICK_EXCEEDS_ALLOCATION' => l10n.cdcPickExceeds,
          _ => l10n.cdcPickFailed,
        },
        _ => l10n.cdcPickFailed,
      };
      // 서버 상태가 바뀌었으면 다시 읽어 맞춘다(같은 키 재전송으로 풀리지 않는다)
      if (f
          case ProblemFailure(
            problem: Problem(code: 'VERSION_CONFLICT' || 'INVALID_STATE'),
          )
          when _task != null) {
        _retry = null;
        try {
          _setTask(await _repo.get(cdcId: _cdcId, taskId: _task!.taskId));
        } on PmartFailure {
          // 다시 읽지 못하면 지금 화면을 둔다
        }
      }
      if (_task == null) _phase = _Phase.failed;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pull({bool fresh = false}) {
    if (fresh) _pullKey = null;
    final key = _pullKey ??= IdempotencyKey.generate();
    return _run(() async {
      final r = await _repo.nextPick(
        cdcId: _cdcId,
        workerId: _workerId,
        key: key,
      );
      _pullKey = null;
      switch (r) {
        case CdcGotTask(:final task):
          _setTask(task);
        case CdcNoTask():
          _task = null;
          _phase = _Phase.noTask;
      }
    });
  }

  Future<void> _start() {
    final task = _task!;
    final key = _startKey ??= IdempotencyKey.generate();
    return _run(() async {
      final t = await _repo.start(cdcId: _cdcId, task: task, key: key);
      _startKey = null;
      _setTask(t);
    });
  }

  List<CdcPickLine>? _lines() {
    final out = <CdcPickLine>[];
    for (final l in _task!.lines.where((l) => l.remaining > 0)) {
      final picked = int.tryParse(_picked[l.key]?.text.trim() ?? '');
      if (picked == null || picked < 0 || picked > l.remaining) return null;
      final short = l.remaining - picked;
      if (short > 0 && _reason[l.key] == null) return null;
      out.add(
        CdcPickLine(
          line: l,
          pickedQty: picked,
          shortQty: short,
          shortReason: short > 0 ? _reason[l.key] : null,
        ),
      );
    }
    return out;
  }

  Future<void> _report() {
    final task = _task!;
    final lines = _lines()!;
    final key = _reportKey ??= IdempotencyKey.generate();
    return _run(() async {
      await _repo.reportPick(
        cdcId: _cdcId,
        task: task,
        workerId: _workerId,
        lines: lines,
        key: key,
      );
      _reportKey = null;
      // 202 는 접수 — 작업을 다시 읽어 끝났는지 본다
      _setTask(await _repo.get(cdcId: _cdcId, taskId: task.taskId));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.cdcAreaPick)),
      body: SafeArea(
        child: _cdcId.isEmpty
            ? _Center(l10n.multipleCenters)
            : switch (_phase) {
                _Phase.loading => const Center(
                  child: CircularProgressIndicator(),
                ),
                _Phase.failed => _Center(
                  _message ?? l10n.cdcPickFailed,
                  action: FilledButton(
                    key: const ValueKey('cdc-retry'),
                    onPressed: _busy ? null : () => _retry?.call() ?? _pull(),
                    child: Text(l10n.retry),
                  ),
                ),
                _Phase.noTask => _Center(
                  _message ?? l10n.cdcPickNoTask,
                  textKey: const ValueKey('cdc-no-task'),
                  action: FilledButton(
                    key: const ValueKey('cdc-pull'),
                    onPressed: _busy ? null : () => _pull(fresh: true),
                    child: Text(l10n.cdcPickPull),
                  ),
                ),
                _Phase.task => _taskBody(l10n, _task!),
              },
      ),
    );
  }

  Widget _taskBody(AppLocalizations l10n, CdcTask t) {
    final theme = Theme.of(context);
    final lines = t.finished || t.accepted
        ? t.lines
        : t.lines.where((l) => l.remaining > 0).toList();
    final ready = t.inProgress && _lines() != null;
    final Widget action;
    if (t.finished) {
      action = FilledButton(
        key: const ValueKey('cdc-pull'),
        onPressed: _busy ? null : () => _pull(fresh: true),
        child: Text(l10n.cdcPickNext),
      );
    } else if (t.accepted) {
      action = FilledButton(
        key: const ValueKey('cdc-start'),
        onPressed: _busy ? null : _start,
        child: Text(l10n.cdcPickStart),
      );
    } else if (t.inProgress) {
      action = FilledButton(
        key: const ValueKey('cdc-report'),
        onPressed: _busy || !ready ? null : _report,
        child: Text(l10n.cdcPickReport),
      );
    } else {
      // HELD·EXCEPTION·CANCELLED 등 — 관리자 확인
      action = FilledButton(
        key: const ValueKey('cdc-pull'),
        onPressed: _busy ? null : () => _pull(fresh: true),
        child: Text(l10n.cdcPickNext),
      );
    }
    final shorts = t.lines.fold<int>(0, (a, l) => a + l.shortQty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            children: [
              _Header(task: t),
              const SizedBox(height: 12),
              if (t.finished)
                _Banner(
                  key: const ValueKey('cdc-done'),
                  text: shorts > 0
                      ? l10n.cdcPickDoneShort(shorts)
                      : l10n.cdcPickDone,
                  ok: shorts == 0,
                )
              else if (!t.accepted && !t.inProgress)
                _Banner(text: l10n.cdcPickOther(t.state), ok: false),
              if (t.accepted)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    l10n.cdcPickAcceptedHint,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: PdaColors.muted,
                    ),
                  ),
                ),
              for (final l in lines)
                _LineCard(
                  line: l,
                  editable: t.inProgress,
                  picked: _picked[l.key],
                  reason: _reason[l.key],
                  onChanged: () => setState(() {}),
                  onReason: (r) => setState(() {
                    if (r != null) _reason[l.key] = r;
                  }),
                ),
            ],
          ),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              _message!,
              key: const ValueKey('cdc-message'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SizedBox(
            height: 52,
            child: _retry != null
                ? FilledButton(
                    key: const ValueKey('cdc-retry'),
                    onPressed: _busy ? null : _retry,
                    child: Text(l10n.cdcPickResend),
                  )
                : action,
          ),
        ),
      ],
    );
  }
}

class _Center extends StatelessWidget {
  const _Center(this.text, {this.action, this.textKey});

  final String text;
  final Widget? action;
  final Key? textKey;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            key: textKey,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.text, required this.ok});

  final String text;
  final bool ok;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: ok
          ? PdaColors.softer
          : Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.task});

  final CdcTask task;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = task;
    String? due;
    if (t.dueAt case final d?) due = formatSeoulDateTime(d);
    return Container(
      key: const ValueKey('cdc-task'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PdaColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.label,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (t.pickMethod != null) t.pickMethod!,
              if (t.floor != null) l10n.cdcPickFloor(t.floor!),
              if (t.zone != null) l10n.cdcPickZone(t.zone!),
              if (t.waveNumber != null) t.waveNumber!,
            ].join(' · '),
            style: const TextStyle(color: PdaColors.muted),
          ),
          if (t.trfNumbers.isNotEmpty)
            Text(
              'TRF ${t.trfNumbers.join(', ')}',
              style: const TextStyle(color: PdaColors.muted),
            ),
          if (due != null)
            Text(
              l10n.cdcPickDue(due),
              style: const TextStyle(color: PdaColors.muted),
            ),
        ],
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.line,
    required this.editable,
    required this.picked,
    required this.reason,
    required this.onChanged,
    required this.onReason,
  });

  final CdcTaskLine line;
  final bool editable;
  final TextEditingController? picked;
  final String? reason;
  final VoidCallback onChanged;
  final ValueChanged<String?> onReason;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final l = line;
    final n = int.tryParse(picked?.text.trim() ?? '');
    final short = editable && n != null && n >= 0 && n <= l.remaining
        ? l.remaining - n
        : 0;
    return Container(
      key: ValueKey('cdc-line-${l.sku}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PdaColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.locationCode,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: PdaColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l.productName ?? l.sku,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          Text(
            '${l.sku} · LOT ${l.lot}',
            style: const TextStyle(color: PdaColors.muted),
          ),
          const SizedBox(height: 6),
          Text(
            editable
                ? l10n.cdcPickLeft(l.remaining)
                : l10n.cdcPickLineResult(l.plannedQty, l.pickedQty, l.shortQty),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (editable && picked != null) ...[
            const SizedBox(height: 8),
            TextField(
              key: ValueKey('cdc-picked-${l.sku}'),
              controller: picked,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: l10n.cdcPickPickedLabel,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => onChanged(),
            ),
            if (short > 0) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey('cdc-reason-${l.sku}'),
                initialValue: reason,
                decoration: InputDecoration(
                  labelText: l10n.cdcPickShortLabel(short),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final r in cdcShortReasons)
                    DropdownMenuItem(
                      value: r,
                      child: Text(_reasonText(l10n, r)),
                    ),
                ],
                onChanged: onReason,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

String _reasonText(AppLocalizations l10n, String r) => switch (r) {
  'NOT_FOUND' => l10n.cdcShortNotFound,
  'DAMAGED' => l10n.cdcShortDamaged,
  'EXPIRED' => l10n.cdcShortExpired,
  'LOCATION_BLOCKED' => l10n.cdcShortBlocked,
  _ => l10n.cdcShortOther,
};
