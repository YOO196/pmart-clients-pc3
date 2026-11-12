import 'package:flutter/material.dart';

import 'customer_theme.dart';

/// 작은 꼬리표(NEW·순위 등). [strong] 이면 주 색 바탕.
class PmartTag extends StatelessWidget {
  const PmartTag(this.text, {super.key, this.strong = false});

  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: strong ? scheme.primary : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: strong ? scheme.onPrimary : scheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}

/// 구획 제목 줄: 제목(+설명) 왼쪽, 동작(전체보기 등) 오른쪽.
class PmartSectionHeader extends StatelessWidget {
  const PmartSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      PmartSpace.page,
      PmartSpace.sm,
      PmartSpace.sm,
      PmartSpace.sm,
    ),
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(fontSize: 20),
                ),
                if (subtitle case final s? when s.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(s, style: theme.textTheme.bodySmall),
                  ),
              ],
            ),
          ),
          if (trailing != null)
            trailing!
          else
            const SizedBox(height: 40, width: PmartSpace.sm),
        ],
      ),
    );
  }
}

/// 화면 아래 고정 동작 영역(합계·주 버튼). 위쪽에 얇은 선, 아래 안전 영역.
class PmartBottomBar extends StatelessWidget {
  const PmartBottomBar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      PmartSpace.page,
      PmartSpace.md,
      PmartSpace.page,
      PmartSpace.md,
    ),
    this.safeArea = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool safeArea;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = Padding(padding: padding, child: child);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: safeArea ? SafeArea(top: false, child: body) : body,
    );
  }
}

/// 구획 사이의 두꺼운 띠(화면을 카드 대신 띠로 나눈다).
class PmartSectionGap extends StatelessWidget {
  const PmartSectionGap({super.key, this.height = 8});

  final double height;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainer,
    child: SizedBox(height: height, width: double.infinity),
  );
}
