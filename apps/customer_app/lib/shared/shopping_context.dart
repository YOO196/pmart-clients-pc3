import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../features/catalog/data/mock_catalog_repository.dart';
import 'providers.dart';

/// 현재 쇼핑 주소의 담당 센터. 둘러보기 조회의 `mfcId`.
///
/// 주소 단계에서 `GET /me/shopping-context` 결과로 바꾼다. 그 전까지 local 은 null(취급 표시 없음).
final currentMfcIdProvider = Provider<String?>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockCatalogRepository.mfcId,
    PmartEnv.local => null,
  },
);
