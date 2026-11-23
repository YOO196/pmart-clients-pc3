import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_api_notification/pmart_api_notification.dart' as api;
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/notifications/data/mock_notifications_repository.dart';
import 'package:customer_app/features/notifications/data/notifications_repository.dart';
import 'package:customer_app/features/notifications/domain/notifications.dart';
import 'package:customer_app/features/push/domain/push_route.dart';
import 'package:customer_app/features/reviews/data/mock_reviews_repository.dart';
import 'package:customer_app/features/reviews/presentation/reviews_screens.dart';

import 'support/app_harness.dart';

/// 리뷰 요청 알림(notification 0.4.4 `templateKey` REVIEW_REQUESTED) → 그 주문의 리뷰 쓰기. 목 모드.
void main() {
  setUpAll(initPmartFormatting);

  Map<String, dynamic> reviewNotice(String orderId) => {
    'notificationId': 'ntf-rv',
    'category': 'ORDER',
    'templateKey': 'REVIEW_REQUESTED',
    'title': '받은 상품은 어떠셨나요?',
    'body': '상품 리뷰를 남겨 주세요.',
    'destination': {'type': 'ORDER', 'ref': orderId},
    'sourceEventId': 'evt-rv',
    'sourceEventType': 'DeliveryCompleted',
    'state': 'NOTICE_UNREAD',
    'createdAt': '2026-10-24T03:30:00Z',
    'readAt': null,
  };

  Map<String, dynamic> eligible(String orderId, String line, String name) => {
    'orderId': orderId,
    'orderLineId': line,
    'productId': 'P-$line',
    'productName': name,
    'deliveredAt': '2026-10-24T02:30:00Z',
    'eligibleUntil': '2026-11-07T02:30:00Z',
    'state': 'REV_ELIGIBLE',
    'reviewId': null,
  };

  Future<void> tapReviewNotice(
    WidgetTester t, {
    required String orderId,
    required MockReviewsRepository reviews,
  }) async {
    t.view
      ..physicalSize = const Size(800, 2000)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp(
        const [],
        notifications: MockNotificationsRepository(
          latency: Duration.zero,
          notices: [reviewNotice(orderId)],
        ),
        reviews: reviews,
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-notifications')));
    await t.pumpAndSettle();
    await t.tap(find.text('받은 상품은 어떠셨나요?'));
    await t.pumpAndSettle();
  }

  testWidgets('쓸 상품이 하나면 바로 리뷰 쓰기 화면', (t) async {
    await tapReviewNotice(
      t,
      orderId: 'order-seed-1',
      reviews: MockReviewsRepository(latency: Duration.zero),
    );
    expect(find.byType(ReviewWriteScreen), findsOneWidget);
    expect(
      t
          .widget<ReviewWriteScreen>(find.byType(ReviewWriteScreen))
          .target
          .orderLineId,
      'ol-1',
    );
  });

  testWidgets('여럿이면 고르기, 고르면 그 상품의 쓰기', (t) async {
    await tapReviewNotice(
      t,
      orderId: 'order-x',
      reviews: MockReviewsRepository(
        latency: Duration.zero,
        eligibilities: [
          eligible('order-x', 'l-1', '우유'),
          eligible('order-x', 'l-2', '요거트'),
        ],
      ),
    );
    expect(
      find.byKey(const ValueKey('order-review-entry-list')),
      findsOneWidget,
    );
    // 초안 09-B: 주문 머리 + 품목 카드, 카드의 상품 띠를 누르면 그 상품 쓰기.
    expect(find.textContaining('쓸 수 있는 리뷰 2개'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('review-pick-open-l-2')));
    await t.pumpAndSettle();
    expect(
      t
          .widget<ReviewWriteScreen>(find.byType(ReviewWriteScreen))
          .target
          .orderLineId,
      'l-2',
    );
  });

  testWidgets('쓸 수 있는 리뷰가 없으면 안내(빈 쓰기 화면을 열지 않는다)', (t) async {
    await tapReviewNotice(
      t,
      orderId: 'order-seed-2',
      reviews: MockReviewsRepository(latency: Duration.zero),
    );
    expect(
      find.byKey(const ValueKey('order-review-entry-none')),
      findsOneWidget,
    );
    expect(find.byType(ReviewWriteScreen), findsNothing);
  });

  // 초안 09-B: 주문 머리(배송 날짜·남은 수·같은 기한), 별을 누르면 그 별점으로, 이미 쓴 품목은 "작성 완료".
  testWidgets('고르기: 주문 머리 · 별 바로 쓰기 · 작성 완료', (t) async {
    await tapReviewNotice(
      t,
      orderId: 'order-x',
      reviews: MockReviewsRepository(
        latency: Duration.zero,
        eligibilities: [
          eligible('order-x', 'l-1', '우유'),
          eligible('order-x', 'l-2', '요거트'),
          {
            ...eligible('order-x', 'l-3', '두부'),
            'state': 'PUBLISHED',
            'reviewId': 'rv-3',
          },
        ],
      ),
    );
    expect(find.text('10월 24일 배송된 상품,\n어떠셨나요?'), findsOneWidget);
    expect(find.text('쓸 수 있는 리뷰 2개 · 11.7(토)까지'), findsOneWidget);
    expect(find.byKey(const ValueKey('review-pick-done-l-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('review-pick-star-l-3-1')), findsNothing);
    await t.tap(find.byKey(const ValueKey('review-pick-star-l-1-3')));
    await t.pumpAndSettle();
    final w = t.widget<ReviewWriteScreen>(find.byType(ReviewWriteScreen));
    expect((w.target.orderLineId, w.target.initialRating), ('l-1', 3));
    expect(find.text('보통이에요'), findsOneWidget);
  });

  // 초안 09-C·D: 등록 확정 뒤 같은 주문에 남은 품목으로 이어 쓰기.
  testWidgets('등록 뒤: 남은 품목 이어 쓰기', (t) async {
    final repo = MockReviewsRepository(
      latency: Duration.zero,
      eligibilities: [
        eligible('order-x', 'l-1', '우유'),
        eligible('order-x', 'l-2', '요거트'),
      ],
    );
    await tapReviewNotice(t, orderId: 'order-x', reviews: repo);
    await t.tap(find.byKey(const ValueKey('review-pick-star-l-1-5')));
    await t.pumpAndSettle();
    expect(find.text('상품은 어떠셨나요?'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('review-submit')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-result-done')), findsOneWidget);
    expect(find.text('소중한 리뷰 고마워요'), findsOneWidget);
    expect(find.text('이 주문에 쓸 리뷰가 1개 더 있어요'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('review-pick-open-l-2')));
    await t.pumpAndSettle();
    expect(
      t
          .widget<ReviewWriteScreen>(find.byType(ReviewWriteScreen))
          .target
          .orderLineId,
      'l-2',
    );
  });

  // 초안 09-E: 쓸 리뷰가 없으면 제목·이유 + [주문 상세] · [내가 쓴 리뷰](내가 쓴 리뷰 칸으로).
  testWidgets('쓸 리뷰 없음: 내가 쓴 리뷰로 가기', (t) async {
    await tapReviewNotice(
      t,
      orderId: 'order-seed-2',
      reviews: MockReviewsRepository(latency: Duration.zero),
    );
    expect(find.text('이미 썼거나 작성 기간이 지났을 수 있어요'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('order-review-entry-order')),
      findsOneWidget,
    );
    await t.tap(find.byKey(const ValueKey('order-review-entry-mine')));
    await t.pumpAndSettle();
    expect(find.byType(ReviewManageScreen), findsOneWidget);
    expect(
      DefaultTabController.of(
        t.element(find.byKey(const ValueKey('review-tab-mine'))),
      ).index,
      1,
    );
  });

  test('경로: REVIEW_REQUESTED + ORDER 만 리뷰 쓰기, 그 밖은 기존 목적지', () {
    const order = NoticeDestination(
      type: NoticeDestinationType.order,
      ref: 'o-1',
    );
    expect(
      noticeRoute(order, templateKey: 'REVIEW_REQUESTED'),
      '/orders/o-1/review',
    );
    expect(
      noticeRoute(order, templateKey: 'DELIVERY_COMPLETED'),
      '/orders/o-1',
    );
    expect(noticeRoute(order), '/orders/o-1');
    expect(
      pushRoute({
        'templateKey': 'REVIEW_REQUESTED',
        'destinationType': 'ORDER',
        'destinationRef': 'o-1',
      }),
      '/orders/o-1/review',
    );
  });

  test('계약 → 앱: templateKey 그대로, 비면 null', () {
    InboxNotice of(Object? key) => noticeFromContract(
      api.Notification.fromJson({...reviewNotice('o-1'), 'templateKey': key}),
    );
    expect(of('REVIEW_REQUESTED').templateKey, 'REVIEW_REQUESTED');
    expect(of(' ').templateKey, isNull);
    expect(of(null).templateKey, isNull);
  });
}
