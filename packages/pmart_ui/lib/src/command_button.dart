import 'package:flutter/material.dart';

/// 변경 명령 버튼. 실행 중에는 눌리지 않는다(연타로 같은 행위가 두 번 나가지 않게).
///
/// [onPressed] 가 null 이면 비활성이다. 결과 불명(RESULT_UNKNOWN) 동안에는 호출 측이 null 을 넘긴다.
class CommandButton extends StatefulWidget {
  const CommandButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final Future<void> Function()? onPressed;

  /// 바깥 상태가 진행 중임을 알 때(예: 컨트롤러가 요청 중).
  final bool busy;

  @override
  State<CommandButton> createState() => _CommandButtonState();
}

class _CommandButtonState extends State<CommandButton> {
  bool _running = false;

  bool get _disabled => widget.onPressed == null || widget.busy || _running;

  Future<void> _run() async {
    if (_disabled) return;
    setState(() => _running = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showSpinner = widget.busy || _running;
    return FilledButton(
      onPressed: _disabled ? null : _run,
      child: showSpinner
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(widget.label),
    );
  }
}
