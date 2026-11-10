import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import 'providers.dart';

/// 증빙 사진(격리·폐기 판정). 안드로이드 카메라로 찍어 올리고 참조(evidenceRef)를 돌려준다.
/// 실제 촬영·업로드는 패키지(예: image_picker)와 업로드 경로(BR-52 R18)가 필요해 아직 없다 —
/// 목 모드는 더미 참조를 준다.
abstract interface class EvidenceCamera {
  /// 찍었으면 증빙 참조, 취소·불가면 null.
  Future<String?> capture(BuildContext context, {required String purpose});

  /// 이 기기·빌드에서 찍을 수 있는지.
  bool get available;
}

final evidenceCameraProvider = Provider<EvidenceCamera>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockEvidenceCamera(),
    PmartEnv.local => const UnavailableEvidenceCamera(),
  },
);

/// 목: 누르면 바로 더미 사진 참조.
final class MockEvidenceCamera implements EvidenceCamera {
  int _seq = 0;

  @override
  bool get available => true;

  @override
  Future<String?> capture(
    BuildContext context, {
    required String purpose,
  }) async => 'EVD-mock-${++_seq}';
}

/// 촬영 패키지 승인 전 — 찍을 수 없다(화면이 안내한다).
final class UnavailableEvidenceCamera implements EvidenceCamera {
  const UnavailableEvidenceCamera();

  @override
  bool get available => false;

  @override
  Future<String?> capture(
    BuildContext context, {
    required String purpose,
  }) async => null;
}
