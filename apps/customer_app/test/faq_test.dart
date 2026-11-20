import 'package:dio/dio.dart' show Dio, DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/support/data/faq_repository.dart';
import 'package:customer_app/features/support/data/mock_faq_repository.dart';
import 'package:customer_app/features/support/presentation/faq_screens.dart';
import 'package:customer_app/shared/providers.dart' show sourceSystem;

import 'support/app_harness.dart';

/// 자주 묻는 질문(customer-assistant 0.2.0, 백엔드 알림 2026-11-18 gap-a §8). 목 모드.
void main() {
  setUpAll(initPmartFormatting);

  late MockFaqRepository faqs;
  setUp(() => faqs = MockFaqRepository(latency: Duration.zero));

  Future<void> openSupport(WidgetTester t, {bool login = true}) async {
    t.view
      ..physicalSize = const Size(800, 2000)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp([faqRepositoryProvider.overrideWithValue(faqs)]),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    if (login) {
      await t.tap(find.byKey(const ValueKey('my-login')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('login-kakao')));
      await t.pumpAndSettle();
    }
    await t.tap(find.byKey(const ValueKey('my-support')));
    await t.pumpAndSettle();
  }

  testWidgets('고객센터 메인: 분류 칩 → 그 분류로 서버에 묻고, 질문을 누르면 답을 마크다운으로', (t) async {
    await openSupport(t);
    expect(
      find.byKey(const ValueKey('support-faq-cat-CANCEL')),
      findsOneWidget,
    );
    await t.tap(find.byKey(const ValueKey('support-faq-cat-CANCEL')));
    await t.pumpAndSettle();
    expect(faqs.queries.last, (q: null, category: 'CANCEL'));
    expect(find.byKey(const ValueKey('faq-faq-cancel-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('faq-faq-refund-1')), findsNothing);

    await t.tap(find.byKey(const ValueKey('faq-faq-cancel-1')));
    await t.pumpAndSettle();
    expect(find.byType(MarkdownBody), findsOneWidget);
    // 마크다운 기호(##, **)가 글자로 보이지 않는다.
    expect(find.textContaining('##'), findsNothing);
    expect(find.textContaining('**'), findsNothing);
  });

  testWidgets('폰 크기 화면: 질문 유형을 고른 뒤 질문 목록이 화면 전체와 같이 내려간다(좁은 칸에 갇히지 않음)', (
    t,
  ) async {
    await openSupport(t);
    // 360x640dp 폰(질문 유형 알약이 여러 줄)
    t.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('support-faqs')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('faq-cat-CANCEL')));
    await t.pumpAndSettle();
    // 질문 유형·목록이 한 스크롤이다 — 목록의 첫 질문까지 내려 볼 수 있다.
    final first = find.byKey(const ValueKey('faq-faq-cancel-1'));
    await t.scrollUntilVisible(
      first,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('faq-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await t.pumpAndSettle();
    final r = t.getRect(first);
    expect(r.top, greaterThanOrEqualTo(0));
    expect(r.bottom, lessThanOrEqualTo(640));
    expect(r.height, greaterThan(30)); // 줄이 잘리지 않고 다 보인다
    await t.tap(first);
    await t.pumpAndSettle();
    expect(find.byType(MarkdownBody), findsOneWidget);
  });

  testWidgets('검색칸: 검색어를 q 로 묻고, 결과가 없으면 "찾는 질문이 없어요"', (t) async {
    await openSupport(t);
    await t.enterText(find.byKey(const ValueKey('faq-search-field')), '포인트');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
    expect(faqs.queries.last.q, '포인트');
    expect(find.byKey(const ValueKey('faq-empty')), findsOneWidget);
  });

  testWidgets('조회 실패는 빈 FAQ 가 아니라 실패 안내', (t) async {
    faqs.failNext = const NetworkFailure(DioExceptionType.connectionError);
    await openSupport(t);
    expect(find.byKey(const ValueKey('support-faq-failed')), findsOneWidget);
  });

  testWidgets('비회원에게는 FAQ 구역을 두지 않는다(서버 403)', (t) async {
    await openSupport(t, login: false);
    expect(find.byKey(const ValueKey('support-faqs')), findsNothing);
    expect(faqs.queries, isEmpty);
  });

  test('API: GET /customer-assistant/faqs?q=&category=', () async {
    final adapter = FakeAdapter(
      (_, _) async => const FakeReply(
        200,
        body: {
          'items': [
            {
              'faqId': 'f-1',
              'category': 'CANCEL',
              'categoryTitle': '취소',
              'question': 'Q',
              'answer': '**A**',
            },
          ],
          'categories': [
            {'category': 'CANCEL', 'title': '취소', 'count': 1},
          ],
        },
      ),
    );
    final Dio dio = createPmartDio(
      baseUrl: 'http://test.invalid/api/v1',
      sourceSystem: sourceSystem,
      tokens: TokenStore(MemoryKeyValueStore()),
      refresher: (_) async => null,
      adapter: adapter,
      delay: (_) async {},
    );
    final list = await ApiFaqRepository(dio).list(q: '취소', category: 'CANCEL');
    final sent = adapter.requests.single;
    expect(sent.path, endsWith('/customer-assistant/faqs'));
    expect(sent.uri.queryParameters, {'q': '취소', 'category': 'CANCEL'});
    expect(list.items.single.answer, '**A**');
    expect(list.categories.single.count, 1);
  });
}
