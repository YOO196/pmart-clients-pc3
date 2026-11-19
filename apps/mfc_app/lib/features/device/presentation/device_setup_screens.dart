import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../router.dart' show afterLoginProvider;
import '../../../shared/field_widgets.dart' show StepBody;
import '../../../shared/menu_tile.dart';
import '../../../shared/pda_theme.dart';
import '../../../shared/printer/label_printer.dart';
import '../../../shared/providers.dart';
import '../../../shared/scanner/scan_input.dart';
import '../../../shared/scanner/scanner.dart';

/// 기기 설정(시작 메뉴 → 기기 설정, 사용자 2026-11-17). 로그인 없이 연다.
/// 모양은 메인의 업무 고르기 목록과 같다([MenuTile]).
class DeviceSetupScreen extends ConsumerWidget {
  const DeviceSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mock = ref.watch(envProvider) == PmartEnv.mock;
    final printer = ref.watch(printerSettingsProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.setupTitle),
        actions: [
          if (mock)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(label: Text(l10n.mockModeBadge)),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final tile in [
                MenuTile(
                  key: const ValueKey('setup-printer'),
                  icon: Icons.print_outlined,
                  title: l10n.setupPrinter,
                  hint: printer == null
                      ? null
                      : printer.mode == PrinterMode.networkZpl
                      ? l10n.setupPrinterNetwork(printer.host, printer.port)
                      : l10n.setupPrinterPreview,
                  onTap: () => context.push('/setup/printer'),
                ),
                MenuTile(
                  key: const ValueKey('setup-scanner'),
                  icon: Icons.qr_code_scanner,
                  title: l10n.setupScanner,
                  hint: l10n.setupScannerHint,
                  onTap: () => context.push('/setup/scanner'),
                ),
                MenuTile(
                  key: const ValueKey('setup-device'),
                  icon: Icons.smartphone_outlined,
                  title: l10n.setupDevice,
                  hint: l10n.setupDeviceHint,
                  onTap: () => context.push('/setup/device'),
                ),
              ])
                // 메뉴 칸 높이 96 — 늘려 채우지 않는다.
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(height: 96, child: tile),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 앱 시작 메뉴(로그인 전, 사용자 2026-11-17) — 로그인 · 기기 설정 · 재고 확인.
/// 2026-11-20 사용자 "첫 화면 아래 공간이 많다, 로그인 상자를 키우고 기기 설정·재고 확인은 아래에":
/// 로그인 = 화면 대부분을 쓰는 큰 보라 상자(로고·이름·설명), 기기 설정·재고 확인 = 아래 나란히 두 칸.
/// 재고 확인은 로그인이 필요해 누르면 로그인 화면 → 로그인되면 바로 재고 확인으로 간다.
class StartScreen extends ConsumerWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mock = ref.watch(envProvider) == PmartEnv.mock;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.homeTitle),
        actions: [
          if (mock)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(label: Text(l10n.mockModeBadge)),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 로그인 — 큰 보라 상자. 아래 두 칸을 키워 상자를 조금 줄였다(사용자 2026-11-20 "너무 커졌어, 조금만 줄여").
              Expanded(
                child: SizedBox(
                  width: double.infinity,
                  child: SizedBox(
                    height: double.infinity,
                    child: Material(
                      color: PdaColors.primary,
                      borderRadius: BorderRadius.circular(20),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: const ValueKey('start-login'),
                        onTap: () {
                          ref.read(afterLoginProvider.notifier).set(null);
                          context.push('/login');
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(26),
                                child: Image.asset(
                                  'assets/images/pick_pda_logo.png',
                                  key: const ValueKey('start-logo'),
                                  width: 104,
                                  height: 104,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.login,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    l10n.startLogin,
                                    style: theme.textTheme.headlineMedium
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                l10n.startLoginHint,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.85),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // 기기 설정 · 재고 확인 — 아래 나란히(크게).
              SizedBox(
                height: 180,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _StartTile(
                        key: const ValueKey('start-setup'),
                        icon: Icons.settings_outlined,
                        title: l10n.setupTitle,
                        hint: l10n.startSetupHintShort,
                        onTap: () => context.push('/setup'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StartTile(
                        key: const ValueKey('start-stock'),
                        icon: Icons.manage_search,
                        title: l10n.stockCheckTitle,
                        hint: l10n.startNeedsLogin,
                        onTap: () {
                          ref
                              .read(afterLoginProvider.notifier)
                              .set('/stock-check');
                          context.push('/login');
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 시작 화면 아래 칸 — 아이콘 동그라미 + 이름 + 한 줄.
class _StartTile extends StatelessWidget {
  const _StartTile({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: PdaColors.line, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: PdaColors.softer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: PdaColors.primary, size: 26),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              hint,
              style: theme.textTheme.bodySmall?.copyWith(color: PdaColors.body),
            ),
          ],
        ),
      ),
    );
  }
}

/// 스캐너 확인 — 찍은 값을 그대로 보인다(서버로 보내지 않는다).
/// 스캔 단추는 다른 화면처럼 아래 고정 칸, 가운데는 읽은 값(크게)·읽은 횟수(사용자 2026-11-20 "확인이 안 되네").
class ScannerCheckScreen extends StatefulWidget {
  const ScannerCheckScreen({super.key});

  @override
  State<ScannerCheckScreen> createState() => _ScannerCheckScreenState();
}

class _ScannerCheckScreenState extends State<ScannerCheckScreen> {
  String? _last;
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scannerCheckTitle)),
      body: StepBody(
        actions: [
          ScanInput(
            id: 'scanner-check',
            label: l10n.scannerCheckLabel,
            cameraTitle: l10n.scannerCheckLabel,
            testValues: const [TestScan('8801115114154', '8801115114154')],
            onScan: (code) {
              setState(() {
                _last = code;
                _count++;
              });
              return const ScanFeedback.ok();
            },
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.scannerCheckHelp,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: PdaColors.body,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: _last == null ? PdaColors.soft : PdaColors.softer,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _last == null ? PdaColors.line : PdaColors.lilac,
                      width: 1.5,
                    ),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: _last == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const BarcodeIcon(size: 56, color: PdaColors.muted),
                            const SizedBox(height: 12),
                            Text(
                              l10n.scannerCheckEmpty,
                              key: const ValueKey('scanner-check-empty'),
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: PdaColors.body,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  color: PdaColors.ok,
                                  size: 22,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  l10n.scannerCheckLast,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: PdaColors.okInk,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: SelectableText(
                                _last!,
                                key: const ValueKey('scanner-check-value'),
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: PdaColors.lilac),
                              ),
                              child: Text(
                                l10n.scannerCheckCount(_count),
                                key: const ValueKey('scanner-check-count'),
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: PdaColors.primary,
                                ),
                              ),
                            ),
                          ],
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

/// 기기 정보 — 기기 ID·실행 모드·서버 주소를 한 상자에 줄마다(이름표 + 진한 값).
class DeviceInfoScreen extends ConsumerWidget {
  const DeviceInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mock = ref.watch(envProvider) == PmartEnv.mock;
    Widget row(String label, Widget value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(color: PdaColors.body),
          ),
          const SizedBox(height: 6),
          value,
        ],
      ),
    );
    final valueStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.deviceInfoTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    row(
                      l10n.deviceInfoMode,
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: mock ? PdaColors.warning : PdaColors.okSoft,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            mock
                                ? l10n.deviceInfoModeMock
                                : l10n.deviceInfoModeLocal,
                            key: const ValueKey('device-mode'),
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: mock
                                  ? PdaColors.onWarning
                                  : PdaColors.okInk,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Divider(),
                    row(
                      l10n.deviceInfoId,
                      FutureBuilder<String>(
                        future: ref.watch(deviceIdProvider).get(),
                        builder: (_, s) => SelectableText(
                          s.data ?? '…',
                          key: const ValueKey('device-id'),
                          style: valueStyle?.copyWith(
                            letterSpacing: 0.3,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    if (!mock) ...[
                      const Divider(),
                      row(
                        l10n.deviceInfoServer,
                        SelectableText(
                          ref.watch(apiBaseUrlProvider),
                          style: valueStyle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.deviceInfoHelp,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: PdaColors.body,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
