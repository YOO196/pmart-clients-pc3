import 'package:dio/dio.dart';
import 'package:pmart_api_pricing/pmart_api_pricing.dart' as pr;
import 'package:pmart_api_product/pmart_api_product.dart' as pd;
import 'package:pmart_api_product_content/pmart_api_product_content.dart' as pc;
import 'package:pmart_api_search/pmart_api_search.dart' as sr;
import 'package:pmart_api_storefront/pmart_api_storefront.dart' as sf;
import 'package:pmart_core/pmart_core.dart';

import '../domain/catalog.dart';

/// 둘러보기(홈·카테고리·검색·상품 상세). 실패는 [PmartFailure] 로 던진다.
abstract interface class CatalogRepository {
  Future<HomeView> home({String? mfcId, HomeTab? tab});

  /// 자리별 배너(storefront 0.9.0 `GET /storefront/banners?placement=` — POPUP 홈 팝업). sortOrder 순.
  Future<List<HomeBanner>> banners({required String placement});

  /// 함께 산 상품(storefront 0.19.0 `GET /storefront/products/{id}/related?kind=BOUGHT_TOGETHER` — BR-100 R5).
  /// 최근 30일 확정 주문에 같이 담긴 상품, 많은 순. 없으면 빈 목록.
  Future<List<ProductTile>> boughtTogether(String productId, {String? mfcId});

  /// MD 탭 내용(storefront 0.9.0 `GET /storefront/custom-tabs/{tabKey}`). 기간이 지나면 404 TAB_NOT_FOUND.
  Future<HomeView> customTab(String tabKey, {String? mfcId});

  /// 영역 하나만 다시 조회한다(UNAVAILABLE 영역 재시도·전체보기). [cursor] 는 다음 묶음.
  /// 홈 구성이 바뀌었으면 `LAYOUT_VERSION_CHANGED` [ProblemFailure].
  Future<HomeSection> section(
    HomeSection section, {
    required int layoutVersion,
    String? mfcId,
    String? cursor,
  });

  Future<List<CategoryNode>> categories();

  /// 카테고리 대표 사진(search 0.13.0 `GET /search/category-images`, BR-89, 로그인 없이) — categoryId → 사진 경로.
  /// 상품이 없는 카테고리는 빠진다(앱 그림으로). 실패는 [PmartFailure].
  Future<Map<String, String>> categoryImages({String? mfcId});

  Future<ProductPage> search(
    ProductQuery query, {
    String? mfcId,
    String? cursor,
    CancelToken? cancelToken,
  });

  Future<List<FilterAttribute>> filters(ProductQuery query, {String? mfcId});

  /// 자동완성. 실패해도 직접 검색은 된다(호출자가 빈 제안으로 처리).
  Future<List<String>> suggestions(String keyword);

  /// 검색 첫 화면의 인기 검색어(search 0.5.2 — `GET /search/suggestions` 를 q 없이). 집계가 없으면 빈 목록.
  Future<List<String>> popularKeywords();

  Future<ProductDetail> product(String productId, {String? mfcId});

  /// `GET /product-contents/{id}/rating-summary`(product-content 0.2.1, 비회원 가능) — 리뷰 등록 사건으로 채우는 서버 집계.
  /// 상세 응답의 `rating` 이 비어 와도(LAN 2026-11-19) 이 값은 있다. 리뷰가 없으면 null. 실패는 [PmartFailure].
  Future<RatingSummary?> ratingSummary(String productId);
}

/// 실서버 구현(storefront·product·search·product-content).
final class ApiCatalogRepository implements CatalogRepository {
  ApiCatalogRepository(Dio dio)
    : _storefront = sf.PmartApiStorefront(dio: dio).getStorefrontApi(),
      _categories = pd.PmartApiProduct(dio: dio).getCategoriesApi(),
      _search = sr.PmartApiSearch(dio: dio).getSearchApi(),
      _contents = pc.PmartApiProductContent(dio: dio).getProductContentsApi(),
      _prices = pr.PmartApiPricing(dio: dio).getPricesApi();

  final sf.StorefrontApi _storefront;
  final pd.CategoriesApi _categories;
  final sr.SearchApi _search;
  final pc.ProductContentsApi _contents;
  final pr.PricesApi _prices;

  @override
  Future<HomeView> home({String? mfcId, HomeTab? tab}) async {
    final res = await pmartGuard(
      () => _storefront.getHome(mfcId: mfcId, tab: _tabToContract(tab)),
    );
    return homeFromContract(_body(res.data, 'HomeLayout'));
  }

