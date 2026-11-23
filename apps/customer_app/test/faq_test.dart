import 'package:dio/dio.dart' show Dio, DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/support/data/faq_repository.dart';
import 'package:customer_app/features/support/data/mock_faq_repository.dart';
import 'package:customer_app/features/support/domain/faq.dart';
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

    // 레퍼런스 고객센터 3: 다른 화면으로 가지 않고 그 자리에서 펼친다 — 다시 누르면 접힌다.
    expect(find.byType(FaqDetailScreen), findsNothing);
    expect(find.byKey(const ValueKey('faq-open-faq-cancel-1')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('faq-faq-cancel-1')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('faq-open-faq-cancel-1')), findsNothing);
    expect(find.byType(MarkdownBody), findsNothing);
  });

  test('답 안 링크는 앱 안 화면만 연다', () {
    expect(FaqAnswer.opens('/orders'), isTrue);
    expect(FaqAnswer.opens('/orders/o-1'), isTrue);
    expect(FaqAnswer.opens('https://example.com'), isFalse);
    expect(FaqAnswer.opens('//evil.example'), isFalse);
    expect(FaqAnswer.opens('/payments/x'), isFalse);
    expect(FaqAnswer.opens(null), isFalse);
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

  group('질문 유형(사용자 2026-11-21 — 4줄 넘으면 더보기, 고른 것 검정)', () {
    final many = [
      for (final (i, t) in const [
        '반품·교환',
        '결제',
        '회원 정보',
        '쿠폰·할인',
        '주문 변경',
        '배송지',
        '상품 문의',
        '품절·결품',
        '오배송',
        '파손',
        '영수증',
        '리뷰',
        '찜',
        '알림',
        '탈퇴',
        '앱 사용',
        '개인정보',
        '기타',
      ].indexed)
        FaqCategory(category: 'X$i', title: t, count: 0),
    ];

    Future<void> openList(WidgetTester t) async {
      faqs = MockFaqRepository(latency: Duration.zero, extraCategories: many);
      await openSupport(t);
      t.view
        ..physicalSize = const Size(360, 1400)
        ..devicePixelRatio = 1;
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('support-faqs')));
      await t.pumpAndSettle();
    }

    testWidgets('4줄까지만 보이고 [더보기]로 전부, [접기]로 다시', (t) async {
      await openList(t);
      final last = find.byKey(const ValueKey('faq-cat-X17'));
      expect(last, findsNothing);
      expect(find.text('더보기'), findsOneWidget);
      // 보이는 알약은 4줄 안
      final tops = {
        for (final e
            in find
                .byWidgetPredicate(
                  (w) =>
                      w.key is ValueKey<String> &&
                      (w.key! as ValueKey<String>).value.startsWith('faq-cat-'),
                )
                .evaluate())
          t.getTopLeft(find.byWidget(e.widget)).dy.round(),
      };
      expect(tops.length, lessThanOrEqualTo(4));
      await t.tap(find.byKey(const ValueKey('faq-types-more')));
      await t.pumpAndSettle();
      expect(last, findsOneWidget);
      expect(find.text('접기'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('faq-types-more')));
      await t.pumpAndSettle();
      expect(last, findsNothing);
    });

    testWidgets('고른 유형은 검정 바탕, 4줄 밖 유형을 골랐으면 펼친 채로', (t) async {
      await openList(t);
      await t.tap(find.byKey(const ValueKey('faq-types-more')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('faq-cat-X17')));
      await t.pumpAndSettle();
      expect(faqs.queries.last.category, 'X17');
      // 접기를 눌러도 고른 것이 4줄 밖이면 펼친 채로 둔다
      await t.tap(find.byKey(const ValueKey('faq-types-more')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('faq-cat-X17')), findsOneWidget);
      final box = t.widget<Container>(
        find.descendant(
          of: find.byKey(const ValueKey('faq-cat-X17')),
          matching: find.byType(Container),
        ),
      );
      final scheme = Theme.of(
        t.element(find.byKey(const ValueKey('faq-cat-X17'))),
      ).colorScheme;
      expect((box.decoration! as BoxDecoration).color, scheme.onSurface);
    });

    test('줄 계산: 폭이 넉넉하면 전부, 좁으면 4줄까지만', () {
      final labels = [for (var i = 0; i < 30; i++) '유형$i'];
      expect(chipsFitInLines(labels, 100000, null, lines: 4), 30);
      final n = chipsFitInLines(labels, 200, null, lines: 4);
      expect(n, lessThan(30));
      expect(n, greaterThan(0));
    });
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
