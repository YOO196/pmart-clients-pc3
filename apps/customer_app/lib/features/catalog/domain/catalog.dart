import 'package:flutter/foundation.dart';

/// 판매 상태 사본. 이 값으로 구매 가능을 확정하지 않는다(담기 결과는 장바구니 서버 판정).
enum SaleState { onSale, temporarilySoldOut, saleStopped, unknown }

/// 현재 센터의 가용 사본. 조회 실패는 [unknown] 이지 품절·0개가 아니다.
enum Availability { available, low, soldOut, unknown }

enum DisplayBadge { none, isNew, rank }

/// 목록·진열·검색 결과의 상품 카드.
@immutable
class ProductTile {
  const ProductTile({
    required this.productId,
    required this.name,
    required this.saleState,
    this.imageUrl,
    this.representativeSku,
    this.basePrice,
    this.carried,
    this.rating,
    this.reviewCount,
    this.badge = DisplayBadge.none,
    this.rank,
  });

  final String productId;
  final String name;
  final String? imageUrl;
  final String? representativeSku;

  /// pricing 사본. 없으면 null(0원으로 바꾸지 않는다).
  final int? basePrice;
  final SaleState saleState;

  /// 현재 센터 취급 여부. 불명이면 null.
  final bool? carried;

  /// 평점·리뷰 수 사본. 집계가 없으면 null(0점·0건으로 바꾸지 않는다).
  final double? rating;
  final int? reviewCount;
  final DisplayBadge badge;
  final int? rank;

  /// 담기 버튼을 보여도 되는지(안내용). 확정은 장바구니 서버 판정.
  bool get canOfferAdd => saleState == SaleState.onSale && carried != false;
}

/// 판매중지는 빼고 일시품절은 뒤로 보낸다(C 1068). 나머지 순서는 서버 순서 그대로.
List<ProductTile> arrangeForDisplay(Iterable<ProductTile> tiles) {
  final visible = tiles.where((t) => t.saleState != SaleState.saleStopped);
  return [
    ...visible.where((t) => t.saleState != SaleState.temporarilySoldOut),
    ...visible.where((t) => t.saleState == SaleState.temporarilySoldOut),
  ];
}

enum SectionKind {
  theme,
  season,
  weeklyPick,
  isNew,
  ranking,
  highRating,
  inProgressOrder,
  unknown,
}

@immutable
class HomeSection {
  const HomeSection({
    required this.sectionId,
    required this.kind,
    required this.title,
    required this.available,
    required this.items,
    this.subtitle,
    this.nextCursor,
  });

  final String sectionId;
  final SectionKind kind;
  final String title;
  final String? subtitle;

  /// false 면 이 영역만 조회 실패(UNAVAILABLE). 다른 영역은 그대로 보인다.
  final bool available;
  final List<ProductTile> items;
  final String? nextCursor;
}

enum HomeTab { home, ranking, isNew }

@immutable
class HomeBanner {
  const HomeBanner({required this.bannerId, this.imageUrl, this.altText});

  final String bannerId;
  final String? imageUrl;
  final String? altText;
}

@immutable
class HomeView {
  const HomeView({
    required this.layoutVersion,
    required this.tabs,
    required this.banners,
    required this.sections,
  });

  final int layoutVersion;
  final List<HomeTab> tabs;
  final List<HomeBanner> banners;
  final List<HomeSection> sections;

  bool get hasUnavailableSection => sections.any((s) => !s.available);

  HomeView replaceSection(HomeSection section) => HomeView(
    layoutVersion: layoutVersion,
    tabs: tabs,
    banners: banners,
    sections: [
      for (final s in sections) s.sectionId == section.sectionId ? section : s,
    ],
  );
}

@immutable
class CategoryNode {
  const CategoryNode({
    required this.categoryId,
    required this.name,
    required this.depth,
    this.parentId,
  });

  final String categoryId;
  final String? parentId;
  final int depth;
  final String name;
}

/// 정렬. 할인율순은 1차 제외(계약 SortKey).
enum SortKey { relevance, popular, newest, priceAsc, priceDesc, rating }

@immutable
class ProductQuery {
  const ProductQuery({
    this.keyword,
    this.categoryId,
    this.sort = SortKey.relevance,
    this.filters = const {},
  });

  final String? keyword;
  final String? categoryId;
  final SortKey sort;

  /// `attributeKey.value` 형식(계약 filters).
  final Set<String> filters;

  ProductQuery copyWith({SortKey? sort, Set<String>? filters}) => ProductQuery(
    keyword: keyword,
    categoryId: categoryId,
    sort: sort ?? this.sort,
    filters: filters ?? this.filters,
  );

  @override
  bool operator ==(Object other) =>
      other is ProductQuery &&
      other.keyword == keyword &&
      other.categoryId == categoryId &&
      other.sort == sort &&
      setEquals(other.filters, filters);

  @override
  int get hashCode =>
      Object.hash(keyword, categoryId, sort, Object.hashAllUnordered(filters));
}

@immutable
class ProductPage {
  const ProductPage({required this.items, this.nextCursor, this.total});

  final List<ProductTile> items;
  final String? nextCursor;
  final int? total;
}

@immutable
class FilterValue {
  const FilterValue({required this.value, required this.label, this.count});

  final String value;
  final String label;

  /// 현재 조건의 결과 수. 0이면 선택 불가. 없으면 null(선택은 허용).
  final int? count;
}

@immutable
class FilterAttribute {
  const FilterAttribute({
    required this.key,
    required this.label,
    required this.multiSelect,
    required this.values,
  });

  final String key;
  final String label;
  final bool multiSelect;
  final List<FilterValue> values;

  String token(FilterValue v) => '$key.${v.value}';
}

enum UnitType { each, bundle }

@immutable
class SaleOption {
  const SaleOption({
    required this.sku,
    required this.label,
    required this.availability,
    this.unitType,
    this.unitsPerSku,
    this.capacityLabel,
    this.basePrice,
    this.priceVersion,
    this.carried,
  });

  final String sku;
  final String label;
  final UnitType? unitType;
  final int? unitsPerSku;
  final String? capacityLabel;
  final int? basePrice;
  final int? priceVersion;
  final Availability availability;
  final bool? carried;

  bool get canOfferAdd =>
      carried != false &&
      availability != Availability.soldOut &&
      availability != Availability.unknown;
}

@immutable
class RatingSummary {
  const RatingSummary({required this.average, required this.count});

  final double average;
  final int count;
}

@immutable
class ProductDetail {
  const ProductDetail({
    required this.productId,
    required this.name,
    required this.options,
    this.imageUrls = const [],
    this.description,
    this.storageGuide,
    this.returnGuide,
    this.notices = const [],
    this.categoryPath = const [],
    this.rating,
  });

  final String productId;
  final String name;
  final List<String> imageUrls;
  final String? description;
  final String? storageGuide;
  final String? returnGuide;
  final List<String> notices;
  final List<String> categoryPath;

  /// 집계 없음·실패는 null. 0점·0건으로 표시하지 않는다.
  final RatingSummary? rating;
  final List<SaleOption> options;
}
