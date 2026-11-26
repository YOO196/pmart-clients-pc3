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
import '../data/cdc_flow_repository.dart';
import '../domain/cdc_flow.dart';
import 'cdc_widgets.dart';

/// DC 분배·검품·상차·지게차 적치 — MFC 업무 화면과 같은 흐름(단계 알약·진행 막대·큰 지시·스캔 칸·완료 표시).
/// 사용자 2026-11-26 "업무화면 다 만들어", "mfc 쪽 업무화면 참고해봐".
/// 분배·검품·상차는 계약이 TRF·LPN 단위(cdc-outbound results)라 피킹 끝난 TRF 를 고른 뒤 스캔으로 진행한다.
/// 결과 등록은 202 접수 — 보낸 뒤 서버 값을 다시 읽어 그것만 보인다.
final cdcFlowRepositoryProvider = Provider<CdcFlowRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockCdcFlowRepository(),
    PmartEnv.local => ApiCdcFlowRepository(ref.watch(dioProvider)),
  },
);

String _contents(CdcLpn l) =>
    l.contents.map((c) => '${c.sku} ${c.qty}').join(' · ');

/// 단계 화면 몸통 — 위 목록 + 아래 고정 칸(MFC 피킹과 같은 배치)
Widget _stepBody(List<Widget> body, List<Widget> actions) => Column(
  children: [
    Expanded(
      child: ListView(padding: const EdgeInsets.all(16), children: body),
    ),
    ActionBar(children: actions),
  ],
);

/// 피킹 끝난 TRF 고르기(분배·검품·상차 첫 단계)
class _TrfPick extends ConsumerStatefulWidget {
  const _TrfPick({required this.steps, required this.onPick});

  final List<String> steps;
  final ValueChanged<CdcTrf> onPick;

  @override
  ConsumerState<_TrfPick> createState() => _TrfPickState();
}

class _TrfPickState extends ConsumerState<_TrfPick> {
  AsyncValue<List<CdcTrf>> _trfs = const AsyncLoading();

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() => _trfs = const AsyncLoading());
    final v = await AsyncValue.guard(
      () =>
          ref.read(cdcFlowRepositoryProvider).pickedTransfers(cdcCenterOf(ref)),
    );
    if (mounted) setState(() => _trfs = v);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (_trfs) {
      AsyncData(:final value) when value.isEmpty => CdcCenterNotice(
        key: const ValueKey('cdc-empty'),
        icon: Icons.hourglass_empty,
        text: l10n.cdcTrfEmpty,
        action: FilledButton(
          key: const ValueKey('cdc-reload'),
          onPressed: _load,
          child: Text(l10n.nextRetry),
        ),
      ),
      AsyncData(:final value) => _stepBody([
        StepHeader(names: widget.steps, current: 0),
        ScanPrompt(text: l10n.cdcTrfTitle, detail: l10n.cdcTrfChoose),
        for (final t in value)
          _TrfCard(
            key: ValueKey('cdc-trf-${t.trfId}'),
            trf: t,
            onTap: () => widget.onPick(t),
          ),
      ], const []),
      AsyncError() => CdcCenterNotice(
        icon: Icons.cloud_off,
        text: l10n.cdcLoadFailed,
        action: FilledButton(
          key: const ValueKey('cdc-reload'),
          onPressed: _load,
          child: Text(l10n.retry),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _TrfCard extends StatelessWidget {
  const _TrfCard({super.key, required this.trf, required this.onTap});

  final CdcTrf trf;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: PdaColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trf.label,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${trf.mfcId} · ${l10n.cdcPickDue(formatSeoulDateTime(trf.dueAt))}',
                        style: const TextStyle(color: PdaColors.muted),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${trf.pickedQty}',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      l10n.cdcTrfPickedLabel,
                      style: const TextStyle(color: PdaColors.muted),
                    ),
                  ],
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, color: PdaColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 화면 틀 — 위 제목(업무·TRF), 뒤로 가면 한 단계 앞으로
class _Frame extends StatelessWidget {
  const _Frame({
    required this.title,
    required this.subtitle,
    required this.canPop,
    required this.onBack,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final bool canPop;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (subtitle != null)
                Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: PdaColors.onBarMuted,
                  ),
                ),
              Text(subtitle ?? title, key: const ValueKey('cdc-flow-title')),
            ],
          ),
        ),
        body: SafeArea(child: child),
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

class _CdcSortScreenState extends ConsumerState<CdcSortScreen> with CdcCommand {
  CdcTrf? _trf;
  AsyncValue<(List<CdcSortItem>, List<CdcLpn>)> _data = const AsyncLoading();
  String? _box;
  String? _zone;

  /// 이 BOX 에 담은 수(줄 키 → 수)
  final _inBox = <String, int>{};
  String? _last;
  String? _scanError;
  String? _notice;

