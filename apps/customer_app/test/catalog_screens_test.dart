import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:customer_app/features/catalog/presentation/product_list_view.dart'
    show hasBatchim, rieulOrNoBatchim;
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/cart/presentation/cart_screen.dart'
    show AddToCartBar;
import 'package:customer_app/features/catalog/data/mock_catalog_repository.dart';
import 'package:customer_app/features/catalog/domain/catalog.dart';
import 'package:customer_app/features/address/presentation/address_screens.dart'
    show AddressListScreen;
import 'package:customer_app/shared/shopping_context.dart'
    show currentMfcIdProvider;
import 'package:customer_app/features/catalog/presentation/widgets/product_tile_card.dart';

import 'support/app_harness.dart';

/// 상세설명·상세정보 이미지가 있는 상품 상세.
final class _WithContentImages extends MockCatalogRepository {
  _WithContentImages() : super(latency: Duration.zero);

  @override
  Future<ProductDetail> product(String productId, {String? mfcId}) async {
    final p = await super.product(productId, mfcId: mfcId);
    return ProductDetail(
      productId: p.productId,
      name: p.name,
      options: p.options,
      description: p.description,
      notices: p.notices,
      descriptionImageUrls: const [
        'https://img.test/d0',
        'https://img.test/d1',
      ],
      detailImageUrls: const ['https://img.test/t0'],
    );
  }
}

/// 홈 조회 자체가 실패하는 저장소.
/// 상세 응답에는 평점이 없고(null) 평점 집계만 있는 서버.
final class _RatingFromSummary extends MockCatalogRepository {
  _RatingFromSummary({super.latency});

  @override
  Future<RatingSummary?> ratingSummary(String productId) async =>
      const RatingSummary(average: 4.1, count: 480);
}

/// 상세 응답을 [release] 가 끝날 때까지 늦추는 목.
final class _SlowDetail extends MockCatalogRepository {
  _SlowDetail({super.latency});

  final release = Completer<void>();

  @override
  Future<ProductDetail> product(String productId, {String? mfcId}) async {
    await release.future;
    return super.product(productId, mfcId: mfcId);
  }
}

