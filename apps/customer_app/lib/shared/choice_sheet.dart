import 'package:flutter/material.dart';
import 'package:pmart_ui/pmart_ui.dart';

/// 아래에서 올라오는 고르기 시트(레퍼런스 "정렬"): 위 제목 + ✕, 줄마다 이름, 지금 고른 줄은 굵게 + ✓.
/// 닫으면 null(기존 값 유지).
Future<T?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T value, String label, Key? key)> options,
  required T selected,
  Key? closeKey,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  builder: (context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    key: closeKey,
                    tooltip: MaterialLocalizations.of(context)
                        .closeButtonTooltip,
                    icon: const PmartLineIcon(PmartLineIcons.close, size: 24),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            for (final (value, label, key) in options)
              InkWell(
                key: key,
                onTap: () => Navigator.of(context).pop(value),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 15, 20, 15),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontSize: 16,
                            fontWeight: value == selected
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (value == selected)
                        const PmartLineIcon(PmartLineIcons.check, size: 22),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  },
);
