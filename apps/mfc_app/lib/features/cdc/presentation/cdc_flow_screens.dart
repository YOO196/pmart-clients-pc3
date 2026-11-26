import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/pda_theme.dart';
import '../../../shared/providers.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/cdc_flow_repository.dart';
import '../domain/cdc_flow.dart';

/// DC 분배·검품·상차·지게차 적치(사용자 2026-11-26 "업무화면 다 만들어").
/// 결과 등록은 202 접수 — 보낸 뒤 서버 값을 다시 읽어 그것만 보인다. 같은 행위의 재전송은 같은 멱등 키.
final cdcFlowRepositoryProvider = Provider<CdcFlowRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockCdcFlowRepository(),
    PmartEnv.local => ApiCdcFlowRepository(ref.watch(dioProvider)),
  },
);

/// 보내기·다시 읽기 공통 — 실패 문구, 같은 키 재전송.
mixin _Command<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool busy = false;
  String? message;
  String? notice;
  IdempotencyKey? _key;
  Future<void> Function()? retry;

  String get cdcId {
    final c = ref.read(employeeSessionProvider)?.centers ?? const [];
    return c.length == 1 ? c.single : '';
  }

  String get workerId => ref.read(employeeSessionProvider)?.operatorId ?? '';

  CdcFlowRepository get repo => ref.read(cdcFlowRepositoryProvider);

  /// [send] 는 키를 받아 보낸다. 성공하면 [after](다시 읽기)와 [done] 문구.
  Future<void> command(
    Future<void> Function(IdempotencyKey key) send, {
    required Future<void> Function() after,
    required String done,
  }) async {
    final key = _key ??= IdempotencyKey.generate();
    setState(() {
      busy = true;
      message = null;
      notice = null;
    });
    try {
      await send(key);
      _key = null;
      retry = null;
      await after();
      notice = done;
    } on PmartFailure catch (f) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      final unknown = f is UnknownResultFailure || f is NetworkFailure;
      // 결과를 모르면 같은 키로 다시 보내게 한다. 거절이면 키를 버리고 다시 읽는다.
      retry = unknown ? () => command(send, after: after, done: done) : null;
      if (!unknown) {
        _key = null;
        try {
          await after();
        } on PmartFailure {
          // 다시 읽지 못하면 지금 화면을 둔다
        }
      }
      message = switch (f) {
        _ when unknown => l10n.cdcPickUnknown,
        ProblemFailure(:final problem) => cdcProblemText(l10n, problem.code),
        _ => l10n.cdcPickFailed,
      };
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget feedback(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notice != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              notice!,
              key: const ValueKey('cdc-notice'),
              style: const TextStyle(
                color: PdaColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              message!,
              key: const ValueKey('cdc-message'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }

  Widget bottomButton(
    BuildContext context, {
    required Key key,
    required String label,
    required VoidCallback? onPressed,
  }) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: SizedBox(
          height: 52,
          child: retry != null
              ? FilledButton(
                  key: const ValueKey('cdc-retry'),
                  onPressed: busy ? null : retry,
                  child: Text(l10n.cdcPickResend),
                )
              : FilledButton(
                  key: key,
                  onPressed: busy ? null : onPressed,
                  child: Text(label),
                ),
        ),
      ),
    );
  }
}

String cdcProblemText(AppLocalizations l10n, String code) => switch (code) {
  'LPN_ALREADY_SEALED' => l10n.cdcErrLpnSealed,
  'SORT_EXCEEDS_PICKED' => l10n.cdcErrSortExceeds,
  'LPN_NOT_PASSED' => l10n.cdcErrNotPassed,
  'TRIP_MISMATCH' => l10n.cdcErrTripMismatch,
  'LOAD_EXCEEDS_INSPECTED' => l10n.cdcErrNotPassed,
  'EXECUTION_EXCEEDS_REMAINING' ||
  'PICK_EXCEEDS_ALLOCATION' => l10n.cdcPickExceeds,
  'VERSION_CONFLICT' ||
  'INVALID_STATE' ||
  'NOT_ASSIGNEE' => l10n.cdcPickChanged,
  'NOT_FOUND' => l10n.cdcErrNotFound,
  _ => l10n.cdcPickFailed,
};

