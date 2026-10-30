import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'features/auth/presentation/auth_controller.dart';
import 'l10n/gen/app_localizations.dart';
import 'router.dart';

class CustomerApp extends ConsumerWidget {
  const CustomerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 저장된 세션 확인(한 번). 결과는 sessionProvider 로 퍼진다.
    ref.watch(sessionRestoreProvider);
    return _app(ref);
  }

  Widget _app(WidgetRef ref) => MaterialApp.router(
    onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
    theme: PmartTheme.light(),
    darkTheme: PmartTheme.dark(),
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
  );
}