  CdcFlowRepository get _repo => ref.read(cdcFlowRepositoryProvider);

  Future<void> _load() async {
    final trf = _trf!;
    setState(() => _data = const AsyncLoading());
    final v = await AsyncValue.guard(
      () async => (
        await _repo.sortItems(cdcCenterOf(ref), trf),
        await _repo.lpns(cdcCenterOf(ref), trf.trfId),
      ),
    );
    if (mounted) setState(() => _data = v);
  }

  void _resetBox() {
    _box = null;
    _zone = null;
    _inBox.clear();
    _last = null;
    _scanError = null;
  }

  void _back() => setState(() {
    if (_box != null) {
      _resetBox();
    } else {
      _trf = null;
      _notice = null;
      failText = null;
      resend = null;
    }
  });

  ScanFeedback _scanBox(List<CdcLpn> lpns, String code) {
    final l10n = AppLocalizations.of(context);
    final c = code.trim();
    if (lpns.any((l) => l.lpn == c)) {
      setState(() => _scanError = l10n.cdcErrLpnSealed);
      return ScanFeedback.error(l10n.cdcErrLpnSealed);
    }
    setState(() {
      _box = c;
      _scanError = null;
      _notice = null;
    });
    return const ScanFeedback.ok();
  }

  ScanFeedback _scanItem(List<CdcSortItem> items, String code) {
    final l10n = AppLocalizations.of(context);
    final hit = items
        .where((i) => i.remaining > 0 && cdcCodeIsItem(code, i.sku, i.lot))
        .firstOrNull;
    if (hit == null) {
      setState(() => _scanError = l10n.cdcSortNotThisTrf);
      return ScanFeedback.error(l10n.cdcSortNotThisTrf);
    }
    final n = (_inBox[hit.key] ?? 0) + 1;
    if (n > hit.remaining) {
      setState(() => _scanError = l10n.cdcErrSortExceeds);
      return ScanFeedback.error(l10n.cdcErrSortExceeds);
    }
    setState(() {
      _inBox[hit.key] = n;
      _last = hit.key;
      _scanError = null;
    });
    return const ScanFeedback.ok();
  }

