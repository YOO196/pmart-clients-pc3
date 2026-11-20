import 'package:dio/dio.dart';
import 'package:pmart_api_promotion/pmart_api_promotion.dart' as api;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;
import '../domain/coupon.dart';

/// 쿠폰 받기·내 쿠폰함(promotion-service 0.2.0 고객 경로). 회원만 — 비회원은 부르지 않는다.
abstract interface class CouponRepository {
  /// `GET /coupon-campaigns` — 지금 내려받을 수 있는 쿠폰 행사.
  Future<List<CouponCampaign>> campaigns();

  /// `POST /coupon-campaigns/{promotionId}/downloads` → 201 받은 쿠폰. 같은 [key] 는 같은 결과.
  /// 422 COUPON_LIMIT_REACHED·COUPON_SOLD_OUT·NOT_ACTIVE 는 [ProblemFailure].
  Future<Coupon> download(String promotionId, {required IdempotencyKey key});

  /// `GET /me/coupons?status=` — 없으면 전부. AVAILABLE 은 기한 가까운 순, 나머지는 받은 순(최근 먼저).
  Future<List<Coupon>> myCoupons({CouponStatus? status});
}

final class ApiCouponRepository implements CouponRepository {
  ApiCouponRepository(Dio dio)
    : _api = api.PmartApiPromotion(dio: dio).getCouponsApi();

  final api.CouponsApi _api;

  @override
  Future<List<CouponCampaign>> campaigns() async {
    final res = await pmartGuard(() => _api.listCouponCampaigns());
    final body =
        res.data ?? (throw const ContractViolationFailure('쿠폰 행사 본문 없음'));
    return [for (final c in body.items) campaignFromContract(c)];
  }

  @override
  Future<Coupon> download(
    String promotionId, {
    required IdempotencyKey key,
  }) async {
    final res = await pmartGuard(
      () => _api.downloadCoupon(
        promotionId: promotionId,
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        extra: commandOptions(key).extra,
      ),
    );
    return couponFromContract(
      // 2xx 인데 본문이 없으면 받았는지 모른다(같은 키로 다시 보내 확인).
      res.data ?? (throw UnknownResultFailure(requestId: key.value)),
    );
  }

  @override
  Future<List<Coupon>> myCoupons({CouponStatus? status}) async {
    final res = await pmartGuard(
      () => _api.listMyCoupons(
        status: switch (status) {
          CouponStatus.available => 'AVAILABLE',
          CouponStatus.used => 'USED',
          CouponStatus.expired => 'EXPIRED',
          CouponStatus.unknown || null => null,
        },
      ),
    );
    final body =
        res.data ?? (throw const ContractViolationFailure('쿠폰함 본문 없음'));
    return [for (final c in body.items) couponFromContract(c)];
  }
}

CouponDiscount discountFromContract(api.Discount d) => CouponDiscount(
  type: switch (d.type) {
    api.DiscountTypeEnum.RATE => CouponDiscountType.rate,
    api.DiscountTypeEnum.AMOUNT => CouponDiscountType.amount,
  },
  value: d.value,
  maxAmount: d.maxAmount,
);

Coupon couponFromContract(api.Coupon c) => Coupon(
  couponId: c.couponId,
  promotionId: c.promotionId,
  name: c.name,
  discount: discountFromContract(c.discount),
  minOrderAmount: c.minOrderAmount,
  status: CouponStatus.fromWire(c.status.value),
  issuedAt: c.issuedAt,
  validUntil: c.validUntil,
  usedOrderId: c.usedOrderId,
);

CouponCampaign campaignFromContract(api.CouponCampaign c) => CouponCampaign(
  promotionId: c.promotionId,
  name: c.name,
  discount: discountFromContract(c.discount),
  minOrderAmount: c.minOrderAmount,
  perCustomerLimit: c.perCustomerLimit,
  myIssuedCount: c.myIssuedCount,
  remaining: c.remaining,
  endsAt: c.endsAt,
  useDays: c.useDays,
  useUntil: c.useUntil,
);

/// ⚠ 화면 개발·시험용 목. 데이터는 계약 JSON 으로 둔다. 쿠폰 이름·금액은 지어낸 예시다.
final class MockCouponRepository implements CouponRepository {
  MockCouponRepository({
    this.latency = const Duration(milliseconds: 200),
    DateTime Function()? now,
    List<Map<String, Object?>>? campaigns,
    List<Map<String, Object?>>? coupons,
  }) : _now = now ?? DateTime.now,
       campaignJson = campaigns ?? seedCampaigns(),
       couponJson = coupons ?? seedCoupons();

  final Duration latency;
  final DateTime Function() _now;

  /// 계약 `CouponCampaign` JSON.
  final List<Map<String, Object?>> campaignJson;

  /// 계약 `Coupon` JSON(내 쿠폰함).
  final List<Map<String, Object?>> couponJson;

  /// 다음 조회를 실패시킨다.
  PmartFailure? failNextRead;

  /// 다음 내려받기를 실패시킨다.
  PmartFailure? failNextDownload;

  final downloadKeys = <String>[];
  final _byKey = <String, Map<String, Object?>>{};
  var _seq = 0;

  static Map<String, Object?> _amount(int v) => {'type': 'AMOUNT', 'value': v};

