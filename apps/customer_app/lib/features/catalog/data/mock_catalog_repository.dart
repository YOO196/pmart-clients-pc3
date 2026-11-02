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
    this.unavailableSectionIds = const {'S-WEEKLY'},
    this.pageSize = 6,
  });

  final Duration latency;

  /// 홈에서 UNAVAILABLE 로 내려줄 영역(부분 실패 시연). 재조회하면 성공한다.
  final Set<String> unavailableSectionIds;
  final int pageSize;

  static const mfcId = 'MFC-MOCK-01';

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
  };

  static const _sections = [
    ('S-RANK', 'RANKING', '지금 많이 사는 상품'),
    ('S-NEW', 'NEW', '새로 들어왔어요'),
    ('S-WEEKLY', 'WEEKLY_PICK', '이번 주 장보기'),
  ];

  List<MockProduct> _sectionProducts(String sectionId) => switch (sectionId) {
    'S-RANK' => [
      ...mockProducts,
    ]..sort((a, b) => b.popularity.compareTo(a.popularity)),
    'S-NEW' => mockProducts.where((p) => p.newness > 0).toList(),
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
              },
    ],
  };

  @override
  Future<HomeView> home({String? mfcId, HomeTab? tab}) async {
    await _wait();
    return homeFromContract(sf.HomeLayout.fromJson(homeJson()));
  }

  @override
  Future<HomeSection> section(
    HomeSection section, {
    required int layoutVersion,
    String? mfcId,
  }) async {
    await _wait();
    if (layoutVersion != 7) {
      throw const ProblemFailure(
        Problem(status: 409, code: 'LAYOUT_VERSION_CHANGED'),
      );
    }
    return sectionItemsFromContract(
      section,
      sf.ListSectionItems200Response.fromJson({
        'sectionId': section.sectionId,
        'items': [
          for (final p in _sectionProducts(section.sectionId))
            displayItemJson(p),
        ],
        'page': {'nextCursor': null, 'size': 50},
      }),
    );
  }

  static const categoryTreeJson = <String, Object?>{
    'version': 3,
    'nodes': [
      {
        'categoryId': 'C-FV',
        'level': 'TOP',
        'name': '과일·채소',
        'sortOrder': 1,
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
        'categoryId': 'C-DAIRY',
        'level': 'TOP',
        'name': '우유·유제품',
        'sortOrder': 2,
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
        'categoryId': 'C-SNACK',
        'level': 'TOP',
        'name': '과자·간식',
        'sortOrder': 3,
        'exposed': true,
      },
      {
        'categoryId': 'C-CHIPS',
        'parentId': 'C-SNACK',
        'level': 'SUB',
        'name': '스낵',
        'sortOrder': 1,
        'exposed': true,
      },
      {
        'categoryId': 'C-HIDDEN',
        'level': 'TOP',
        'name': '숨김',
        'sortOrder': 9,
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
    final all = _match(query).toList();
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
    }
    final start = int.tryParse(cursor ?? '') ?? 0;
    final end = (start + pageSize).clamp(0, all.length);
    return searchFromContract(
      sr.SearchResult.fromJson({
        'query': ?query.keyword,
        'items': [
          for (final p in all.sublist(start, end))
            {
              ...displayItemJson(p)..remove('badge'),
              'categoryPath': [?_parents[p.categoryId], p.categoryId],
            },
        ],
        'total': all.length,
        'page': {
          'nextCursor': end < all.length ? '$end' : null,
          'size': pageSize,
        },
        'appliedSort': _sortWire(query.sort),
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
}
