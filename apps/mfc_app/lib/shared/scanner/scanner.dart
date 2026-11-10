import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mobile_camera_scanner.dart';

/// 스캔 한 건을 처리한 결과. 카메라 화면이 진동·문구로 바로 알려 준다.
@immutable
class ScanFeedback {
  const ScanFeedback.ok([this.message]) : ok = true;
  const ScanFeedback.error(String this.message) : ok = false;

  final bool ok;
  final String? message;
}

typedef ScanHandler = ScanFeedback Function(String code);

/// 카메라 스캐너 어댑터. 전용 PDA 스캐너(브로드캐스트 인텐트)가 정해지면 같은 자리에 구현을 바꿔 끼운다.
/// 키보드 웨지 입력은 [ScanInput] 의 입력칸이 그대로 받는다.
abstract interface class CameraScanner {
  /// 카메라 화면을 연다. 인식할 때마다 [onScan] 을 부른다.
  /// [continuous] 가 false 면 처음 받아들인 코드 뒤에 닫는다.
  Future<void> open(
    BuildContext context, {
    required ScanHandler onScan,
    required String title,
    bool continuous = true,
  });
}

final cameraScannerProvider = Provider<CameraScanner>(
  (_) => const MobileCameraScanner(),
);

/// 같은 코드가 카메라 앞에 머물러 여러 번 인식되는 것을 막는다.
/// 다른 코드는 바로 받는다. 같은 코드는 카메라에서 [window] 동안 안 보였다가 다시 보여야 받는다
/// (같은 상품 두 개를 찍을 때는 한 번 화면 밖으로 뺐다가 다시 비춘다). 비추고 있는 동안은 계속 무시한다.
class ScanDedup {
  ScanDedup({this.window = const Duration(milliseconds: 1500)});

  final Duration window;
  String? _last;
  DateTime? _seenAt;

  bool accept(String code, DateTime now) {
    final c = code.trim();
    if (c.isEmpty) return false;
    final held =
        c == _last && _seenAt != null && now.difference(_seenAt!) < window;
    _last = c;
    _seenAt = now;
    return !held;
  }
}
