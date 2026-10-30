import 'package:dio/dio.dart';
import 'package:pmart_api_product/pmart_api_product.dart' as pd;
import 'package:pmart_api_product_content/pmart_api_product_content.dart' as pc;
import 'package:pmart_api_search/pmart_api_search.dart' as sr;
import 'package:pmart_api_storefront/pmart_api_storefront.dart' as sf;
import 'package:pmart_core/pmart_core.dart';

import '../domain/catalog.dart';

/// 둘러보기(홈·카테고리·검색·상품 상세). 실패는 [PmartFailure] 로 던진다.
abstract interface class CatalogRepository {
  Future<HomeView> home({String? mfcId, HomeTab? tab});

  /// 영역 하나만 다시 조회한다(UNAVAILABLE 영역 재시도·더보기).
  /// 홈 구성이 바뀌었으면 `LAYOUT_VERSION_CHANGED` [ProblemFailure].
  Future<HomeSection> section(
    HomeSection section, {
    required int layoutVersion,
    String? mfcId,
  });

  Future<List<CategoryNode>> categories();

  Future<ProductPage> search(
    ProductQuery query, {
    String? mfcId,
    String? cursor,
    CancelToken? cancelToken,
  });

  Future<List<FilterAttribute>> filters(ProductQuery query, {String? mfcId});

  /// 자동완성. 실패해도 직접 검색은 된다(호출자가 빈 제안으로 처리).
  Future<List<String>> suggestions(String keyword);

  Future<ProductDetail> product(String productId, {String? mfcId});
}

/// 실서버 구현(storefront·product·search·product-content).
final class ApiCatalogRepository implements CatalogRepository {
  ApiCatalogRepository(Dio dio)
    : _storefront = sf.PmartApiStorefront(dio: dio).getStorefrontApi(),
      _categories = pd.PmartApiProduct(dio: dio).getCategoriesApi(),
      _search = sr.PmartApiSearch(dio: dio).getSearchApi(),
      _contents = pc.PmartApiProductContent(dio: dio).getProductContentsApi();

  final sf.StorefrontApi _storefront;
  final pd.CategoriesApi _categories;
  final sr.SearchApi _search;
  final pc.ProductContentsApi _contents;

  @override
  Future<HomeView> home({String? mfcId, HomeTab? tab}) async {
    final res = await pmartGuard(
      () => _storefront.getHome(mfcId: mfcId, tab: _tabToContract(tab)),
    );
    return homeFromContract(_body(res.data, 'HomeLayout'));
  }

  @override
  Future<HomeSection> section(
    HomeSection section, {
    required int layoutVersion,
    String? mfcId,
  }) async {
    final res = await pmartGuard(
      () => _storefront.listSectionItems(
        sectionId: section.sectionId,
        mfcId: mfcId,
        layoutVersion: layoutVersion,
      ),
    );
    return sectionItemsFromContract(section, _body(res.data, 'SectionItems'));
  }

  @override
  Future<List<CategoryNode>> categories() async {
    final res = await pmartGuard(() => _categories.getCategoryTree());
    return categoriesFromContract(_body(res.data, 'CategoryTree'));
  }

  @override
  Future<ProductPage> search(
    ProductQuery query, {
    String? mfcId,
    String? cursor,
    CancelToken? cancelToken,
  }) async {
    final res = await pmartGuard(
      () => _search.searchProducts(
        q: query.keyword,
        categoryId: query.categoryId,
        mfcId: mfcId,
        sort: _sortToContract(query.sort),
        filters: query.filters.isEmpty ? null : query.filters.toList(),
        cursor: cursor,
        cancelToken: cancelToken,
      ),
    );
    return searchFromContract(_body(res.data, 'SearchResult'));
  }

  @override
  Future<List<FilterAttribute>> filters(
    ProductQuery query, {
    String? mfcId,
  }) async {
    final res = await pmartGuard(
      () => _search.getSearchFilters(
        q: query.keyword,
        categoryId: query.categoryId,
        mfcId: mfcId,
      ),
    );
    return filtersFromContract(_body(res.data, 'SearchFilters'));
  }

  @override
  Future<List<String>> suggestions(String keyword) async {
    final res = await pmartGuard(
      () => _search.getSearchSuggestions(q: keyword),
    );
    return res.data?.keywords ?? const [];
  }

  @override
  Future<ProductDetail> product(String productId, {String? mfcId}) async {
    final res = await pmartGuard(
      () => _contents.getProductContent(productId: productId, mfcId: mfcId),
    );
    return productFromContract(_body(res.data, 'ProductContent'));
  }
}

