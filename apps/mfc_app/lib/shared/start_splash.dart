import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 앱을 켠 직후 세션을 되살리는 동안 — 픽PDA 시작 그림(사용자 지시 2026-11-20, 원본 tool/icon/pick_pda_splash.png).
/// 배경색은 Android 시작 화면(`splash_background`)과 같아 그림이 뜨기 전에도 이어 보인다.
class StartSplashScreen extends StatelessWidget {
  const StartSplashScreen({super.key});

  static const background = Color(0xFFE6D8FC);
  static const image = 'assets/images/splash.jpg';

  @override
  Widget build(BuildContext context) => const AnnotatedRegion(
    value: SystemUiOverlayStyle.dark,
    child: Scaffold(
      resizeToAvoidBottomInset: false,
      key: ValueKey('start-splash'),
      backgroundColor: background,
      body: SizedBox.expand(
        child: Image(
          image: AssetImage(image),
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      ),
    ),
  );
}
