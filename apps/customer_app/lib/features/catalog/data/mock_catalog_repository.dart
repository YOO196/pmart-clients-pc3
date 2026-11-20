import 'package:dio/dio.dart';
import 'package:pmart_api_product/pmart_api_product.dart' as pd;
import 'package:pmart_api_product_content/pmart_api_product_content.dart' as pc;
import 'package:pmart_api_search/pmart_api_search.dart' as sr;
import 'package:pmart_api_storefront/pmart_api_storefront.dart' as sf;
import 'package:pmart_core/pmart_core.dart';

import '../domain/catalog.dart';
import 'catalog_repository.dart';

/// 목 상품 한 건. 계약 필드만으로 픽스처 JSON 을 만든다.
final class MockProduct {
  const MockProduct({
    required this.productId,
    required this.name,
    required this.sku,
    required this.price,
    required this.categoryId,
    required this.capacity,
    this.saleState = 'ON_SALE',
    this.availability = 'AVAILABLE',
    this.rating,
    this.reviewCount,
    this.popularity = 0,
    this.newness = 0,
    this.bundleSku,
    this.bundlePrice,
  });

  final String productId;
  final String name;
  final String sku;
  final int price;
  final String categoryId;
  final String capacity;
  final String saleState;
  final String availability;
  final double? rating;
  final int? reviewCount;
  final int popularity;
  final int newness;
  final String? bundleSku;
  final int? bundlePrice;
}

const mockProducts = <MockProduct>[
  MockProduct(
    productId: 'P-0001',
    name: '서울우유 1L',
    sku: 'E-00000001',
    price: 2980,
    categoryId: 'C-MILK',
    capacity: '1l',
    rating: 4.8,
    reviewCount: 1203,
    popularity: 99,
    bundleSku: 'B-00000011',
    bundlePrice: 5800,
  ),
  MockProduct(
    productId: 'P-0002',
    name: '그릭요거트 플레인 400g',
    sku: 'E-00000002',
    price: 5980,
    categoryId: 'C-YOGURT',
    capacity: '400g',
    rating: 4.6,
    reviewCount: 312,
    popularity: 70,
    newness: 5,
  ),
  MockProduct(
    productId: 'P-0003',
    name: '제주 감귤 1kg',
    sku: 'E-00000003',
    price: 7900,
    categoryId: 'C-FRUIT',
    capacity: '1kg',
    availability: 'LOW',
    rating: 4.4,
    reviewCount: 88,
    popularity: 80,
    newness: 9,
  ),
  MockProduct(
    productId: 'P-0004',
    name: '친환경 대추방울토마토 500g',
    sku: 'E-00000004',
    price: 6480,
    categoryId: 'C-VEG',
    capacity: '500g',
    saleState: 'TEMPORARILY_SOLD_OUT',
    availability: 'SOLD_OUT',
    rating: 4.2,
    reviewCount: 41,
    popularity: 60,
  ),
  MockProduct(
    productId: 'P-0005',
    name: '감자칩 오리지널 110g',
    sku: 'E-00000005',
    price: 1980,
    categoryId: 'C-CHIPS',
    capacity: '110g',
    rating: 4.5,
    reviewCount: 640,
    popularity: 85,
  ),
  MockProduct(
    productId: 'P-0006',
    name: '저지방 우유 900mL',
    sku: 'E-00000006',
    price: 2780,
    categoryId: 'C-MILK',
    capacity: '900ml',
    popularity: 40,
    newness: 10,
  ),
  MockProduct(
    productId: 'P-0007',
    name: '양파 1.5kg',
    sku: 'E-00000007',
    price: 3980,
    categoryId: 'C-VEG',
    capacity: '1.5kg',
    rating: 4.1,
    reviewCount: 57,
    popularity: 50,
  ),
  MockProduct(
    productId: 'P-0008',
    name: '단종 예정 과자 80g',
    sku: 'E-00000008',
    price: 1500,
    categoryId: 'C-CHIPS',
    capacity: '80g',
    saleState: 'SALE_STOPPED',
    availability: 'SOLD_OUT',
  ),
];

