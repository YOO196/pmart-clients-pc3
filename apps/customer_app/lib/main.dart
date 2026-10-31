import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_map_sdk/kakao_map_sdk.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'app.dart';
import 'features/address/presentation/map_pick_screen.dart' show kakaoNativeAppKey;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initPmartFormatting();
  // 카카오 지도는 키가 있을 때만 켠다(빌드 때 --dart-define-from-file=.secrets/customer.env). 키는 로그에 남기지 않는다.
  if (kakaoNativeAppKey.isNotEmpty) {
    await KakaoMapSdk.instance.initialize(kakaoNativeAppKey);
  }
  runApp(
    // Riverpod 3 의 자동 재시도를 끈다. 재시도 규칙은 pmart_core(429·retryable)만 따른다.
    ProviderScope(retry: (_, _) => null, child: const CustomerApp()),
  );
}
