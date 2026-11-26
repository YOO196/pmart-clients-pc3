import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/field_widgets.dart';
import '../../../shared/pda_theme.dart';
import '../../../shared/providers.dart';
import '../../../shared/scanner/scan_input.dart';
import '../../../shared/scanner/scanner.dart';
import '../../inbound/domain/inbound.dart';
import '../../inbound/presentation/inbound_controller.dart';
import '../../tasks/presentation/task_controllers.dart';
import '../data/unload_repository.dart';

final unloadRepositoryProvider = Provider<UnloadRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockUnloadRepository(mfcId: mockMfcId),
    PmartEnv.local => ApiUnloadRepository(ref.watch(dioProvider)),
  },
);

/// 하차 — 도착한 운행 고르기 → 박스 스캔(파손 표시) → 정차 인계 → 입고 수령으로.
/// 스캔 ≠ 인계: 서버가 인계를 받은 뒤에만 "인계 기록"이라고 보인다(결과 불명이면 같은 키로 다시).
class UnloadScreen extends ConsumerStatefulWidget {
  const UnloadScreen({super.key});

  @override
  ConsumerState<UnloadScreen> createState() => _UnloadScreenState();
}

class _UnloadScreenState extends ConsumerState<UnloadScreen> {
  AsyncValue<List<UnloadTrip>> _trips = const AsyncLoading();
  UnloadTrip? _trip;
  AsyncValue<List<InboundPromiseView>> _promises = const AsyncLoading();
  final _scanned = <String>[];
  final _damaged = <String>{};
  String? _scanError;
  IdempotencyKey? _key;
  InboundCommandOutcome? _outcome;
  bool _busy = false;