  @override
  Future<HomeView> customTab(String tabKey, {String? mfcId}) async {
    final res = await pmartGuard(
      () => _storefront.getCustomTab(tabKey: tabKey, mfcId: mfcId),
    );
    return customTabFromContract(res.data!);
  }

  @override
  Future<List<ProductTile>> boughtTogether(
    String productId, {
    String? mfcId,
  }) async {
    final res = await pmartGuard(
      () => _storefront.listRelatedProducts(
        productId: productId,
        kind: 'BOUGHT_TOGETHER',
        mfcId: mfcId,
      ),
    );
    return [
      for (final i in res.data?.items ?? const <sf.DisplayItem>[])
        _tileFromDisplay(i),
    ];
  }

  @override
  Future<List<HomeBanner>> banners({required String placement}) async {
    final res = await pmartGuard(
      () => _storefront.listBanners(placement: placement),
    );
    return [
      for (final b in [
        ...?res.data?.items,
      ]..sort((a, b) => (a.sortOrder ?? 0).compareTo(b.sortOrder ?? 0)))
        homeBannerFromContract(b),
    ];
  }

  @override
  Future<HomeSection> section(
    HomeSection section, {
    required int layoutVersion,
    String? mfcId,
    String? cursor,
  }) async {
    final res = await pmartGuard(
      () => _storefront.listSectionItems(
        sectionId: section.sectionId,
        mfcId: mfcId,
        layoutVersion: layoutVersion,
        cursor: cursor,
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
  Future<Map<String, String>> categoryImages({String? mfcId}) async {
    final res = await pmartGuard(() => _search.getCategoryImages(mfcId: mfcId));
    return {
      for (final i
          in res.data?.items ??
              const <sr.GetCategoryImages200ResponseItemsInner>[])
        if (i.imageUrl.trim().isNotEmpty) i.categoryId: i.imageUrl,
    };
  }

  /// 검색·카테고리 한 묶음 크기. 서버 기본 50 대신 첫 화면 두세 쪽 분량(백엔드 요청 2026-11-19 search-page-size).
  static const searchPageSize = 20;

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
        size: searchPageSize,
        noCorrection: query.noCorrection ? true : null,
        onSale: query.onSale ? true : null,
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
        onSale: query.onSale ? true : null,
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
  Future<List<String>> popularKeywords() async {
    final res = await pmartGuard(() => _search.getSearchSuggestions());
    return res.data?.popular ?? const [];
  }

  @override
  Future<RatingSummary?> ratingSummary(String productId) async {
    final res = await pmartGuard(
      () => _contents.getRatingSummary(productId: productId),
    );
    final r = _body(res.data, 'RatingSummary');
    return switch (r.averageRating) {
      final num avg when r.reviewCount > 0 => RatingSummary(
        average: avg.toDouble(),
        count: r.reviewCount,
      ),
      _ => null,
    };
  }

  @override
  Future<ProductDetail> product(String productId, {String? mfcId}) async {
    final res = await pmartGuard(
      () => _contents.getProductContent(productId: productId, mfcId: mfcId),
    );
    final content = _body(res.data, 'ProductContent');
    return productFromContract(content, prices: await _pricesFor(content));
  }

  /// 표시 가격·기간 할인을 `GET /prices?skus=` 로 읽는다(pricing 0.3.0 — 할인은 product-content 에 없어 모든 옵션을 묻는다).
  /// 옵션 `price` 가 있으면 정가는 그 값을 먼저 쓴다(BR-36). 가격 조회가 실패해도 상세는 보이고,
  /// 그 옵션은 "가격 확인 중"으로 남는다(0원·판매 불가로 확정하지 않는다).
  Future<OptionPrices?> _pricesFor(pc.ProductContent c) async {
    final skus = [
      for (final o in c.options ?? const <pc.SaleOption>[])
        if (o.sku != null) o.sku!,
    ];
    if (skus.isEmpty) return null;
    try {
      // 계약은 style=form, explode=false(`skus=a,b`). dio 기본 배열 인코딩은 `skus=a&skus=b` 라 직접 잇는다.
      final res = await pmartGuard(
        () => _prices.listPrices(skus: [skus.join(',')]),
      );
      final body = res.data;
      if (body == null) return null;
      return OptionPrices(
        prices: {
          for (final p in body.items ?? const <pr.Price>[])
            p.sku: (basePrice: p.basePrice, priceVersion: p.priceVersion),
        },
        discounts: {
          for (final p in body.items ?? const <pr.Price>[])
            if (p.discount case final d?)
              p.sku: SaleDiscount(
                salePrice: d.salePrice,
                ratePercent: d.ratePercent,
                name: d.name,
                endsAt: d.endsAt,
              ),
        },
        notSet: {...?body.notSet},
      );
    } on PmartFailure {
      return null;
    }
  }
}

/// `GET /prices?skus=` 결과. [notSet] 은 유효 가격이 없는 SKU(PRICE_NOT_SET, 판매 불가).
final class OptionPrices {
  const OptionPrices({
    required this.prices,
    required this.notSet,
    this.discounts = const {},
  });

  /// SKU 별 지금 기간 할인(pricing 0.3.0). 할인을 모르면(discountAvailable=false) 없다 — 정가만.
  final Map<String, SaleDiscount> discounts;

  final Map<String, ({int basePrice, int priceVersion})> prices;
  final Set<String> notSet;
}

/// 카드 할인(서버 값). 할인가가 없거나 정가 이상이면 할인 없음 — 정가만 보인다.
SaleDiscount? saleDiscountOf({
  required int? salePrice,
  required int? basePrice,
  int? ratePercent,
  String? name,
  DateTime? endsAt,
}) => switch (salePrice) {
  final int s when basePrice == null || s < basePrice => SaleDiscount(
    salePrice: s,
    ratePercent: ratePercent,
    name: switch (name?.trim()) {
      null || '' => null,
      final n => n,
    },
    endsAt: endsAt,
  ),
  _ => null,
};

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
  SortKey.reviewCount => sr.SortKey.REVIEW_COUNT,
  SortKey.discountRate => sr.SortKey.DISCOUNT_RATE,
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
  soldOut: i.availability?.value == 'SOLD_OUT',
  lowStockQty: i.lowStockQty,
  rating: i.rating?.toDouble(),
  reviewCount: i.reviewCount,
  badge: switch (i.badge) {
    sf.DisplayItemBadgeEnum.NEW => DisplayBadge.isNew,
    sf.DisplayItemBadgeEnum.RANK => DisplayBadge.rank,
    _ => DisplayBadge.none,
  },
  rank: i.rank,
  discount: saleDiscountOf(
    salePrice: i.salePrice,
    basePrice: i.basePrice,
    ratePercent: i.discountRatePercent,
    name: i.discountName,
    endsAt: i.discountEndsAt,
  ),
  unitPrice: switch (i.unitPrice) {
    null => null,
    final u => UnitPrice(
      basis: u.basis,
      unitLabel: u.unit.value == 'ML' ? 'ml' : 'g',
      price: u.price,
    ),
  },
);

SectionKind _kind(sf.SectionKindEnum? k) => switch (k) {
  sf.SectionKindEnum.THEME => SectionKind.theme,
  sf.SectionKindEnum.SEASON => SectionKind.season,
  sf.SectionKindEnum.WEEKLY_PICK => SectionKind.weeklyPick,
  sf.SectionKindEnum.NEW => SectionKind.isNew,
  sf.SectionKindEnum.RANKING => SectionKind.ranking,
  sf.SectionKindEnum.HIGH_RATING => SectionKind.highRating,
  sf.SectionKindEnum.IN_PROGRESS_ORDER => SectionKind.inProgressOrder,
  // storefront 0.10.0 배너 묶음 영역(HOME_INLINE) — 테마 사이에 넘겨 보는 배너로 그린다.
  sf.SectionKindEnum.BANNER => SectionKind.banner,
  null => SectionKind.unknown,
};

/// 배너(storefront Banner) → 화면 모델.
HomeBanner homeBannerFromContract(sf.Banner b) => HomeBanner(
  bannerId: _required(b.bannerId, 'Banner.bannerId'),
  imageUrl: b.imageUrl,
  altText: b.altText,
  placement: b.placement,
  link: switch (b.linkType?.value) {
    'SECTION' => BannerLink.section,
    'PRODUCT' => BannerLink.product,
    'CATEGORY' => BannerLink.category,
    _ => BannerLink.none,
  },
  linkRef: b.linkRef,
);

HomeView homeFromContract(sf.HomeLayout h) => HomeView(
  layoutVersion: h.layoutVersion,
  tabs: [for (final t in h.tabs ?? const <sf.TabKey>[]) _tabFromContract(t)],
  banners: [
    // sortOrder 순(storefront 0.7.0 — HOME_TOP 가로 넘기기 순서)
    for (final b in [
      ...?h.banners,
    ]..sort((a, b) => (a.sortOrder ?? 0).compareTo(b.sortOrder ?? 0)))
      homeBannerFromContract(b),
  ],
  sections: sectionsFromContract(h.sections),
  customTabs: [
    for (final c in h.customTabs ?? const <sf.CustomTab>[]) customTabFromTab(c),
  ],
  bannerIntervalSeconds: h.bannerIntervalSeconds,
);

/// 진열 영역(storefront Section) → 화면 모델.
List<HomeSection> sectionsFromContract(Iterable<sf.Section> sections) => [
  for (final s in sections)
    // 0.10.0 배너 묶음(kind BANNER, items 비움, 백엔드 요청서 8번): 받은 순서 그대로 테마 사이에 — 배너가 없으면 뺀다.
    if (s.kind == sf.SectionKindEnum.BANNER)
      if ([
            for (final b in s.banners ?? const <sf.Banner>[])
              homeBannerFromContract(b),
          ]
          case final banners when banners.isNotEmpty)
        HomeSection(
          sectionId: _required(s.sectionId, 'Section.sectionId'),
          kind: SectionKind.banner,
          title: s.title ?? '',
          available: true,
          items: const [],
          banners: banners,
          intervalSeconds: s.intervalSeconds,
        )
      else
        ...[]
    else
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
        viewAllRef: s.viewAllRef,
        endsAt: s.endsAt,
        showTimer: (s.showTimer ?? false) && s.endsAt != null,
        timerStyle: s.timerStyle?.value == 'BAND'
            ? TimerStyle.band
            : TimerStyle.label,
      ),
];

/// MD 탭 이름표.
CustomTab customTabFromTab(sf.CustomTab c) => CustomTab(
  tabKey: c.tabKey,
  title: c.title,
  endsAt: c.endsAt,
  showTimer: (c.showTimer ?? false) && c.endsAt != null,
);

/// MD 탭 내용 — 영역 모양은 홈과 같다.
HomeView customTabFromContract(sf.CustomTabLayout l) => HomeView(
  layoutVersion: l.layoutVersion,
  tabs: const [],
  banners: const [],
  sections: sectionsFromContract(l.sections),
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
  viewAllRef: base.viewAllRef,
  endsAt: base.endsAt,
  showTimer: base.showTimer,
  timerStyle: base.timerStyle,
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
        section: switch (n.section?.trim()) {
          final s? when s.isNotEmpty => s,
          _ => null,
        },
      ),
  ];
}

