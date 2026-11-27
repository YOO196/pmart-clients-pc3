import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/field_widgets.dart';
import '../../../shared/pda_motion.dart';
import '../../../shared/pda_theme.dart';
import '../../../shared/providers.dart';
import '../../../shared/scanner/scan_input.dart';
import '../../../shared/scanner/scanner.dart';
import '../data/cdc_flow_repository.dart';
import '../domain/cdc_flow.dart';
import 'cdc_home.dart';
import 'cdc_location.dart';
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

/// 피킹 끝난 TRF 고르기(분배·검품·상차 첫 단계)
/// 분배·패킹 TRF 목록 표시(저장소 [CdcFlowRepository.sortTransfers] — 덜 담은 INSPECTED 도 넣는다)
const sortStates = ['PICKED', 'SORTED'];

class _TrfPick extends ConsumerStatefulWidget {
  const _TrfPick({
    required this.steps,
    required this.onPick,
    required this.states,
    required this.emptyText,
  });

  final List<String> steps;

  /// 이 화면이 다루는 TRF 상태(분배·패킹 PICKED·SORTED, 검품 SORTED·INSPECTED)
  final List<String> states;
  final String emptyText;
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
      () => widget.states == sortStates
          ? ref.read(cdcFlowRepositoryProvider).sortTransfers(cdcCenterOf(ref))
          : ref
                .read(cdcFlowRepositoryProvider)
                .transfers(cdcCenterOf(ref), widget.states),
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
        text: widget.emptyText,
        action: FilledButton(
          key: const ValueKey('cdc-reload'),
          onPressed: _load,
          child: Text(l10n.nextRetry),
        ),
      ),
      AsyncData(:final value) => cdcStepBody(
        step: 'trf',
        body: [
          StepHeader(names: widget.steps, current: 0),
          ScanPrompt(text: l10n.cdcTrfTitle),
          for (final (i, t) in value.indexed)
            EnterFade(
              key: ValueKey('fade-${t.trfId}'),
              index: i,
              child: _TrfCard(
                key: ValueKey('cdc-trf-${t.trfId}'),
                trf: t,
                onTap: () => widget.onPick(t),
              ),
            ),
        ],
        actions: const [],
      ),

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
      child: Pressable(
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide.none,
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
                            fontWeight: FontWeight.w700,
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
                          fontWeight: FontWeight.w700,
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
      ),
    );
  }
}

/// 화면 틀 — 위 제목(업무·TRF), 뒤로 가면 한 단계 앞으로
class _Frame extends StatelessWidget {
  const _Frame({
    required this.area,
    required this.title,
    required this.subtitle,
    required this.canPop,
    required this.onBack,
    required this.child,
    this.busy = false,
  });

  final CdcWorkArea area;
  final bool busy;
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
          title: Row(
            children: [
              CdcBarIcon(area: area),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (subtitle != null)
                      Text(
                        title,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: PdaColors.onBarMuted,
                        ),
                      ),
                    Text(
                      subtitle ?? title,
                      key: const ValueKey('cdc-flow-title'),
                    ),
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
        ),
        body: SafeArea(child: child),
      ),
    );
  }
}

// ---------------------------------------------------------------- 분배·라인

/// 패킹(박스 닫기) — MFC 한 곳 몫(TRF 하나)을 빈 BOX 에 담아 닫는다. 분배·패킹 메뉴에서 묶음이 TRF 하나면 이 화면이 열린다
/// (사용자 2026-11-26 "분배·패킹을 합쳐줘" — 묶음 피킹은 칸으로 나누고, 한 곳 몫은 바로 BOX 에).
class CdcSortScreen extends ConsumerStatefulWidget {
  const CdcSortScreen({super.key, this.initialTrf, this.onExit});

  /// 분배·패킹 메뉴에서 고른 TRF — 있으면 TRF 고르기 없이 바로
  final CdcTrf? initialTrf;

  /// 뒤로·다른 묶음 — 분배·패킹 묶음 목록으로
  final VoidCallback? onExit;

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

  @override
  void initState() {
    super.initState();
    if (widget.initialTrf case final t?) {
      _trf = t;
      Future.microtask(_load);
    }
  }

  void _exit() {
    if (widget.onExit case final f?) {
      f();
    } else {
      setState(() {
        _trf = null;
        _notice = null;
      });
    }
  }