// ---------------------------------------------------------------- 공통 조각

/// 조회 상태(읽는 중·실패·빈 목록·내용)
class _Load<T> extends StatelessWidget {
  const _Load({
    required this.value,
    required this.onRetry,
    required this.empty,
    required this.isEmpty,
    required this.builder,
  });

  final AsyncValue<T> value;
  final VoidCallback onRetry;
  final String empty;
  final bool Function(T) isEmpty;
  final Widget Function(T) builder;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (value) {
      AsyncData(:final value) when isEmpty(value) => _CenterText(
        empty,
        key: const ValueKey('cdc-empty'),
      ),
      AsyncData(:final value) => builder(value),
      AsyncError() => _CenterText(
        l10n.cdcLoadFailed,
        action: FilledButton(
          key: const ValueKey('cdc-reload'),
          onPressed: onRetry,
          child: Text(l10n.retry),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _CenterText extends StatelessWidget {
  const _CenterText(this.text, {super.key, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.child,
    this.onTap,
    this.selected = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? PdaColors.primary : PdaColors.line,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(14), child: child),
      ),
    ),
  );
}

const _title = TextStyle(fontSize: 18, fontWeight: FontWeight.w800);
const _muted = TextStyle(color: PdaColors.muted);
const _strong = TextStyle(fontWeight: FontWeight.w700);

String _contentsText(CdcLpn l) =>
    l.contents.map((c) => '${c.sku} ${c.qty}').join(' · ');

/// 피킹 끝난 TRF 고르기 — 분배·검품·상차 공통 첫 화면
class _TrfList extends ConsumerStatefulWidget {
  const _TrfList({required this.onPick});

  final ValueChanged<CdcTrf> onPick;

  @override
  ConsumerState<_TrfList> createState() => _TrfListState();
}

class _TrfListState extends ConsumerState<_TrfList> {
  AsyncValue<List<CdcTrf>> _trfs = const AsyncLoading();

  String get _cdcId {
    final c = ref.read(employeeSessionProvider)?.centers ?? const [];
    return c.length == 1 ? c.single : '';
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() => _trfs = const AsyncLoading());
    final v = await AsyncValue.guard(
      () => ref.read(cdcFlowRepositoryProvider).pickedTransfers(_cdcId),
    );
    if (mounted) setState(() => _trfs = v);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _Load(
      value: _trfs,
      onRetry: _load,
      empty: l10n.cdcTrfEmpty,
      isEmpty: (v) => v.isEmpty,
      builder: (trfs) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(l10n.cdcTrfChoose, style: _muted),
            ),
            for (final t in trfs)
              _Card(
                key: ValueKey('cdc-trf-${t.trfId}'),
                onTap: () => widget.onPick(t),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.label, style: _title),
                    Text(
                      '${t.mfcId} · ${l10n.cdcPickDue(formatSeoulDateTime(t.dueAt))}',
                      style: _muted,
                    ),
                    Text(l10n.cdcTrfPicked(t.pickedQty), style: _strong),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// TRF 를 고른 뒤 화면 — 위에 TRF 머리, 뒤로 가면 TRF 목록
class _TrfScaffold extends StatelessWidget {
  const _TrfScaffold({
    required this.title,
    required this.trf,
    required this.onBack,
    required this.body,
    this.bottom,
  });

  final String title;
  final CdcTrf? trf;
  final VoidCallback onBack;
  final Widget body;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final t = trf;
    return PopScope(
      canPop: t == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(t == null ? title : '$title · ${t.label}')),
        body: SafeArea(child: body),
        bottomNavigationBar: bottom,
      ),
    );
  }
}

// ---------------------------------------------------------------- 분배·라인

class CdcSortScreen extends ConsumerStatefulWidget {
  const CdcSortScreen({super.key});

  @override
  ConsumerState<CdcSortScreen> createState() => _CdcSortScreenState();
}

