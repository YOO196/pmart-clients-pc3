import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import 'scanner.dart';

/// 스캔 입력. 입력칸은 키보드 웨지(하드웨어 스캐너)·직접 입력을 받고, 카메라 버튼은 카메라 스캐너를 연다.
/// 두 경로 모두 같은 [onScan] 으로 간다.
class ScanInput extends ConsumerStatefulWidget {
  const ScanInput({
    super.key,
    required this.id,
    required this.label,
    required this.cameraTitle,
    required this.onScan,
    this.continuous = true,
    this.autofocus = true,
  });

  /// 입력칸 키는 `ValueKey(id)`, 카메라 버튼은 `ValueKey('$id-camera')`.
  final String id;
  final String label;
  final String cameraTitle;
  final ScanHandler onScan;
  final bool continuous;
  final bool autofocus;

  @override
  ConsumerState<ScanInput> createState() => _ScanInputState();
}

class _ScanInputState extends ConsumerState<ScanInput> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String v) {
    final code = v.trim();
    _text.clear();
    // 하드웨어 스캐너(키보드 웨지)가 다음 입력을 계속 받게 한다.
    _focus.requestFocus();
    if (code.isEmpty) return;
    widget.onScan(code);
  }

  Future<void> _camera() async {
    await ref
        .read(cameraScannerProvider)
        .open(
          context,
          onScan: widget.onScan,
          title: widget.cameraTitle,
          continuous: widget.continuous,
        );
    if (mounted && widget.autofocus) _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: ValueKey(widget.id),
            controller: _text,
            focusNode: _focus,
            autofocus: widget.autofocus,
            decoration: InputDecoration(labelText: widget.label),
            onSubmitted: _submit,
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          key: ValueKey('${widget.id}-camera'),
          tooltip: l10n.scanWithCamera,
          iconSize: 32,
          constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
          icon: const Icon(Icons.qr_code_scanner),
          onPressed: _camera,
        ),
      ],
    );
  }
}