ProductTile _hitTile(sr.SearchHit h) => ProductTile(
  productId: _required(h.productId, 'SearchHit.productId'),
  name: _required(h.name, 'SearchHit.name'),
  imageUrl: h.imageUrl,
  representativeSku: h.representativeSku,
  basePrice: h.basePrice,
  saleState: _saleState(h.saleState?.value),
  carried: h.carried,
  soldOut: h.availability?.value == 'SOLD_OUT',
  lowStockQty: h.lowStockQty,
  rating: h.rating?.toDouble(),
  reviewCount: h.reviewCount,
  discount: saleDiscountOf(
    salePrice: h.salePrice,
    basePrice: h.basePrice,
    ratePercent: h.discountRatePercent,
    name: h.discountName,
    endsAt: h.discountEndsAt,
  ),
);

ProductPage searchFromContract(sr.SearchResult r) => ProductPage(
  items: arrangeForDisplay(r.items.map(_hitTile)),
  // 0건(교정해도 0건)일 때만 비슷한 상품(search 0.12.0, BR-87). 없거나 비면 null.
  similarItems: switch (r.similarItems) {
    final s? when s.isNotEmpty => arrangeForDisplay(s.map(_hitTile)),
    _ => null,
  },
  nextCursor: r.page.nextCursor,
  total: r.total,
  correctedQuery: switch (r.correctedQuery?.trim()) {
    final q? when q.isNotEmpty => q,
    _ => null,
  },
  suggestedQuery: switch (r.suggestedQuery?.trim()) {
    final q? when q.isNotEmpty => q,
    _ => null,
  },
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

List<String> _imageUrlsOf(List<pc.Image> sorted, pc.ImageRoleEnum role) => [
  for (final i in sorted)
    if (i.role == role && i.url != null && i.url!.isNotEmpty) i.url!,
];

ProductDetail productFromContract(pc.ProductContent c, {OptionPrices? prices}) {
  final images = [...?c.images]
    ..sort((a, b) => (a.sortOrder ?? 0).compareTo(b.sortOrder ?? 0));
  final rating = c.rating;
  return ProductDetail(
    productId: _required(c.productId, 'ProductContent.productId'),
    name: _required(c.name, 'ProductContent.name'),
    mainImageUrl:
        c.mainImage?.url ??
        images.where((i) => i.role == pc.ImageRoleEnum.MAIN).firstOrNull?.url,
    // 역할(role)별로 나눈다. 역할이 없는 이미지는 어디에 둘지 모르므로 쓰지 않는다.
    descriptionImageUrls: _imageUrlsOf(images, pc.ImageRoleEnum.DESCRIPTION),
    detailImageUrls: _imageUrlsOf(images, pc.ImageRoleEnum.DETAIL),
    description: c.description,
    storageGuide: c.storageGuide,
    returnGuide: c.returnGuide,
    notices: c.notices ?? const [],
    origin: _text(c.origin),
    expiryGuide: _text(c.expiryGuide),
    legalInfo: switch (c.legalInfo) {
      final rows? => [
        for (final r in rows) (label: _text(r.label), value: r.value),
      ],
      null => null,
    },
    categoryPath: c.categoryPath ?? const [],
    nutrition: switch (c.nutrition) {
      null => null,
      final n => ProductNutrition(
        basis: n.basisUnit == pc.NutritionBasisUnitEnum.ML
            ? NutritionBasis.milliliter
            : NutritionBasis.gram,
        energyKcal: n.energyKcal,
        sodiumMg: n.sodiumMg,
        sugarsG: n.sugarsG,
        proteinG: n.proteinG,
        fatG: n.fatG,
      ),
    },
    allergens: switch (c.allergens) {
      null => null,
      final a => ProductAllergens(
        contains: [...?a.contains],
        mayContain: [...?a.mayContain],
        text: switch (a.text?.trim()) {
          final t? when t.isNotEmpty => t,
          _ => null,
        },
      ),
    },
    rating: switch (rating) {
      final r? when r.averageRating != null => RatingSummary(
        average: r.averageRating!.toDouble(),
        count: r.reviewCount,
      ),
      _ => null,
    },
    options: [
      for (final o in c.options ?? const <pc.SaleOption>[])
        if (_saleState(o.saleState) != SaleState.saleStopped)
          SaleOption(
            sku: _required(o.sku, 'SaleOption.sku'),
            label: o.label,
            unitType: switch (o.unitType) {
              pc.SaleOptionUnitTypeEnum.E => UnitType.each,
              pc.SaleOptionUnitTypeEnum.B => UnitType.bundle,
              null => null,
            },
            unitsPerSku: o.unitsPerSku,
            capacityLabel: o.capacityLabel,
            basePrice: o.price?.basePrice ?? prices?.prices[o.sku]?.basePrice,
            priceVersion:
                o.price?.priceVersion ?? prices?.prices[o.sku]?.priceVersion,
            priceNotSet: prices?.notSet.contains(o.sku) ?? false,
            discount: prices?.discounts[o.sku],
            carried: o.availability?.carried,
            unitPrice: switch (o.unitPrice) {
              null => null,
              final u => UnitPrice(
                basis: u.basis,
                unitLabel: u.unit.value == 'ML' ? 'ml' : 'g',
                price: u.price,
              ),
            },
            availability:
                _saleState(o.saleState) == SaleState.temporarilySoldOut
                ? Availability.soldOut
                // 재고가 붙지 않았다 = 서버가 센터를 모른다(mfcId 없이 부름). 0·품절이 아니다.
                : o.availability == null
                ? Availability.noCenter
                : switch (o.availability?.state) {
                    pc.SaleOptionAvailabilityStateEnum.AVAILABLE =>
                      Availability.available,
                    pc.SaleOptionAvailabilityStateEnum.LOW => Availability.low,
                    pc.SaleOptionAvailabilityStateEnum.SOLD_OUT =>
                      Availability.soldOut,
                    _ => Availability.unknown,
                  },
            lowStockQty: o.availability?.lowStockQty,
          ),
    ],
  );
}

/// 빈 글은 없는 것으로(지어내지 않는다).
String? _text(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