  Future<void> _load() async {
    final trf = _trf!;
    final had = _data.hasValue;
    setState(() {
      if (had) {
        reloading = true;
      } else {
        _data = const AsyncLoading();
      }
    });
    final v = await AsyncValue.guard(
      () async => (
        await _repo.sortItems(cdcCenterOf(ref), trf),
        await _repo.lpns(cdcCenterOf(ref), trf.trfId),
      ),
    );
    if (mounted) {
      setState(() {
        reloading = false;
        // 다시 읽기 실패면 보던 화면을 그대로 둔다
        if (!(had && v.hasError)) _data = v;
      });
    }
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
    } else if (widget.onExit != null) {
      widget.onExit!();
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
      area: CdcWorkArea.distribute,
      busy: busy || reloading,
      title: l10n.cdcAreaDistribute,
      subtitle: trf == null ? null : l10n.cdcPackSubtitle(trf.label, trf.mfcId),
      canPop: trf == null && widget.onExit == null,
      onBack: _back,
      child: trf == null
          ? _TrfPick(
              states: sortStates,
              emptyText: l10n.cdcTrfEmptySort,
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
    final step = left.isEmpty
        ? 'done'
        : _box == null
        ? 'box-${lpns.length}'
        : 'items-$_box';
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
      actions.addAll([
        FilledButton(
          key: const ValueKey('cdc-go-inspect'),
          onPressed: () => context.pushReplacement('/cdc/work/inspect'),
          child: Text(l10n.cdcGoInspect),
        ),
        OutlinedButton(
          key: const ValueKey('cdc-other-trf'),
          onPressed: _exit,
          child: Text(l10n.cdcDistOtherWave),
        ),
      ]);
      return cdcStepBody(step: step, body: body, actions: actions);
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
          CdcReveal(
            trigger: _last == i.key ? n : null,
            child: CdcItemCard(
              key: ValueKey('cdc-sort-${i.sku}'),
              name: i.productName ?? i.sku,
              sku: i.sku,
              lot: i.lot,
              qty: i.remaining - n,
              qtyLabel: l10n.cdcLeftUnit,
              footer: n > 0 ? l10n.cdcSortInBox(n) : null,
              emphasize: _last == i.key,
            ),
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
      // 이 TRF 에 남은 것을 다 담았으면 스캔 칸을 치우고 닫기만(사용자 2026-11-26 "다 담았는데 상품 바코드 칸이 남아 덜 담은 줄")
      final allIn = left.every((i) => (_inBox[i.key] ?? 0) >= i.remaining);
      if (allIn) {
        body.add(
          NoticeBox(
            text: l10n.cdcSortAllIn,
            textKey: const ValueKey('cdc-sort-all-in'),
          ),
        );
      }
      actions.addAll([
        if (!allIn)
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
      actions.insert(0, CdcErrorLine(e, key: const ValueKey('cdc-scan-error')));
    }
    if (failText case final f?) {
      actions.insert(0, CdcErrorLine(f, key: const ValueKey('cdc-message')));
    }
    return cdcStepBody(step: step, body: body, actions: actions);
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

  /// 검품하는 출고대기 자리(통로 91) — C-01 "출고대기 박스 스캔"
  String? _staging;
  final _temp = TextEditingController();

  @override
  void dispose() {
    _temp.dispose();
    super.dispose();
  }

  String? _scanError;
  String? _notice;

  CdcFlowRepository get _repo => ref.read(cdcFlowRepositoryProvider);

  Future<void> _load() async {
    final had = _lpns.hasValue;
    setState(() {
      if (had) {
        reloading = true;
      } else {
        _lpns = const AsyncLoading();
      }
    });
    final v = await AsyncValue.guard(
      () => _repo.lpns(cdcCenterOf(ref), _trf!.trfId),
    );
    if (mounted) {
      setState(() {
        reloading = false;
        if (!(had && v.hasError)) _lpns = v;
      });
    }
  }

  void _back() => setState(() {
    if (_box != null) {
      _box = null;
    } else if (_staging != null) {
      _staging = null;
      _scanError = null;
    } else {
      _trf = null;
      _notice = null;
      failText = null;
      resend = null;
    }
  });

  ScanFeedback _scanStaging(String code) {
    final l10n = AppLocalizations.of(context);
    final c = code.trim().toUpperCase();
    if (CdcLocationCode.parse(c)?.aisle != '91') {
      setState(() => _scanError = l10n.cdcInspectNotStaging);
      return ScanFeedback.error(l10n.cdcInspectNotStaging);
    }
    setState(() {
      _staging = c;
      _scanError = null;
    });
    return const ScanFeedback.ok();
  }

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
      _temp.clear();
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
          CdcInspection(
            lpn: box.lpn,
            passed: passed,
            failReason: reason,
            temperatureC: double.tryParse(
              _temp.text.trim().replaceAll(',', '.'),
            ),
          ),
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
    final steps = [
      l10n.cdcStepTrf,
      l10n.cdcStepStaging,
      l10n.cdcStepBox,
      l10n.cdcStepJudge,
    ];
    final trf = _trf;
    return _Frame(
      area: CdcWorkArea.inspect,
      busy: busy || reloading,
      title: l10n.cdcAreaInspect,
      subtitle: trf?.label,
      canPop: trf == null,
      onBack: _back,
      child: trf == null
          ? _TrfPick(
              states: const ['SORTED', 'INSPECTED'],
              emptyText: l10n.cdcTrfEmptyInspect,
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
    body.add(
      StepHeader(
        names: steps,
        current: _staging == null ? 1 : (_box == null ? 2 : 3),
      ),
    );
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
    final step = _staging == null
        ? 'staging'
        : box == null
        ? 'list'
        : 'box-${box.lpn}';
    if (lpns.any((l) => l.inspection == 'FAILED')) {
      body.add(
        NoticeBox(
          text: l10n.cdcInspectRepack,
          textKey: const ValueKey('cdc-repack'),
          warning: true,
        ),
      );
    }
    if (_staging == null) {
      body.add(
        ScanPrompt(
          text: l10n.cdcInspectStagingTitle,
          detail: l10n.cdcInspectStagingHelp,
        ),
      );
      actions.add(
        ScanInput(
          id: 'cdc-staging-scan',
          label: l10n.cdcStepStaging,
          cameraTitle: l10n.cdcStepStaging,
          continuous: false,
          autofocus: false,
          testValues: [
            const TestScan('6층 출고대기 01', 'CDC01-A-6-91-01-0-1'),
            TestScan(l10n.tsWrong, 'CDC01-A-6-90-01-0-1'),
          ],
          onScan: _scanStaging,
        ),
      );
    } else if (box == null) {
      final allPassed = done == lpns.length && lpns.every((l) => l.passed);
      body.add(
        allPassed
            ? DoneMark(
                key: const ValueKey('cdc-inspect-done'),
                title: l10n.cdcInspectAllDone,
                message: l10n.cdcInspectNextLoad,
              )
            : ScanPrompt(
                text: done == lpns.length
                    ? l10n.cdcInspectAllDone
                    : l10n.cdcInspectScanTitle,
                detail: l10n.cdcInspectScanHelp,
              ),
      );
      if (allPassed) {
        actions.add(
          FilledButton(
            key: const ValueKey('cdc-go-load'),
            onPressed: () => context.pushReplacement('/cdc/work/load'),
            child: Text(l10n.cdcGoLoad),
          ),
        );
      }
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
      body.add(
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: TextField(
            key: const ValueKey('cdc-temp'),
            controller: _temp,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: InputDecoration(
              labelText: l10n.cdcInspectTemp,
              helperText: l10n.cdcInspectTempHelp,
              suffixText: '°C',
            ),
          ),
        ),
      );
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
      actions.insert(0, CdcErrorLine(e, key: const ValueKey('cdc-scan-error')));
    }
    if (failText case final f?) {
      actions.insert(0, CdcErrorLine(f, key: const ValueKey('cdc-message')));
    }
    return cdcStepBody(step: step, body: body, actions: actions);
  }
}

/// BOX 한 줄(번호·내용·검품 상태)
class _BoxLine extends StatelessWidget {
  const _BoxLine({required this.lpn, this.checked = false, this.trfNumber});

  final CdcLpn lpn;
  final bool checked;

  /// 이 박스의 TRF 화면 번호(상차 — 어느 TRF 박스인지)
  final String? trfNumber;

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
    return AnimatedContainer(
      key: ValueKey('cdc-lpn-${lpn.lpn}'),
      duration: PdaMotion.of(context, PdaMotion.base),
      curve: PdaMotion.standard,
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
              child: PopIn(
                child: Icon(Icons.check_circle, color: PdaColors.primary),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lpn.lpn,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                Text(
                  [?trfNumber, _contents(lpn)].join(' · '),
                  style: const TextStyle(color: PdaColors.muted),
                ),
              ],
            ),
          ),
          Text(
            text,
            key: ValueKey('cdc-insp-${lpn.lpn}'),
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 상차

/// 상차(DC 시뮬레이터 요청 C-01) — 도크(통로 90) 스캔 → 그 도크의 운행(계획완료 때 자동 배정, transport-execution) →
/// 차량 확인 → 검품 합격 BOX 스캔 → `POST /loading-results`(TRF 마다, 도크·구획 = 운행 온도대) → 다 실으면
/// `POST /trips/{tripId}/loading-completions`(입차한 운행만 — CHECKED_IN → LOADED). 상차는 출발이 아니다.
class CdcLoadScreen extends ConsumerStatefulWidget {
  const CdcLoadScreen({super.key});

  @override
  ConsumerState<CdcLoadScreen> createState() => _CdcLoadScreenState();
}

class _CdcLoadScreenState extends ConsumerState<CdcLoadScreen> with CdcCommand {
  CdcTrip? _trip;
  bool _vehicleOk = false;
  bool _looking = false;

  /// 운행의 TRF 마다 LPN(서버 값)
  AsyncValue<Map<String, List<CdcLpn>>> _lpns = const AsyncLoading();

  /// 스캔한 BOX → 그 TRF
  final _scanned = <String, String>{};
  String? _scanError;
  String? _notice;

  CdcFlowRepository get _repo => ref.read(cdcFlowRepositoryProvider);

  Future<void> _load() async {
    final trip = _trip;
    if (trip == null) return;
    final had = _lpns.hasValue;
    setState(() {
      if (had) {
        reloading = true;
      } else {
        _lpns = const AsyncLoading();
      }
    });
    final v = await AsyncValue.guard(() async {
      final cdc = cdcCenterOf(ref);
      return {for (final t in trip.trfIds) t: await _repo.lpns(cdc, t)};
    });
    if (mounted) {
      setState(() {
        reloading = false;
        if (!(had && v.hasError)) _lpns = v;
      });
    }
  }

  Future<void> _reloadTrip() async {
    final t = await AsyncValue.guard(() => _repo.trip(_trip!.tripId));
    if (mounted && t.hasValue) setState(() => _trip = t.value);
  }

  void _back() => setState(() {
    _scanError = null;
    if (_scanned.isNotEmpty) {
      _scanned.clear();
    } else if (_vehicleOk) {
      _vehicleOk = false;
    } else {
      _trip = null;
      _notice = null;
      failText = null;
      resend = null;
    }
  });

  ScanFeedback _scanDock(String code) {
    final l10n = AppLocalizations.of(context);
    final c = code.trim().toUpperCase();
    if (CdcLocationCode.parse(c)?.aisle != '90') {
      setState(() => _scanError = l10n.cdcLoadNotDock);
      return ScanFeedback.error(l10n.cdcLoadNotDock);
    }
    setState(() {
      _looking = true;
      _scanError = null;
    });
    () async {
      final r = await AsyncValue.guard(
        () => _repo.tripAtDock(cdcCenterOf(ref), c),
      );
      if (!mounted) return;
      setState(() {
        _looking = false;
        switch (r) {
          case AsyncData(:final value?):
            _trip = value;
            _vehicleOk = false;
            _scanned.clear();
            _notice = null;
          case AsyncData():
            _scanError = l10n.cdcLoadNoTrip(c);
          default:
            _scanError = l10n.cdcLoadFailed;
        }
      });
      if (_trip != null) await _load();
    }();
    return const ScanFeedback.ok();
  }

  ScanFeedback _scanVehicle(String code) {
    final l10n = AppLocalizations.of(context);
    if (!_trip!.isVehicle(code)) {
      setState(() => _scanError = l10n.cdcLoadWrongVehicle);
      return ScanFeedback.error(l10n.cdcLoadWrongVehicle);
    }
    setState(() {
      _vehicleOk = true;
      _scanError = null;
    });
    return const ScanFeedback.ok();
  }

  ScanFeedback _scanBox(Map<String, List<CdcLpn>> all, String code) {
    final l10n = AppLocalizations.of(context);
    final c = code.trim();
    String? trf;
    CdcLpn? hit;
    for (final e in all.entries) {
      final l = e.value.where((l) => l.lpn == c).firstOrNull;
      if (l != null) {
        trf = e.key;
        hit = l;
      }
    }
    final error = switch (hit) {
      null => l10n.cdcLoadNotThisTrip,
      final l when l.loaded => l10n.cdcLoadAlready,
      final l when !l.passed => l10n.cdcErrNotPassed,
      _ when _scanned.containsKey(c) => l10n.cdcLoadScannedAlready,
      _ => null,
    };
    if (error != null) {
      setState(() => _scanError = error);
      return ScanFeedback.error(error);
    }
    setState(() {
      _scanned[c] = trf!;
      _scanError = null;
      _notice = null;
    });
    return const ScanFeedback.ok();
  }

  /// 스캔한 BOX 를 TRF 마다 상차 등록(TRF 하나 = 한 번, 결과 불명이면 같은 키로 다시)
  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final trip = _trip!;
    final byTrf = <String, List<String>>{};
    for (final e in _scanned.entries) {
      (byTrf[e.value] ??= []).add(e.key);
    }
    var sent = 0;
    for (final e in byTrf.entries) {
      final ok = await send(
        (key) => _repo.reportLoading(
          trfId: e.key,
          tripId: trip.tripId,
          vehicleId: trip.vehicleId ?? '',
          dockCode: trip.dockCode,
          compartment: trip.tempClass,
          workerId: cdcWorkerOf(ref),
          lpns: e.value,
          key: key,
        ),
        reload: _load,
      );
      if (!ok || !mounted) return;
      sent += e.value.length;
      setState(() => e.value.forEach(_scanned.remove));
    }
    if (mounted) setState(() => _notice = l10n.cdcLoadDone(sent));
  }

  Future<void> _complete(Map<String, List<CdcLpn>> all) async {
    final trip = _trip!;
    // 덜 실었으면 확인부터(사용자 2026-11-26 "박스 스캔 다 안 했는데 상차완료가 그대로 됐다") — 서버는 받지만
    // 안 실은 TRF 는 미상차(NOT_LOADED)로 이번 운행 출발 구성에서 빠진다(transport-execution loading-completions).
    final missing = [
      for (final l in all.values.expand((l) => l))
        if (l.passed && !l.loaded) l,
    ].length;
    if (missing > 0) {
      final l10n = AppLocalizations.of(context);
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          key: const ValueKey('cdc-load-partial-dialog'),
          title: Text(l10n.cdcLoadPartialTitle(missing)),
          content: Text(l10n.cdcLoadPartialBody),
          actions: [
            TextButton(
              key: const ValueKey('cdc-load-partial-cancel'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cdcLoadPartialKeep),
            ),
            FilledButton(
              key: const ValueKey('cdc-load-partial-ok'),
              style: FilledButton.styleFrom(backgroundColor: PdaColors.danger),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.cdcLoadPartialGo),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    } else {
      // 다 실었어도 한 번 더 묻는다(사용자 2026-11-27 "상차완료할 거냐고 한 번 더 확인") — 되돌릴 수 없는 운행 확정
      final l10n = AppLocalizations.of(context);
      final boxes = all.values
          .expand((l) => l)
          .where((l) => l.loaded && l.tripId == trip.tripId)
          .length;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          key: const ValueKey('cdc-load-confirm-dialog'),
          title: Text(l10n.cdcLoadConfirmTitle),
          content: Text(l10n.cdcLoadConfirmBody(boxes, all.length)),
          actions: [
            TextButton(
              key: const ValueKey('cdc-load-confirm-cancel'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              key: const ValueKey('cdc-load-confirm-ok'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.cdcLoadConfirmGo),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    bool mine(CdcLpn l) => l.loaded && l.tripId == trip.tripId;
    // BOX 만 — 그릇(R/T·PLT)은 개수로(MFC 인계 비교는 BOX 끼리)
    final transfers = {
      for (final e in all.entries)
        e.key: [
          for (final l in e.value)
            if (mine(l) && l.unitType == 'BOX') l.lpn,
        ],
    };
    final rtCounts = {
      for (final e in all.entries)
        if (e.value.any((l) => mine(l) && l.unitType != 'BOX'))
          e.key: e.value.where((l) => mine(l) && l.unitType != 'BOX').length,
    };
    await send((key) async {
      final t = await _repo.completeLoading(
        tripId: trip.tripId,
        transfers: transfers,
        rtCounts: rtCounts,
        key: key,
      );
      if (mounted) setState(() => _trip = t);
    }, reload: _load);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final trip = _trip;
    return _Frame(
      area: CdcWorkArea.load,
      busy: busy || reloading || _looking,
      title: l10n.cdcAreaLoad,
      // 긴 tripId 대신 실을 TRF 번호(T…)
      subtitle: trip == null
          ? null
          : trip.trfNumbers.isEmpty
          ? l10n.cdcLoadTripNoNumber
          : l10n.cdcLoadTripIs(trip.trfNumbers.join(' · ')),
      canPop: trip == null,
      onBack: _back,
      child: trip == null
          ? _dockStep(l10n)
          : switch (_lpns) {
              AsyncData(:final value) => _work(l10n, trip, value),
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

  List<String> _steps(AppLocalizations l10n) => [
    l10n.cdcStepDock,
    l10n.cdcStepVehicle,
    l10n.cdcStepBox,
    l10n.cdcStepLoadDone,
  ];

  Widget _dockStep(AppLocalizations l10n) => cdcStepBody(
    step: 'dock',
    body: [
      StepHeader(names: _steps(l10n), current: 0),
      ScanPrompt(text: l10n.cdcLoadDockTitle, detail: l10n.cdcLoadDockHelp),
    ],
    actions: [
      if (_scanError case final e?)
        CdcErrorLine(e, key: const ValueKey('cdc-scan-error')),
      ScanInput(
        id: 'cdc-dock-scan',
        label: l10n.cdcLoadDock,
        cameraTitle: l10n.cdcLoadDock,
        continuous: false,
        autofocus: false,
        testValues: [
          const TestScan('6층 1번 도크', 'CDC01-A-6-90-01-0-1'),
          TestScan(l10n.tsWrong, 'CDC01-A-6-90-04-0-1'),
        ],
        onScan: _scanDock,
      ),
    ],
  );

  Widget _tripCard(AppLocalizations l10n, CdcTrip t) => Container(
    key: const ValueKey('cdc-trip-card'),
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: PdaColors.lilac, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MetaPair(label: l10n.cdcLoadVehicle, value: t.vehicleLabel),
        if (t.driverName case final d?)
          MetaPair(label: l10n.cdcLoadDriver, value: d),
        MetaPair(label: l10n.cdcLoadTemp, value: _zoneText(l10n, t.tempClass)),
        if (t.dockCode case final d?)
          MetaPair(label: l10n.cdcLoadDock, value: d),
        MetaPair(
          label: l10n.cdcLoadStops,
          value: [
            for (final s in t.stops)
              ['${s.seq}. ${s.mfcId}', ...s.knownNumbers].join(' · '),
          ].join('\n'),
        ),
      ],
    ),
  );

  Widget _work(
    AppLocalizations l10n,
    CdcTrip trip,
    Map<String, List<CdcLpn>> all,
  ) {
    final passed = [
      for (final l in all.values.expand((l) => l))
        if (l.passed) l,
    ];
    final loaded = passed.where((l) => l.loaded).length;
    final body = <Widget>[];
    final actions = <Widget>[];
    final allLoaded = passed.isNotEmpty && loaded == passed.length;
    final stepId = trip.loadedDone
        ? 'done'
        : !_vehicleOk
        ? 'vehicle'
        : allLoaded
        ? 'complete'
        : 'boxes';
    final step = !_vehicleOk ? 1 : (allLoaded ? 3 : 2);
    if (!trip.loadedDone) {
      body.add(StepHeader(names: _steps(l10n), current: step));
    }
    body.add(_tripCard(l10n, trip));
    if (_notice case final n?) {
      body.add(NoticeBox(text: n, textKey: const ValueKey('cdc-notice')));
    }
    if (trip.loadedDone) {
      body.add(
        DoneMark(
          key: const ValueKey('cdc-load-done'),
          title: l10n.cdcLoadCompleted,
          message: l10n.cdcLoadNotDeparture,
        ),
      );
      actions.add(
        // 상차완료면 이 일은 끝 — 홈으로(사용자 2026-11-26 "상차 완료하면 끝이지 왜 다른 도크로 가기가 뜨니")
        FilledButton(
          key: const ValueKey('cdc-load-finish'),
          onPressed: () => context.go('/'),
          child: Text(l10n.cdcLoadFinish),
        ),
      );
      return cdcStepBody(step: stepId, body: body, actions: actions);
    }
    if (!_vehicleOk) {
      body.add(
        ScanPrompt(
          text: l10n.cdcLoadVehicleTitle,
          detail: l10n.cdcLoadVehicleHelp(trip.vehicleLabel),
        ),
      );
      actions.add(
        ScanInput(
          id: 'cdc-vehicle-scan',
          label: l10n.cdcLoadVehicle,
          cameraTitle: l10n.cdcLoadVehicle,
          continuous: false,
          autofocus: false,
          testValues: [
            TestScan(trip.vehicleLabel, trip.vehicleLabel),
            TestScan(l10n.tsWrong, '대구99사9999'),
          ],
          onScan: _scanVehicle,
        ),
      );
    } else {
      body.add(
        ProgressLine(
          textKey: const ValueKey('cdc-load-progress'),
          text: l10n.cdcLoadProgress(loaded, passed.length),
          done: loaded,
          total: passed.length,
        ),
      );
      if (passed.isEmpty) {
        body.add(
          CdcCenterNotice(
            key: const ValueKey('cdc-empty'),
            icon: Icons.inventory_2_outlined,
            text: l10n.cdcLoadEmpty,
          ),
        );
      }
      for (final l in passed) {
        body.add(
          CdcReveal(
            trigger: _scanned.isNotEmpty && _scanned.keys.last == l.lpn
                ? _scanned.length
                : null,
            child: _BoxLine(
              lpn: l,
              checked: _scanned.containsKey(l.lpn),
              trfNumber: [
                for (final e in all.entries)
                  if (e.value.any((x) => x.lpn == l.lpn))
                    trip.trfNumberOf(e.key),
              ].nonNulls.firstOrNull,
            ),
          ),
        );
      }
      if (allLoaded && !trip.checkedIn) {
        body.add(
          NoticeBox(
            text: l10n.cdcLoadWaitCheckIn,
            textKey: const ValueKey('cdc-wait-check-in'),
          ),
        );
      }
      if (!allLoaded) {
        actions.add(
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
        );
      }
      if (resendButton(context) case final b?) {
        actions.add(b);
      } else if (_scanned.isNotEmpty) {
        actions.add(
          FilledButton(
            key: const ValueKey('cdc-load-go'),
            onPressed: busy ? null : _submit,
            child: Text(l10n.cdcLoadSubmit(_scanned.length)),
          ),
        );
      } else if (loaded > 0) {
        actions.add(
          trip.checkedIn
              ? (allLoaded
                    ? FilledButton(
                        key: const ValueKey('cdc-load-complete'),
                        onPressed: busy ? null : () => _complete(all),
                        child: Text(l10n.cdcLoadComplete(loaded)),
                      )
                    : OutlinedButton(
                        key: const ValueKey('cdc-load-complete'),
                        onPressed: busy ? null : () => _complete(all),
                        child: Text(
                          l10n.cdcLoadCompletePartial(loaded, passed.length),
                        ),
                      ))
              : OutlinedButton(
                  key: const ValueKey('cdc-trip-reload'),
                  onPressed: busy ? null : _reloadTrip,
                  child: Text(l10n.cdcLoadReloadTrip),
                ),
        );
      }
    }
    if (_scanError case final e?) {
      actions.insert(0, CdcErrorLine(e, key: const ValueKey('cdc-scan-error')));
    }
    if (failText case final f?) {
      actions.insert(0, CdcErrorLine(f, key: const ValueKey('cdc-message')));
    }
    return cdcStepBody(step: stepId, body: body, actions: actions);
  }
}

// ---------------------------------------------------------------- 분배·라인(DAS)

/// 분배·라인(DAS, DC 시뮬레이터 요청 C-01) — 피킹이 끝난 묶음(Wave)을 고르고, 상품을 스캔하면
/// 칸(= TRF·MFC)마다 넣을 수량(작업 줄 shares 로 집은 몫 − 이미 BOX 에 담은 것)이 뜬다. 넣은 것은 이 화면에만 적고,
/// MFC 몫을 다 넣으면 그 칸 BOX 를 닫는다 → `POST /sorting-results`(한 BOX = 한 TRF). 서버에 남는 것은 닫은 BOX 뿐이다.
class CdcDistributeScreen extends ConsumerStatefulWidget {
  const CdcDistributeScreen({super.key});

  @override
  ConsumerState<CdcDistributeScreen> createState() =>
      _CdcDistributeScreenState();
}

class _CdcDistributeScreenState extends ConsumerState<CdcDistributeScreen>
    with CdcCommand {
  AsyncValue<List<CdcTrf>> _trfs = const AsyncLoading();
  String? _wave;

  /// MFC 한 곳 몫 묶음 — 칸 나누기 없이 패킹 화면으로
  CdcTrf? _pack;
  AsyncValue<Map<String, List<CdcSortItem>>> _items = const AsyncLoading();

  /// 칸(TRF)마다 넣은 수량(아직 BOX 를 닫지 않은 것) — 상품 키 → 수량
  final _put = <String, Map<String, int>>{};
  String? _item;
  String? _closing;
  String? _scanError;
  String? _notice;

  CdcFlowRepository get _repo => ref.read(cdcFlowRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _loadTrfs();
  }

  Future<void> _loadTrfs() async {
    setState(() => _trfs = const AsyncLoading());
    final v = await AsyncValue.guard(
      () => _repo.sortTransfers(cdcCenterOf(ref)),
    );
    if (mounted) setState(() => _trfs = v);
  }

  List<CdcTrf> get _slots => [
    for (final t in _trfs.value ?? const <CdcTrf>[])
      if (t.waveId == _wave) t,
  ];

  Future<void> _loadItems() async {
    final had = _items.hasValue;
    setState(() {
      if (had) {
        reloading = true;
      } else {
        _items = const AsyncLoading();
      }
    });
    final v = await AsyncValue.guard(() async {
      final cdc = cdcCenterOf(ref);
      return {for (final t in _slots) t.trfId: await _repo.sortItems(cdc, t)};
    });
    if (mounted) {
      setState(() {
        reloading = false;
        if (!(had && v.hasError)) _items = v;
      });
    }
  }

  int _left(String trfId, CdcSortItem i) =>
      i.remaining - (_put[trfId]?[i.key] ?? 0);

  int _putCount(String trfId) =>
      (_put[trfId] ?? const <String, int>{}).values.fold(0, (a, b) => a + b);

  void _back() => setState(() {
    _scanError = null;
    if (_closing != null) {
      _closing = null;
    } else if (_item != null) {
      _item = null;
    } else {
      _wave = null;
      _put.clear();
      _notice = null;
      failText = null;
      resend = null;
      _items = const AsyncLoading();
    }
  });

  ScanFeedback _scanItem(Map<String, List<CdcSortItem>> all, String code) {
    final l10n = AppLocalizations.of(context);
    for (final e in all.entries) {
      for (final i in e.value) {
        if (cdcCodeIsItem(code, i.sku, i.lot) && _left(e.key, i) > 0) {
          setState(() {
            _item = i.key;
            _scanError = null;
            _notice = null;
          });
          return const ScanFeedback.ok();
        }
      }
    }
    setState(() => _scanError = l10n.cdcDistNoItem);
    return ScanFeedback.error(l10n.cdcDistNoItem);
  }

  void _putAll(String trfId, CdcSortItem i) {
    PdaHaptics.scanned();
    setState(() {
      final m = _put[trfId] ??= {};
      m[i.key] = (m[i.key] ?? 0) + _left(trfId, i);
      final more = (_items.value ?? const {}).entries.any(
        (e) => e.value.any((x) => x.key == _item && _left(e.key, x) > 0),
      );
      if (!more) _item = null;
    });
  }

  ScanFeedback _scanBox(CdcTrf trf, String code) {
    final l10n = AppLocalizations.of(context);
    final lpn = code.trim();
    if (lpn.isEmpty) return ScanFeedback.error(l10n.cdcErrLpnSealed);
    final contents = [
      for (final e in (_put[trf.trfId] ?? const <String, int>{}).entries)
        if (e.value > 0)
          CdcLpnContent(
            sku: e.key.split('|').first,
            lot: e.key.split('|').last,
            qty: e.value,
          ),
    ];
    final slot = _slots.indexOf(trf) + 1;
    () async {
      final ok = await send(
        (key) => _repo.reportSort(
          trf: trf,
          workerId: cdcWorkerOf(ref),
          box: CdcBoxDraft(lpn: lpn, temperatureZone: null, contents: contents),
          key: key,
        ),
        reload: _loadItems,
      );
      if (ok && mounted) {
        setState(() {
          _put.remove(trf.trfId);
          _closing = null;
          _notice = l10n.cdcDistClosed(slot);
        });
      }
    }();
    return const ScanFeedback.ok();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_pack case final t?) {
      return CdcSortScreen(
        key: ValueKey('pack-${t.trfId}'),
        initialTrf: t,
        onExit: () {
          setState(() => _pack = null);
          _loadTrfs();
        },
      );
    }
    final wave = _wave;
    final waveLabel = _slots.firstOrNull?.waveNumber ?? wave;
    return _Frame(
      area: CdcWorkArea.distribute,
      busy: busy || reloading,
      title: l10n.cdcAreaDistribute,
      subtitle: wave == null ? null : waveLabel,
      canPop: wave == null,
      onBack: _back,
      child: switch (_trfs) {
        AsyncError() => CdcCenterNotice(
          icon: Icons.cloud_off,
          text: l10n.cdcLoadFailed,
          action: FilledButton(
            key: const ValueKey('cdc-reload'),
            onPressed: _loadTrfs,
            child: Text(l10n.retry),
          ),
        ),
        AsyncData(:final value) when wave == null => _waves(l10n, value),
        AsyncData() => switch (_items) {
          AsyncData(:final value) => _work(l10n, value),
          AsyncError() => CdcCenterNotice(
            icon: Icons.cloud_off,
            text: l10n.cdcLoadFailed,
            action: FilledButton(
              key: const ValueKey('cdc-reload'),
              onPressed: _loadItems,
              child: Text(l10n.retry),
            ),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  List<String> _steps(AppLocalizations l10n) => [
    l10n.cdcStepWave,
    l10n.cdcStepItem,
    l10n.cdcStepSlot,
    l10n.cdcStepClose,
  ];

  Widget _waves(AppLocalizations l10n, List<CdcTrf> trfs) {
    final waves = <String, List<CdcTrf>>{};
    for (final t in trfs) {
      // 묶음(Wave)마다 — 묶음이 없는 TRF 는 그 TRF 하나로
      (waves[t.waveId ?? t.trfId] ??= []).add(t);
    }
    if (waves.isEmpty) {
      return CdcCenterNotice(
        key: const ValueKey('cdc-empty'),
        icon: Icons.inventory_2_outlined,
        text: l10n.cdcDistEmpty,
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        StepHeader(names: _steps(l10n), current: 0),
        ScanPrompt(text: l10n.cdcDistPickWave),
        for (final e in waves.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Pressable(
              child: GestureDetector(
                onTap: () {
                  if (e.value.length == 1) {
                    setState(() => _pack = e.value.single);
                    return;
                  }
                  setState(() => _wave = e.key);
                  _loadItems();
                },
                child: Container(
                  key: ValueKey('cdc-wave-${e.key}'),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.value.first.waveNumber ?? e.key,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        e.value.length == 1
                            ? l10n.cdcDistModePack(e.value.single.mfcId)
                            : l10n.cdcDistModeSplit(
                                e.value.length,
                                [for (final t in e.value) t.mfcId].join(' · '),
                              ),
                        style: const TextStyle(color: PdaColors.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _slotCard(
    AppLocalizations l10n,
    int n,
    CdcTrf t, {
    required Widget trailing,
    String? detail,
    bool strong = false,
    String keyPrefix = 'cdc-slot',
  }) => Container(
    key: ValueKey('$keyPrefix-${t.trfId}'),
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: strong ? PdaColors.primary : PdaColors.line,
        width: strong ? 2 : 1,
      ),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.cdcDistSlot(n, t.mfcId),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (detail != null)
                Text(detail, style: const TextStyle(color: PdaColors.muted)),
            ],
          ),
        ),
        trailing,
      ],
    ),
  );

  /// 칸(TRF)에 넣을 것이 남았나 — 다 넣었고 넣은 것이 있으면 BOX 를 닫을 차례
  bool _slotFull(String trfId, Map<String, List<CdcSortItem>> all) =>
      _putCount(trfId) > 0 &&
      (all[trfId] ?? const <CdcSortItem>[]).every((i) => _left(trfId, i) == 0);

  Widget _work(AppLocalizations l10n, Map<String, List<CdcSortItem>> all) {
    final slots = _slots;
    final picked = all.values
        .expand((l) => l)
        .fold<int>(0, (a, i) => a + i.pickedQty);
    final done =
        all.values.expand((l) => l).fold<int>(0, (a, i) => a + i.sortedQty) +
        [for (final t in slots) _putCount(t.trfId)]
            .fold<int>(0, (a, b) => a + b);
    final leftAll = [
      for (final e in all.entries)
        for (final i in e.value)
          if (_left(e.key, i) > 0) i,
    ];
    // 한 번에 한 단계만(사용자 2026-11-26 "BOX 닫기·담기·칸·묶음이 왔다갔다 해서 헷갈려"):
    // 다 찬 칸이 있으면 그 칸 BOX 닫기 → 상품을 골랐으면 그 상품 넣기 → 아니면 상품 스캔 → 남은 것이 없으면 끝.
    final closing =
        slots.where((t) => t.trfId == _closing).firstOrNull ??
        slots.where((t) => _slotFull(t.trfId, all)).firstOrNull;
    final item = closing == null ? _item : null;
    final finished = leftAll.isEmpty && closing == null;
    final body = <Widget>[];
    final actions = <Widget>[];
    if (!finished) {
      body.add(
        StepHeader(
          names: _steps(l10n),
          current: closing != null ? 3 : (item == null ? 1 : 2),
        ),
      );
    }
    body.add(
      ProgressLine(
        textKey: const ValueKey('cdc-dist-progress'),
        text: l10n.cdcDistProgress(done, picked),
        done: done,
        total: picked,
      ),
    );
    if (_notice case final n?) {
      body.add(NoticeBox(text: n, textKey: const ValueKey('cdc-notice')));
    }
    String step;
    if (finished) {
      step = 'done';
      body.add(
        DoneMark(
          key: const ValueKey('cdc-dist-done'),
          title: l10n.cdcDistAllDone,
          message: l10n.cdcDistNextInspect,
        ),
      );
      actions.addAll([
        FilledButton(
          key: const ValueKey('cdc-go-inspect'),
          onPressed: () => context.pushReplacement('/cdc/work/inspect'),
          child: Text(l10n.cdcGoInspect),
        ),
        OutlinedButton(
          key: const ValueKey('cdc-other-wave'),
          onPressed: () => setState(() {
            _wave = null;
            _put.clear();
            _notice = null;
            _items = const AsyncLoading();
            _loadTrfs();
          }),
          child: Text(l10n.cdcDistOtherWave),
        ),
      ]);
    } else if (closing != null) {
      step = 'close-${closing.trfId}';
      final n = slots.indexOf(closing) + 1;
      body.add(
        ScanPrompt(
          text: l10n.cdcDistCloseTitle(n),
          detail: l10n.cdcDistCloseHelp(
            closing.mfcId,
            _putCount(closing.trfId),
          ),
        ),
      );
      actions.add(
        ScanInput(
          id: 'cdc-dist-box-scan',
          label: l10n.cdcScanBox,
          cameraTitle: l10n.cdcScanBox,
          continuous: false,
          testValues: const [TestScan('BOX-26112600101', 'BOX-26112600101')],
          onScan: (code) => _scanBox(closing, code),
        ),
      );
    } else if (item == null) {
      step = 'item';
      body.add(ScanPrompt(text: l10n.cdcDistScanItem));
      // 칸마다 남은 수는 보기만(단추 없음)
      for (final (k, t) in slots.indexed) {
        final left = (all[t.trfId] ?? const <CdcSortItem>[]).fold<int>(
          0,
          (a, i) => a + _left(t.trfId, i),
        );
        body.add(
          _slotCard(
            l10n,
            k + 1,
            t,
            keyPrefix: 'cdc-slot-sum',
            detail: l10n.cdcDistSlotState(_putCount(t.trfId), left),
            trailing: left == 0
                ? const Icon(Icons.check_circle, color: PdaColors.primary)
                : const SizedBox.shrink(),
          ),
        );
      }
      actions.add(
        ScanInput(
          id: 'cdc-dist-item-scan',
          label: l10n.cdcDistItemLabel,
          cameraTitle: l10n.cdcDistItemLabel,
          continuous: false,
          testValues: [
            for (final i in {for (final i in leftAll) i.key: i}.values)
              TestScan(i.productName ?? i.sku, i.sku),
            TestScan(l10n.tsWrong, 'SKU-0000'),
          ],
          onScan: (code) => _scanItem(all, code),
        ),
      );
    } else {
      step = item;
      final first = all.values
          .expand((l) => l)
          .firstWhere((i) => i.key == item);
      body.add(
        CdcItemCard(
          key: const ValueKey('cdc-dist-item'),
          name: first.productName ?? first.sku,
          sku: first.sku,
          lot: first.lot,
          qty: [
            for (final e in all.entries)
              for (final i in e.value)
                if (i.key == item) _left(e.key, i),
          ].fold<int>(0, (a, b) => a + b),
          emphasize: true,
        ),
      );
      body.add(ScanPrompt(text: l10n.cdcDistPutTitle));
      for (final (k, t) in slots.indexed) {
        final i = (all[t.trfId] ?? const <CdcSortItem>[])
            .where((i) => i.key == item)
            .firstOrNull;
        if (i == null) continue;
        final left = _left(t.trfId, i);
        if (left == 0) continue;
        body.add(
          _slotCard(
            l10n,
            k + 1,
            t,
            strong: true,
            trailing: FilledButton(
              key: ValueKey('cdc-put-${t.trfId}'),
              onPressed: () => _putAll(t.trfId, i),
              child: Text(l10n.cdcDistPut(left)),
            ),
          ),
        );
      }
      actions.add(
        OutlinedButton(
          key: const ValueKey('cdc-dist-other-item'),
          onPressed: () => setState(() => _item = null),
          child: Text(l10n.cdcDistOtherItem),
        ),
      );
    }
    if (resendButton(context) case final b?) actions.add(b);
    if (_scanError case final e?) {
      actions.insert(0, CdcErrorLine(e, key: const ValueKey('cdc-scan-error')));
    }
    if (failText case final f?) {
      actions.insert(0, CdcErrorLine(f, key: const ValueKey('cdc-message')));
    }
    return cdcStepBody(step: step, body: body, actions: actions);
  }
}
