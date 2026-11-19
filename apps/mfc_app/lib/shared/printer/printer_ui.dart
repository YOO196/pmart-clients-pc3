import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../l10n/gen/app_localizations.dart';
import '../location_guide.dart';
import '../pda_theme.dart';
import '../ui_state_of.dart';
import 'label.dart';
import 'label_printer.dart';

/// 라벨을 출력하고 결과를 알린다. 미리보기 모드면 화면에 라벨을 띄운다.
Future<void> printPackageLabel(
  BuildContext context,
  WidgetRef ref,
  PackageLabel label,
) => printLabel(context, ref, label);

/// 라벨(포장·상품 바코드)을 출력하고 결과를 알린다. [sentText] 는 프린터로 보낸 뒤의 안내(없으면 공통 문구).
Future<void> printLabel(
  BuildContext context,
  WidgetRef ref,
  PrintableLabel label, {
  String? sentText,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final outcome = await ref.read(labelPrintServiceProvider).print(label);
  if (!context.mounted) return;
  switch (outcome) {
    case PrintPreview(:final label):
      await showDialog<void>(
        context: context,
        builder: (_) => switch (label) {
          final ProductBarcodeLabel p => ProductBarcodePreviewDialog(label: p),
          final PackageLabel p => LabelPreviewDialog(label: p),
          final LotLabel p => LotLabelPreviewDialog(label: p),
          _ => const SizedBox.shrink(),
        },
      );
    case PrintSent():
      messenger.showSnackBar(
        SnackBar(content: Text(sentText ?? l10n.printSent)),
      );
    case PrintFailed(:final reason):
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (reason) {
            PrintFailure.notConfigured => l10n.printNotConfigured,
            PrintFailure.unreachable => l10n.printUnreachable,
          }),
          action: SnackBarAction(
            label: l10n.printerSettingsTitle,
            onPressed: () => context.push('/settings/printer'),
          ),
        ),
      );
  }
}

/// LOT 라벨 미리보기(프린터 없음). 바코드 그림은 그리지 않고 값만 보인다.
class LotLabelPreviewDialog extends StatelessWidget {
  const LotLabelPreviewDialog({super.key, required this.label});

  final LotLabel label;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      key: const ValueKey('lot-label-preview'),
      title: Text(l10n.lotLabelPreviewTitle(label.copies)),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(
              label.gs1 ?? label.labelValue,
              key: const ValueKey('lot-label-code'),
              style: theme.textTheme.titleMedium?.copyWith(letterSpacing: 0.5),
            ),
            const Divider(),
            Text(
              l10n.lotLabelNo(label.lotNo),
              style: theme.textTheme.headlineSmall,
            ),
            Text(label.productName ?? label.sku),
            if (label.expiryDate != null)
              Text(l10n.stockCheckExpiry(label.expiryDate!)),
            if (label.receivedOn != null)
              Text(l10n.lotLabelReceived(label.receivedOn!)),
            const SizedBox(height: 12),
            Text(l10n.labelPreviewNote, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.confirmOk),
        ),
      ],
    );
  }
}

/// 프린터가 없을 때 쓰는 포장 라벨 미리보기 — 실제 라벨처럼(왼쪽 QR 자리, 오른쪽 인계 숫자·온도대·봉투) 그린다.
/// 2026-11-20 사용자 "라벨 미리보기 팝업창 이상하게 뜨지 않니?" — 글줄만 늘어서고 QR 원문·시스템 ID 가 제목처럼 보였다.
/// 시스템 값(QR 원문)은 맨 아래 작게만(ADR-0070). QR 그림은 그리지 않는다(QR 렌더링 패키지 미승인).
class LabelPreviewDialog extends StatelessWidget {
  const LabelPreviewDialog({super.key, required this.label});

  final PackageLabel label;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: PdaColors.muted);
    return Dialog(
      key: const ValueKey('label-preview'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: PdaColors.paper,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.labelPreviewTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(l10n.labelPreviewNote, style: muted),
            const SizedBox(height: 16),
            // 라벨 한 장(용지 812×609 — 가로가 긴 꼴).
            PackageLabelCard(label: label),
            const SizedBox(height: 10),
            // 시스템 값 — 맨 아래 작게(문의·대조용).
            SelectableText(
              label.qrCode,
              key: const ValueKey('label-qr-text'),
              style: muted?.copyWith(letterSpacing: 0.5),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('label-ok'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.confirmOk),
            ),
          ],
        ),
      ),
    );
  }
}

/// 프린터가 없을 때 쓰는 상품 바코드 스티커 미리보기.
class ProductBarcodePreviewDialog extends StatelessWidget {
  const ProductBarcodePreviewDialog({super.key, required this.label});

  final ProductBarcodeLabel label;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      key: const ValueKey('barcode-label-preview'),
      title: Text(l10n.labelPreviewTitle),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 바코드 그림은 그리지 않는다(렌더링 패키지 미승인). 원문만 보인다.
          SelectableText(
            label.barcode,
            key: const ValueKey('barcode-label-text'),
            style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 0.5),
          ),
          const Divider(),
          if (label.productName != null)
            Text(label.productName!, style: theme.textTheme.titleMedium),
          Text(l10n.reprintSku(label.sku)),
          const SizedBox(height: 12),
          Text(l10n.labelPreviewNote, style: theme.textTheme.bodySmall),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.confirmOk),
        ),
      ],
    );
  }
}

