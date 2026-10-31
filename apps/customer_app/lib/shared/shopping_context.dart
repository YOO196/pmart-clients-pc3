import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../features/address/presentation/address_controller.dart';
import '../features/auth/domain/auth.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/catalog/data/mock_catalog_repository.dart';
import 'providers.dart';

/// 현재 쇼핑 주소의 담당 센터. 둘러보기·장바구니 조회의 `mfcId`.
///
/// 회원은 `GET /me/addresses` 의 쇼핑 컨텍스트, 비회원은 고른 비회원 배송지의 판정 센터.
/// 비회원이 배송지를 아직 등록하지 않았으면 목에서만 기본 센터를 쓰고, local 은 null(취급 표시 없음).
/// 이 값이 바뀌면 이를 지켜보는 조회가 새로 시작되고, 이전 센터의 늦은 응답은 버려진다.
final currentMfcIdProvider = Provider<String?>((ref) {
  final mfcId = ref.watch(
    addressBookProvider.select((v) => v.value?.context.mfcId),
  );
  if (ref.watch(sessionProvider) is MemberSession) return mfcId;
  final hasGuestAddress = ref.watch(
    addressBookProvider.select((v) => v.value?.addresses.isNotEmpty ?? false),
  );
  if (hasGuestAddress) return mfcId;
  return switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockCatalogRepository.mfcId,
    PmartEnv.local => null,
  };
});
