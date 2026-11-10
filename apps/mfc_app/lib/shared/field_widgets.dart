import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../l10n/gen/app_localizations.dart';

/// 단계 표시(1 → 2 → 3 …). [current] 까지 채운다.
class StepHeader extends StatelessWidget {
  const StepHeader({super.key, required this.names, required this.current});

  final List<String> names;
  final int current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      key: ValueKey('step-$current'),
      children: [
        for (final (i, n) in names.indexed)
          Expanded(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: i <= current
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                  foregroundColor: i <= current
                      ? scheme.onPrimary
                      : scheme.onSurfaceVariant,
                  child: Text('${i + 1}'),
                ),
                const SizedBox(height: 4),
                Text(
                  n,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: i == current ? FontWeight.bold : null,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 끝·대기·오류 안내 + 버튼 하나.
class ResultView extends StatelessWidget {
  const ResultView({
    super.key,
    required this.icon,
    required this.text,
    required this.action,
    required this.onAction,
    this.busy = false,
  });

  final IconData icon;
  final String text;
  final String action;
  final Future<void> Function() onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (busy)
        const Center(child: CircularProgressIndicator())
      else
        Icon(icon, size: 64),
      const SizedBox(height: 16),
      Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 24),
      CommandButton(
        key: const ValueKey('result-action'),
        label: action,
        busy: busy,
        onPressed: onAction,
      ),
    ],
  );
}

/// 이 칸에 왔는지 확인하는 줄: 지시 위치 + 스캔했으면 ✓.
class TargetLine extends StatelessWidget {
  const TargetLine({
    super.key,
    required this.label,
    required this.code,
    required this.confirmed,
  });

  final String label;
  final String code;
  final bool confirmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          confirmed ? Icons.check_circle : Icons.place_outlined,
          color: confirmed ? theme.colorScheme.primary : null,
        ),
        const SizedBox(width: 8),
        Text(label, style: theme.textTheme.titleMedium),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            code,
            style: theme.textTheme.headlineSmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// 수량 −/＋, 숫자를 누르면 직접 입력.
class QtyStepper extends StatelessWidget {
  const QtyStepper({
    super.key,
    required this.id,
    required this.label,
    required this.value,
    required this.onChanged,
    this.max,
    this.enabled = true,
  });

  final String id;
  final String label;
  final int value;
  final int? max;
  final bool enabled;
  final ValueChanged<int> onChanged;

  void _set(int v) {
    final m = max;
    onChanged(v < 0 ? 0 : (m != null && v > m ? m : v));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.titleMedium)),
        IconButton.outlined(
          key: ValueKey('$id-minus'),
          onPressed: enabled && value > 0 ? () => _set(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        InkWell(
          key: ValueKey('$id-value'),
          onTap: enabled
              ? () async {
                  final v = await showDialog<int>(
                    context: context,
                    builder: (_) => QtyDialog(title: label, initial: value),
                  );
                  if (v != null) _set(v);
                }
              : null,
          child: SizedBox(
            width: 64,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
          ),
        ),
        IconButton.filledTonal(
          key: ValueKey('$id-plus'),
          onPressed: enabled && (max == null || value < max!)
              ? () => _set(value + 1)
              : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

/// 수량 직접 입력. 컨트롤러는 다이얼로그가 닫힌 뒤 해제한다.
class QtyDialog extends StatefulWidget {
  const QtyDialog({super.key, required this.title, required this.initial});

  final String title;
  final int initial;

  @override
  State<QtyDialog> createState() => _QtyDialogState();
}

class _QtyDialogState extends State<QtyDialog> {
  late final _c = TextEditingController(text: '${widget.initial}');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('qty-input'),
        controller: _c,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('qty-ok'),
          onPressed: () =>
              Navigator.of(context).pop(int.tryParse(_c.text.trim())),
          child: Text(l10n.confirmOk),
        ),
      ],
    );
  }
}
