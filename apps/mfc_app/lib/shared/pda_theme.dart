import 'package:flutter/material.dart';

/// PDA 전용 테마 — 흰 바탕 + 중립 회색, 보라는 포인트(주 버튼·지금 단계·수량·위치 값)에만
/// (사용자 2026-11-19 "흰색 기본에 포인트 컬러만 연보라 내지는 보라"). 배치는 시안 `pda-preview.html`.
/// 공통 `PmartTheme` 은 다른 앱도 쓰므로 건드리지 않고 이 앱에서만 쓴다.
///
/// 글자 #1F1D24 · 보조 글자 #6B6873 · 선 #E9E8EE · 바탕 흰색 · 회색 칸 #F4F4F7 ·
/// 기본 보라 #6B45B0 · 옅은 보라 #F6F1FD / #ECE2FA(포인트 바탕).
abstract final class PdaColors {
  static const ink = Color(0xFF1F1D24);

  /// 보조 글씨. 예전 #6B6873 은 현장 밝은 곳에서 안 보였다(사용자 2026-11-20 "중요한 걸 회색으로 안 보이게") — 더 진하게.
  static const muted = Color(0xFF55525D);

  /// 설명 글씨(제목 아래 한 줄 등) — 보조보다 진하게.
  static const body = Color(0xFF3A3741);
  static const line = Color(0xFFE9E8EE);
  static const paper = Colors.white;
  static const dark = Color(0xFF3F2A66);
  static const primary = Color(0xFF6B45B0);

  /// 중립 회색 칸(아직 안 한 단계·보조 바탕).
  static const soft = Color(0xFFF4F4F7);

  /// 옅은 보라(포인트 바탕).
  static const softer = Color(0xFFF6F1FD);
  static const lilac = Color(0xFFECE2FA);
  static const notice = Color(0xFFF6F1FD);
  static const onNotice = Color(0xFF4E3285);

  /// 주의 띠(노랑) — 멈춰 확인해야 하는 안내에만.
  static const warning = Color(0xFFFFF2DA);
  static const onWarning = Color(0xFF724815);
  static const danger = Color(0xFF9B392B);

  /// 됐다(초록) — 확인된 상태 한 줄.
  static const ok = Color(0xFF2E8B57);
  static const okInk = Color(0xFF1F5E3B);
  static const okSoft = Color(0xFFE3F4EA);

  /// 거절·오류 칩 바탕(옅은 빨강).
  static const dangerSoft = Color(0xFFFBE6E3);
}

abstract final class PdaTheme {
  /// 앱 글꼴(pubspec fonts). 시험은 글꼴 파일이 없어도 이름만 두면 기본 글꼴로 그린다.
  static const fontFamily = 'Pretendard';

  static ThemeData light() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: PdaColors.primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: PdaColors.primary,
          onPrimary: Colors.white,
          primaryContainer: PdaColors.softer,
          onPrimaryContainer: PdaColors.dark,
          secondaryContainer: PdaColors.lilac,
          onSecondaryContainer: PdaColors.dark,
          surface: PdaColors.paper,
          onSurface: PdaColors.ink,
          onSurfaceVariant: PdaColors.muted,
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: Colors.white,
          surfaceContainer: PdaColors.soft,
          surfaceContainerHigh: PdaColors.soft,
          surfaceContainerHighest: PdaColors.soft,
          outline: const Color(0xFFC9C7D1),
          outlineVariant: PdaColors.line,
          inverseSurface: PdaColors.dark,
        );
    final shape10 = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    // 글자 모양은 기본 글꼴 묶음에서 이어 받는다(글꼴 이름을 비워 두면 화면마다 글꼴이 달라진다).
    // PDA 는 팔 길이에서 본다 — 작은 글씨를 한 단계 키운다(본문 15, 작은 글씨 13).
    // 글꼴은 Pretendard(앱에 넣음) — 기기 기본 글꼴은 얇아 안 보였다. 굵기는 역할마다 정한다:
    // 본문 400, 이름표·단추 600, 제목 700, 큰 제목 800(사용자 2026-11-20 "너무 얇아도, 너무 두꺼워도 문제").
    final m3 = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: fontFamily,
    ).textTheme;
    const w4 = FontWeight.w400, w6 = FontWeight.w600, w7 = FontWeight.w700;
    final base = m3.copyWith(
      headlineLarge: m3.headlineLarge!.copyWith(fontWeight: FontWeight.w800),
      headlineMedium: m3.headlineMedium!.copyWith(fontWeight: FontWeight.w800),
      headlineSmall: m3.headlineSmall!.copyWith(fontWeight: FontWeight.w800),
      titleLarge: m3.titleLarge!.copyWith(fontWeight: w7),
      titleMedium: m3.titleMedium!.copyWith(fontWeight: w7),
      titleSmall: m3.titleSmall!.copyWith(fontWeight: w6),
      bodyLarge: m3.bodyLarge!.copyWith(fontWeight: w4),
      bodyMedium: m3.bodyMedium!.copyWith(
        fontSize: 15,
        fontWeight: w4,
        height: 1.45,
      ),
      bodySmall: m3.bodySmall!.copyWith(
        fontSize: 13,
        fontWeight: w4,
        height: 1.45,
      ),
      labelLarge: m3.labelLarge!.copyWith(fontWeight: w6),
      labelMedium: m3.labelMedium!.copyWith(fontSize: 13, fontWeight: w6),
      labelSmall: m3.labelSmall!.copyWith(fontSize: 12, fontWeight: w6),
    );
    final bold = base.labelLarge!.copyWith(fontWeight: FontWeight.w800);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: fontFamily,
      textTheme: base,
      scaffoldBackgroundColor: PdaColors.paper,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: PdaColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: base.titleMedium!.copyWith(
          color: PdaColors.ink,
          fontSize: 17,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
        shape: const Border(bottom: BorderSide(color: PdaColors.line)),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.only(top: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: const BorderSide(color: PdaColors.line),
        ),
      ),
      dividerTheme: const DividerThemeData(color: PdaColors.line, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          // 스캔 단추와 같은 글자 — 20·700(단추 높이 56~58 에 맞는 비율, 사용자 2026-11-20 "글자가 작다").
          textStyle: bold.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 50),
          shape: shape10,
          backgroundColor: Colors.white,
          foregroundColor: PdaColors.ink,
          side: const BorderSide(color: PdaColors.line),
          textStyle: bold.copyWith(fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: PdaColors.primary,
          textStyle: bold.copyWith(fontSize: 14),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        side: const BorderSide(color: PdaColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        labelStyle: bold.copyWith(fontSize: 14, color: PdaColors.ink),
        selectedColor: PdaColors.dark,
        secondaryLabelStyle: bold.copyWith(fontSize: 14, color: Colors.white),
        checkmarkColor: Colors.white,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: PdaColors.primary,
        linearTrackColor: PdaColors.lilac,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: PdaColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: PdaColors.line),
        ),
      ),
      // 목록 줄 이름은 600(얇으면 안 보인다), 아래 줄은 본문 400 진한 글씨.
      listTileTheme: ListTileThemeData(
        iconColor: PdaColors.primary,
        titleTextStyle: base.bodyLarge!.copyWith(
          fontWeight: FontWeight.w600,
          color: PdaColors.ink,
        ),
        subtitleTextStyle: base.bodyMedium!.copyWith(color: PdaColors.body),
      ),
    );
  }
}
