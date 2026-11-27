import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'line_icons.dart';
import 'ui_state_view.dart' show PmartStateStyle;

/// 고객 앱 브랜드 색(연보라, 사용자 결정 2026-11-11).
///
/// 레퍼런스 앱의 브랜드 색·일러스트는 쓰지 않는다(docs/apps/customer-app-design-review.md §5).
/// 화면에서는 되도록 `Theme.of(context).colorScheme` 을 쓰고, 여기 값은 테마를 만드는 데만 쓴다.
abstract final class PmartBrand {
  /// 주 색. 흰 글자를 올리는 버튼·선택 표시(명암비 4.5:1 이상).
  static const violet = Color(0xFF6A4EE0);

  /// 연보라(브랜드 바탕). 배너·선택된 칩·강조 바탕.
  static const lavender = Color(0xFFE9E3FF);

  /// 아주 옅은 연보라. 화면 구획 바탕.
  static const lavenderMist = Color(0xFFF7F5FF);

  /// 연보라 위 글자·아이콘.
  static const deepViolet = Color(0xFF2B1B73);
}

/// 간격(4의 배수). 화면 좌우 여백은 [page].
abstract final class PmartSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// 화면 좌우 여백
  static const page = 16.0;
}

/// 모서리 반경.
abstract final class PmartRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

/// 고객 앱 테마(연보라). 라이더·MFC 앱은 [PmartTheme] 을 그대로 쓴다.
abstract final class PmartCustomerTheme {
  /// [fontFamily] 는 앱이 등록한 글꼴 이름(고객 앱은 Pretendard). 없으면 기기 기본 글꼴.
  static ThemeData light({String? fontFamily}) =>
      _build(_lightScheme, fontFamily);

  static ThemeData dark({String? fontFamily}) =>
      _build(_darkScheme, fontFamily);

  static final ColorScheme _lightScheme =
      ColorScheme.fromSeed(
        seedColor: PmartBrand.violet,
        brightness: Brightness.light,
      ).copyWith(
        primary: PmartBrand.violet,
        onPrimary: Colors.white,
        primaryContainer: PmartBrand.lavender,
        onPrimaryContainer: PmartBrand.deepViolet,
        secondary: const Color(0xFF645A8F),
        onSecondary: Colors.white,
        secondaryContainer: const Color(0xFFEFEAFB),
        onSecondaryContainer: const Color(0xFF2A2350),
        // 강조(새 상품·알림 점 등 주 색과 구분해야 하는 작은 표시)
        tertiary: const Color(0xFFD9457A),
        onTertiary: Colors.white,
        tertiaryContainer: const Color(0xFFFFE3EC),
        onTertiaryContainer: const Color(0xFF5C0F2E),
        surface: Colors.white,
        // 회색은 레퍼런스처럼 중립색(보라 기를 섞지 않는다). 보라는 주 색에만 쓴다.
        onSurface: const Color(0xFF1F1F23),
        onSurfaceVariant: const Color(0xFF6B6B73),
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: const Color(0xFFFAFAFB),
        surfaceContainer: const Color(0xFFF3F4F6),
        surfaceContainerHigh: const Color(0xFFF1F1F4),
        surfaceContainerHighest: const Color(0xFFE9E9ED),
        outline: const Color(0xFF9A9AA3),
        outlineVariant: const Color(0xFFE4E4E9),
        surfaceTint: Colors.transparent,
      );

  static final ColorScheme _darkScheme =
      ColorScheme.fromSeed(
        seedColor: PmartBrand.violet,
        brightness: Brightness.dark,
      ).copyWith(
        primary: const Color(0xFFB9A8FF),
        onPrimary: const Color(0xFF24145F),
        primaryContainer: const Color(0xFF41308F),
        onPrimaryContainer: PmartBrand.lavender,
        surfaceTint: Colors.transparent,
      );