class _CdcSortScreenState extends ConsumerState<CdcSortScreen> with _Command {
  CdcTrf? _trf;
  AsyncValue<(List<CdcSortItem>, List<CdcLpn>)> _data = const AsyncLoading();
  final _box = TextEditingController();
  final _qty = <String, TextEditingController>{};
  String? _zone;

  @override
  void dispose() {
    _box.dispose();
    for (final c in _qty.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final trf = _trf!;
    setState(() => _data = const AsyncLoading());
    final v = await AsyncValue.guard(
      () async =>
          (await repo.sortItems(cdcId, trf), await repo.lpns(cdcId, trf.trfId)),
    );
    if (!mounted) return;
    if (v case AsyncData(:final value)) {
      for (final c in _qty.values) {
        c.dispose();
      }
      _qty
        ..clear()
        ..addAll({
          for (final i in value.$1)
            if (i.remaining > 0)
              i.key: TextEditingController(text: '${i.remaining}'),
        });
    }
    setState(() => _data = v);
  }

  List<CdcLpnContent>? _contents(List<CdcSortItem> items) {
    final out = <CdcLpnContent>[];
    for (final i in items.where((i) => i.remaining > 0)) {
      final n = int.tryParse(_qty[i.key]?.text.trim() ?? '');
      if (n == null || n < 0 || n > i.remaining) return null;
      if (n > 0) out.add(CdcLpnContent(sku: i.sku, lot: i.lot, qty: n));
    }
    return out.isEmpty ? null : out;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final trf = _trf;
    final data = _data.value;
    final contents = data == null ? null : _contents(data.$1);
    final box = _box.text.trim();
    return _TrfScaffold(
      title: l10n.cdcAreaSort,
      trf: trf,
      onBack: () => setState(() {
        _trf = null;
        message = notice = null;
        retry = null;
      }),
      body: trf == null
          ? _TrfList(
              onPick: (t) {
                setState(() => _trf = t);
                _load();
              },
            )
          : _Load(
              value: _data,
              onRetry: _load,
              empty: '',
              isEmpty: (_) => false,
              builder: (d) => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (d.$1.every((i) => i.remaining == 0))
                    _CenterText(
                      l10n.cdcSortAllDone,
                      key: const ValueKey('cdc-sort-done'),
                    )
                  else ...[
                    TextField(
                      key: const ValueKey('cdc-box'),
                      controller: _box,
                      keyboardType: TextInputType.visiblePassword,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: l10n.cdcSortBoxLabel,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('cdc-zone'),
                      initialValue: _zone,
                      decoration: InputDecoration(
                        labelText: l10n.cdcSortZoneLabel,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final z in cdcTemperatureZones)
                          DropdownMenuItem(
                            value: z,
                            child: Text(_zoneText(l10n, z)),
                          ),
                      ],
                      onChanged: (z) => setState(() => _zone = z),
                    ),
                    const SizedBox(height: 12),
                    Text(l10n.cdcSortItemsHint, style: _muted),
                    const SizedBox(height: 8),
                    for (final i in d.$1.where((i) => i.remaining > 0))
                      _Card(
                        key: ValueKey('cdc-sort-${i.sku}'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(i.productName ?? i.sku, style: _title),
                            Text('${i.sku} · LOT ${i.lot}', style: _muted),
                            Text(
                              l10n.cdcSortLeft(i.pickedQty, i.remaining),
                              style: _strong,
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              key: ValueKey('cdc-sort-qty-${i.sku}'),
                              controller: _qty[i.key],
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                labelText: l10n.cdcSortQtyLabel,
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ],
                        ),
                      ),
                  ],
                  if (d.$2.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(l10n.cdcSortBoxes(d.$2.length), style: _strong),
                    const SizedBox(height: 6),
                    for (final l in d.$2)
                      _Card(
                        key: ValueKey('cdc-lpn-${l.lpn}'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.lpn, style: _strong),
                            Text(_contentsText(l), style: _muted),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
      bottom:
          trf == null || data == null || data.$1.every((i) => i.remaining == 0)
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                feedback(context),
                bottomButton(
                  context,
                  key: const ValueKey('cdc-sort-go'),
                  label: l10n.cdcSortSubmit,
                  onPressed: box.isEmpty || contents == null
                      ? null
                      : () => command(
                          (key) => repo.reportSort(
                            trf: trf,
                            workerId: workerId,
                            box: CdcBoxDraft(
                              lpn: box,
                              temperatureZone: _zone,
                              contents: contents,
                            ),
                            key: key,
                          ),
                          after: () async {
                            _box.clear();
                            await _load();
                          },
                          done: l10n.cdcSortDone(box),
                        ),
                ),
              ],
            ),
    );
  }
}

String _zoneText(AppLocalizations l10n, String z) => switch (z) {
  'CHILLED' => l10n.cdcZoneChilled,
  'FROZEN' => l10n.cdcZoneFrozen,
  _ => l10n.cdcZoneAmbient,
};

// ---------------------------------------------------------------- 검품

class CdcInspectScreen extends ConsumerStatefulWidget {
  const CdcInspectScreen({super.key});