T _body<T>(T? data, String name) =>
    data ?? (throw ContractViolationFailure('$name 본문 없음'));

/// 핵심 식별 필드가 없으면 계약 위반이다(빈 값으로 메우지 않는다).
T _required<T>(T? value, String field) =>
    value ?? (throw ContractViolationFailure('$field 없음'));

sf.TabKey? _tabToContract(HomeTab? tab) => switch (tab) {
  null => null,
  HomeTab.home => sf.TabKey.HOME,
  HomeTab.ranking => sf.TabKey.RANKING,
  HomeTab.isNew => sf.TabKey.NEW,
};

HomeTab _tabFromContract(sf.TabKey t) => switch (t) {
  sf.TabKey.HOME => HomeTab.home,
  sf.TabKey.RANKING => HomeTab.ranking,
  sf.TabKey.NEW => HomeTab.isNew,
};

sr.SortKey _sortToContract(SortKey s) => switch (s) {
  SortKey.relevance => sr.SortKey.RELEVANCE,
  SortKey.popular => sr.SortKey.POPULAR,
  SortKey.newest => sr.SortKey.NEWEST,
  SortKey.priceAsc => sr.SortKey.PRICE_ASC,
  SortKey.priceDesc => sr.SortKey.PRICE_DESC,
  SortKey.rating => sr.SortKey.RATING,
};

SaleState _saleState(String? wire) => switch (wire) {
  'ON_SALE' => SaleState.onSale,
  'TEMPORARILY_SOLD_OUT' => SaleState.temporarilySoldOut,
  'SALE_STOPPED' => SaleState.saleStopped,
  _ => SaleState.unknown,
};

ProductTile _tileFromDisplay(sf.DisplayItem i) => ProductTile(
  productId: _required(i.productId, 'DisplayItem.productId'),
  name: _required(i.name, 'DisplayItem.name'),
  imageUrl: i.imageUrl,
  representativeSku: i.representativeSku,
  basePrice: i.basePrice,
  saleState: _saleState(i.saleState?.value),
  carried: i.carried,
  rating: i.rating?.toDouble(),
  reviewCount: i.reviewCount,
  badge: switch (i.badge) {
    sf.DisplayItemBadgeEnum.NEW => DisplayBadge.isNew,
    sf.DisplayItemBadgeEnum.RANK => DisplayBadge.rank,
    _ => DisplayBadge.none,
  },
  rank: i.rank,
);

SectionKind _kind(sf.SectionKindEnum? k) => switch (k) {
  sf.SectionKindEnum.THEME => SectionKind.theme,
  sf.SectionKindEnum.SEASON => SectionKind.season,
  sf.SectionKindEnum.WEEKLY_PICK => SectionKind.weeklyPick,
  sf.SectionKindEnum.NEW => SectionKind.isNew,
  sf.SectionKindEnum.RANKING => SectionKind.ranking,
  sf.SectionKindEnum.HIGH_RATING => SectionKind.highRating,
  sf.SectionKindEnum.IN_PROGRESS_ORDER => SectionKind.inProgressOrder,
  null => SectionKind.unknown,
};

HomeView homeFromContract(sf.HomeLayout h) => HomeView(
  layoutVersion: h.layoutVersion,
  tabs: [for (final t in h.tabs ?? const <sf.TabKey>[]) _tabFromContract(t)],
  banners: [
    for (final b in h.banners ?? const <sf.Banner>[])
      HomeBanner(
        bannerId: _required(b.bannerId, 'Banner.bannerId'),
        imageUrl: b.imageUrl,
        altText: b.altText,
      ),
  ],
  sections: [
    for (final s in h.sections)
      HomeSection(
        sectionId: _required(s.sectionId, 'Section.sectionId'),
        kind: _kind(s.kind),
        title: s.title ?? '',
        subtitle: s.subtitle,
        // state 가 없으면 성공으로 보지 않는다. 영역 하나만 실패로 표시한다.
        available: s.state == sf.SectionStateEnum.OK,
        items: arrangeForDisplay(
          (s.items ?? const <sf.DisplayItem>[]).map(_tileFromDisplay),
        ),
        nextCursor: s.nextCursor,
      ),
  ],
);

HomeSection sectionItemsFromContract(
  HomeSection base,
  sf.ListSectionItems200Response r,
) => HomeSection(
  sectionId: base.sectionId,
  kind: base.kind,
  title: base.title,
  subtitle: base.subtitle,
  available: true,
  items: arrangeForDisplay(
    (r.items ?? const <sf.DisplayItem>[]).map(_tileFromDisplay),
  ),
  nextCursor: r.page?.nextCursor,
);