  static List<Map<String, Object?>> seedCampaigns() => [
    {
      'promotionId': 'PRM-MOCK-1',
      'name': '[목] 주말 장보기 3천원 할인',
      'discount': _amount(3000),
      'minOrderAmount': 20000,
      'perCustomerLimit': 1,
      'myIssuedCount': 0,
      'remaining': 120,
      'endsAt': '2026-11-30T14:59:59Z',
      'useDays': 7,
      'useUntil': null,
    },
    {
      'promotionId': 'PRM-MOCK-2',
      'name': '[목] 신선식품 10% 할인',
      'discount': {'type': 'RATE', 'value': 10, 'maxAmount': 5000},
      'minOrderAmount': 15000,
      'perCustomerLimit': 1,
      'myIssuedCount': 0,
      'remaining': 0,
      'endsAt': '2026-11-30T14:59:59Z',
      'useDays': null,
      'useUntil': '2026-12-15T14:59:59Z',
    },
  ];

  static List<Map<String, Object?>> seedCoupons() => [
    {
      'couponId': 'CPN-MOCK-1',
      'promotionId': 'PRM-MOCK-9',
      'name': '[목] 첫 주문 7천원 할인',
      'discount': _amount(7000),
      'minOrderAmount': 15000,
      'status': 'AVAILABLE',
      'issuedAt': '2026-11-18T01:00:00Z',
      'validUntil': '2026-11-25T14:59:59Z',
      'usedOrderId': null,
    },
    {
      'couponId': 'CPN-MOCK-2',
      'promotionId': 'PRM-MOCK-8',
      'name': '[목] 전 상품 3천원 할인',
      'discount': _amount(3000),
      'minOrderAmount': 30000,
      'status': 'AVAILABLE',
      'issuedAt': '2026-11-19T01:00:00Z',
      'validUntil': '2026-11-28T14:59:59Z',
      'usedOrderId': null,
    },
    {
      'couponId': 'CPN-MOCK-3',
      'promotionId': 'PRM-MOCK-7',
      'name': '[목] 가을 장보기 2천원 할인',
      'discount': _amount(2000),
      'minOrderAmount': 10000,
      'status': 'USED',
      'issuedAt': '2026-11-02T01:00:00Z',
      'validUntil': '2026-11-09T14:59:59Z',
      'usedOrderId': 'order-seed-1',
    },
    {
      'couponId': 'CPN-MOCK-4',
      'promotionId': 'PRM-MOCK-6',
      'name': '[목] 10월 15% 할인',
      'discount': {'type': 'RATE', 'value': 15, 'maxAmount': 4000},
      'minOrderAmount': 20000,
      'status': 'EXPIRED',
      'issuedAt': '2026-10-10T01:00:00Z',
      'validUntil': '2026-10-31T14:59:59Z',
      'usedOrderId': null,
    },
  ];

  Future<void> _wait() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  void _failRead() {
    if (failNextRead case final f?) {
      failNextRead = null;
      throw f;
    }
  }

  @override
  Future<List<CouponCampaign>> campaigns() async {
    await _wait();
    _failRead();
    return [
      for (final c in campaignJson)
        campaignFromContract(api.CouponCampaign.fromJson({...c})),
    ];
  }

  @override
  Future<Coupon> download(
    String promotionId, {
    required IdempotencyKey key,
  }) async {
    await _wait();
    downloadKeys.add(key.value);
    if (failNextDownload case final f?) {
      failNextDownload = null;
      throw f;
    }
    final saved = _byKey[key.value];
    if (saved != null) return couponFromContract(api.Coupon.fromJson(saved));
    final c = campaignJson.where((c) => c['promotionId'] == promotionId);
    if (c.isEmpty) {
      throw const ProblemFailure(
        Problem(status: 404, code: ProblemCode.notFound),
      );
    }
    final campaign = c.first;
    if ((campaign['myIssuedCount']! as int) >=
        (campaign['perCustomerLimit']! as int)) {
      throw const ProblemFailure(
        Problem(status: 422, code: CouponProblemCode.limitReached),
      );
    }
    if (campaign['remaining'] == 0) {
      throw const ProblemFailure(
        Problem(status: 422, code: CouponProblemCode.soldOut),
      );
    }
    final issued = _now().toUtc();
    final until = switch (campaign['useUntil']) {
      final String u => u,
      _ =>
        issued
            .add(Duration(days: campaign['useDays']! as int))
            .toIso8601String(),
    };
    final coupon = <String, Object?>{
      'couponId': 'CPN-MOCK-D${++_seq}',
      'promotionId': promotionId,
      'name': campaign['name'],
      'discount': campaign['discount'],
      'minOrderAmount': campaign['minOrderAmount'],
      'status': 'AVAILABLE',
      'issuedAt': issued.toIso8601String(),
      'validUntil': until,
      'usedOrderId': null,
    };
    campaign['myIssuedCount'] = (campaign['myIssuedCount']! as int) + 1;
    if (campaign['remaining'] case final int r) campaign['remaining'] = r - 1;
    couponJson.insert(0, coupon);
    _byKey[key.value] = coupon;
    return couponFromContract(api.Coupon.fromJson({...coupon}));
  }

  @override
  Future<List<Coupon>> myCoupons({CouponStatus? status}) async {
    await _wait();
    _failRead();
    final wire = switch (status) {
      CouponStatus.available => 'AVAILABLE',
      CouponStatus.used => 'USED',
      CouponStatus.expired => 'EXPIRED',
      _ => null,
    };
    final list = [
      for (final c in couponJson)
        if (wire == null || c['status'] == wire)
          couponFromContract(api.Coupon.fromJson({...c})),
    ];
    if (status == CouponStatus.available) {
      list.sort((a, b) => a.validUntil.compareTo(b.validUntil));
    }
    return list;
  }

  /// 목 주문서가 쿠폰 할인을 흉내 낼 때 쓰는 표(계약 `Coupon` 값). 서버 계산을 대신하지 않는다.
  Map<String, Object?>? couponJsonOf(String couponId) =>
      couponJson.where((c) => c['couponId'] == couponId).firstOrNull;
}
