import 'package:flutter/foundation.dart';

/// 판매 상태 사본. 이 값으로 구매 가능을 확정하지 않는다(담기 결과는 장바구니 서버 판정).
enum SaleState { onSale, temporarilySoldOut, saleStopped, unknown }

/// 현재 센터의 가용 사본. 조회 실패는 [unknown] 이지 품절·0개가 아니다.
/// 옵션의 재고 상태. [noCenter] 는 서버가 재고를 붙이지 않은 것(배달 주소·담당 센터를 모름) — 품절이 아니다.
/// [unknown] 은 재고 조회 실패 — 역시 품절이 아니다(백엔드 요청 2026-11-20 availability-display).
enum Availability { available, low, soldOut, unknown, noCenter }

/// 상품의 어느 옵션도 담을 수 없을 때 그 까닭(안내 문구를 고른다). 담기 막기는 같다.
enum CannotBuyReason { noCenter, stockUnknown, notCarried, soldOut }

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
    this.unitPrice,
  });

  /// 카드의 "100g당 999원"(storefront 0.3.0 `unitPrice` — 서버가 계산). 없으면 줄을 그리지 않는다.
  final UnitPrice? unitPrice;

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

/// 단위 가격(서버 계산 — 앱은 표시만). [basis] 100 · [unitLabel] g/ml · [price] 원.
@immutable
class UnitPrice {
  const UnitPrice({
    required this.basis,
    required this.unitLabel,
    required this.price,
  });

  final int basis;
  final String unitLabel;
  final int price;
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
    this.viewAllRef,
  });

  final String sectionId;
  final SectionKind kind;
  final String title;
  final String? subtitle;

  /// false 면 이 영역만 조회 실패(UNAVAILABLE). 다른 영역은 그대로 보인다.
  final bool available;
  final List<ProductTile> items;
  final String? nextCursor;

  /// 서버가 준 "전체보기" 연결(계약 `Section.viewAllRef`). 형식은 계약에 정해져 있지 않아 있는지만 본다.
  final String? viewAllRef;

  /// 전체보기를 보여도 되는지. 서버가 연결을 주었거나 다음 묶음이 있을 때만(앱이 임의로 만들지 않는다).
  bool get hasViewAll =>
      available && (viewAllRef != null || nextCursor != null);
}

enum HomeTab { home, ranking, isNew }

/// 배너를 눌렀을 때 갈 곳(storefront 0.7.0 `linkType`). NONE·NOTICE 는 누를 수 없다.
enum BannerLink { section, product, category, none }

@immutable
class HomeBanner {
  const HomeBanner({
    required this.bannerId,
    this.imageUrl,
    this.altText,
    this.placement,
    this.link = BannerLink.none,
    this.linkRef,
  });

  /// HOME_TOP(위 넘기기)·HOME_MIDDLE(첫 테마 영역 아래). 없으면 위로 본다.
  final String? placement;
  final BannerLink link;

  /// SECTION → sectionId, PRODUCT → 상품 ID, CATEGORY → 카테고리 ID.
  final String? linkRef;

  bool get middle => placement == 'HOME_MIDDLE';

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
    this.section,
  });

  /// 상위 카테고리 묶음 이름("맛있는것"·"편리한것", 계약 section). 없으면 묶지 않는다.
  final String? section;

  final String categoryId;
  final String? parentId;

  /// 1=상위, 2=하위, 3=칩1, 4=칩2 (계약 CategoryLevel)
  final int depth;
  final String name;
}

/// 정렬. 할인율순은 1차 제외(계약 SortKey).
enum SortKey {
  relevance,
  popular,
  newest,
  priceAsc,
  priceDesc,
  rating,

  /// 리뷰 많은 순(search 0.3.0 `REVIEW_COUNT`).
  reviewCount,
}

@immutable
class ProductQuery {
  const ProductQuery({
    this.keyword,
    this.categoryId,
    this.sort = SortKey.relevance,
    this.filters = const {},
    this.noCorrection = false,
  });

