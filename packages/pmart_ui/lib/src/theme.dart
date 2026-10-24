import 'package:flutter/material.dart';

/// 임시 테마. 디자인 확정 전까지 중립 팔레트를 쓴다.
///
/// 레퍼런스 앱(배민·B마트)의 브랜드 색(민트)·일러스트를 쓰지 않는다
/// (docs/apps/customer-app-design-review.md §5).
abstract final class PmartTheme {
  static const _seed = Color(0xFF3557C5);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48)),
      ),
    );
  }
}
