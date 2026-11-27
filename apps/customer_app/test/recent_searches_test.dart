import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart' show NetworkFailure;
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/catalog/data/mock_catalog_repository.dart';
import 'package:customer_app/features/catalog/data/recent_searches_repository.dart';
import 'package:customer_app/features/catalog/presentation/catalog_providers.dart';

import 'support/app_harness.dart';

Future<void> _login(WidgetTester t) async {
  await t.tap(find.text('마이페이지').last);
  await t.pumpAndSettle();
  await t.tap(find.byKey(const ValueKey('my-login')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const ValueKey('login-kakao')));
  await t.pumpAndSettle();
}

Future<void> _openSearch(WidgetTester t) async {
  await openSearchScreen(t);
  await t.pumpAndSettle();
}

void main() {
  setUpAll(initPmartFormatting);

  MockRecentSearchesRepository repo0() =>
      MockRecentSearchesRepository(latency: Duration.zero);

  testWidgets('비회원은 최근 검색어 칸이 없다', (t) async {
    final repo = repo0();
    await t.pumpWidget(
      testApp([recentSearchesRepositoryProvider.overrideWithValue(repo)]),
    );
    await t.pumpAndSettle();
    await _openSearch(t);
    expect(find.text('최근 검색어'), findsNothing);
  });

  testWidgets('회원: 누르면 그 검색어로 검색, 지우기는 서버가 받은 뒤 빠진다, 칸을 비우면 다시 보인다', (t) async {
    final repo = repo0();
    await t.pumpWidget(
      testApp([recentSearchesRepositoryProvider.overrideWithValue(repo)]),
    );
    await t.pumpAndSettle();
    await _login(t);
    await _openSearch(t);

    expect(find.byKey(const ValueKey('recent-우유')), findsOneWidget);
    expect(find.byKey(const ValueKey('recent-감귤')), findsOneWidget);

    // 지우기 실패: 그대로 남고 안내
    repo.failNextDelete = true;
    await t.tap(find.byTooltip('감귤 삭제'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('recent-감귤')), findsOneWidget);
    expect(find.text('지우지 못했어요. 잠시 후 다시 시도해 주세요'), findsOneWidget);

    await t.tap(find.byTooltip('감귤 삭제'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('recent-감귤')), findsNothing);
    expect(repo.deleteKeys.toSet().length, 2); // 누를 때마다 새 키

    await t.tap(find.byKey(const ValueKey('recent-우유')));
    await t.pumpAndSettle();
    expect(find.text('최근 검색어'), findsNothing); // 결과 화면
    expect(find.byKey(const ValueKey('tile-P-0001')), findsOneWidget);

    await t.enterText(find.byKey(const ValueKey('search-field')), '');
    await t.pumpAndSettle();
    expect(find.text('최근 검색어'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('recent-clear')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('recent-empty')), findsOneWidget);
  });

  testWidgets('조회 실패는 "없음"이 아니라 실패로 보이고 다시 시도할 수 있다', (t) async {
    final repo = repo0()..failNextList = true;
    await t.pumpWidget(
      testApp([recentSearchesRepositoryProvider.overrideWithValue(repo)]),
    );
    await t.pumpAndSettle();
    await _login(t);
    await _openSearch(t);

    expect(find.byKey(const ValueKey('recent-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('recent-empty')), findsNothing);
    await t.tap(find.text('다시 시도'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('recent-우유')), findsOneWidget);
  });

  // 인기 검색어(search 0.5.2 — `GET /search/suggestions` 를 q 없이).
  testWidgets('인기 검색어: 비회원에게도 서버 순서대로 번호를 붙여 보이고, 누르면 그 검색어로 검색', (t) async {
    await t.pumpWidget(
      testApp([recentSearchesRepositoryProvider.overrideWithValue(repo0())]),
    );
    await t.pumpAndSettle();
    await _openSearch(t);

    expect(find.text('인기 검색어'), findsOneWidget);
    // 접힌 상자에는 하나씩(1위부터) — [펼쳐서 보기]로 전체(사용자 레퍼런스 2026-11-26).
    await t.tap(find.byKey(const ValueKey('popular-expand')));
    await t.pumpAndSettle();
    final first = find.byKey(const ValueKey('popular-1'));
    expect(
      find.descendant(of: first, matching: find.text('우유')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('popular-2')),
        matching: find.text('요거트'),
      ),
      findsOneWidget,
    );

    await t.tap(first);
    await t.pumpAndSettle();
    expect(find.text('인기 검색어'), findsNothing); // 결과 화면
    expect(find.byKey(const ValueKey('tile-P-0001')), findsOneWidget);
  });

  testWidgets('인기 검색어: 집계가 없으면(빈 목록) 구역을 숨긴다', (t) async {
    await t.pumpWidget(
      testApp([
        recentSearchesRepositoryProvider.overrideWithValue(repo0()),
      ], catalog: _Popular(const [])),
    );
    await t.pumpAndSettle();
    await _openSearch(t);
    expect(find.byKey(const ValueKey('popular-keywords')), findsNothing);
    expect(find.text('인기 검색어'), findsNothing);
  });

  testWidgets('인기 검색어: 못 읽어도 구역만 숨기고 최근 검색어·검색은 그대로', (t) async {
    await t.pumpWidget(
      testApp([
        recentSearchesRepositoryProvider.overrideWithValue(repo0()),
      ], catalog: _Popular(null)),
    );
    await t.pumpAndSettle();
    await _login(t);
    await _openSearch(t);
    expect(find.byKey(const ValueKey('popular-keywords')), findsNothing);
    expect(find.byKey(const ValueKey('recent-우유')), findsOneWidget);

    await t.enterText(find.byKey(const ValueKey('search-field')), '우유');
    await t.tap(find.byKey(const ValueKey('search-submit')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('tile-P-0001')), findsOneWidget);
  });
}

/// 인기 검색어 응답을 정한다(null = 조회 실패).
final class _Popular extends MockCatalogRepository {
  _Popular(this.keywords) : super(latency: Duration.zero);

  final List<String>? keywords;

  @override
  Future<List<String>> popularKeywords() async =>
      keywords ??
      (throw const NetworkFailure(DioExceptionType.connectionTimeout));
}