  String get _mfcId => ref.read(currentMfcIdProvider);

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadTrips);
  }

  Future<void> _loadTrips() async {
    setState(() => _trips = const AsyncLoading());
    final v = await AsyncValue.guard(
      () => ref.read(unloadRepositoryProvider).trips(_mfcId),
    );
    if (mounted) setState(() => _trips = v);
  }

  Future<void> _open(UnloadTrip t) async {
    setState(() {
      _trip = t;
      _promises = const AsyncLoading();
      _scanned.clear();
      _damaged.clear();
      _outcome = null;
      _key = null;
      _scanError = null;
    });
    final repo = ref.read(inboundRepositoryProvider);
    final v = await AsyncValue.guard(
      () => Future.wait([for (final id in t.trfIds) repo.promise(id)]),
    );
    if (mounted) setState(() => _promises = v);
  }

  /// 박스 → 그 TRF
  Map<String, String> _boxOwner(List<InboundPromiseView> ps) => {
    for (final p in ps)
      for (final b in p.boxList) b.boxId: p.trfId,
  };

  ScanFeedback _scan(List<InboundPromiseView> ps, String code) {
    final l10n = AppLocalizations.of(context);
    final c = code.trim();
    final error = !_boxOwner(ps).containsKey(c)
        ? l10n.unloadNotThisTrip
        : _scanned.contains(c)
        ? l10n.unloadScannedAlready
        : null;
    if (error != null) {
      setState(() => _scanError = error);
      return ScanFeedback.error(error);
    }
    setState(() {
      _scanned.add(c);
      _scanError = null;
    });
    return const ScanFeedback.ok();
  }

  Future<void> _handover(List<InboundPromiseView> ps) async {
    final l10n = AppLocalizations.of(context);
    final owner = _boxOwner(ps);
    final missing = owner.length - _scanned.length;
    if (missing > 0 && _outcome is! InboundUnknown) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          key: const ValueKey('unload-missing-dialog'),
          title: Text(l10n.unloadMissingTitle(missing)),
          content: Text(l10n.unloadMissingBody),
          actions: [
            TextButton(
              key: const ValueKey('unload-missing-keep'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.unloadKeepScanning),
            ),
            FilledButton(
              key: const ValueKey('unload-missing-ok'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.unloadHandoverAnyway),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final trip = _trip!;
    final transfers = {
      for (final p in ps)
        p.trfId: (
          [
            for (final b in _scanned)
              if (owner[b] == p.trfId) b,
          ],
          [
            for (final b in _damaged)
              if (owner[b] == p.trfId) b,
          ],
        ),
    };
    setState(() => _busy = true);
    final key = _key ??= IdempotencyKey.generate();
    final r = await ref
        .read(unloadRepositoryProvider)
        .handover(
          tripId: trip.tripId,
          stopSeq: trip.stopSeq,
          transfers: transfers,
          key: key,
        );
    if (!mounted) return;
    if (r is! InboundUnknown) _key = null;
    setState(() {
      _busy = false;
      _outcome = r;
    });
  }

  void _back() {
    if (_trip != null && _outcome is! InboundAccepted) {
      setState(() => _trip = null);
    } else if (_trip != null) {
      setState(() => _trip = null);
      _loadTrips();
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final trip = _trip;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        leading: BackButton(onPressed: _back),
        title: Text(
          trip == null
              ? l10n.unloadTitle
              : l10n.unloadTripTitle(trip.vehicleLabel),
        ),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: SafeArea(
        child: trip == null
            ? _tripList(l10n)
            : switch (_promises) {
                AsyncData(:final value) => _work(l10n, trip, value),
                AsyncError() => _notice(
                  l10n.unloadLoadFailed,
                  () => _open(trip),
                ),
                _ => const Center(child: CircularProgressIndicator()),
              },
      ),
    );
  }

  Widget _notice(String text, VoidCallback retry) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton(
          key: const ValueKey('unload-retry'),
          onPressed: retry,
          child: Text(AppLocalizations.of(context).retry),
        ),
      ],
    ),
  );

  String _time(DateTime? t) => t == null
      ? '-'
      : '${t.toLocal().hour.toString().padLeft(2, '0')}:${t.toLocal().minute.toString().padLeft(2, '0')}';

  Widget _tripList(AppLocalizations l10n) => switch (_trips) {
    AsyncData(:final value) when value.isEmpty => _notice(
      l10n.unloadNone,
      _loadTrips,
    ),
    AsyncData(:final value) => StepBody(
      actions: [
        OutlinedButton(
          key: const ValueKey('unload-refresh'),
          onPressed: _loadTrips,
          child: Text(l10n.unloadRefresh),
        ),
      ],
      child: ListView(
        children: [
          ScanPrompt(
            text: l10n.unloadPickTrip,
            detail: l10n.unloadPickTripHelp,
          ),
          for (final t in value)
            Card(
              key: ValueKey('unload-trip-${t.tripId}'),
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: t.arrived ? PdaColors.primary : PdaColors.line,
                  width: t.arrived ? 2 : 1,
                ),
              ),
              child: ListTile(
                enabled: t.arrived,
                onTap: t.arrived ? () => _open(t) : null,
                title: Text(
                  t.vehicleLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                subtitle: Text(
                  [
                    ?t.driverName,
                    l10n.unloadTrfCount(t.trfIds.length),
                    switch (t.stopState) {
                      'ARRIVED' => l10n.unloadArrivedAt(_time(t.arrivedAt)),
                      'PLANNED' => l10n.unloadEta(
                        _time(t.estimatedArrivalAt ?? t.plannedArrivalAt),
                      ),
                      _ => l10n.unloadDone,
                    },
                  ].join(' · '),
                ),
                trailing: t.arrived
                    ? const Icon(Icons.chevron_right, color: PdaColors.primary)
                    : null,
              ),
            ),
        ],
      ),
    ),
    AsyncError() => _notice(l10n.unloadLoadFailed, _loadTrips),
    _ => const Center(child: CircularProgressIndicator()),
  };

  Widget _work(
    AppLocalizations l10n,
    UnloadTrip trip,
    List<InboundPromiseView> ps,
  ) {
    final owner = _boxOwner(ps);
    final total = owner.length;
    final outcome = _outcome;
    if (outcome is InboundAccepted) {
      return StepBody(
        actions: [
          for (final p in ps)
            FilledButton(
              key: ValueKey('unload-receive-${p.trfId}'),
              onPressed: () => context.pushReplacement('/inbound/${p.trfId}'),
              child: Text(l10n.unloadGoReceive(p.trfId)),
            ),
        ],
        child: ListView(
          children: [
            DoneMark(
              key: const ValueKey('unload-done'),
              title: l10n.unloadRecorded,
              message: l10n.unloadRecordedHelp(
                _scanned.length,
                _damaged.length,
              ),
            ),
          ],
        ),
      );
    }
    final last = _scanned.isEmpty ? null : _scanned.last;
    return StepBody(
      actions: [
        if (_scanError case final e?)
          Text(
            e,
            key: const ValueKey('unload-scan-error'),
            style: const TextStyle(
              color: PdaColors.danger,
              fontWeight: FontWeight.w700,
            ),
          ),
        if (outcome is InboundRejected)
          Text(
            switch (outcome.code) {
              'INVALID_STATE' => l10n.unloadNotArrived,
              'HANDOVER_RECORDED' => l10n.unloadAlreadyRecorded,
              _ => l10n.unloadRejected,
            },
            key: const ValueKey('unload-rejected'),
            style: const TextStyle(
              color: PdaColors.danger,
              fontWeight: FontWeight.w700,
            ),
          ),
        if (outcome is InboundUnknown)
          Text(
            l10n.unloadUnknown,
            key: const ValueKey('unload-unknown'),
            style: const TextStyle(
              color: PdaColors.danger,
              fontWeight: FontWeight.w700,
            ),
          ),
        if (_scanned.length < total)
          ScanInput(
            id: 'unload-box-scan',
            label: l10n.unloadScanBox,
            cameraTitle: l10n.unloadScanBox,
            continuous: false,
            testValues: [
              for (final b
                  in owner.keys.where((b) => !_scanned.contains(b)).take(3))
                TestScan(b, b),
              TestScan(l10n.tsWrong, 'BOX-99999999'),
            ],
            testActions: [
              TestAction('all', l10n.unloadTestAll, () {
                setState(() {
                  for (final b in owner.keys) {
                    if (!_scanned.contains(b)) _scanned.add(b);
                  }
                });
              }),
            ],
            onScan: (code) => _scan(ps, code),
          ),
        FilledButton(
          key: const ValueKey('unload-handover'),
          onPressed: _scanned.isEmpty || _busy ? null : () => _handover(ps),
          child: Text(
            outcome is InboundUnknown
                ? l10n.unloadResend
                : l10n.unloadHandover(_scanned.length, _damaged.length),
          ),
        ),
      ],
      child: ListView(
        children: [
          StepHeader(
            names: [
              l10n.unloadStepTrip,
              l10n.unloadStepBoxes,
              l10n.unloadStepHandover,
            ],
            current: 1,
          ),
          MetaPair(label: l10n.unloadVehicle, value: trip.vehicleLabel),
          MetaPair(label: l10n.unloadArrived, value: _time(trip.arrivedAt)),
          const SizedBox(height: 8),
          ProgressLine(
            textKey: const ValueKey('unload-progress'),
            text: l10n.unloadProgress(_scanned.length, total),
            done: _scanned.length,
            total: total,
          ),
          for (final p in ps)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l10n.unloadTrfLine(
                  p.trfId,
                  _scanned.where((b) => owner[b] == p.trfId).length,
                  p.boxList.length,
                ),
                key: ValueKey('unload-trf-${p.trfId}'),
              ),
            ),
          if (last != null) ...[
            const SizedBox(height: 12),
            NoticeBox(text: l10n.unloadLastBox(last)),
            Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                key: const ValueKey('unload-damaged'),
                selected: _damaged.contains(last),
                label: Text(l10n.unloadDamaged),
                onSelected: (v) => setState(() {
                  if (v) {
                    _damaged.add(last);
                  } else {
                    _damaged.remove(last);
                  }
                }),
              ),
            ),
          ],
          if (_damaged.isNotEmpty)
            Text(
              l10n.unloadDamagedCount(_damaged.length),
              style: const TextStyle(color: PdaColors.danger),
            ),
        ],
      ),
    );
  }
}
