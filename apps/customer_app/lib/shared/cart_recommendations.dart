import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart' show PmartFailure;

import '../features/catalog/domain/catalog.dart';
import '../features/catalog/presentation/catalog_providers.dart';
import 'shopping_context.dart' show currentMfcIdProvider;

/// 장바구니 막대를 펼친 시트의 "회원님을 위한 추천 상품"(사용자 새 UI 2026-11-24) — 한 번에 6개(3칸 × 2줄).
///
/// 개인 추천 API 가 계약에 없어(BR-98) 지금은 홈 구성의 첫 상품 진열 영역(storefront 편성 — 서버 값)을 쓴다.
/// [다른 추천 상품 보기]는 다음 6개, 받은 것을 다 보면 그 영역의 다음 묶음(`nextCursor`)을 받고, 끝이면 처음으로.
const cartRecommendationPageSize = 6;

final cartRecommendationsProvider =
    AsyncNotifierProvider.autoDispose<
      CartRecommendationsController,
      List<ProductTile>
    >(CartRecommendationsController.new);

class CartRecommendationsController extends AsyncNotifier<List<ProductTile>> {
  final _pool = <ProductTile>[];
  HomeSection? _section;
  int _layoutVersion = 0;
  String? _cursor;
  int _offset = 0;

  /// 추천으로 쓸 영역: 상품이 있는 첫 영역(진행 중 주문·배너 묶음 제외).
  static HomeSection? pick(HomeView home) => home.sections
      .where(
        (s) =>
            s.available &&
            s.items.isNotEmpty &&
            s.kind != SectionKind.inProgressOrder &&
            s.banners.isEmpty,
      )
      .firstOrNull;

  @override
  Future<List<ProductTile>> build() async {
    final home = await ref.watch(homeProvider.future);
    _section = pick(home);
    _layoutVersion = home.layoutVersion;
    _pool
      ..clear()
      ..addAll(_section?.items ?? const []);
    _cursor = _section?.nextCursor;
    _offset = 0;
    return _page();
  }

  List<ProductTile> _page() => [
    for (var i = 0; i < cartRecommendationPageSize && i < _pool.length; i++)
      _pool[(_offset + i) % _pool.length],
  ];

  /// 다른 추천 상품 보기. 다음 묶음 조회가 실패하면 받은 것 안에서 돈다(빈 목록으로 바꾸지 않는다).
  Future<void> next() async {
    final section = _section;
    if (section == null || _pool.isEmpty) return;
    var offset = _offset + cartRecommendationPageSize;
    if (offset + cartRecommendationPageSize > _pool.length && _cursor != null) {
      try {
        final more = await ref
            .read(catalogRepositoryProvider)
            .section(
              section,
              layoutVersion: _layoutVersion,
              mfcId: ref.read(currentMfcIdProvider),
              cursor: _cursor,
            );
        if (!ref.mounted) return;
        _pool.addAll(more.items);
        _cursor = more.nextCursor;
      } on PmartFailure {
        _cursor = null;
      }
    }
    if (offset >= _pool.length) offset = 0;
    _offset = offset;
    state = AsyncData(_page());
  }
}
