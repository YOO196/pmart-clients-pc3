import 'package:dio/dio.dart';
import 'package:pmart_api_customer/pmart_api_customer.dart' as api;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;
import '../domain/wishlist.dart';

/// 찜(customer 0.13.0 `wishlist`, ADR-0081). 회원만 — 비회원은 부르지 않는다.
abstract interface class WishlistRepository {
  /// `GET /me/wishlist-product-ids` — 하트 표시용 전체 ID(최근 찜한 순).
  Future<List<String>> productIds();

  /// `GET /me/wishlist-items?page=&size=` — 최근 찜한 순.
  Future<WishlistPage> list({int page = 0, int size = 20});

  /// `PUT /me/wishlist-items/{productId}` — 이미 찜했으면 그대로 200. 실패는 [PmartFailure]
  /// (422 WISHLIST_LIMIT_EXCEEDED·409 INVALID_STATE). 같은 [key] 재전송은 다시 넣지 않는다.
  Future<void> add(String productId, {required IdempotencyKey key});

  /// `DELETE /me/wishlist-items/{productId}` — 없어도 204.
  Future<void> remove(String productId, {required IdempotencyKey key});
}

final class ApiWishlistRepository implements WishlistRepository {
  ApiWishlistRepository(Dio dio)
    : _api = api.PmartApiCustomer(dio: dio).getWishlistApi();

  final api.WishlistApi _api;

  @override
  Future<List<String>> productIds() async {
    final res = await pmartGuard(() => _api.listWishlistProductIds());
    final body =
        res.data ?? (throw const ContractViolationFailure('찜 ID 목록 본문 없음'));
    return body.productIds;
  }

  @override
  Future<WishlistPage> list({int page = 0, int size = 20}) async {
    final res = await pmartGuard(
      () => _api.listWishlistItems(page: page, size: size),
    );
    return wishlistPageFromContract(
      res.data ?? (throw const ContractViolationFailure('찜 목록 본문 없음')),
    );
  }

  @override
  Future<void> add(String productId, {required IdempotencyKey key}) async {
    await pmartGuard(
      () => _api.addWishlistItem(
        productId: productId,
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        extra: commandOptions(key).extra,
      ),
    );
  }

  @override
  Future<void> remove(String productId, {required IdempotencyKey key}) async {
    await pmartGuard(
      () => _api.removeWishlistItem(
        productId: productId,
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        extra: commandOptions(key).extra,
      ),
    );
  }
}

WishlistPage wishlistPageFromContract(api.ListWishlistItems200Response r) =>
    WishlistPage(
      total: r.total,
      limit: r.limit,
      items: [
        for (final w in r.items)
          WishlistItem(
            productId: w.productId,
            addedAt: w.addedAt,
            saleState: WishSaleState.fromWire(w.saleState.value),
            name: switch (w.name?.trim()) {
              null || '' => null,
              final n => n,
            },
            imageUrl: switch (w.imageUrl?.trim()) {
              null || '' => null,
              final u => u,
            },
            price: w.price,
          ),
      ],
    );

/// ⚠ 화면 개발·시험용 목. 데이터는 계약 JSON(`WishlistItem`)으로 둔다.
final class MockWishlistRepository implements WishlistRepository {
  MockWishlistRepository({
    this.latency = const Duration(milliseconds: 200),
    this.limit = 200,
    List<Map<String, Object?>>? seed,
    DateTime Function()? now,
  }) : items = seed ?? seedItems(),
       _now = now ?? DateTime.now;

  final Duration latency;
  final int limit;
  final DateTime Function() _now;

  /// 찜한 것(최근 것이 앞). 계약 `WishlistItem` JSON.
  final List<Map<String, Object?>> items;

  /// 다음 요청(찜·빼기)을 이 오류로 실패시킨다.
  PmartFailure? failNext;

  /// 다음 조회(ID·목록)를 실패시킨다.
  PmartFailure? failNextRead;

  final addKeys = <String>[];
  final removeKeys = <String>[];
  int idReads = 0;

  /// 목 상품(카탈로그 목과 같은 ID)의 표시 값.
  static const _catalog = <String, ({String name, int price, String state})>{
    'P-0001': (name: '서울우유 1L', price: 2980, state: 'ON_SALE'),
    'P-0002': (name: '그릭요거트 플레인 400g', price: 5980, state: 'ON_SALE'),
    'P-0003': (name: '제주 감귤 1kg', price: 7900, state: 'ON_SALE'),
    'P-0004': (name: '친환경 대추방울토마토 500g', price: 4980, state: 'SOLD_OUT'),
    'P-0005': (name: '감자칩 오리지널 110g', price: 1980, state: 'ON_SALE'),
    'P-0006': (name: '저지방 우유 900mL', price: 2780, state: 'ON_SALE'),
    'P-0008': (name: '단종 예정 과자 80g', price: 1500, state: 'ENDED'),
  };

  static Map<String, Object?> _json(String productId, String addedAt) =>
      switch (_catalog[productId]) {
        final c? => {
          'productId': productId,
          'addedAt': addedAt,
          'name': c.name,
          'imageUrl': null,
          'price': c.price,
          'saleState': c.state,
        },
        // 상품 정보를 못 읽은 것 — 이름·가격 없이 UNKNOWN
        null => {
          'productId': productId,
          'addedAt': addedAt,
          'name': null,
          'imageUrl': null,
          'price': null,
          'saleState': 'UNKNOWN',
        },
      };

  static List<Map<String, Object?>> seedItems() => [
    _json('P-0002', '2026-10-23T03:00:00Z'),
    _json('P-0004', '2026-10-22T03:00:00Z'),
  ];

  Future<void> _wait() => Future<void>.delayed(latency);

  void _failRead() {
    if (failNextRead case final f?) {
      failNextRead = null;
      throw f;
    }
  }

  @override
  Future<List<String>> productIds() async {
    await _wait();
    idReads++;
    _failRead();
    return [for (final w in items) w['productId']! as String];
  }

  @override
  Future<WishlistPage> list({int page = 0, int size = 20}) async {
    await _wait();
    _failRead();
    final start = (page * size).clamp(0, items.length);
    final end = (start + size).clamp(0, items.length);
    return wishlistPageFromContract(
      api.ListWishlistItems200Response.fromJson({
        'items': [
          for (final w in items.sublist(start, end)) Map<String, dynamic>.of(w),
        ],
        'total': items.length,
        'limit': limit,
      }),
    );
  }

  @override
  Future<void> add(String productId, {required IdempotencyKey key}) async {
    await _wait();
    addKeys.add(key.value);
    if (failNext case final f?) {
      failNext = null;
      throw f;
    }
    if (items.any((w) => w['productId'] == productId)) return;
    if (items.length >= limit) {
      throw ProblemFailure(
        Problem(
          status: 422,
          code: WishlistProblemCode.limitExceeded,
          details: [ProblemDetail(field: 'limit', reason: '$limit')],
        ),
      );
    }
    items.insert(0, _json(productId, _now().toUtc().toIso8601String()));
  }

  @override
  Future<void> remove(String productId, {required IdempotencyKey key}) async {
    await _wait();
    removeKeys.add(key.value);
    if (failNext case final f?) {
      failNext = null;
      throw f;
    }
    items.removeWhere((w) => w['productId'] == productId);
  }
}