  Future<void> _seal(List<CdcSortItem> items) async {
    final l10n = AppLocalizations.of(context);
    final box = _box!;
    final contents = [
      for (final i in items)
        if ((_inBox[i.key] ?? 0) > 0)
          CdcLpnContent(sku: i.sku, lot: i.lot, qty: _inBox[i.key]!),
    ];
    final ok = await send(
      (key) => _repo.reportSort(
        trf: _trf!,
        workerId: cdcWorkerOf(ref),
        box: CdcBoxDraft(lpn: box, temperatureZone: _zone, contents: contents),
        key: key,
      ),
      reload: _load,
    );
    if (ok && mounted) {
      setState(() {
        _resetBox();
        _notice = l10n.cdcSortDone(box);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final steps = [l10n.cdcStepTrf, l10n.cdcStepBox, l10n.cdcStepItem];
    final trf = _trf;
    return _Frame(
      title: l10n.cdcAreaSort,
      subtitle: trf?.label,
      canPop: trf == null,
      onBack: _back,
      child: trf == null
          ? _TrfPick(
              steps: steps,
              onPick: (t) {
                setState(() => _trf = t);
                _load();
              },
            )
          : switch (_data) {
              AsyncData(:final value) => _work(l10n, steps, value.$1, value.$2),
              AsyncError() => CdcCenterNotice(
                icon: Icons.cloud_off,
                text: l10n.cdcLoadFailed,
                action: FilledButton(
                  key: const ValueKey('cdc-reload'),
                  onPressed: _load,
                  child: Text(l10n.retry),
                ),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
    );
  }

  Widget _work(
    AppLocalizations l10n,
    List<String> steps,
    List<CdcSortItem> items,
    List<CdcLpn> lpns,
  ) {
    final picked = items.fold<int>(0, (a, i) => a + i.pickedQty);
    final sorted = items.fold<int>(0, (a, i) => a + i.sortedQty);
    final body = <Widget>[];
    final actions = <Widget>[];
    final left = items.where((i) => i.remaining > 0).toList();
    if (left.isNotEmpty) {
      body.add(StepHeader(names: steps, current: _box == null ? 1 : 2));
    }
    body.add(
      ProgressLine(
        textKey: const ValueKey('cdc-sort-progress'),
        text: l10n.cdcSortProgress(sorted, picked),
        done: sorted,
        total: picked,
      ),
    );
    if (_notice case final n?) {
      body.add(NoticeBox(text: n, textKey: const ValueKey('cdc-notice')));
    }
    if (left.isEmpty) {
      body.add(
        DoneMark(
          key: const ValueKey('cdc-sort-done'),
          title: l10n.cdcSortAllDone,
          message: l10n.cdcSortBoxes(lpns.length),
        ),
      );
      actions.add(
        FilledButton(
          key: const ValueKey('cdc-other-trf'),
          onPressed: () => setState(() {
            _trf = null;
            _notice = null;
          }),
          child: Text(l10n.cdcOtherTrf),
        ),
      );
      return _stepBody(body, actions);
    }
    if (_box == null) {
      body.add(
        ScanPrompt(
          text: l10n.cdcSortScanBoxTitle,
          detail: l10n.cdcSortBoxNth(lpns.length + 1),
        ),
      );
      for (final i in left) {
        body.add(
          CdcItemCard(
            key: ValueKey('cdc-sort-${i.sku}'),
            name: i.productName ?? i.sku,
            sku: i.sku,
            lot: i.lot,
            qty: i.remaining,
            qtyLabel: l10n.cdcLeftUnit,
          ),
        );
      }
      actions.add(
        ScanInput(
          id: 'cdc-box-scan',
          label: l10n.cdcScanBox,
          cameraTitle: l10n.cdcScanBox,
          continuous: false,
          autofocus: false,
          testValues: [
            TestScan(l10n.cdcTsNewBox, 'BOX-2611260${lpns.length + 11}'),
            for (final l in lpns) TestScan(l10n.cdcTsUsedBox, l.lpn),
          ],
          onScan: (code) => _scanBox(lpns, code),
        ),
      );
    } else {
      final inBox = _inBox.values.fold<int>(0, (a, n) => a + n);
      body.add(
        ScanPrompt(
          text: l10n.cdcSortScanItemTitle,
          detail: l10n.cdcSortBoxIs(_box!),
        ),
      );
      body.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Wrap(
            spacing: 8,
            children: [
              for (final z in cdcTemperatureZones)
                ChoiceChip(
                  key: ValueKey('cdc-zone-$z'),
                  label: Text(_zoneText(l10n, z)),
                  selected: _zone == z,
                  onSelected: (s) => setState(() => _zone = s ? z : null),
                ),
            ],
          ),
        ),
      );
      for (final i in left) {
        final n = _inBox[i.key] ?? 0;
        body.add(
          CdcItemCard(
            key: ValueKey('cdc-sort-${i.sku}'),
            name: i.productName ?? i.sku,
            sku: i.sku,
            lot: i.lot,
            qty: i.remaining - n,
            qtyLabel: l10n.cdcLeftUnit,
            footer: n > 0 ? l10n.cdcSortInBox(n) : null,
            emphasize: _last == i.key,
          ),
        );
      }
      if (_last case final k?) {
        final i = left.where((i) => i.key == k).firstOrNull;
        if (i != null) {
          body.add(
            CountQtyField(
              id: 'cdc-sort-qty',
              label: l10n.cdcSortQtyLabel,
              help: l10n.cdcSortQtyHelp(i.productName ?? i.sku, i.remaining),
              addLabel: l10n.pickQtyAdd,
              value: _inBox[k] ?? 0,
              max: i.remaining,
              onAdd: () => setState(() => _inBox[k] = (_inBox[k] ?? 0) + 1),
              onSet: (v) => setState(() {
                if (v >= 0 && v <= i.remaining) _inBox[k] = v;
              }),
            ),
          );
        }
      }
      actions.addAll([
        ScanInput(
          id: 'cdc-sort-item-scan',
          label: l10n.cdcScanItem,
          cameraTitle: l10n.cdcCameraItem,
          continuous: false,
          testValues: [
            for (final i in left) TestScan(i.productName ?? i.sku, i.sku),
            TestScan(l10n.tsWrong, 'SKU-0000'),
          ],
          onScan: (code) => _scanItem(items, code),
        ),
        if (resendButton(context) case final b?)
          b
        else
          FilledButton(
            key: const ValueKey('cdc-sort-go'),
            onPressed: inBox == 0 || busy ? null : () => _seal(items),
            child: Text(l10n.cdcSortSeal(inBox)),
          ),
      ]);
    }
    if (_scanError case final e?) {
      body.add(CdcErrorLine(e, key: const ValueKey('cdc-scan-error')));
    }
    if (failText case final f?) {
      body.add(CdcErrorLine(f, key: const ValueKey('cdc-message')));
    }
    return _stepBody(body, actions);
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
    with CdcCommand {
  CdcTrf? _trf;
  AsyncValue<List<CdcLpn>> _lpns = const AsyncLoading();
  CdcLpn? _box;
  String? _scanError;
  String? _notice;

  CdcFlowRepository get _repo => ref.read(cdcFlowRepositoryProvider);

  Future<void> _load() async {
    setState(() => _lpns = const AsyncLoading());
    final v = await AsyncValue.guard(
      () => _repo.lpns(cdcCenterOf(ref), _trf!.trfId),
    );
    if (mounted) setState(() => _lpns = v);
  }

  void _back() => setState(() {
    if (_box != null) {
      _box = null;
      _scanError = null;
    } else {
      _trf = null;
      _notice = null;
      failText = null;
      resend = null;
    }
  });

  ScanFeedback _scanBox(List<CdcLpn> lpns, String code) {
    final l10n = AppLocalizations.of(context);
    final hit = lpns
        .where((l) => l.lpn == code.trim() && !l.loaded)
        .firstOrNull;
    if (hit == null) {
      setState(() => _scanError = l10n.cdcNotThisTrfBox);
      return ScanFeedback.error(l10n.cdcNotThisTrfBox);
    }
    setState(() {
      _box = hit;
      _scanError = null;
      _notice = null;
    });
    return const ScanFeedback.ok();
  }

  Future<void> _judge(bool passed) async {
    final l10n = AppLocalizations.of(context);
    final box = _box!;
    String? reason;
    if (!passed) {
      reason = await showCdcReasonDialog(
        context,
        title: l10n.cdcInspectReason,
        keyPrefix: 'cdc-fail',
        options: [
          ('QTY_MISMATCH', Icons.exposure, l10n.cdcFailQty),
          ('SEAL_BROKEN', Icons.lock_open, l10n.cdcFailSeal),
          ('TEMPERATURE', Icons.thermostat, l10n.cdcFailTemp),
          ('DAMAGE', Icons.broken_image_outlined, l10n.cdcFailDamage),
          ('WRONG_TRF', Icons.swap_horiz, l10n.cdcFailWrongTrf),
          ('OTHER', Icons.more_horiz, l10n.cdcShortOther),
        ],
      );
      if (reason == null || !mounted) return;
    }
    final ok = await send(
      (key) => _repo.reportInspection(
        trfId: _trf!.trfId,
        inspectorId: cdcWorkerOf(ref),
        items: [
          CdcInspection(lpn: box.lpn, passed: passed, failReason: reason),
        ],
        key: key,
      ),
      reload: _load,
    );
    if (ok && mounted) {
      setState(() {
        _box = null;
        _notice = passed
            ? l10n.cdcInspectSentPass(box.lpn)
            : l10n.cdcInspectSentFail(box.lpn);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final steps = [l10n.cdcStepTrf, l10n.cdcStepBox, l10n.cdcStepJudge];
    final trf = _trf;
    return _Frame(
      title: l10n.cdcAreaInspect,
      subtitle: trf?.label,
      canPop: trf == null,
      onBack: _back,
      child: trf == null
          ? _TrfPick(
              steps: steps,
              onPick: (t) {
                setState(() => _trf = t);
                _load();
              },
            )
          : switch (_lpns) {
              AsyncData(:final value) => _work(l10n, steps, value),
              AsyncError() => CdcCenterNotice(
                icon: Icons.cloud_off,
                text: l10n.cdcLoadFailed,
                action: FilledButton(
                  key: const ValueKey('cdc-reload'),
                  onPressed: _load,
                  child: Text(l10n.retry),
                ),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
    );
  }

  Widget _work(AppLocalizations l10n, List<String> steps, List<CdcLpn> all) {
    final lpns = all.where((l) => !l.loaded).toList();
    if (lpns.isEmpty) {
      return CdcCenterNotice(
        key: const ValueKey('cdc-empty'),
        icon: Icons.inventory_2_outlined,
        text: l10n.cdcInspectEmpty,
      );
    }
    final done = lpns.where((l) => l.inspection != null).length;
    final body = <Widget>[];
    final actions = <Widget>[];
    body.add(StepHeader(names: steps, current: _box == null ? 1 : 2));
    body.add(
      ProgressLine(
        textKey: const ValueKey('cdc-inspect-progress'),
        text: l10n.cdcInspectProgress(done, lpns.length),
        done: done,
        total: lpns.length,
      ),
    );
    if (_notice case final n?) {
      body.add(NoticeBox(text: n, textKey: const ValueKey('cdc-notice')));
    }
    final box = _box;
    if (box == null) {
      body.add(
        ScanPrompt(
          text: done == lpns.length
              ? l10n.cdcInspectAllDone
              : l10n.cdcInspectScanTitle,
          detail: l10n.cdcInspectScanHelp,
        ),
      );
      for (final l in lpns) {
        body.add(_BoxLine(lpn: l));
      }
      actions.add(
        ScanInput(
          id: 'cdc-insp-scan',
          label: l10n.cdcScanBox,
          cameraTitle: l10n.cdcScanBox,
          continuous: false,
          autofocus: false,
          testValues: [
            for (final l in lpns) TestScan(l.lpn, l.lpn),
            TestScan(l10n.tsWrong, 'BOX-0000'),
          ],
          onScan: (code) => _scanBox(lpns, code),
        ),
      );
    } else {
      body.add(
        ScanPrompt(
          text: l10n.cdcInspectCheckTitle,
          detail: l10n.cdcInspectCheckHelp(box.lpn),
        ),
      );
      for (final c in box.contents) {
        body.add(
          CdcItemCard(
            name: c.sku,
            sku: c.sku,
            lot: c.lot,
            qty: c.qty,
            qtyLabel: l10n.cdcQtyUnit,
          ),
        );
      }
      if (box.inspection != null) {
        body.add(
          NoticeBox(
            text: l10n.cdcInspectAgain(
              box.passed ? l10n.cdcInspectPassed : l10n.cdcInspectFailed,
            ),
            warning: true,
          ),
        );
      }
      if (resendButton(context) case final b?) {
        actions.add(b);
      } else {
        actions.addAll([
          FilledButton.icon(
            key: const ValueKey('cdc-pass'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(60),
            ),
            onPressed: busy ? null : () => _judge(true),
            icon: const Icon(Icons.check_circle_outline),
            label: Text(l10n.cdcInspectPass),
          ),
          OutlinedButton.icon(
            key: const ValueKey('cdc-fail'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              foregroundColor: PdaColors.danger,
            ),
            onPressed: busy ? null : () => _judge(false),
            icon: const Icon(Icons.report_gmailerrorred),
            label: Text(l10n.cdcInspectFail),
          ),
        ]);
      }
    }
    if (_scanError case final e?) {
      body.add(CdcErrorLine(e, key: const ValueKey('cdc-scan-error')));
    }
    if (failText case final f?) {
      body.add(CdcErrorLine(f, key: const ValueKey('cdc-message')));
    }
    return _stepBody(body, actions);
  }
}

/// BOX 한 줄(번호·내용·검품 상태)
class _BoxLine extends StatelessWidget {
  const _BoxLine({required this.lpn, this.checked = false});

  final CdcLpn lpn;
  final bool checked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (text, color) = lpn.loaded
        ? (l10n.cdcBoxLoaded, PdaColors.primary)
        : switch (lpn.inspection) {
            'PASSED' => (l10n.cdcInspectPassed, PdaColors.primary),
            'FAILED' => (l10n.cdcInspectFailed, PdaColors.danger),
            _ => (l10n.cdcInspectNone, PdaColors.muted),
          };
    return Container(
      key: ValueKey('cdc-lpn-${lpn.lpn}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: checked ? PdaColors.primary : PdaColors.line,
          width: checked ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          if (checked)
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: Icon(Icons.check_circle, color: PdaColors.primary),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lpn.lpn,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                Text(
                  _contents(lpn),
                  style: const TextStyle(color: PdaColors.muted),
                ),
              ],
            ),
          ),
          Text(
            text,
            key: ValueKey('cdc-insp-${lpn.lpn}'),
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 상차

class CdcLoadScreen extends ConsumerStatefulWidget {
  const CdcLoadScreen({super.key});

  @override
  ConsumerState<CdcLoadScreen> createState() => _CdcLoadScreenState();
}

class _CdcLoadScreenState extends ConsumerState<CdcLoadScreen> with CdcCommand {
  CdcTrf? _trf;
  AsyncValue<List<CdcLpn>> _lpns = const AsyncLoading();
  String? _trip;
  String? _vehicle;
  final _scanned = <String>[];
  String? _scanError;
  String? _notice;

  CdcFlowRepository get _repo => ref.read(cdcFlowRepositoryProvider);

  Future<void> _load() async {
    setState(() => _lpns = const AsyncLoading());
    final v = await AsyncValue.guard(
      () => _repo.lpns(cdcCenterOf(ref), _trf!.trfId),
    );
    if (mounted) setState(() => _lpns = v);
  }

  void _back() => setState(() {
    _scanError = null;
    if (_scanned.isNotEmpty) {
      _scanned.clear();
    } else if (_vehicle != null) {
      _vehicle = null;
    } else if (_trip != null) {
      _trip = null;
    } else {
      _trf = null;
      _notice = null;
      failText = null;
      resend = null;
    }
  });

  ScanFeedback _scanBox(List<CdcLpn> lpns, String code) {
    final l10n = AppLocalizations.of(context);
    final c = code.trim();
    final hit = lpns.where((l) => l.lpn == c).firstOrNull;
    final error = switch (hit) {
      null => l10n.cdcNotThisTrfBox,
      final l when l.loaded => l10n.cdcLoadAlready,
      final l when !l.passed => l10n.cdcErrNotPassed,
      _ when _scanned.contains(c) => l10n.cdcLoadScannedAlready,
      _ => null,
    };
    if (error != null) {
      setState(() => _scanError = error);
      return ScanFeedback.error(error);
    }
    setState(() {
      _scanned.add(c);
      _scanError = null;
      _notice = null;
    });
    return const ScanFeedback.ok();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final lpns = [..._scanned];
    final ok = await send(
      (key) => _repo.reportLoading(
        trfId: _trf!.trfId,
        tripId: _trip!,
        vehicleId: _vehicle!,
        dockCode: null,
        workerId: cdcWorkerOf(ref),
        lpns: lpns,
        key: key,
      ),
      reload: _load,
    );
    if (ok && mounted) {
      setState(() {
        _scanned.clear();
        _notice = l10n.cdcLoadDone(lpns.length);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final steps = [
      l10n.cdcStepTrf,
      l10n.cdcStepTrip,
      l10n.cdcStepVehicle,
      l10n.cdcStepBox,
    ];
    final trf = _trf;
    return _Frame(
      title: l10n.cdcAreaLoad,
      subtitle: trf?.label,
      canPop: trf == null,
      onBack: _back,
      child: trf == null
          ? _TrfPick(
              steps: steps,
              onPick: (t) {
                setState(() => _trf = t);
                _load();
              },
            )
          : switch (_lpns) {
              AsyncData(:final value) => _work(l10n, steps, value),
              AsyncError() => CdcCenterNotice(
                icon: Icons.cloud_off,
                text: l10n.cdcLoadFailed,
                action: FilledButton(
                  key: const ValueKey('cdc-reload'),
                  onPressed: _load,
                  child: Text(l10n.retry),
                ),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
    );
  }

  Widget _work(AppLocalizations l10n, List<String> steps, List<CdcLpn> all) {
    final passed = all.where((l) => l.passed).toList();
    if (passed.isEmpty) {
      return CdcCenterNotice(
        key: const ValueKey('cdc-empty'),
        icon: Icons.inventory_2_outlined,
        text: l10n.cdcLoadEmpty,
      );
    }
    final loaded = passed.where((l) => l.loaded).length;
    final body = <Widget>[];
    final actions = <Widget>[];
    final step = _trip == null
        ? 1
        : _vehicle == null
        ? 2
        : 3;
    if (loaded < passed.length) {
      body.add(StepHeader(names: steps, current: step));
    }
    body.add(
      ProgressLine(
        textKey: const ValueKey('cdc-load-progress'),
        text: l10n.cdcLoadProgress(loaded, passed.length),
        done: loaded,
        total: passed.length,
      ),
    );
    if (_notice case final n?) {
      body.add(NoticeBox(text: n, textKey: const ValueKey('cdc-notice')));
    }
    if (loaded == passed.length) {
      body.add(
        DoneMark(
          key: const ValueKey('cdc-load-done'),
          title: l10n.cdcLoadAllDone,
          message: l10n.cdcLoadNotDeparture,
        ),
      );
      for (final l in passed) {
        body.add(_BoxLine(lpn: l));
      }
      actions.add(
        FilledButton(
          key: const ValueKey('cdc-other-trf'),
          onPressed: () => setState(() {
            _trf = null;
            _trip = null;
            _vehicle = null;
            _notice = null;
          }),
          child: Text(l10n.cdcOtherTrf),
        ),
      );
      return _stepBody(body, actions);
    }
    if (_trip == null) {
      body.add(
        ScanPrompt(text: l10n.cdcLoadTripTitle, detail: l10n.cdcLoadTripHelp),
      );
      actions.add(
        ScanInput(
          id: 'cdc-trip-scan',
          label: l10n.cdcLoadTrip,
          cameraTitle: l10n.cdcLoadTrip,
          continuous: false,
          autofocus: false,
          testValues: const [TestScan('TRIP-2611260007', 'TRIP-2611260007')],
          onScan: (code) {
            setState(() => _trip = code.trim());
            return const ScanFeedback.ok();
          },
        ),
      );
    } else if (_vehicle == null) {
      body.add(
        ScanPrompt(
          text: l10n.cdcLoadVehicleTitle,
          detail: l10n.cdcLoadTripIs(_trip!),
        ),
      );
      actions.add(
        ScanInput(
          id: 'cdc-vehicle-scan',
          label: l10n.cdcLoadVehicle,
          cameraTitle: l10n.cdcLoadVehicle,
          continuous: false,
          autofocus: false,
          testValues: const [TestScan('경북12가3456', '경북12가3456')],
          onScan: (code) {
            setState(() => _vehicle = code.trim());
            return const ScanFeedback.ok();
          },
        ),
      );
    } else {
      body.add(
        ScanPrompt(
          text: l10n.cdcLoadScanTitle,
          detail: l10n.cdcLoadVehicleIs(_vehicle!, _trip!),
        ),
      );
      for (final l in passed) {
        body.add(_BoxLine(lpn: l, checked: _scanned.contains(l.lpn)));
      }
      actions.addAll([
        ScanInput(
          id: 'cdc-load-scan',
          label: l10n.cdcScanBox,
          cameraTitle: l10n.cdcScanBox,
          continuous: false,
          testValues: [
            for (final l in passed.where((l) => !l.loaded))
              TestScan(l.lpn, l.lpn),
            TestScan(l10n.tsWrong, 'BOX-0000'),
          ],
          onScan: (code) => _scanBox(all, code),
        ),
        if (resendButton(context) case final b?)
          b
        else
          FilledButton(
            key: const ValueKey('cdc-load-go'),
            onPressed: _scanned.isEmpty || busy ? null : _submit,
            child: Text(l10n.cdcLoadSubmit(_scanned.length)),
          ),
      ]);
    }
    if (_scanError case final e?) {
      body.add(CdcErrorLine(e, key: const ValueKey('cdc-scan-error')));
    }
    if (failText case final f?) {
      body.add(CdcErrorLine(f, key: const ValueKey('cdc-message')));
    }
    return _stepBody(body, actions);
  }
}

// ---------------------------------------------------------------- 지게차 적치

class CdcPutawayScreen extends ConsumerStatefulWidget {
  const CdcPutawayScreen({super.key});

  @override
  ConsumerState<CdcPutawayScreen> createState() => _CdcPutawayScreenState();
}

class _CdcPutawayScreenState extends ConsumerState<CdcPutawayScreen>
    with CdcCommand {
  CdcPutaway? _task;
  bool _opening = false;

  /// 확인한 위치(지시와 다르면 이유와 함께)
  String? _loc;
  String? _reason;
  int _qty = 0;
  String? _scanError;

  CdcFlowRepository get _repo => ref.read(cdcFlowRepositoryProvider);

  CdcPutawayRow? get _row => _task?.rows.where((r) => r.u > 0).firstOrNull;

  void _back() => setState(() {
    _scanError = null;
    if (_loc != null) {
      _loc = null;
      _reason = null;
    } else {
      _task = null;
      failText = null;
      resend = null;
    }
  });

  ScanFeedback _scanTask(String code) {
    final id = code.trim();
    setState(() {
      _opening = true;
      _scanError = null;
    });
    _repo
        .putaway(id)
        .then(
          (t) {
            if (!mounted) return;
            setState(() {
              _opening = false;
              _setTask(t);
            });
          },
          onError: (Object e) {
            if (!mounted) return;
            final l10n = AppLocalizations.of(context);
            setState(() {
              _opening = false;
              _scanError = e is ProblemFailure && e.problem.status == 404
                  ? l10n.cdcErrNotFound
                  : l10n.cdcLoadFailed;
            });
          },
        );
    return const ScanFeedback.ok();
  }

  void _setTask(CdcPutaway t) {
    _task = t;
    _loc = null;
    _reason = null;
    _qty = _row?.u ?? 0;
  }

  Future<ScanFeedback> _scanLoc(CdcPutawayRow row, String code) async {
    final l10n = AppLocalizations.of(context);
    final c = code.trim();
    if (c.toUpperCase() == row.location.toUpperCase()) {
      setState(() {
        _loc = row.location;
        _reason = null;
        _scanError = null;
      });
      return const ScanFeedback.ok();
    }
    // 지시와 다른 칸 — 이유가 있어야 여기에 둔다
    final reason = await showCdcReasonDialog(
      context,
      title: l10n.cdcPutawayOtherLoc(c),
      keyPrefix: 'cdc-pa-reason',
      options: [
        ('LOCATION_FULL', Icons.inventory, l10n.cdcPaFull),
        ('LOCATION_BLOCKED', Icons.block, l10n.cdcShortBlocked),
        ('DAMAGED', Icons.broken_image_outlined, l10n.cdcShortDamaged),
        ('WRONG_LOT', Icons.swap_horiz, l10n.cdcPaWrongLot),
        ('OTHER', Icons.more_horiz, l10n.cdcShortOther),
      ],
    );
    if (reason == null || !mounted) {
      return ScanFeedback.error(l10n.cdcPickWrongLocation);
    }
    setState(() {
      _loc = c;
      _reason = reason;
      _scanError = null;
    });
    return const ScanFeedback.ok();
  }

  Future<void> _done(CdcPutaway t, CdcPutawayRow row) async {
    await send(
      (key) => _repo.executePutaway(
        task: t,
        workerId: cdcWorkerOf(ref),
        lines: [
          CdcPutawayLine(
            row: row,
            toLocation: _loc!,
            completedQty: _qty,
            exceptionReason: _reason,
          ),
        ],
        key: key,
      ),
      reload: () async {
        final next = await _repo.putaway(t.taskId);
        if (mounted) setState(() => _setTask(next));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final steps = [l10n.cdcStepOrder, l10n.cdcStepLocation, l10n.cdcStepQty];
    final t = _task;
    final row = _row;
    final body = <Widget>[];
    final actions = <Widget>[];
    if (t == null) {
      body.addAll([
        StepHeader(names: steps, current: 0),
        ScanPrompt(text: l10n.cdcPutawayScanTitle, detail: l10n.cdcPutawayHint),
        if (_opening) const Center(child: CircularProgressIndicator()),
      ]);
      actions.add(
        ScanInput(
          id: 'cdc-pa-scan',
          label: l10n.cdcPutawayIdLabel,
          cameraTitle: l10n.cdcPutawayIdLabel,
          continuous: false,
          testValues: [
            const TestScan('PA-mock-1', 'PA-mock-1'),
            const TestScan('PA-mock-2', 'PA-mock-2'),
            TestScan(l10n.tsWrong, 'PA-0000'),
          ],
          onScan: _scanTask,
        ),
      );
    } else {
      final total = t.rows.fold<int>(0, (a, r) => a + r.q);
      final done = t.rows.fold<int>(0, (a, r) => a + r.c + r.k);
      if (row != null && !t.finished) {
        body.add(StepHeader(names: steps, current: _loc == null ? 1 : 2));
      }
      body.add(
        ProgressLine(
          textKey: const ValueKey('cdc-pa-progress'),
          text: l10n.cdcProgress(done, total),
          done: done,
          total: total,
        ),
      );
      if (row == null || t.finished) {
        body.add(
          DoneMark(
            key: const ValueKey('cdc-pa-done'),
            title: l10n.cdcPutawayAllDone,
            message: l10n.cdcPutawayState(_putawayStateText(l10n, t.state)),
            messageKey: const ValueKey('cdc-putaway-state'),
          ),
        );
        actions.add(
          FilledButton(
            key: const ValueKey('cdc-pa-next'),
            onPressed: () => setState(() => _task = null),
            child: Text(l10n.cdcPutawayNext),
          ),
        );
      } else if (_loc == null) {
        body.add(
          LocationGuide(
            code: row.location,
            codeKey: const ValueKey('cdc-pa-location'),
            title: l10n.cdcPutawayGoTitle,
            detail: t.taskId,
          ),
        );
        body.add(const SizedBox(height: 12));
        body.add(
          CdcItemCard(
            name: row.sku,
            sku: row.sku,
            lot: row.lot,
            qty: row.u,
            qtyLabel: l10n.cdcLeftUnit,
          ),
        );
        actions.add(
          ScanInput(
            id: 'cdc-pa-loc-scan',
            label: l10n.locScanHint,
            cameraTitle: l10n.cdcCameraLocation,
            continuous: false,
            autofocus: false,
            testValues: [
              TestScan(l10n.tsLocation, row.location),
              TestScan(l10n.cdcTsOtherLoc, 'CDC01-R-6-09-01-1-1'),
            ],
            onScan: (code) {
              _scanLoc(row, code);
              return const ScanFeedback.ok();
            },
          ),
        );
      } else {
        body.add(
          ScanPrompt(
            text: l10n.cdcPutawayPlaceTitle(_qty),
            detail: _reason == null
                ? l10n.pickLocConfirmed(_loc!)
                : l10n.cdcPutawayOtherConfirmed(_loc!),
          ),
        );
        body.add(
          CdcItemCard(
            name: row.sku,
            sku: row.sku,
            lot: row.lot,
            qty: row.u,
            qtyLabel: l10n.cdcLeftUnit,
            emphasize: true,
          ),
        );
        body.add(
          CountQtyField(
            id: 'cdc-pa-qty',
            label: l10n.cdcPutawayQty,
            help: l10n.cdcPutawayQtyHelp(row.u),
            addLabel: l10n.pickQtyAdd,
            value: _qty,
            max: row.u,
            onAdd: () => setState(() => _qty += 1),
            onSet: (v) => setState(() {
              if (v >= 0 && v <= row.u) _qty = v;
            }),
          ),
        );
        actions.add(
          resendButton(context) ??
              FilledButton(
                key: const ValueKey('cdc-putaway-go'),
                onPressed: _qty == 0 || busy ? null : () => _done(t, row),
                child: Text(l10n.cdcPutawaySubmit),
              ),
        );
      }
    }
    if (_scanError case final e?) {
      body.add(CdcErrorLine(e, key: const ValueKey('cdc-putaway-error')));
    }
    if (failText case final f?) {
      body.add(CdcErrorLine(f, key: const ValueKey('cdc-message')));
    }
    return _Frame(
      title: l10n.cdcAreaPutaway,
      subtitle: t?.taskId,
      canPop: t == null,
      onBack: _back,
      child: _stepBody(body, actions),
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
