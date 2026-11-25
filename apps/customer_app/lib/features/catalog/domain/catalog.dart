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
    this.discount,
    this.soldOut = false,
    this.lowStockQty,
  });

  /// 목록 카드 품절(search 0.10.0 `SearchHit.availability`·storefront 0.13.0 `DisplayItem.availability` = SOLD_OUT —
  /// 그 센터가 취급하는 옵션이 모두 품절). UNKNOWN·null(센터 모름·조회 실패)은 false — 품절이라고 하지 않는다.
  /// 목록 순서는 바꾸지 않는다(백엔드 회신 2026-11-23 "거르지도 줄 세우지도 않는다").
  final bool soldOut;

  /// "N개 남음"(storefront 0.18.0·search 0.14.0 BR-100 R7) — 넉넉한 옵션이 없고 남은 게 적을 때(10개 이하)만.
  /// 안내일 뿐 확보가 아니다. 없으면 null.
  final int? lowStockQty;

  /// 기간 할인(storefront 0.8.0·search 0.6.0, ADR-0082 4단계). 없으면 정가만 보인다. 결제 금액은 주문서 견적.
  final SaleDiscount? discount;

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
  bool get canOfferAdd =>
      saleState == SaleState.onSale && carried != false && !soldOut;
}

/// 표시용 기간 할인(서버 값 — 할인가·할인율을 앱이 계산하지 않는다). 결제 금액은 주문서 견적이 정한다.
@immutable
class SaleDiscount {
  const SaleDiscount({
    required this.salePrice,
    this.ratePercent,
    this.name,
    this.endsAt,
  });

  /// 할인가(개당).
  final int salePrice;

  /// 할인율(내림, %). 없으면 할인율을 적지 않는다.
  final int? ratePercent;
  final String? name;
  final DateTime? endsAt;
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

  /// storefront 0.10.0 배너 묶음(HOME_INLINE) — 상품 대신 [HomeSection.banners].
  banner,
  unknown,
}

/// 타이머 테마 머리 모양(storefront 0.12.0 `timerStyle`, BR-84 — 운영자가 편성에서 고른다).
/// [label] = 초안 06-C 제목 위 분홍 글자(기본·값 없음), [band] = 06-D 연분홍 띠 + 시·분·초 칸.
enum TimerStyle { label, band }

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
    this.endsAt,
    this.showTimer = false,
    this.timerStyle = TimerStyle.label,
    this.banners = const [],
    this.intervalSeconds,
  });

  /// [showTimer] 일 때의 머리 모양. 서버 값이 없으면 [TimerStyle.label].
  final TimerStyle timerStyle;

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

  /// storefront 0.9.0 편성 테마의 끝 시각(지나면 서버가 뺀다).
  final DateTime? endsAt;

  /// true 면 제목 옆에 [endsAt] 까지 남은 시간을 보이고, 0 이 되면 영역을 숨긴다(백엔드 요청서 2026-11-21 ③).
  final bool showTimer;

  /// storefront 0.10.0 배너 묶음 영역(kind BANNER, HOME_INLINE): 이 자리에서 넘겨 보는 배너(서버 순서).
  final List<HomeBanner> banners;

  /// 배너 묶음의 자동 넘김 간격(초). null 이면 홈 `bannerIntervalSeconds` → 앱 기본값.
  final int? intervalSeconds;

  /// 순위 진열(랭킹 탭·자동 랭킹 테마 — 항목마다 badge RANK·rank). 홈에서는 순위 숫자를 단 3칸 격자로 그린다.
  bool get ranked =>
      items.isNotEmpty &&
      items.every((t) => t.badge == DisplayBadge.rank && t.rank != null);

  /// 서버가 다음 묶음·연결 없이 한 번에 준 순위 진열(자동 랭킹 테마 — storefront 0.9.0, 상위 N).
  /// 전체 보기는 받은 목록을 그대로 보인다.
  bool get rankedComplete => ranked && nextCursor == null && viewAllRef == null;

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

/// MD 탭(storefront 0.9.0, 백엔드 요청서 2026-11-21 ⑤). 내용은 `GET /storefront/custom-tabs/{tabKey}`.
@immutable
class CustomTab {
  const CustomTab({
    required this.tabKey,
    required this.title,
    this.endsAt,
    this.showTimer = false,
  });

  /// `X-…`
  final String tabKey;
  final String title;

  /// 기간 끝(지나면 탭을 지운다 — 서버도 404 TAB_NOT_FOUND).
  final DateTime? endsAt;

  /// true 면 탭 이름 위에 남은 시간.
  final bool showTimer;
}

@immutable
class HomeView {
  const HomeView({
    required this.layoutVersion,
    required this.tabs,
    required this.banners,
    required this.sections,
    this.customTabs = const [],
    this.bannerIntervalSeconds,
  });

  final int layoutVersion;
  final List<HomeTab> tabs;

  /// MD 탭(storefront 0.9.0 `customTabs`) — 고정 탭 뒤에 서버 순서로 붙인다.
  final List<CustomTab> customTabs;

