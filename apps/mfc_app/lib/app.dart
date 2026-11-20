import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'l10n/gen/app_localizations.dart';
import 'router.dart';
import 'shared/pda_theme.dart';
import 'shared/providers.dart';

class MfcApp extends ConsumerWidget {
  const MfcApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
    // LAN 앱도 debug 빌드라 오른쪽 위 "DEBUG" 띠가 앱바 버튼을 가렸다.
    debugShowCheckedModeBanner: false,
    // PDA 시안(2026-11-19) 보라 테마. 현장은 밝은 화면만 쓴다(어두운 테마 없음).
    theme: PdaTheme.light(),
    themeMode: ThemeMode.light,
    locale: const Locale('ko'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      PmartUiLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    routerConfig: ref.watch(routerProvider),
    // 목업 앱은 화면 맨 위에 주황 띠(실서버 앱과 구별 — 사용자 2026-11-20). 웹 미리보기는 안드로이드 폰 크기로 그린다.
    builder: (context, child) {
      var c = child!;
      if (ref.watch(envProvider) == PmartEnv.mock) c = MockStrip(child: c);
      return kIsWeb ? PhoneFrame(child: c) : c;
    },
  );
}

/// 웹 미리보기용 폰 화면(412×915dp, 흔한 안드로이드 폰). 창이 더 작으면 그 크기에 맞춘다.
class PhoneFrame extends StatelessWidget {
  const PhoneFrame({super.key, required this.child});

  static const size = Size(412, 915);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final w = mq.size.width < size.width ? mq.size.width : size.width;
    final h = mq.size.height < size.height ? mq.size.height : size.height;
    return ColoredBox(
      color: const Color(0xFF2B2B2B),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: w,
            height: h,
            child: MediaQuery(
              data: mq.copyWith(size: Size(w, h)),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 목업 앱 표시 — 상태 표시줄 아래 주황 띠 한 줄. 모든 화면 위에 늘 보인다(앱 이름·아이콘도 따로 — build.gradle.kts).
class MockStrip extends StatelessWidget {
  const MockStrip({super.key, required this.child});

  static const color = Color(0xFFFF9F1C);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Column(
      children: [
        ColoredBox(
          key: const ValueKey('mock-strip'),
          color: color,
          child: Padding(
            padding: EdgeInsets.only(top: mq.padding.top),
            child: SizedBox(
              height: 24,
              child: Center(
                child: Text(
                  AppLocalizations.of(context).mockAppStrip,
                  style: const TextStyle(
                    fontFamily: PdaTheme.fontFamily,
                    color: Color(0xFF3B2300),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }
}
