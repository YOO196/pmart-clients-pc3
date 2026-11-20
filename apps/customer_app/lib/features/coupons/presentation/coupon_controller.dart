import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart';
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/coupon_repository.dart';
import '../domain/coupon.dart';

final couponRepositoryProvider = Provider<CouponRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockCouponRepository(),
    PmartEnv.local => ApiCouponRepository(ref.watch(dioProvider)),
  },
);

/// 지금 쓸 수 있는 내 쿠폰(`GET /me/coupons?status=AVAILABLE`). 비회원이면 null — 부르지 않는다.
/// 주문서 "N개 보유"·쿠폰 고르기가 함께 본다. 조회 실패는 "쿠폰 없음"이 아니다(오류로 둔다).
final availableCouponsProvider = FutureProvider.autoDispose<List<Coupon>?>((
  ref,
) async {
  if (ref.watch(sessionProvider) is! MemberSession) return null;
  return ref
      .watch(couponRepositoryProvider)
      .myCoupons(status: CouponStatus.available);
});

/// 사용·만료된 쿠폰(전부 받아 AVAILABLE 을 뺀다 — 계약은 상태 하나 또는 전부).
final pastCouponsProvider = FutureProvider.autoDispose<List<Coupon>?>((
  ref,
) async {
  if (ref.watch(sessionProvider) is! MemberSession) return null;
  final all = await ref.watch(couponRepositoryProvider).myCoupons();
  return [
    for (final c in all)
      if (c.status != CouponStatus.available) c,
  ];
});

/// 지금 받을 수 있는 쿠폰 행사. 비회원이면 null.
final couponCampaignsProvider =
    FutureProvider.autoDispose<List<CouponCampaign>?>((ref) async {
      if (ref.watch(sessionProvider) is! MemberSession) return null;
      return ref.watch(couponRepositoryProvider).campaigns();
    });

/// 쿠폰 받기 한 번의 결과. 서버가 201 을 준 뒤에만 [CouponDownloaded].
sealed class CouponDownloadResult {
  const CouponDownloadResult();
}

final class CouponDownloaded extends CouponDownloadResult {
  const CouponDownloaded(this.coupon);

  final Coupon coupon;
}

/// 서버가 거절했다(COUPON_LIMIT_REACHED·COUPON_SOLD_OUT·NOT_ACTIVE 등 — [code] 로만 나눈다).
final class CouponDownloadRejected extends CouponDownloadResult {
  const CouponDownloadRejected(this.code);

  final String code;
}

/// 받았는지 모른다(같은 키로 다시 보내도 모름) — 쿠폰함을 다시 읽어 확인한다.
final class CouponDownloadUnknown extends CouponDownloadResult {
  const CouponDownloadUnknown();
}

final class CouponDownloadFailed extends CouponDownloadResult {
  const CouponDownloadFailed();
}

/// 쿠폰 받기. 결과를 모르면 같은 키로 한 번 더 보낸다(같은 키 = 같은 결과).
/// 끝나면 행사 목록·쿠폰함을 다시 읽는다(받은 수·남은 수량은 서버 값으로만 바뀐다).
Future<CouponDownloadResult> downloadCoupon(
  WidgetRef ref,
  String promotionId,
) async {
  final repo = ref.read(couponRepositoryProvider);
  final key = IdempotencyKey.generate();
  CouponDownloadResult result;
  try {
    try {
      result = CouponDownloaded(await repo.download(promotionId, key: key));
    } on UnknownResultFailure {
      result = CouponDownloaded(await repo.download(promotionId, key: key));
    }
  } on UnknownResultFailure {
    result = const CouponDownloadUnknown();
  } on ProblemFailure catch (f) {
    result = CouponDownloadRejected(f.problem.code);
  } on PmartFailure {
    result = const CouponDownloadFailed();
  }
  ref
    ..invalidate(couponCampaignsProvider)
    ..invalidate(availableCouponsProvider);
  return result;
}