  /// storefront 0.10.0 맨 위 배너 자동 넘김 간격(초). null 이면 앱 기본값. 배너가 1개면 넘기지 않는다.
  final int? bannerIntervalSeconds;
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
    customTabs: customTabs,
    bannerIntervalSeconds: bannerIntervalSeconds,
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

  /// 할인율 높은 순(search 0.9.0 `DISCOUNT_RATE`, BR-83) — 할인 목록(onSale)에서만. 다른 목록에서 보내면 서버가 400.
  discountRate,
}

@immutable
class ProductQuery {
  const ProductQuery({
    this.keyword,
    this.categoryId,
    this.sort = SortKey.relevance,
    this.filters = const {},
    this.noCorrection = false,
    this.onSale = false,
  });

  /// 지금 기간 할인이 있는 상품만(search 0.8.0 `onSale`, BR-82) — 카테고리 [할인] 타일.
  final bool onSale;

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
    onSale: onSale,
  );

  @override
  bool operator ==(Object other) =>
      other is ProductQuery &&
      other.keyword == keyword &&
      other.categoryId == categoryId &&
      other.sort == sort &&
      other.noCorrection == noCorrection &&
      other.onSale == onSale &&
      setEquals(other.filters, filters);

  @override
  int get hashCode => Object.hash(
    keyword,
    categoryId,
    sort,
    noCorrection,
    onSale,
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
    this.similarItems,
  });

  /// 첫 쪽이 0건(교정해도 0건)일 때 서버가 고른 비슷한 상품(search 0.12.0, BR-87). 없으면 null.
  final List<ProductTile>? similarItems;

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
    this.discount,
    this.lowStockQty,
  });

  /// 기간 할인(pricing 0.3.0 `discount`). 없거나 모르면(discountAvailable=false) null — 정가만.
  final SaleDiscount? discount;

  /// 남은 수량(product-content 0.10.0 BR-100 R7 — availability LOW 일 때만, 10개 이하).
  final int? lowStockQty;

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

/// 영양 기준 단위(product-content 0.6.0 `basisUnit`) — 100g당 / 100mL당.
enum NutritionBasis { gram, milliliter }

/// 상품 영양(100g·100mL 기준, 서버 값 그대로 — 반올림·계산하지 않는다). 모르는 칸은 null.
@immutable
class ProductNutrition {
  const ProductNutrition({
    required this.basis,
    this.energyKcal,
    this.sodiumMg,
    this.sugarsG,
    this.proteinG,
    this.fatG,
  });

  final NutritionBasis basis;
  final num? energyKcal;
  final num? sodiumMg;
  final num? sugarsG;
  final num? proteinG;
  final num? fatG;
}

/// 상품 알레르기(product-content 0.6.0, 법정 이름). [contains] 함유 · [mayContain] 같은 시설 제조 · [text] 표시사항 원문.
@immutable
class ProductAllergens {
  const ProductAllergens({
    this.contains = const [],
    this.mayContain = const [],
    this.text,
  });

  final List<String> contains;
  final List<String> mayContain;
  final String? text;

  /// 두 목록이 다 비었다 — 모름(알레르기가 없다는 뜻이 아니다).
  bool get unknown => contains.isEmpty && mayContain.isEmpty;
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
    this.origin,
    this.purchaseLimitUnits,
    this.expiryGuide,
    this.legalInfo,
    this.categoryPath = const [],
    this.rating,
    this.nutrition,
    this.allergens,
  });

  /// 영양(product-content 0.6.0). null = 모름("정보 없음" — 0 으로 바꾸지 않는다).
  final ProductNutrition? nutrition;

  /// 알레르기(product-content 0.6.0). null 이거나 두 목록이 다 비면 모름(알레르기 "없음"이 아니다).
  final ProductAllergens? allergens;

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

  /// 원산지 값(product-content 0.9.0 BR-100 R1). 없으면 null.
  final String? origin;

  /// 1회 최대 구매 낱개 수 — 이 상품 모든 옵션 합(product-content 0.11.0 BR-101). 확정은 서버 거절. 없으면 null.
  final int? purchaseLimitUnits;

  /// 소비기한·제조일 안내 값(0.9.0 R1). 없으면 null.
  final String? expiryGuide;

  /// 상품정보제공고시 표(0.9.0 R1 — notices 줄 순서, ":" 없으면 label null). 옛 응답이면 null.
  final List<({String? label, String value})>? legalInfo;
  final List<String> categoryPath;

  /// 집계 없음·실패는 null. 0점·0건으로 표시하지 않는다.
  final RatingSummary? rating;
  final List<SaleOption> options;
}

/// 상품페이지 관리 카드 묶음(storefront 0.20.0 BR-102). [title] 이 없거나 [items] 가 비면 앱은 구획을 뺀다.
@immutable
class CareCards {
  const CareCards({this.title, this.items = const []});

  final String? title;
  final List<CareCard> items;
}

@immutable
class CareCard {
  const CareCard({
    required this.cardId,
    required this.title,
    required this.body,
    this.imageUrl,
  });

  final String cardId;
  final String title;

  /// 줄바꿈(`\n`) 그대로.
  final String body;
  final String? imageUrl;
}