/// 목 구현. 픽스처 JSON 을 생성 모델로 읽고 실서버 구현과 같은 변환을 거친다.
base class MockCatalogRepository implements CatalogRepository {
  MockCatalogRepository({
    this.latency = const Duration(milliseconds: 300),
    // 앱(목 모드)에서는 모든 영역을 정상으로 보인다(사용자 2026-11-20 "이번 주 장보기도 고쳐").
    // 부분 실패는 시험에서 이 값을 넘겨 확인한다.
    this.unavailableSectionIds = const {},
    this.pageSize = 6,
  });

  final Duration latency;

  /// 홈에서 UNAVAILABLE 로 내려줄 영역(부분 실패 시험용). 재조회하면 성공한다.
  final Set<String> unavailableSectionIds;
  final int pageSize;

  /// 라이더앱 목과 같은 부산진구지점(목 전용).
  static const mfcId = 'MFC-BSJ-01';

  Future<void> _wait() => Future<void>.delayed(latency);

  static Map<String, Object?> displayItemJson(MockProduct p) => {
    'productId': p.productId,
    'name': p.name,
    'representativeSku': p.sku,
    'basePrice': p.price,
    'priceVersion': 1,
    'saleState': p.saleState,
    'carried': true,
    'rating': ?p.rating,
    'reviewCount': ?p.reviewCount,
    'badge': p.newness > 0 ? 'NEW' : 'NONE',
    ...?_unitPriceJson(p),
  };

  /// 서버처럼 내용량(용량 문자열)이 있으면 100g/100mL당 가격을 준다(storefront 0.3.0).
  static Map<String, Object?>? _unitPriceJson(MockProduct p) {
    final m = RegExp(r'^([\d.]+)\s*(kg|g|l|ml)$')
        .firstMatch(p.capacity.toLowerCase());
    if (m == null) return null;
    final n = double.parse(m.group(1)!);
    final (amount, unit) = switch (m.group(2)) {
      'kg' => ((n * 1000).round(), 'G'),
      'g' => (n.round(), 'G'),
      'l' => ((n * 1000).round(), 'ML'),
      _ => (n.round(), 'ML'),
    };
    if (amount <= 0) return null;
    return {
      'netContent': {'amount': amount, 'unit': unit},
      'unitPrice': {
        'basis': 100,
        'unit': unit,
        'price': (p.price * 100 / amount).round(),
      },
    };
  }

  static const _sections = [
    ('S-RANK', 'RANKING', '지금 많이 사는 상품'),
    ('S-NEW', 'NEW', '새로 들어왔어요'),
    ('S-WEEKLY', 'WEEKLY_PICK', '이번 주 장보기'),
  ];

  List<MockProduct> _sectionProducts(String sectionId) => switch (sectionId) {
    'S-RANK' || 'S-RANK-TOP' => [
      ...mockProducts,
    ]..sort((a, b) => b.popularity.compareTo(a.popularity)),
    'S-NEW' || 'S-NEW-ALL' => mockProducts.where((p) => p.newness > 0).toList(),
    _ => mockProducts.where((p) => p.categoryId != 'C-CHIPS').toList(),
  };

  Map<String, Object?> homeJson() => {
    'layoutVersion': 7,
    'tab': 'HOME',
    'tabs': ['HOME', 'RANKING', 'NEW'],
    'banners': [
      {
        'bannerId': 'BN-1',
        'placement': 'HOME_TOP',
        'altText': '신선식품 30분 배달',
        'linkType': 'NONE',
        'sortOrder': 1,
      },
      // storefront 0.7.0: 누르면 영역·상품·카테고리로(백엔드 요청 2026-11-20 home-banners-themes)
      {
        'bannerId': 'BN-2',
        'placement': 'HOME_TOP',
        'altText': '새로 들어왔어요',
        'linkType': 'SECTION',
        'linkRef': 'S-NEW',
        'sortOrder': 2,
      },
      {
        'bannerId': 'BN-3',
        'placement': 'HOME_MIDDLE',
        'altText': '과일·채소 모아 보기',
        'linkType': 'CATEGORY',
        'linkRef': 'C-FV',
        'sortOrder': 1,
      },
    ],
    'sections': [
      for (final (id, kind, title) in _sections)
        unavailableSectionIds.contains(id)
            ? {
                'sectionId': id,
                'kind': kind,
                'title': title,
                'state': 'UNAVAILABLE',
              }
            : {
                'sectionId': id,
                'kind': kind,
                'title': title,
                'state': 'OK',
                'items': [
                  for (final p in _sectionProducts(id)) displayItemJson(p),
                ],
                'nextCursor': null,
                'viewAllRef': id,
              },
    ],
  };

  /// 랭킹·신상품 탭 구성(계약 `GET /storefront/home?tab=`). 순위·NEW 배지는 서버 값으로 준다.
  Map<String, Object?> tabJson(HomeTab tab) {
    final (wire, id, kind, title) = switch (tab) {
      HomeTab.ranking => ('RANKING', 'S-RANK-TOP', 'RANKING', '지금 TOP'),
      _ => ('NEW', 'S-NEW-ALL', 'NEW', '이번 주 신상품'),
    };
    final products = _sectionProducts(
      tab == HomeTab.ranking ? 'S-RANK' : 'S-NEW',
    );
    return {
      'layoutVersion': 7,
      'tab': wire,
      'tabs': ['HOME', 'RANKING', 'NEW'],
      'banners': const <Object?>[],
      'sections': [
        {
          'sectionId': id,
          'kind': kind,
          'title': title,
          'state': 'OK',
          'items': [
            for (final (i, p) in products.indexed)
              {
                ...displayItemJson(p),
                if (tab == HomeTab.ranking) ...{'badge': 'RANK', 'rank': i + 1},
              },
          ],
          'nextCursor': null,
        },
      ],
    };
  }

  @override
  Future<HomeView> home({String? mfcId, HomeTab? tab}) async {
    await _wait();
    return homeFromContract(
      sf.HomeLayout.fromJson(
        tab == null || tab == HomeTab.home ? homeJson() : tabJson(tab),
      ),
    );
  }

  @override
  Future<HomeSection> section(
    HomeSection section, {
    required int layoutVersion,
    String? mfcId,
    String? cursor,
  }) async {
    await _wait();
    if (layoutVersion != 7) {
      throw const ProblemFailure(
        Problem(status: 409, code: 'LAYOUT_VERSION_CHANGED'),
      );
    }
    // 서버 흉내: [pageSize] 씩 끊어 주고 남았으면 다음 커서를 준다.
    final all = _sectionProducts(section.sectionId);
    final start = int.tryParse(cursor ?? '') ?? 0;
    final end = (start + pageSize).clamp(0, all.length);
    return sectionItemsFromContract(
      section,
      sf.ListSectionItems200Response.fromJson({
        'sectionId': section.sectionId,
        'items': [
          for (final p in all.sublist(start.clamp(0, all.length), end))
            displayItemJson(p),
        ],
        'page': {
          'nextCursor': end < all.length ? '$end' : null,
          'size': pageSize,
        },
      }),
    );
  }

  /// 레퍼런스 카테고리 화면(2026-11-20 사용자 제공 그림)과 같은 상위 카테고리·묶음. 상품은 과일·우유·과자에만 있다.
  static const categoryTreeJson = <String, Object?>{
    'version': 4,
    'nodes': [
      {
        'categoryId': 'C-RICE',
        'level': 'TOP',
        'section': '맛있는것',
        'name': '밥·도시락',
        'sortOrder': 1,
        'exposed': true,
      },
      {
        'categoryId': 'C-NOODLE',
        'level': 'TOP',
        'section': '맛있는것',
        'name': '라면·면',
        'sortOrder': 2,
        'exposed': true,
      },
      {
        'categoryId': 'C-SOUP',
        'level': 'TOP',
        'section': '맛있는것',
        'name': '국·탕·찌개',
        'sortOrder': 3,
        'exposed': true,
      },
      {
        'categoryId': 'C-SIDE',
        'level': 'TOP',
        'section': '맛있는것',
        'name': '요리·반찬',
        'sortOrder': 4,
        'exposed': true,
      },
      {
        'categoryId': 'C-BUNSIK',
        'level': 'TOP',
        'section': '맛있는것',
        'name': '분식·야식',
        'sortOrder': 5,
        'exposed': true,
      },
      {
        'categoryId': 'C-FV',
        'level': 'TOP',
        'section': '맛있는것',
        'name': '과일·채소·샐러드',
        'sortOrder': 6,
        'exposed': true,
      },
      {
        'categoryId': 'C-FRUIT',
        'parentId': 'C-FV',
        'level': 'SUB',
        'name': '과일',
        'sortOrder': 1,
        'exposed': true,
      },
      {
        'categoryId': 'C-VEG',
        'parentId': 'C-FV',
        'level': 'SUB',
        'name': '채소',
        'sortOrder': 2,
        'exposed': true,
      },
      {
        'categoryId': 'C-GRAIN',
        'level': 'TOP',
        'section': '맛있는것',
        'name': '쌀·잡곡·견과',
        'sortOrder': 7,
        'exposed': true,
      },
      {
        'categoryId': 'C-MEAT',
        'level': 'TOP',
        'section': '맛있는것',
        'name': '정육·수산·계란',
        'sortOrder': 8,
        'exposed': true,
      },
      {
        'categoryId': 'C-DRINK',
        'level': 'TOP',
        'section': '맛있는것',
        'name': '음료·커피·생수',
        'sortOrder': 9,
        'exposed': true,
      },
      {
        'categoryId': 'C-SNACK',
        'level': 'TOP',
        'section': '맛있는것',
        'name': '과자·초콜릿·시리얼',
        'sortOrder': 10,
        'exposed': true,
      },
      {
        'categoryId': 'C',
        'parentId': 'C-SNACK',
        'level': 'SUB',
        'name': '-',
        'sortOrder': 1,
        'exposed': true,
      },
      {
        'categoryId': '스',
        'parentId': 'C-SNACK',
        'level': 'SUB',
        'name': '낵',
        'sortOrder': 2,
        'exposed': true,
      },
      {
        'categoryId': 'C-BREAD',
        'level': 'TOP',
        'section': '맛있는것',
        'name': '빵·떡·잼',
        'sortOrder': 11,
        'exposed': true,
      },
      {
        'categoryId': 'C-ICE',
        'level': 'TOP',
        'section': '맛있는것',
        'name': '아이스크림',
        'sortOrder': 12,
        'exposed': true,
      },
      {
        'categoryId': 'C-DAIRY',
        'level': 'TOP',
        'section': '맛있는것',
        'name': '우유·유제품',
        'sortOrder': 13,
        'exposed': true,
      },
      {
        'categoryId': 'C-MILK',
        'parentId': 'C-DAIRY',
        'level': 'SUB',
        'name': '우유',
        'sortOrder': 1,
        'exposed': true,
      },
      {
        'categoryId': 'C-YOGURT',
        'parentId': 'C-DAIRY',
        'level': 'SUB',
        'name': '요거트',
        'sortOrder': 2,
        'exposed': true,
      },
      {
        'categoryId': 'C-SAUCE',
        'level': 'TOP',
        'section': '맛있는것',
        'name': '양념·장류·오일',
        'sortOrder': 14,
        'exposed': true,
      },
      {
        'categoryId': 'C-HAM',
        'level': 'TOP',
        'section': '맛있는것',
        'name': '햄·어묵·통조림',
        'sortOrder': 15,
        'exposed': true,
      },
      {
        'categoryId': 'C-DIET',
        'level': 'TOP',
        'section': '맛있는것',
        'name': '건강·식단관리',
        'sortOrder': 16,
        'exposed': true,
      },
      {
        'categoryId': 'C-ORGANIC',
        'level': 'TOP',
        'section': '맛있는것',
        'name': '유기농·친환경',
        'sortOrder': 17,
        'exposed': true,
      },
      {
        'categoryId': 'C-HAIR',
        'level': 'TOP',
        'section': '편리한것',
        'name': '헤어·바디·쉐이빙',
        'sortOrder': 18,
        'exposed': true,
      },
      {
        'categoryId': 'C-DETERGENT',
        'level': 'TOP',
        'section': '편리한것',
        'name': '세제·방향·탈취',
        'sortOrder': 19,
        'exposed': true,
      },
      {
        'categoryId': 'C-TISSUE',
        'level': 'TOP',
        'section': '편리한것',
        'name': '화장지·생리대',
        'sortOrder': 20,
        'exposed': true,
      },
      {
        'categoryId': 'C-BEAUTY',
        'level': 'TOP',
        'section': '편리한것',
        'name': '뷰티·클렌징·선케어',
        'sortOrder': 21,
        'exposed': true,
      },
      {
        'categoryId': 'C-CLEAN',
        'level': 'TOP',
        'section': '편리한것',
        'name': '청소·욕실',
        'sortOrder': 22,
        'exposed': true,
      },
      {
        'categoryId': 'C-LIVING',
        'level': 'TOP',
        'section': '편리한것',
        'name': '생활잡화·패션',
        'sortOrder': 23,
        'exposed': true,
      },
      {
        'categoryId': 'C-KITCHEN',
        'level': 'TOP',
        'section': '편리한것',
        'name': '주방·일회용품',
        'sortOrder': 24,
        'exposed': true,
      },
      {
        'categoryId': 'C-STATIONERY',
        'level': 'TOP',
        'section': '편리한것',
        'name': '문구·사무용품',
        'sortOrder': 25,
        'exposed': true,
      },
      {
        'categoryId': 'C-DIGITAL',
        'level': 'TOP',
        'section': '편리한것',
        'name': '가전·게임·전기용품',
        'sortOrder': 26,
        'exposed': true,
      },
      {
        'categoryId': 'C-PET',
        'level': 'TOP',
        'section': '편리한것',
        'name': '반려동물',
        'sortOrder': 27,
        'exposed': true,
      },
      {
        'categoryId': 'C-BABY',
        'level': 'TOP',
        'section': '편리한것',
        'name': '유아·아동',
        'sortOrder': 28,
        'exposed': true,
      },
      {
        'categoryId': 'C-MEDICAL',
        'level': 'TOP',
        'section': '편리한것',
        'name': '건강·의료용품',
        'sortOrder': 29,
        'exposed': true,
      },
      {
        'categoryId': 'C-INTERIOR',
        'level': 'TOP',
        'section': '편리한것',
        'name': '홈인테리어',
        'sortOrder': 30,
        'exposed': true,
      },
      {
        'categoryId': 'C-HIDDEN',
        'level': 'TOP',
        'name': '숨김',
        'sortOrder': 99,
        'exposed': false,
      },
    ],
  };

  @override
  Future<List<CategoryNode>> categories() async {
    await _wait();
    return categoriesFromContract(
      pd.GetCategoryTree200Response.fromJson(categoryTreeJson),
    );
  }

  static const _parents = {
    'C-FRUIT': 'C-FV',
    'C-VEG': 'C-FV',
    'C-MILK': 'C-DAIRY',
    'C-YOGURT': 'C-DAIRY',
    'C-CHIPS': 'C-SNACK',
  };

  /// 목 오타 사전(교정어).
  static const _typos = {'우우': '우유', '감굴': '감귤', '양퍄': '양파'};

  /// 목 제안어(결과가 적을 때).
  static const _hints = {'서울우유': '우유'};

  Iterable<MockProduct> _match(ProductQuery q) => mockProducts.where((p) {
    final keyword = q.keyword?.trim();
    if (keyword != null && keyword.isNotEmpty && !p.name.contains(keyword)) {
      return false;
    }
    final c = q.categoryId;
    if (c != null && p.categoryId != c && _parents[p.categoryId] != c) {
      return false;
    }
    for (final f in q.filters) {
      if (f != 'capacity.${p.capacity}') return false;
    }
    return true;
  });

  @override
  Future<ProductPage> search(
    ProductQuery query, {
    String? mfcId,
    String? cursor,
    CancelToken? cancelToken,
  }) async {
    await _wait();
    if (cancelToken?.isCancelled ?? false) throw const CancelledFailure();
    var all = _match(query).toList();
    // 서버 오타 교정 흉내(search 0.4.0): 0건이고 교정어가 있으면 그 검색어로 찾은 결과를 준다.
    String? corrected;
    String? suggested;
    final typo = _typos[query.keyword?.trim()];
    if (all.isEmpty && !query.noCorrection && typo != null) {
      corrected = typo;
      all = _match(
        ProductQuery(
          keyword: typo,
          categoryId: query.categoryId,
          filters: query.filters,
        ),
      ).toList();
    }
    // 결과가 적고(3건 이하) 제안어가 더 많이 찾으면 제안만(결과는 원래 검색어 것) — search 0.4.0.
    final hint = _hints[query.keyword?.trim()];
    if (corrected == null &&
        !query.noCorrection &&
        hint != null &&
        all.length <= 3) {
      suggested = hint;
    }
    switch (query.sort) {
      case SortKey.relevance:
        break;
      case SortKey.popular:
        all.sort((a, b) => b.popularity.compareTo(a.popularity));
      case SortKey.newest:
        all.sort((a, b) => b.newness.compareTo(a.newness));
      case SortKey.priceAsc:
        all.sort((a, b) => a.price.compareTo(b.price));
      case SortKey.priceDesc:
        all.sort((a, b) => b.price.compareTo(a.price));
      case SortKey.rating:
        all.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
      case SortKey.reviewCount:
        all.sort((a, b) => (b.reviewCount ?? 0).compareTo(a.reviewCount ?? 0));
    }
    final start = int.tryParse(cursor ?? '') ?? 0;
    final end = (start + pageSize).clamp(0, all.length);
    return searchFromContract(
      sr.SearchResult.fromJson({
        'query': ?query.keyword,
        'items': [
          for (final p in all.sublist(start, end))
            {
              // 검색 결과 계약에는 배지·단위 가격이 없다.
              ...displayItemJson(p)
                ..remove('badge')
                ..remove('unitPrice')
                ..remove('netContent'),
              'categoryPath': [?_parents[p.categoryId], p.categoryId],
            },
        ],
        'total': all.length,
        'page': {
          'nextCursor': end < all.length ? '$end' : null,
          'size': pageSize,
        },
        'appliedSort': _sortWire(query.sort),
        'correctedQuery': ?corrected,
        'suggestedQuery': ?suggested,
        'appliedFilters': query.filters.toList(),
      }),
    );
  }

  static String _sortWire(SortKey s) => switch (s) {
    SortKey.relevance => 'RELEVANCE',
    SortKey.popular => 'POPULAR',
    SortKey.newest => 'NEWEST',
    SortKey.priceAsc => 'PRICE_ASC',
    SortKey.priceDesc => 'PRICE_DESC',
    SortKey.rating => 'RATING',
    SortKey.reviewCount => 'REVIEW_COUNT',
  };

  @override
  Future<List<FilterAttribute>> filters(
    ProductQuery query, {
    String? mfcId,
  }) async {
    await _wait();
    final base = _match(
      ProductQuery(keyword: query.keyword, categoryId: query.categoryId),
    );
    final counts = <String, int>{};
    for (final p in base) {
      counts[p.capacity] = (counts[p.capacity] ?? 0) + 1;
    }
    final capacities = {for (final p in mockProducts) p.capacity}.toList()
      ..sort();
    return filtersFromContract(
      sr.GetSearchFilters200Response.fromJson({
        'attributes': [
          {
            'key': 'capacity',
            'label': '용량',
            'multiSelect': false,
            'values': [
              for (final c in capacities)
                {'value': c, 'label': c, 'count': counts[c] ?? 0},
            ],
          },
        ],
      }),
    );
  }

  @override
  Future<List<String>> suggestions(String keyword) async {
    await _wait();
    return [
      for (final p in mockProducts)
        if (p.name.contains(keyword)) p.name,
    ].take(5).toList();
  }

  static Map<String, Object?> productJson(MockProduct p) => {
    'productId': p.productId,
    'name': p.name,
    'contentVersion': 2,
    'productVersion': 4,
    'rating': p.rating == null
        ? null
        : {
            'productId': p.productId,
            'averageRating': p.rating,
            'reviewCount': p.reviewCount,
          },
    'options': [
      {
        'sku': p.sku,
        // 옵션이 없는 단일 SKU 상품은 label 이 없다(백엔드 안내 2026-10-31).
        if (p.bundleSku != null) 'label': '1개',
        'unitType': 'E',
        'unitsPerSku': 1,
        'capacityLabel': p.capacity,
        'saleState': p.saleState,
        'price': {'basePrice': p.price, 'priceVersion': 1},
        'availability': {'carried': true, 'state': p.availability},
        ...?_unitPriceJson(p),
      },
      if (p.bundleSku != null)
        {
          'sku': p.bundleSku,
          'label': '2개 묶음',
          'unitType': 'B',
          'unitsPerSku': 2,
          'capacityLabel': p.capacity,
          'saleState': p.saleState,
          'price': {'basePrice': p.bundlePrice, 'priceVersion': 1},
          'availability': {'carried': true, 'state': 'AVAILABLE'},
        },
    ],
    'description': '${p.name} 상품 설명입니다.',
    'storageGuide': '냉장 보관하세요.',
    'returnGuide': '신선식품은 받은 뒤 24시간 안에 반품을 신청할 수 있어요.',
    'notices': const ['사진은 실제와 다를 수 있어요.'],
    'categoryPath': [?_parents[p.categoryId], p.categoryId],
  };

  @override
  Future<ProductDetail> product(String productId, {String? mfcId}) async {
    await _wait();
    final p = mockProducts.where((p) => p.productId == productId).firstOrNull;
    if (p == null || p.saleState == 'SALE_STOPPED') {
      throw const ProblemFailure(Problem(status: 404, code: 'NOT_FOUND'));
    }
    return productFromContract(pc.ProductContent.fromJson(productJson(p)));
  }

  /// 목 평점 집계 — 상세의 평점과 같은 값(시험이 바꿔 끼운다).
  @override
  Future<RatingSummary?> ratingSummary(String productId) async {
    await _wait();
    return (await product(productId)).rating;
  }
}