  static ThemeData _build(ColorScheme scheme, String? fontFamily) {
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: fontFamily,
      // 화면 전환은 상품상세처럼 오른쪽에서 밀려 들어오고 뒤로 가면 오른쪽으로 빠진다(사용자 2026-11-21).
      // 전체 화면 창(fullscreenDialog — 결제창 등)은 아래에서 올라온다. 아래 탭바 전환·가운데 창·시트는 그대로.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
    final text = _text(base.textTheme, scheme);
    const buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(PmartRadius.sm)),
    );
    // 글꼴 정보를 테마 글자 스타일에서 이어받는다(버튼은 textStyle 을 합치지 않고 그대로 쓴다).
    final buttonText = text.labelLarge!.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w700,
    );

    return base.copyWith(
      // 상태 화면(불러오는 중·오류)을 레퍼런스 모양으로(고객 앱만)
      extensions: const [PmartStateStyle(reference: true)],
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.standard,
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (_) =>
            const PmartLineIcon(PmartLineIcons.back, size: 23),
      ),
      splashFactory: InkSparkle.splashFactory,
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        // 스크롤해도 색이 바뀌지 않게(연보라 테마에서 회색 띠로 보인다). 대신 얇은 그림자.
        scrolledUnderElevation: 0.5,
        shadowColor: scheme.outlineVariant,
        surfaceTintColor: Colors.transparent,
        // 레퍼런스(2026-11-20, 머리줄 150장 모아 봄): 대부분 가운데 제목(고객센터·장바구니·주문하기·주문상세·리뷰관리 등),
        // 높이 약 56dp, ← 가운데 약 23dp. 왼쪽 정렬인 화면(주소·환경설정·문의하기·주문내역)은 centerTitle: false + titleSpacing: pmartLeftTitleSpacing 로 덮는다.
        centerTitle: true,
        toolbarHeight: 56,
        leadingWidth: 46,
        // 레퍼런스 머리줄 제목(장바구니·카테고리 목록 등)은 보통 굵기(2026-11-21 비교). 주문·고객센터처럼 굵은 화면은 그 화면에서 굵게.
        titleTextStyle: text.titleMedium?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PmartRadius.lg),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: buttonShape,
          textStyle: buttonText,
          disabledBackgroundColor: scheme.surfaceContainerHighest,
          disabledForegroundColor: scheme.onSurfaceVariant.withValues(
            alpha: 0.6,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 44),
          shape: buttonShape,
          side: BorderSide(color: scheme.outlineVariant, width: 1.2),
          foregroundColor: scheme.onSurface,
          textStyle: buttonText.copyWith(fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: text.labelLarge),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: scheme.onSurface),
      ),
      chipTheme: ChipThemeData(
        showCheckmark: false,
        backgroundColor: scheme.surface,
        selectedColor: scheme.primary,
        disabledColor: scheme.surfaceContainerHigh,
        side: BorderSide(color: scheme.outlineVariant),
        shape: const StadiumBorder(),
        labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurface),
        secondaryLabelStyle: text.bodyMedium?.copyWith(
          color: scheme.onPrimary,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 52,
        elevation: 0,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            // 레퍼런스 하단 탭(태블릿 나란히 보기 2026-11-26): 아이콘 크게·선 굵게, 글자 굵게.
            size: 24,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurface,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium!.copyWith(
            fontSize: 10.5,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurface,
          ),
        ),
      ),
      // 입력칸: 흰 바탕 + 얇은 테두리(레퍼런스). 초점이 오면 진한 테두리.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outlineVariant, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.onSurface, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
        hintStyle: text.bodyMedium?.copyWith(
          fontSize: 14,
          color: scheme.outline,
        ),
        labelStyle: text.bodyMedium?.copyWith(
          fontSize: 14,
          color: scheme.onSurfaceVariant,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        subtitleTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(PmartRadius.xl),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        // 레퍼런스 확인 창(9-1 주문취소·5-3 배달팁): 모서리 약 20dp, 폭 280dp, 제목 18sp 굵게, 본문 14sp(2026-11-21 글자 폭으로 다시 잼)
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        titleTextStyle: text.titleMedium?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: text.bodyMedium?.copyWith(
          fontSize: 14,
          color: scheme.onSurfaceVariant,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PmartRadius.md),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.primaryContainer,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: scheme.tertiary,
        textColor: scheme.onTertiary,
      ),
    );
  }

  /// 굵기 단계: 제목·금액 700, 구획 제목 700, 버튼·라벨 600, 본문 400.
  /// 자간은 레퍼런스처럼 살짝 좁힌다(-0.2). 줄 높이는 본문 1.45.
  static TextTheme _text(TextTheme t, ColorScheme scheme) {
    TextStyle? s(
      TextStyle? base,
      double size,
      FontWeight weight, {
      double height = 1.35,
      Color? color,
    }) => base?.copyWith(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: -0.2,
      color: color ?? scheme.onSurface,
    );
    return t.copyWith(
      headlineMedium: s(t.headlineMedium, 24, FontWeight.w800, height: 1.25),
      headlineSmall: s(t.headlineSmall, 20, FontWeight.w800, height: 1.3),
      titleLarge: s(t.titleLarge, 18, FontWeight.w800, height: 1.3),
      titleMedium: s(t.titleMedium, 15.5, FontWeight.w700),
      titleSmall: s(t.titleSmall, 14, FontWeight.w700),
      bodyLarge: s(t.bodyLarge, 15, FontWeight.w400, height: 1.45),
      // 레퍼런스와 같은 글자로 재면 14sp(2026-11-21)
      bodyMedium: s(t.bodyMedium, 14, FontWeight.w400, height: 1.45),
      bodySmall: s(
        t.bodySmall,
        12,
        FontWeight.w400,
        height: 1.4,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: s(t.labelLarge, 14, FontWeight.w600),
      labelMedium: s(t.labelMedium, 12.5, FontWeight.w600),
      labelSmall: s(t.labelSmall, 11.5, FontWeight.w600),
    );
  }
}