  @override
  ConsumerState<CdcInspectScreen> createState() => _CdcInspectScreenState();
}

class _CdcInspectScreenState extends ConsumerState<CdcInspectScreen>
    with _Command {
  CdcTrf? _trf;
  AsyncValue<List<CdcLpn>> _lpns = const AsyncLoading();

  /// LPN → 합격(true)·불합격(false)
  final _pick = <String, bool>{};
  final _reason = <String, String>{};

  Future<void> _load() async {
    setState(() => _lpns = const AsyncLoading());
    final v = await AsyncValue.guard(() => repo.lpns(cdcId, _trf!.trfId));
    if (!mounted) return;
    _pick.clear();
    _reason.clear();
    setState(() => _lpns = v);
  }

  List<CdcInspection>? _items() {
    if (_pick.isEmpty) return null;
    final out = <CdcInspection>[];
    for (final e in _pick.entries) {
      if (!e.value && _reason[e.key] == null) return null;
      out.add(
        CdcInspection(
          lpn: e.key,
          passed: e.value,
          failReason: e.value ? null : _reason[e.key],
        ),
      );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final trf = _trf;
    final items = _items();
    return _TrfScaffold(
      title: l10n.cdcAreaInspect,
      trf: trf,
      onBack: () => setState(() {
        _trf = null;
        message = notice = null;
        retry = null;
      }),
      body: trf == null
          ? _TrfList(
              onPick: (t) {
                setState(() => _trf = t);
                _load();
              },
            )
          : _Load(
              value: _lpns,
              onRetry: _load,
              empty: l10n.cdcInspectEmpty,
              isEmpty: (v) => v.where((l) => !l.loaded).isEmpty,
              builder: (lpns) => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(l10n.cdcInspectHint, style: _muted),
                  ),
                  for (final l in lpns.where((l) => !l.loaded))
                    _Card(
                      key: ValueKey('cdc-lpn-${l.lpn}'),
                      selected: _pick.containsKey(l.lpn),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(l.lpn, style: _title)),
                              Text(
                                switch (l.inspection) {
                                  'PASSED' => l10n.cdcInspectPassed,
                                  'FAILED' => l10n.cdcInspectFailed,
                                  _ => l10n.cdcInspectNone,
                                },
                                key: ValueKey('cdc-insp-${l.lpn}'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: l.passed
                                      ? PdaColors.primary
                                      : (l.inspection == 'FAILED'
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .error
                                            : PdaColors.muted),
                                ),
                              ),
                            ],
                          ),
                          Text(_contentsText(l), style: _muted),
                          const SizedBox(height: 8),
                          SegmentedButton<bool>(
                            key: ValueKey('cdc-judge-${l.lpn}'),
                            emptySelectionAllowed: true,
                            segments: [
                              ButtonSegment(
                                value: true,
                                label: Text(l10n.cdcInspectPass),
                              ),
                              ButtonSegment(
                                value: false,
                                label: Text(l10n.cdcInspectFail),
                              ),
                            ],
                            selected: {?_pick[l.lpn]},
                            onSelectionChanged: (s) => setState(() {
                              if (s.isEmpty) {
                                _pick.remove(l.lpn);
                              } else {
                                _pick[l.lpn] = s.single;
                              }
                            }),
                          ),
                          if (_pick[l.lpn] == false) ...[
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              key: ValueKey('cdc-fail-${l.lpn}'),
                              initialValue: _reason[l.lpn],
                              decoration: InputDecoration(
                                labelText: l10n.cdcInspectReason,
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: [
                                for (final r in cdcFailReasons)
                                  DropdownMenuItem(
                                    value: r,
                                    child: Text(_failText(l10n, r)),
                                  ),
                              ],
                              onChanged: (r) => setState(() {
                                if (r != null) _reason[l.lpn] = r;
                              }),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
      bottom: trf == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                feedback(context),
                bottomButton(
                  context,
                  key: const ValueKey('cdc-inspect-go'),
                  label: l10n.cdcInspectSubmit(_pick.length),
                  onPressed: items == null
                      ? null
                      : () => command(
                          (key) => repo.reportInspection(
                            trfId: trf.trfId,
                            inspectorId: workerId,
                            items: items,
                            key: key,
                          ),
                          after: _load,
                          done: l10n.cdcInspectDone(items.length),
                        ),
                ),
              ],
            ),
    );
  }
}