/// 프린터 설정(포장대 고정형 네트워크 라벨 프린터).
class PrinterSettingsScreen extends ConsumerWidget {
  const PrinterSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.printerSettingsTitle)),
      body: UiStateView<PrinterSettings>(
        state: uiStateOf(ref.watch(printerSettingsProvider)),
        onRetry: () => ref.invalidate(printerSettingsProvider),
        ready: (context, s) => _PrinterSettingsForm(initial: s),
      ),
    );
  }
}

class _PrinterSettingsForm extends ConsumerStatefulWidget {
  const _PrinterSettingsForm({required this.initial});

  final PrinterSettings initial;

  @override
  ConsumerState<_PrinterSettingsForm> createState() =>
      _PrinterSettingsFormState();
}

class _PrinterSettingsFormState extends ConsumerState<_PrinterSettingsForm> {
  late PrinterMode _mode = widget.initial.mode;
  late final _host = TextEditingController(text: widget.initial.host);
  late final _port = TextEditingController(text: '${widget.initial.port}');

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  /// 네트워크 모드면 주소·포트가 맞아야 한다. 미리보기 모드는 입력값을 그대로 남긴다.
  PrinterSettings? _value() {
    final port = int.tryParse(_port.text.trim());
    final s = PrinterSettings(
      mode: _mode,
      host: _host.text.trim(),
      port: port ?? PrinterSettings.defaultPort,
    );
    if (_mode == PrinterMode.networkZpl && (port == null || !s.networkReady)) {
      return null;
    }
    return s;
  }

  Future<bool> _save() async {
    final l10n = AppLocalizations.of(context);
    // 앞 안내가 줄 서 있지 않게 바로 바꾼다.
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    final v = _value();
    if (v == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.printerInvalid)));
      return false;
    }
    await ref.read(printerSettingsProvider.notifier).save(v);
    messenger.showSnackBar(SnackBar(content: Text(l10n.printerSaved)));
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final network = _mode == PrinterMode.networkZpl;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<PrinterMode>(
          segments: [
            ButtonSegment(
              value: PrinterMode.preview,
              label: Text(l10n.printerModePreview),
            ),
            ButtonSegment(
              value: PrinterMode.networkZpl,
              label: Text(l10n.printerModeNetwork),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (v) => setState(() => _mode = v.first),
        ),
        const SizedBox(height: 8),
        Text(network ? l10n.printerNetworkHelp : l10n.printerPreviewHelp),
        // 화면 미리보기면 라벨이 어떻게 뜨는지 바로 보인다(사용자 2026-11-20 "화면 미리보기라면서 왜 라벨 미리보기가 안 떠 있어").
        if (!network) ...[
          const SizedBox(height: 12),
          Text(
            l10n.printerPreviewSample,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          const PackageLabelCard(
            key: ValueKey('printer-sample-label'),
            label: PackageLabel(
              packageId: 'SAMPLE',
              packageVersion: 1,
              qrCode: 'PKG:SAMPLE:1',
              handoverCode: '3817',
              orderNumber: '10000001',
              temperatureZone: 'CHILLED',
              bagCount: 1,
            ),
          ),
        ],
        if (network) ...[
          TextField(
            key: const ValueKey('printer-host'),
            controller: _host,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(labelText: l10n.printerHost),
          ),
          TextField(
            key: const ValueKey('printer-port'),
            controller: _port,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.printerPort),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const ValueKey('printer-save'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          onPressed: _save,
          child: Text(l10n.printerSave),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const ValueKey('printer-test'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
          ),
          onPressed: () async {
            if (!await _save() || !context.mounted) return;
            // 시험 라벨. 실제 포장 ID 가 아니다.
            await printPackageLabel(
              context,
              ref,
              const PackageLabel(
                packageId: 'TEST-LABEL',
                packageVersion: 1,
                qrCode: 'PKG:TEST-LABEL:1',
                orderId: 'TEST',
                temperatureZone: 'CHILLED',
                bagCount: 1,
              ),
            );
          },
          child: Text(l10n.printerTestPrint),
        ),
      ],
    );
  }
}

/// 포장 라벨 한 장 모양(왼쪽 QR 자리, 오른쪽 인계 번호·온도대·봉투·주문번호) — 미리보기 창·프린터 설정이 같이 쓴다.
class PackageLabelCard extends StatelessWidget {
  const PackageLabelCard({super.key, required this.label});

  final PackageLabel label;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final zone = label.temperatureZone?.toUpperCase();
    final zoneText = switch (zone) {
      'AMBIENT' => l10n.zoneAmbient,
      'CHILLED' => l10n.zoneChilled,
      'FROZEN' => l10n.zoneFrozen,
      null => null,
      final z => z,
    };
    final muted = theme.textTheme.bodySmall?.copyWith(color: PdaColors.muted);
    return Container(
      key: const ValueKey('label-card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: PdaColors.ink, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              border: Border.all(color: PdaColors.line, width: 1.5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.qr_code_2, size: 80, color: PdaColors.ink),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label.handoverCode case final c?) ...[
                  Text(l10n.labelHandoverCode, style: muted),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      c,
                      key: const ValueKey('label-handover-code'),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3,
                        color: PdaColors.ink,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (zoneText != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: tempChipColor(switch (zone) {
                            'CHILLED' => 'C',
                            'FROZEN' => 'F',
                            _ => 'A',
                          }),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          zoneText,
                          key: const ValueKey('label-zone'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: PdaColors.ink,
                          ),
                        ),
                      ),
                    if (label.bagCount != null)
                      Text(
                        l10n.labelBags(label.bagCount!),
                        style: theme.textTheme.titleSmall,
                      ),
                  ],
                ),
                if (label.orderNumber case final n?) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.labelOrderNumber(n),
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