  /// 오타 교정 없이 원래 검색어로(search 0.4.0 `noCorrection`) — "원래 검색어로 찾기".
  final bool noCorrection;

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
    noCorrection: noCorrection,
  );

  @override
  bool operator ==(Object other) =>
      other is ProductQuery &&
      other.keyword == keyword &&
      other.categoryId == categoryId &&
      other.sort == sort &&
      other.noCorrection == noCorrection &&
      setEquals(other.filters, filters);

  @override
  int get hashCode => Object.hash(
    keyword,
    categoryId,
    sort,
    noCorrection,
    Object.hashAllUnordered(filters),
  );
}

@immutable
class ProductPage {
  const ProductPage({
    required this.items,
    this.nextCursor,
    this.total,
    this.correctedQuery,
    this.suggestedQuery,
  });

  /// 원래 검색어가 0건이라 서버가 이 검색어로 고쳐 찾은 결과다(search 0.4.0).
  final String? correctedQuery;

  /// 결과가 적어 서버가 제안하는 검색어(결과는 원래 검색어 것).
  final String? suggestedQuery;

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
    required this.availability,
    this.label,
    this.unitType,
    this.unitsPerSku,
    this.capacityLabel,
    this.basePrice,
    this.priceVersion,
    this.priceNotSet = false,
    this.carried,
    this.unitPrice,
  });

  /// "100g당 999원"(product-content `unitPrice`, 서버 계산). 없으면 줄을 그리지 않는다.
  final UnitPrice? unitPrice;

  final String sku;

  /// 옵션 이름. 옵션 없이 SKU 가 하나뿐인 상품은 없다(SKU 코드를 대신 쓰지 않는다).
  final String? label;
  final UnitType? unitType;
  final int? unitsPerSku;
  final String? capacityLabel;
  final int? basePrice;
  final int? priceVersion;

  /// 유효 가격이 없다(PRICE_NOT_SET). 0원이 아니라 판매 불가다.
  final bool priceNotSet;
  final Availability availability;
  final bool? carried;

  bool get canOfferAdd =>
      !priceNotSet &&
      carried != false &&
      availability != Availability.soldOut &&
      availability != Availability.unknown &&
      availability != Availability.noCenter;
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
    this.mainImageUrl,
    this.descriptionImageUrls = const [],
    this.detailImageUrls = const [],
    this.description,
    this.storageGuide,
    this.returnGuide,
    this.notices = const [],
    this.categoryPath = const [],
    this.rating,
  });

  /// 담을 수 있는 옵션이 하나도 없을 때의 까닭. 담을 수 있는 옵션이 있거나 까닭이 재고·취급이 아니면(가격 미설정 등) null.
  /// "다 팔렸어요"는 [CannotBuyReason.soldOut] 일 때만 쓴다.
  CannotBuyReason? get cannotBuyReason {
    if (options.isEmpty || options.any((o) => o.canOfferAdd)) return null;
    if (options.any((o) => o.availability == Availability.noCenter)) {
      return CannotBuyReason.noCenter;
    }
    if (options.every((o) => o.carried == false)) {
      return CannotBuyReason.notCarried;
    }
    if (options.any(
      (o) => o.carried != false && o.availability == Availability.unknown,
    )) {
      return CannotBuyReason.stockUnknown;
    }
    if (options.every(
      (o) => o.carried == false || o.availability == Availability.soldOut,
    )) {
      return CannotBuyReason.soldOut;
    }
    return null;
  }

  final String productId;
  final String name;

  /// 대표 이미지(계약 mainImage, 없으면 images 의 MAIN).
  final String? mainImageUrl;

  /// 상세설명 롱이미지 조각(role DESCRIPTION). sortOrder 순서대로 이어 붙여 보인다.
  final List<String> descriptionImageUrls;

  /// 상세정보 표 이미지(role DETAIL). sortOrder 순서.
  final List<String> detailImageUrls;
  final String? description;
  final String? storageGuide;
  final String? returnGuide;
  final List<String> notices;
  final List<String> categoryPath;

  /// 집계 없음·실패는 null. 0점·0건으로 표시하지 않는다.
  final RatingSummary? rating;
  final List<SaleOption> options;
}