List<CategoryNode> categoriesFromContract(pd.GetCategoryTree200Response r) {
  final nodes = [
    for (final n in r.nodes ?? const <pd.CategoryNode>[])
      if (n.exposed != false) n,
  ]..sort((a, b) => (a.sortOrder ?? 0).compareTo(b.sortOrder ?? 0));
  return [
    for (final n in nodes)
      CategoryNode(
        categoryId: _required(n.categoryId, 'CategoryNode.categoryId'),
        parentId: n.parentId,
        // 계약 CategoryLevel(상위>하위>칩1>칩2, ADR-0015) → 깊이 1~4
        depth: switch (n.level) {
          pd.CategoryLevel.TOP => 1,
          pd.CategoryLevel.SUB => 2,
          pd.CategoryLevel.CHIP1 => 3,
          pd.CategoryLevel.CHIP2 => 4,
        },
        name: n.name,
      ),
  ];
}

ProductPage searchFromContract(sr.SearchResult r) => ProductPage(
  items: arrangeForDisplay(
    r.items.map(
      (h) => ProductTile(
        productId: _required(h.productId, 'SearchHit.productId'),
        name: _required(h.name, 'SearchHit.name'),
        imageUrl: h.imageUrl,
        representativeSku: h.representativeSku,
        basePrice: h.basePrice,
        saleState: _saleState(h.saleState?.value),
        carried: h.carried,
        rating: h.rating?.toDouble(),
        reviewCount: h.reviewCount,
      ),
    ),
  ),
  nextCursor: r.page.nextCursor,
  total: r.total,
);

List<FilterAttribute> filtersFromContract(sr.GetSearchFilters200Response r) => [
  for (final a in r.attributes ?? const <sr.FilterAttribute>[])
    FilterAttribute(
      key: _required(a.key, 'FilterAttribute.key'),
      label: a.label ?? a.key!,
      multiSelect: a.multiSelect ?? false,
      values: [
        for (final v in a.values ?? const <sr.FilterAttributeValuesInner>[])
          FilterValue(
            value: _required(v.value, 'FilterAttribute.values.value'),
            label: v.label ?? v.value!,
            count: v.count,
          ),
      ],
    ),
];

ProductDetail productFromContract(pc.ProductContent c) {
  final images = [...?c.images]
    ..sort((a, b) => (a.sortOrder ?? 0).compareTo(b.sortOrder ?? 0));
  final rating = c.rating;
  return ProductDetail(
    productId: _required(c.productId, 'ProductContent.productId'),
    name: _required(c.name, 'ProductContent.name'),
    imageUrls: [
      if (c.mainImage?.url case final String url) url,
      for (final i in images)
        if (i.role != pc.ImageRoleEnum.MAIN && i.url != null) i.url!,
    ],
    description: c.description,
    storageGuide: c.storageGuide,
    returnGuide: c.returnGuide,
    notices: c.notices ?? const [],
    categoryPath: c.categoryPath ?? const [],
    rating: (rating?.averageRating != null && rating?.reviewCount != null)
        ? RatingSummary(
            average: rating!.averageRating!.toDouble(),
            count: rating.reviewCount!,
          )
        : null,
    options: [
      for (final o in c.options ?? const <pc.SaleOption>[])
        if (_saleState(o.saleState) != SaleState.saleStopped)
          SaleOption(
            sku: _required(o.sku, 'SaleOption.sku'),
            label: o.label ?? o.sku!,
            unitType: switch (o.unitType) {
              pc.SaleOptionUnitTypeEnum.E => UnitType.each,
              pc.SaleOptionUnitTypeEnum.B => UnitType.bundle,
              null => null,
            },
            unitsPerSku: o.unitsPerSku,
            capacityLabel: o.capacityLabel,
            basePrice: o.price?.basePrice,
            priceVersion: o.price?.priceVersion,
            carried: o.availability?.carried,
            availability:
                _saleState(o.saleState) == SaleState.temporarilySoldOut
                ? Availability.soldOut
                : switch (o.availability?.state) {
                    pc.SaleOptionAvailabilityStateEnum.AVAILABLE =>
                      Availability.available,
                    pc.SaleOptionAvailabilityStateEnum.LOW => Availability.low,
                    pc.SaleOptionAvailabilityStateEnum.SOLD_OUT =>
                      Availability.soldOut,
                    _ => Availability.unknown,
                  },
          ),
    ],
  );
}
