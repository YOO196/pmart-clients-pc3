import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../l10n/gen/app_localizations.dart';
import 'scanner.dart';

/// `mobile_scanner`(CameraX + ML Kit, 번들) 카메라 스캐너. 일반 안드로이드 기기용(2026-11-10 결정).
final class MobileCameraScanner implements CameraScanner {
  const MobileCameraScanner();

  @override
  Future<void> open(
    BuildContext context, {
    required ScanHandler onScan,
    required String title,
    bool continuous = true,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          _CameraScanPage(title: title, onScan: onScan, continuous: continuous),
    ),
  );
}

class _CameraScanPage extends StatefulWidget {
  const _CameraScanPage({
    required this.title,
    required this.onScan,
    required this.continuous,
  });

  final String title;
  final ScanHandler onScan;
  final bool continuous;

  @override
  State<_CameraScanPage> createState() => _CameraScanPageState();
}

class _CameraScanPageState extends State<_CameraScanPage> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
  );
  final _dedup = ScanDedup();
  ScanFeedback? _last;
  String? _lastCode;
  int _count = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      final code = b.rawValue;
      if (code == null || !_dedup.accept(code, DateTime.now())) continue;
      final f = widget.onScan(code.trim());
      if (f.ok) {
        HapticFeedback.mediumImpact();
        SystemSound.play(SystemSoundType.click);
      } else {
        HapticFeedback.vibrate();
      }
      if (!mounted) return;
      setState(() {
        _last = f;
        _lastCode = code.trim();
        if (f.ok) _count++;
      });
      if (f.ok && !widget.continuous) {
        // onScan 이 다음 화면을 띄웠을 수 있어 맨 위가 아닌 이 화면만 닫는다.
        final route = ModalRoute.of(context);
        if (route != null) Navigator.of(context).removeRoute(route);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final last = _last;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, s, _) => s.torchState == TorchState.unavailable
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: l10n.scanTorch,
                    icon: Icon(
                      s.torchState == TorchState.on
                          ? Icons.flashlight_on
                          : Icons.flashlight_off,
                    ),
                    onPressed: _controller.toggleTorch,
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) => _CameraError(error: error),
            ),
          ),
          Container(
            width: double.infinity,
            color: last == null
                ? theme.colorScheme.surface
                : last.ok
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.errorContainer,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  last == null
                      ? l10n.scanAim
                      : last.message ??
                            (last.ok ? l10n.scanAccepted : l10n.scanRejected),
                  style: theme.textTheme.titleMedium,
                ),
                if (_lastCode != null)
                  Text(_lastCode!, style: theme.textTheme.bodySmall),
                if (widget.continuous) Text(l10n.scanCount(_count)),
                const SizedBox(height: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.scanClose),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            error.errorCode == MobileScannerErrorCode.permissionDenied
                ? l10n.cameraPermissionDenied
                : l10n.cameraUnavailable,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }
}