/// 가로 진열 카드를 누르되 상세가 늦게 와도 기다리지 않는다.
Future<void> tapTileNoSettle(WidgetTester t, String productId) async {
  final tiles = find.byKey(ValueKey('tile-$productId'));
  if (tiles.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      tiles,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await t.ensureVisible(tiles.first);
  await t.pumpAndSettle();
  await t.tap(tiles.first);
}

final class _HomeDown extends MockCatalogRepository {
  _HomeDown() : super(latency: Duration.zero);

  @override
  Future<HomeView> home({String? mfcId, HomeTab? tab}) async =>
      throw const NetworkFailure(DioExceptionType.connectionTimeout);
}

/// 검색어별로 응답 시점을 테스트가 정한다.
final class _GatedSearch extends MockCatalogRepository {
  _GatedSearch() : super(latency: Duration.zero);

  final gates = <String, Completer<void>>{};

  @override
  Future<ProductPage> search(
    ProductQuery query, {
    String? mfcId,
    String? cursor,
    CancelToken? cancelToken,
  }) async {
    await (gates[query.keyword ?? ''] ??= Completer<void>()).future;
    return super.search(query, mfcId: mfcId, cursor: cursor);
  }
}

/// 첫 묶음 이후 다음 묶음이 실패한다.
final class _SecondPageDown extends MockCatalogRepository {
  _SecondPageDown() : super(latency: Duration.zero, pageSize: 2);

  @override
  Future<ProductPage> search(
    ProductQuery query, {
    String? mfcId,
    String? cursor,
    CancelToken? cancelToken,
  }) {
    if (cursor != null) {
      throw const NetworkFailure(DioExceptionType.connectionError);
    }
    return super.search(query, mfcId: mfcId, cursor: cursor);
  }
}

/// 서버가 비슷한 상품(BR-87)을 주지 않는 경우.
final class _NoSimilar extends MockCatalogRepository {
  _NoSimilar() : super(latency: Duration.zero);

  @override
  Future<ProductPage> search(
    ProductQuery query, {
    String? mfcId,
    String? cursor,
    CancelToken? cancelToken,
  }) async {
    final p = await super.search(query, mfcId: mfcId, cursor: cursor);
    return ProductPage(
      items: p.items,
      nextCursor: p.nextCursor,
      total: p.total,
      correctedQuery: p.correctedQuery,
      suggestedQuery: p.suggestedQuery,
    );
  }
}

Future<void> _search(WidgetTester t, String keyword) async {
  await t.enterText(find.byKey(const ValueKey('search-field')), keyword);
  await t.tap(find.byKey(const ValueKey('search-submit')));
  await t.pump();
}

void main() {
  setUpAll(initPmartFormatting);

  group('홈', () {
    testWidgets('실패한 영역만 실패로 보이고, 그 영역만 다시 불러온다', (t) async {
      await t.pumpWidget(
        testApp(
          [],
          catalog: MockCatalogRepository(
            latency: Duration.zero,
            unavailableSectionIds: const {'S-WEEKLY'},
          ),
        ),
      );
      await t.pumpAndSettle();

      // 첫 진열 영역은 배송 카드·배너·검색창·카테고리 아래에 있다.
      await t.scrollUntilVisible(
        find.text('지금 많이 사는 상품'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(find.text('지금 많이 사는 상품'), findsOneWidget);
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('tile-P-0001')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('tile-P-0001')), findsWidgets);
      final weekly = find.byKey(const ValueKey('section-unavailable-S-WEEKLY'));
      await t.scrollUntilVisible(
        weekly,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('이 영역을 불러오지 못했어요'), findsOneWidget);

      await t.ensureVisible(find.text('이 영역 다시 불러오기'));
      await t.pumpAndSettle();
      await t.tap(find.text('이 영역 다시 불러오기'));
      await t.pumpAndSettle();

      expect(weekly, findsNothing);
      expect(find.text('이 영역을 불러오지 못했어요'), findsNothing);
    });

    testWidgets('판매중지 상품은 진열에 없다', (t) async {
      await t.pumpWidget(testApp([]));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('tile-P-0008')), findsNothing);
    });

    testWidgets('홈 조회 실패는 빈 화면이 아니라 오류다', (t) async {
      await t.pumpWidget(testApp(const [], catalog: _HomeDown()));
      await t.pumpAndSettle();

      expect(find.text('화면을 불러오지 못했어요'), findsOneWidget);
      expect(find.byKey(const ValueKey('ui-empty')), findsNothing);
    });
  });

  group('검색', () {
    // 백엔드 요청 2026-11-20 search-correction-text(search 0.4.0~0.5.1).
    testWidgets(
      '0건이라 서버가 고친 검색어로 찾았으면 화면 폭 띠 "우유를 찾으시는 것 같아요."(초안 16 B-1, 원래 검색어 링크 없음)',
      (t) async {
        await t.pumpWidget(testApp([]));
        await t.pumpAndSettle();
        await t.tap(find.text('검색').last);
        await t.pumpAndSettle();
        await _search(t, '우우');
        await t.pumpAndSettle();
        final band = find.byKey(const ValueKey('search-corrected'));
        expect(band, findsOneWidget);
        expect(
          find.descendant(
            of: band,
            matching: find.textContaining(
              '우유를 찾으시는 것 같아요.',
              findRichText: true,
            ),
          ),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('search-use-original')), findsNothing);
        expect(find.byKey(const ValueKey('tile-P-0001')), findsWidgets);
        // 속성 줄은 고친 검색어 기준 값으로 — 값 없는 빈 줄이 남지 않는다.
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('attribute-rows')),
            matching: find.byType(InkWell),
          ),
          findsWidgets,
        );
        // 이름 속 검색어(고친 검색어 "우유")를 보라 굵게.
        expect(
          find.textContaining('서울우유 1L', findRichText: true),
          findsWidgets,
        );
      },
    );

    test('을/를·로/으로 받침 맞춤', () {
      expect(hasBatchim('우유'), isFalse);
      expect(hasBatchim('두부김치'), isFalse);
      expect(hasBatchim('라면'), isTrue);
      expect(rieulOrNoBatchim('우유'), isTrue);
      expect(rieulOrNoBatchim('라면'), isFalse);
      expect(rieulOrNoBatchim('과일'), isTrue);
    });

    testWidgets('결과가 적으면 "혹시 ○○를 찾으셨나요?" — 누르면 그 검색어로 새로 찾는다', (t) async {
      await t.pumpWidget(testApp([]));
      await t.pumpAndSettle();
      await t.tap(find.text('검색').last);
      await t.pumpAndSettle();
      await _search(t, '지방 우유');
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-suggested')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('search-suggested')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-suggested')), findsNothing);
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('search-field')))
            .controller!
            .text,
        '저지방 우유',
      );
    });

    testWidgets('정상 상품명(서울우유)은 결과가 적어도 제안하지 않는다(BR-88)', (t) async {
      await t.pumpWidget(testApp([]));
      await t.pumpAndSettle();
      await t.tap(find.text('검색').last);
      await t.pumpAndSettle();
      await _search(t, '서울우유');
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-suggested')), findsNothing);
    });

    testWidgets('0건이면 서버가 준 비슷한 상품 — "이런 상품은 어때요?"(초안 16 B-3, BR-87)', (
      t,
    ) async {
      await t.pumpWidget(testApp([]));
      await t.pumpAndSettle();
      await t.tap(find.text('검색').last);
      await t.pumpAndSettle();
      await _search(t, '우유킥');
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-similar')), findsOneWidget);
      expect(find.text('이런 상품은 어때요?'), findsOneWidget);
      expect(find.byKey(const ValueKey('similar-grid')), findsOneWidget);
      expect(find.byType(ProductTileCard), findsWidgets);
      expect(find.text('검색 결과가 없어요'), findsNothing);
      expect(find.byKey(const ValueKey('open-filters')), findsNothing);
    });

    Future<void> openSearch(WidgetTester t) async {
      await t.pumpAndSettle();
      await t.tap(find.text('검색').last);
      await t.pumpAndSettle();
    }

    testWidgets('검색 결과와 0건을 구분한다(비슷한 상품도 없으면 "검색 결과가 없어요")', (t) async {
      await t.pumpWidget(testApp([], catalog: _NoSimilar()));
      await openSearch(t);

      await _search(t, '우유');
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('tile-P-0001')), findsOneWidget);
      expect(find.byKey(const ValueKey('tile-P-0006')), findsOneWidget);
      expect(find.text('상품 2개'), findsOneWidget);

      await _search(t, '없는상품');
      await t.pumpAndSettle();
      expect(find.text('검색 결과가 없어요'), findsOneWidget);
    });

    testWidgets('늦게 온 이전 검색 응답이 마지막 검색 결과를 덮지 않는다', (t) async {
      final repo = _GatedSearch();
      await t.pumpWidget(testApp(const [], catalog: repo));
      await openSearch(t);

      await _search(t, '우유');
      await _search(t, '감귤');
      repo.gates['감귤']!.complete();
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('tile-P-0003')), findsOneWidget);

      // 이전 검색(우유)의 응답이 이제 도착한다.
      (repo.gates['우유'] ??= Completer<void>()).complete();
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('tile-P-0003')), findsOneWidget);
      expect(find.byKey(const ValueKey('tile-P-0001')), findsNothing);
    });

    testWidgets('필터는 적용해야 반영되고, 닫기는 기존 조건을 유지한다', (t) async {
      await t.pumpWidget(testApp([]));
      await openSearch(t);
      await _search(t, '우유');
      await t.pumpAndSettle();

      await t.tap(find.byKey(const ValueKey('open-filters')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('filter-capacity.1l')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('filter-close')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('tile-P-0006')), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('open-filters')));
      await t.pumpAndSettle();
      // 결과가 0개인 값(감자칩 용량)은 고를 수 없다.
      final zero = t.widget<InkWell>(
        find.descendant(
          of: find.byKey(const ValueKey('filter-capacity.110g')),
          matching: find.byType(InkWell),
        ),
      );
      expect(zero.onTap, isNull);
      await t.tap(find.byKey(const ValueKey('filter-capacity.1l')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('filter-apply')));
      await t.pumpAndSettle();

      expect(find.byKey(const ValueKey('tile-P-0001')), findsOneWidget);
      expect(find.byKey(const ValueKey('tile-P-0006')), findsNothing);
      // 고른 수는 필터 알약 위 작은 동그라미.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('filter-count')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('목록 위 속성 줄: 누르면 바로 거르고, 다시 누르면 푼다. 결과 0개 값은 줄에 없다', (t) async {
      await t.pumpWidget(testApp([]));
      await openSearch(t);
      await _search(t, '우유');
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('attribute-rows')), findsOneWidget);
      // 초안 16 B: 검색 결과에선 0건 값도 흐리게 보이되 누를 수 없다.
      final zero = find.byKey(const ValueKey('attr-capacity.110g'));
      expect(zero, findsOneWidget);
      expect(t.widget<InkWell>(zero).onTap, isNull);
      await t.tap(find.byKey(const ValueKey('attr-capacity.1l')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('tile-P-0001')), findsOneWidget);
      expect(find.byKey(const ValueKey('tile-P-0006')), findsNothing);
      await t.tap(find.byKey(const ValueKey('attr-capacity.1l')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('tile-P-0006')), findsOneWidget);
    });

    testWidgets('초안 15 B: 상위를 누르면 시트 없이 상위 탭·하위 동그라미 화면, 하위를 고르면 그 목록·알약 칩', (
      t,
    ) async {
      await t.pumpWidget(testApp(const []));
      await t.pumpAndSettle();
      await t.tap(find.text('카테고리').last);
      await t.pumpAndSettle();
      await t.tap(find.text('과일·채소·샐러드'));
      await t.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byKey(const ValueKey('category-tabs')), findsOneWidget);
      expect(find.byKey(const ValueKey('category-children')), findsOneWidget);
      final all = find.byKey(const ValueKey('category-child-all'));
      expect(all, findsOneWidget);
      expect(find.byType(ProductTileCard), findsWidgets);
      final childKeys = find.descendant(
        of: find.byKey(const ValueKey('category-children')),
        matching: find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith(
                'category-child-C-',
              ),
        ),
      );
      expect(childKeys, findsWidgets);
      await t.tap(childKeys.first);
      await t.pumpAndSettle();
      // 내려 보면 동그라미 줄 대신 알약 칩 줄이 탭 아래 붙는다.
      expect(find.byKey(const ValueKey('category-pills')), findsNothing);
      await t.drag(find.byType(CustomScrollView).last, const Offset(0, -300));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('category-pills')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('category-pill-all')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('category-pills')), findsNothing);
    });

    testWidgets('초안 15 B: 하위 id 로 들어오면 그 상위 탭 + 그 하위가 골라진 상태', (t) async {
      await t.pumpWidget(testApp(const []));
      await t.pumpAndSettle();
      const child = (categoryId: 'C-FRUIT', name: '과일');
      final router = GoRouter.of(t.element(find.byType(Navigator).first));
      unawaited(router.push('/products?categoryId=${child.categoryId}'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('category-tabs')), findsOneWidget);
      final circle = t.widget<Text>(
        find.descendant(
          of: find.byKey(ValueKey('category-child-${child.categoryId}')),
          matching: find.text(child.name),
        ),
      );
      expect(circle.style?.fontWeight, FontWeight.w700);
    });

    testWidgets('다음 묶음 실패는 받은 목록을 지우지 않는다', (t) async {
      await t.pumpWidget(testApp(const [], catalog: _SecondPageDown()));
      await t.pumpAndSettle();
      await t.tap(find.text('카테고리').last);
      await t.pumpAndSettle();
      await t.tap(find.text('과일·채소·샐러드'));
      await t.pumpAndSettle();
      // 초안 15 B: 동그라미·할인 줄 머리를 지나 격자까지 내린다.
      await t.drag(find.byType(CustomScrollView).last, const Offset(0, -500));
      await t.pumpAndSettle();
      final grid = find.descendant(
        of: find.byType(SliverGrid),
        matching: find.byType(ProductTileCard),
      );

      expect(grid, findsNWidgets(2));
      // 격자 아래의 "더 보기"는 스크롤해야 만들어진다.
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('load-more')),
        200,
        // 세로 목록(초안 15 B 화면엔 가로 탭·칩 줄도 Scrollable 이다).
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .last,
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('load-more')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('load-more')));
      await t.pumpAndSettle();

      expect(find.text('다음 상품을 불러오지 못했어요'), findsOneWidget);
      expect(grid, findsNWidgets(2));
    });

    testWidgets('목록 끝에 가까워지면 "더 보기"를 누르지 않아도 다음 묶음을 받는다', (t) async {
      Future<int> open(MockCatalogRepository repo) async {
        await t.pumpWidget(const SizedBox()); // 앞 화면 상태를 버린다
        await t.pumpWidget(testApp(const [], catalog: repo));
        await t.pumpAndSettle();
        await t.tap(find.text('카테고리').last);
        await t.pumpAndSettle();
        await t.tap(find.text('과일·채소·샐러드'));
        await t.pumpAndSettle();
        await t.drag(find.byType(CustomScrollView).last, const Offset(0, -500));
        await t.pumpAndSettle();
        return find
            .descendant(
              of: find.byType(SliverGrid),
              matching: find.byType(ProductTileCard),
            )
            .evaluate()
            .length;
      }

      final all = await open(
        MockCatalogRepository(latency: Duration.zero, pageSize: 100),
      );
      expect(all, greaterThan(1));
      // 한 묶음 1개여도 남은 카드가 적으니 끝까지 이어 받는다.
      final paged = await open(
        MockCatalogRepository(latency: Duration.zero, pageSize: 1),
      );
      expect(paged, all);
      expect(find.byKey(const ValueKey('load-more')), findsNothing);
    });

    test('리뷰 많은 순(REVIEW_COUNT)은 리뷰 수가 많은 상품부터', () async {
      final page = await MockCatalogRepository(
        latency: Duration.zero,
        pageSize: 100,
      ).search(const ProductQuery(sort: SortKey.reviewCount));
      // 품절 상품은 목록 변환에서 맨 뒤로 가므로 앞쪽 순서만 본다.
      final counts = [for (final p in page.items) p.reviewCount ?? 0];
      expect(counts.take(3), [1203, 640, 312]);
    });
  });

  group('상품 상세', () {
    testWidgets('상세설명 이미지를 순서대로, 상세정보 표는 따로 보인다', (t) async {
      await t.pumpWidget(testApp([], catalog: _WithContentImages()));
      await t.pumpAndSettle();
      await tapTile(t, 'P-0006');

      final d0 = find.byKey(const ValueKey('description-image-0'));
      final d1 = find.byKey(const ValueKey('description-image-1'));
      final t0 = find.byKey(const ValueKey('detail-image-0'));
      await t.scrollUntilVisible(t0, 200);
      expect(d0, findsOneWidget);
      expect(d1, findsOneWidget);
      expect(find.text('상세 정보'), findsOneWidget);
      expect(t.getTopLeft(d0).dy, lessThan(t.getTopLeft(d1).dy));
      expect(t.getTopLeft(d1).dy, lessThan(t.getTopLeft(t0).dy));
    });

    testWidgets('이미지가 없으면 상세 정보 칸을 만들지 않는다', (t) async {
      await t.pumpWidget(testApp([]));
      await t.pumpAndSettle();
      await tapTile(t, 'P-0006');

      expect(find.byKey(const ValueKey('description-image-0')), findsNothing);
      expect(find.text('상세 정보'), findsNothing);
    });

    testWidgets('평점이 없으면 0점이 아니라 "평점 정보 없음"이다', (t) async {
      await t.pumpWidget(testApp([]));
      await t.pumpAndSettle();
      await tapTile(t, 'P-0006');

      expect(find.text('저지방 우유 900mL'), findsOneWidget);
      expect(
        t
            .widget<Text>(find.byKey(const ValueKey('product-rating')))
            .textSpan!
            .toPlainText(),
        '평점 정보 없음',
      );
      expect(find.textContaining('0.0'), findsNothing);
    });

    // LAN 2026-11-19: 상세 응답 rating 은 비었는데 rating-summary 는 480개 — 서버 집계를 먼저 쓴다.
    testWidgets('상세 응답에 평점이 없어도 평점 집계(rating-summary)가 있으면 그것을 보인다', (t) async {
      await t.pumpWidget(
        testApp([], catalog: _RatingFromSummary(latency: Duration.zero)),
      );
      await t.pumpAndSettle();
      await tapTile(t, 'P-0006');

      final text = t
          .widget<Text>(find.byKey(const ValueKey('product-rating')))
          .textSpan!
          .toPlainText();
      expect(text, contains('4.1'));
      expect(text, contains('480'));
    });

    // 백엔드 요청 2026-11-19 상세 속도 R1: 상세 응답 전에도 카드 값(이름·가격)으로 첫 화면.
    testWidgets('카드를 누르면 상세 응답 전에도 카드의 이름·가격이 바로 보이고, 응답이 오면 상세로 바뀐다', (
      t,
    ) async {
      final catalog = _SlowDetail(latency: Duration.zero);
      await t.pumpWidget(testApp([], catalog: catalog));
      await t.pumpAndSettle();
      await tapTileNoSettle(t, 'P-0006');
      await t.pump();
      // 밀려 들어오는 화면(CupertinoPage)은 첫 프레임에 만들어지되 한 프레임 가려져 있다 — 다음 프레임부터 보인다.
      expect(
        find.byKey(const ValueKey('product-preview'), skipOffstage: false),
        findsOneWidget,
      );
      await t.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const ValueKey('product-preview')), findsOneWidget);
      // 밀려 들어오는 동안에는 뒤의 홈 카드도 보인다 — 상세(미리 보기) 안의 이름만 본다.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('product-preview')),
          matching: find.text('저지방 우유 900mL'),
        ),
        findsOneWidget,
      );
      catalog.release.complete();
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('product-preview')), findsNothing);
      expect(find.byKey(const ValueKey('product-rating')), findsOneWidget);
    });

    testWidgets('배달 주소(센터)가 없으면 "다 팔렸어요"가 아니라 주소 안내 — 담기는 막고, 누르면 주소 화면', (
      t,
    ) async {
      await t.pumpWidget(
        testApp([currentMfcIdProvider.overrideWithValue(null)]),
      );
      await t.pumpAndSettle();
      await tapTile(t, 'P-0001');

      expect(
        find.byKey(const ValueKey('product-sold-out-cover')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('product-cannot-buy-noCenter')),
        findsOneWidget,
      );
      expect(find.text('배달 주소를 정하면 살 수 있어요'), findsOneWidget);
      final add = t.widget<AddToCartBar>(find.byType(AddToCartBar));
      expect(add.enabled, isFalse);

      await t.tap(find.byKey(const ValueKey('product-cannot-buy-action')));
      await t.pumpAndSettle();
      expect(find.byType(AddressListScreen), findsOneWidget);
    });

    testWidgets('일시품절이면 담기를 열지 않고 품절로 보인다', (t) async {
      await t.pumpWidget(testApp([]));
      await t.pumpAndSettle();
      // 일시품절은 진열 맨 뒤라 화면 밖이다. 검색으로 찾는다.
      await t.tap(find.text('검색').last);
      await t.pumpAndSettle();
      await _search(t, '토마토');
      await t.pumpAndSettle();
      await tapTile(t, 'P-0004');

      expect(find.byKey(const ValueKey('option-E-00000004')), findsOneWidget);
      expect(find.textContaining('일시품절'), findsWidgets);
      final add = t.widget<AddToCartBar>(find.byType(AddToCartBar));
      expect(add.enabled, isFalse);
    });

    testWidgets('옵션이 하나뿐이면 옵션 선택이 없고 가격·담기만 보인다', (t) async {
      await t.pumpWidget(testApp([]));
      await t.pumpAndSettle();
      await tapTile(t, 'P-0006');

      expect(find.text('옵션 선택'), findsNothing);
      expect(find.byType(RadioListTile<String>), findsNothing);
      expect(find.byKey(const ValueKey('product-price')), findsOneWidget);
      // 라벨이 없어도 SKU 코드는 보이지 않는다.
      expect(find.textContaining('E-0000'), findsNothing);
      final add = t.widget<AddToCartBar>(find.byType(AddToCartBar));
      expect(add.enabled, isTrue);
      expect(add.sku, 'E-00000006');
    });

    testWidgets('묶음 옵션은 별도 SKU 로 보인다', (t) async {
      await t.pumpWidget(testApp([]));
      await t.pumpAndSettle();
      await tapTile(t, 'P-0001');
      // 큰 가격·단위 가격 줄 아래라 옵션이 화면 밖일 수 있다.
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('option-B-00000011')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await t.pumpAndSettle();

      expect(find.byKey(const ValueKey('option-E-00000001')), findsOneWidget);
      expect(find.byKey(const ValueKey('option-B-00000011')), findsOneWidget);
      expect(find.text('5,800원'), findsOneWidget);
    });
  });
}
