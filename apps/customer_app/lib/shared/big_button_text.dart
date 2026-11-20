import 'package:flutter/material.dart';

/// 화면 아래 넓은 주 버튼의 글자를 18 로(레퍼런스 4-1 "구매하기"·6-1 결제하기 — 2026-11-21 측정).
/// 테마 기본(16)은 그대로 두고 감싼 [FilledButton]·`CommandButton` 만 바꾼다(작은 버튼까지 커지지 않게).
class BigButtonText extends StatelessWidget {
  const BigButtonText({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.filledButtonTheme.style ?? const ButtonStyle();
    final text =
        base.textStyle?.resolve(const {}) ?? theme.textTheme.labelLarge;
    return FilledButtonTheme(
      data: FilledButtonThemeData(
        style: base.copyWith(
          textStyle: WidgetStatePropertyAll(text?.copyWith(fontSize: 18)),
        ),
      ),
      child: child,
    );
  }
}