String _failText(AppLocalizations l10n, String r) => switch (r) {
  'QTY_MISMATCH' => l10n.cdcFailQty,
  'SEAL_BROKEN' => l10n.cdcFailSeal,
  'TEMPERATURE' => l10n.cdcFailTemp,
  'DAMAGE' => l10n.cdcFailDamage,
  'WRONG_TRF' => l10n.cdcFailWrongTrf,
  _ => l10n.cdcShortOther,
};

// ---------------------------------------------------------------- 상차

class CdcLoadScreen extends ConsumerStatefulWidget {
  const CdcLoadScreen({super.key});

  @override
  ConsumerState<CdcLoadScreen> createState() => _CdcLoadScreenState();
}

class _CdcLoadScreenState extends ConsumerState<CdcLoadScreen> with _Command {
  CdcTrf? _trf;
  AsyncValue<List<CdcLpn>> _lpns = const AsyncLoading();
  final _chosen = <String>{};
  final _trip = TextEditingController();
  final _vehicle = TextEditingController();
  final _dock = TextEditingController();

  @override
  void dispose() {
    _trip.dispose();
    _vehicle.dispose();
    _dock.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _lpns = const AsyncLoading());
    final v = await AsyncValue.guard(() => repo.lpns(cdcId, _trf!.trfId));
    if (!mounted) return;
    _chosen
      ..clear()
      ..addAll([
        for (final l in v.value ?? const <CdcLpn>[])
          if (l.passed && !l.loaded) l.lpn,
      ]);
    setState(() => _lpns = v);
  }

  Widget _field(String key, TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      key: ValueKey(key),
      controller: c,
      keyboardType: TextInputType.visiblePassword,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (_) => setState(() {}),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final trf = _trf;
    final ready =
        _trip.text.trim().isNotEmpty &&
        _vehicle.text.trim().isNotEmpty &&
        _chosen.isNotEmpty;
    return _TrfScaffold(
      title: l10n.cdcAreaLoad,
      trf: trf,
      onBack: () => setState(() {
        _trf = null;
        message = notice = null;
        retry = null;
      }),
      body: trf == null
          ? _TrfList(
              onPick: (t) {
                setState(() => _trf = t);
                _load();
              },
            )
          : _Load(
              value: _lpns,
              onRetry: _load,
              empty: l10n.cdcLoadEmpty,
              isEmpty: (v) => v.where((l) => l.passed).isEmpty,
              builder: (lpns) => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(l10n.cdcLoadHint, style: _muted),
                  ),
                  _field('cdc-trip', _trip, l10n.cdcLoadTrip),
                  _field('cdc-vehicle', _vehicle, l10n.cdcLoadVehicle),
                  _field('cdc-dock', _dock, l10n.cdcLoadDock),
                  const SizedBox(height: 4),
                  for (final l in lpns.where((l) => l.passed))
                    _Card(
                      key: ValueKey('cdc-lpn-${l.lpn}'),
                      selected: _chosen.contains(l.lpn),
                      onTap: l.loaded
                          ? null
                          : () => setState(() {
                              if (!_chosen.remove(l.lpn)) _chosen.add(l.lpn);
                            }),
                      child: Row(
                        children: [
                          Icon(
                            l.loaded
                                ? Icons.local_shipping
                                : _chosen.contains(l.lpn)
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            color: l.loaded || _chosen.contains(l.lpn)
                                ? PdaColors.primary
                                : PdaColors.muted,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.lpn, style: _strong),
                                Text(_contentsText(l), style: _muted),
                                if (l.loaded)
                                  Text(
                                    l10n.cdcLoadLoaded(
                                      l.vehicleId ?? '-',
                                      l.tripId ?? '-',
                                    ),
                                    key: ValueKey('cdc-loaded-${l.lpn}'),
                                    style: const TextStyle(
                                      color: PdaColors.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
      bottom: trf == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                feedback(context),
                bottomButton(
                  context,
                  key: const ValueKey('cdc-load-go'),
                  label: l10n.cdcLoadSubmit(_chosen.length),
                  onPressed: !ready
                      ? null
                      : () {
                          final lpns = _chosen.toList();
                          final dock = _dock.text.trim();
                          command(
                            (key) => repo.reportLoading(
                              trfId: trf.trfId,
                              tripId: _trip.text.trim(),
                              vehicleId: _vehicle.text.trim(),
                              dockCode: dock.isEmpty ? null : dock,
                              workerId: workerId,
                              lpns: lpns,
                              key: key,
                            ),
                            after: _load,
                            done: l10n.cdcLoadDone(lpns.length),
                          );
                        },
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------- 지게차 적치

class CdcPutawayScreen extends ConsumerStatefulWidget {
  const CdcPutawayScreen({super.key});

  @override
  ConsumerState<CdcPutawayScreen> createState() => _CdcPutawayScreenState();
}

class _CdcPutawayScreenState extends ConsumerState<CdcPutawayScreen>
    with _Command {
  final _id = TextEditingController();
  AsyncValue<CdcPutaway>? _task;
  final _qty = <String, TextEditingController>{};
  final _loc = <String, TextEditingController>{};
  final _reason = <String, String>{};

  @override
  void dispose() {
    _id.dispose();
    for (final c in [..._qty.values, ..._loc.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _open(String id) async {
    setState(() {
      _task = const AsyncLoading();
      message = notice = null;
    });
    final v = await AsyncValue.guard(() => repo.putaway(id));
    if (!mounted) return;
    if (v case AsyncData(:final value)) {
      for (final c in [..._qty.values, ..._loc.values]) {
        c.dispose();
      }
      _qty
        ..clear()
        ..addAll({
          for (final r in value.rows)
            if (r.u > 0) r.key: TextEditingController(text: '${r.u}'),
        });
      _loc
        ..clear()
        ..addAll({
          for (final r in value.rows)
            if (r.u > 0) r.key: TextEditingController(text: r.location),
        });
      _reason.clear();
    }
    setState(() => _task = v);
  }

  List<CdcPutawayLine>? _lines(CdcPutaway t) {
    final out = <CdcPutawayLine>[];
    for (final r in t.rows.where((r) => r.u > 0)) {
      final n = int.tryParse(_qty[r.key]?.text.trim() ?? '');
      final loc = _loc[r.key]?.text.trim() ?? '';
      if (n == null || n < 0 || n > r.u || loc.isEmpty) return null;
      final moved = loc != r.location;
      if (moved && _reason[r.key] == null) return null;
      if (n == 0) continue;
      out.add(
        CdcPutawayLine(
          row: r,
          toLocation: loc,
          completedQty: n,
          exceptionReason: moved ? _reason[r.key] : null,
        ),
      );
    }
    return out.isEmpty ? null : out;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final task = _task;
    final t = task?.value;
    final lines = t == null ? null : _lines(t);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.cdcAreaPutaway)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('cdc-putaway-id'),
                    controller: _id,
                    keyboardType: TextInputType.visiblePassword,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: l10n.cdcPutawayIdLabel,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (v) =>
                        v.trim().isEmpty ? null : _open(v.trim()),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('cdc-putaway-open'),
                  onPressed: _id.text.trim().isEmpty || busy
                      ? null
                      : () => _open(_id.text.trim()),
                  child: Text(l10n.cdcPutawayOpen),
                ),
              ],
            ),
            const SizedBox(height: 12),
            switch (task) {
              null => Text(l10n.cdcPutawayHint, style: _muted),
              AsyncData(value: final t) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t.taskId, style: _title),
                  Text(
                    l10n.cdcPutawayState(_putawayStateText(l10n, t.state)),
                    key: const ValueKey('cdc-putaway-state'),
                    style: _strong,
                  ),
                  const SizedBox(height: 8),
                  for (final r in t.rows)
                    _Card(
                      key: ValueKey('cdc-pa-${r.sku}'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.location,
                            style: _title.copyWith(color: PdaColors.primary),
                          ),
                          Text('${r.sku} · LOT ${r.lot}', style: _muted),
                          Text(
                            l10n.cdcPutawayProgress(r.q, r.c, r.u),
                            style: _strong,
                          ),
                          if (r.u > 0 && !t.finished) ...[
                            const SizedBox(height: 8),
                            TextField(
                              key: ValueKey('cdc-pa-qty-${r.sku}'),
                              controller: _qty[r.key],
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                labelText: l10n.cdcPutawayQty,
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              key: ValueKey('cdc-pa-loc-${r.sku}'),
                              controller: _loc[r.key],
                              keyboardType: TextInputType.visiblePassword,
                              autocorrect: false,
                              decoration: InputDecoration(
                                labelText: l10n.cdcPutawayLoc,
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            if ((_loc[r.key]?.text.trim() ?? r.location) !=
                                r.location) ...[
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                key: ValueKey('cdc-pa-reason-${r.sku}'),
                                initialValue: _reason[r.key],
                                decoration: InputDecoration(
                                  labelText: l10n.cdcPutawayReason,
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: [
                                  for (final e in cdcPutawayExceptions)
                                    DropdownMenuItem(
                                      value: e,
                                      child: Text(_paReasonText(l10n, e)),
                                    ),
                                ],
                                onChanged: (e) => setState(() {
                                  if (e != null) _reason[r.key] = e;
                                }),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                ],
              ),
              AsyncError(:final error) => Text(
                error is ProblemFailure && error.problem.status == 404
                    ? l10n.cdcErrNotFound
                    : l10n.cdcLoadFailed,
                key: const ValueKey('cdc-putaway-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ],
        ),
      ),
      bottomNavigationBar: t == null || t.finished
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                feedback(context),
                bottomButton(
                  context,
                  key: const ValueKey('cdc-putaway-go'),
                  label: l10n.cdcPutawaySubmit,
                  onPressed: lines == null
                      ? null
                      : () => command(
                          (key) => repo.executePutaway(
                            task: t,
                            workerId: workerId,
                            lines: lines,
                            key: key,
                          ),
                          after: () => _open(t.taskId),
                          done: l10n.cdcPutawayDone,
                        ),
                ),
              ],
            ),
    );
  }
}

String _putawayStateText(AppLocalizations l10n, String s) => switch (s) {
  'COMPLETED' => l10n.cdcPaCompleted,
  'PARTIALLY_COMPLETED' => l10n.cdcPaPartial,
  'CANCELLED' => l10n.cdcPaCancelled,
  'FAILED' || 'RETRY_READY' || 'EXCEPTION_HOLD' => l10n.cdcPaFailed,
  _ => l10n.cdcPaOpen,
};

String _paReasonText(AppLocalizations l10n, String e) => switch (e) {
  'LOCATION_FULL' => l10n.cdcPaFull,
  'LOCATION_BLOCKED' => l10n.cdcShortBlocked,
  'DAMAGED' => l10n.cdcShortDamaged,
  'WRONG_LOT' => l10n.cdcPaWrongLot,
  _ => l10n.cdcShortOther,
};
