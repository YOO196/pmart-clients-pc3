import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/catalog/data/mock_catalog_repository.dart';
import 'package:customer_app/features/catalog/domain/catalog.dart';

import 'support/app_harness.dart';

/// 홈 조회 자체가 실패하는 저장소.
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

Future<void> _search(WidgetTester t, String keyword) async {
  await t.enterText(find.byKey(const ValueKey('search-field')), keyword);
  await t.tap(find.byKey(const ValueKey('search-submit')));
  await t.pump();
}

void main() {
  setUpAll(initPmartFormatting);

  group('홈', () {
    testWidgets('실패한 영역만 실패로 보이고, 그 영역만 다시 불러온다', (t) async {
      await t.pumpWidget(testApp([]));
      await t.pumpAndSettle();

      expect(find.text('지금 많이 사는 상품'), findsOneWidget);
      expect(find.byKey(const ValueKey('tile-P-0001')), findsWidgets);
      final weekly = find.byKey(const ValueKey('section-unavailable-S-WEEKLY'));
      await t.scrollUntilVisible(
        weekly,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('이 영역을 불러오지 못했어요'), findsOneWidget);

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

      expect(find.text('정보를 불러오지 못했어요'), findsOneWidget);
      expect(find.byKey(const ValueKey('ui-empty')), findsNothing);
    });
  });

  group('검색', () {
    Future<void> openSearch(WidgetTester t) async {
      await t.pumpAndSettle();
      await t.tap(find.text('검색').last);
      await t.pumpAndSettle();
    }

    testWidgets('검색 결과와 0건을 구분한다', (t) async {
      await t.pumpWidget(testApp([]));
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
      final zero = t.widget<FilterChip>(
        find.byKey(const ValueKey('filter-capacity.110g')),
      );
      expect(zero.onSelected, isNull);
      await t.tap(find.byKey(const ValueKey('filter-capacity.1l')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('filter-apply')));
      await t.pumpAndSettle();

      expect(find.byKey(const ValueKey('tile-P-0001')), findsOneWidget);
      expect(find.byKey(const ValueKey('tile-P-0006')), findsNothing);
      expect(find.text('필터 1'), findsOneWidget);
    });

    testWidgets('다음 묶음 실패는 받은 목록을 지우지 않는다', (t) async {
      await t.pumpWidget(testApp(const [], catalog: _SecondPageDown()));
      await t.pumpAndSettle();
      await t.tap(find.text('카테고리').last);
      await t.pumpAndSettle();
      await t.tap(find.text('과일·채소'));
      await t.pumpAndSettle();
      await t.tap(find.text('과일·채소 전체'));
      await t.pumpAndSettle();

      expect(find.byType(Card), findsNWidgets(2));
      await t.tap(find.byKey(const ValueKey('load-more')));
      await t.pumpAndSettle();

      expect(find.text('다음 상품을 불러오지 못했어요'), findsOneWidget);
      expect(find.byType(Card), findsNWidgets(2));
    });
  });

  group('상품 상세', () {
    testWidgets('평점이 없으면 0점이 아니라 "평점 정보 없음"이다', (t) async {
      await t.pumpWidget(testApp([]));
      await t.pumpAndSettle();
      await tapTile(t, 'P-0006');

      expect(find.text('저지방 우유 900mL'), findsOneWidget);
      expect(
        t.widget<Text>(find.byKey(const ValueKey('product-rating'))).data,
        '평점 정보 없음',
      );
      expect(find.textContaining('0.0'), findsNothing);
    });

    testWidgets('일시품절 옵션은 고를 수 없다', (t) async {
      await t.pumpWidget(testApp([]));
      await t.pumpAndSettle();
      // 일시품절은 진열 맨 뒤라 화면 밖이다. 검색으로 찾는다.
      await t.tap(find.text('검색').last);
      await t.pumpAndSettle();
      await _search(t, '토마토');
      await t.pumpAndSettle();
      await tapTile(t, 'P-0004');

      final option = t.widget<RadioListTile<String>>(
        find.byKey(const ValueKey('option-E-00000004')),
      );
      expect(option.enabled, isFalse);
      expect(find.textContaining('일시품절'), findsWidgets);
    });

    testWidgets('묶음 옵션은 별도 SKU 로 보인다', (t) async {
      await t.pumpWidget(testApp([]));
      await t.pumpAndSettle();
      await tapTile(t, 'P-0001');

      expect(find.byKey(const ValueKey('option-E-00000001')), findsOneWidget);
      expect(find.byKey(const ValueKey('option-B-00000011')), findsOneWidget);
      expect(find.text('5,800원'), findsOneWidget);
    });
  });
}
