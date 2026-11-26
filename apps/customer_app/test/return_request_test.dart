import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart' show initPmartFormatting;

import 'package:customer_app/features/claims/data/mock_claims_repository.dart';
import 'package:customer_app/features/claims/data/return_request_repository.dart';
import 'package:customer_app/features/claims/domain/claims.dart';
import 'package:customer_app/features/claims/domain/return_request.dart';
import 'package:customer_app/features/claims/presentation/claims_controller.dart';
import 'package:customer_app/features/claims/presentation/claims_screens.dart';
import 'package:customer_app/features/claims/presentation/return_request_controller.dart';
import 'package:customer_app/features/claims/presentation/return_request_screens.dart';
import 'package:customer_app/features/orders/data/mock_orders_repository.dart';
import 'package:customer_app/features/orders/presentation/orders_providers.dart';
import 'package:customer_app/features/reviews/domain/reviews.dart';
import 'package:customer_app/features/reviews/presentation/reviews_controller.dart';
import 'package:customer_app/features/support/presentation/inquiry_screens.dart';

import 'support/app_harness.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

/// 처음 한 번은 결과를 모르게(타임아웃) 하고, 그 뒤로는 목에 넘긴다. 받은 키를 적는다.
final class _FlakyRepo implements ReturnRequestRepository {
  _FlakyRepo(this.inner);

  final MockReturnRequestRepository inner;
  final keys = <String>[];
  var failFirst = true;

  @override
  Future<ReturnEligibility> eligibility(String orderId) =>
      inner.eligibility(orderId);

  @override
  Future<ClaimView> submit(
    ReturnRequestDraft draft, {
    required IdempotencyKey key,
  }) async {
    keys.add(key.value);
    if (failFirst) {
      failFirst = false;
      throw const UnknownResultFailure(httpStatus: 504);
    }
    return inner.submit(draft, key: key);
  }
}

/// 반품·교환 신청(레퍼런스 12, BR-95 목).
void main() {
  setUpAll(initPmartFormatting);
  Finder key(String k) => find.byKey(ValueKey(k));

  late MockReturnRequestRepository mock;
  _FlakyRepo? flaky;

  Future<void> openEntry(
    WidgetTester t, {
    bool unavailable = false,
    bool flakySubmit = false,
    bool freshSeed = false,
  }) async {
    t.view
      ..physicalSize = const Size(800, 2600)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp([
        returnRequestRepositoryProvider.overrideWith((ref) {
          if (unavailable) return const UnavailableReturnRequestRepository();
          mock = MockReturnRequestRepository(
            orders: ref.watch(ordersRepositoryProvider) as MockOrdersRepository,
            claims: ref.watch(claimsRepositoryProvider) as MockClaimsRepository,
            latency: Duration.zero,
          );
          if (freshSeed) mock.freshProducts.add('P-0002');
          if (flakySubmit) return flaky = _FlakyRepo(mock);
          return mock;
        }),
        reviewPhotoPickerProvider.overrideWithValue(
          (_, max) async => [ReviewPhotoFile(name: 'p.png', bytes: _png)],
        ),
      ]),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(key('my-login'));
    await t.pumpAndSettle();
    await t.tap(key('login-kakao'));
    await t.pumpAndSettle();
    await t.tap(key('my-orders'));
    await t.pumpAndSettle();
    await t.tapAt(
      t.getTopLeft(key('order-order-seed-2')) + const Offset(24, 24),
    );
    await t.pumpAndSettle();
    await t.tap(key('order-return-exchange'));
    await t.pumpAndSettle();
  }

  bool submitEnabled(WidgetTester t) =>
      t
          .widget<FilledButton>(
            find.descendant(
              of: key('rr-submit'),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed !=
      null;

  Future<void> tapVisible(WidgetTester t, String k) async {
    await t.ensureVisible(key(k));
    await t.pumpAndSettle();
    await t.tap(key(k));
    await t.pumpAndSettle();
  }

  testWidgets('어떤 처리 → 교환 → 품목·변심 사유 → 접수하면 처리 내역으로(배달팁은 서버 값)', (t) async {
    await openEntry(t);
    expect(find.text('어떤 처리를 원하세요?'), findsOneWidget);
    await t.tap(key('rr-go-exchange'));
    await t.pumpAndSettle();
    expect(find.text('교환 신청'), findsOneWidget);
    expect(submitEnabled(t), isFalse);

    await tapVisible(t, 'rr-line-ol-3');
    // 받은 2개 모두 고른 채로 시작한다 — 수량 조절은 2개 이상일 때만.
    expect(key('rr-qty-ol-3'), findsOneWidget);
    expect(submitEnabled(t), isFalse); // 이유를 아직 고르지 않았다
    await tapVisible(t, 'rr-reason-dislike');
    expect(find.text('배달팁 9,000원'), findsOneWidget);
    expect(submitEnabled(t), isTrue);

    await tapVisible(t, 'rr-submit');
    expect(find.byType(ClaimScreen), findsOneWidget);
    expect(mock.submitted, hasLength(1));
    final d = mock.submitted.single;
    expect(d.type, ReturnRequestType.exchange);
    expect(d.lines.single, (orderLineId: 'ol-3', qty: 2));
    expect(d.reason, ReturnReason.dislike);
    expect(d.redeliveryNote, isNotNull);
  });

  testWidgets('냉장·냉동 품목도 변심 교환 가능(교환비) — "상담원 확인" 표시, 접수 뒤 심사 중(ADR-0087)', (
    t,
  ) async {
    await openEntry(t, freshSeed: true);
    await t.tap(key('rr-go-exchange'));
    await t.pumpAndSettle();
    expect(find.text('상담원 확인'), findsOneWidget);
    expect(find.text('신선보장'), findsOneWidget);
    await tapVisible(t, 'rr-line-ol-3');
    await tapVisible(t, 'rr-reason-dislike');
    expect(find.text('배달팁 9,000원'), findsOneWidget);
    expect(submitEnabled(t), isTrue);
    await tapVisible(t, 'rr-submit');
    expect(find.byType(ClaimScreen), findsOneWidget);
    expect(mock.submitted, hasLength(1));
  });

  testWidgets('반품은 늘 흐리게 — 고객센터로(BR-95 회신 2026-11-25: 앱 접수는 교환만)', (t) async {
    await openEntry(t);
    expect(key('rr-not-allowed-return'), findsOneWidget);
    expect(find.textContaining('반품(환불)은 고객센터에서'), findsOneWidget);
    expect(key('rr-not-allowed-exchange'), findsNothing);
    await t.tap(key('rr-go-return'));
    await t.pumpAndSettle();
    expect(find.byType(ReturnRequestFormScreen), findsNothing);
    await t.tap(key('rr-inquiry-return'));
    await t.pumpAndSettle();
    expect(find.byType(InquiryFormScreen), findsOneWidget);
  });

  testWidgets('교환 이유에 "일부 안 왔어요"·"배달완료인데 안 왔어요"는 없다(오배송·누락 문의로)', (t) async {
    await openEntry(t);
    await t.tap(key('rr-go-exchange'));
    await t.pumpAndSettle();
    await tapVisible(t, 'rr-group-delivery');
    expect(key('rr-reason-damaged'), findsOneWidget);
    expect(key('rr-reason-partlyMissing'), findsNothing);
    expect(key('rr-reason-notArrived'), findsNothing);
  });

  testWidgets('상품문제 사유는 상세 이유·사진이 있어야 보낼 수 있다(무료)', (t) async {
    await openEntry(t);
    await t.tap(key('rr-go-exchange'));
    await t.pumpAndSettle();
    await tapVisible(t, 'rr-line-ol-3');
    await tapVisible(t, 'rr-group-product');
    await tapVisible(t, 'rr-reason-spoiled');
    expect(find.text('필수'), findsOneWidget);
    expect(find.text('무료'), findsOneWidget);
    expect(submitEnabled(t), isFalse);

    await t.ensureVisible(key('rr-detail'));
    await t.enterText(key('rr-detail'), '뚜껑을 여니 상해 있었어요');
    await t.pumpAndSettle();
    expect(submitEnabled(t), isFalse); // 사진이 아직 없다
    await tapVisible(t, 'rr-photo-add');
    expect(key('rr-photo-0'), findsOneWidget);
    expect(submitEnabled(t), isTrue);

    await tapVisible(t, 'rr-submit');
    expect(find.byType(ClaimScreen), findsOneWidget);
    expect(mock.submitted.single.photos, hasLength(1));
    expect(mock.submitted.single.type, ReturnRequestType.exchange);
  });

  testWidgets('입력하다 뒤로 가면 "신청을 취소할까요?" — 아니요면 남고, 신청 취소면 나간다', (t) async {
    await openEntry(t);
    await t.tap(key('rr-go-exchange'));
    await t.pumpAndSettle();
    await tapVisible(t, 'rr-line-ol-3');

    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('교환 신청을 취소할까요?'), findsOneWidget);
    await t.tap(key('rr-leave-no'));
    await t.pumpAndSettle();
    expect(find.byType(ReturnRequestFormScreen), findsOneWidget);

    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    await t.tap(key('rr-leave-yes'));
    await t.pumpAndSettle();
    expect(find.byType(ReturnRequestFormScreen), findsNothing);
    expect(find.byType(ReturnExchangeEntryScreen), findsOneWidget);
  });

  testWidgets('결과를 모르면 입력을 잠그고 [다시 확인]은 같은 키로 — 클레임은 하나', (t) async {
    await openEntry(t, flakySubmit: true);
    await t.tap(key('rr-go-exchange'));
    await t.pumpAndSettle();
    await tapVisible(t, 'rr-line-ol-3');
    await tapVisible(t, 'rr-reason-wrongOrder');
    await tapVisible(t, 'rr-submit');

    expect(find.byType(ClaimScreen), findsNothing);
    expect(key('rr-message'), findsOneWidget);
    expect(find.text('다시 확인'), findsOneWidget);
    expect(
      t
          .widget<AbsorbPointer>(
            find
                .ancestor(
                  of: key('rr-form'),
                  matching: find.byType(AbsorbPointer),
                )
                .first,
          )
          .absorbing,
      isTrue,
    );

    await tapVisible(t, 'rr-submit');
    expect(find.byType(ClaimScreen), findsOneWidget);
    expect(flaky!.keys, hasLength(2));
    expect(flaky!.keys.toSet(), hasLength(1));
    expect(mock.submitted, hasLength(1));
  });

  testWidgets('실서버(계약 전): 두 칸 모두 흐리게 + 고객센터 문의로', (t) async {
    await openEntry(t, unavailable: true);
    expect(key('rr-not-allowed-return'), findsOneWidget);
    expect(key('rr-not-allowed-exchange'), findsOneWidget);
    await t.tap(key('rr-go-exchange'));
    await t.pumpAndSettle();
    expect(find.byType(ReturnRequestFormScreen), findsNothing);
    await t.tap(key('rr-inquiry-return'));
    await t.pumpAndSettle();
    expect(find.byType(InquiryFormScreen), findsOneWidget);
  });

  test('변심 사유로 변심 불가(신선) 품목을 고르면 막는다', () {
    const fresh = ReturnableLine(
      orderLineId: 'l1',
      title: '감귤',
      orderedQty: 1,
      requestableQty: 1,
      changeOfMindAllowed: false,
      freshGuarantee: true,
    );
    expect(
      returnDraftProblems(
        picked: [fresh],
        reason: ReturnReason.dislike,
        detail: '',
        photos: 0,
      ),
      [ReturnDraftProblem.changeOfMindRestricted],
    );
    expect(
      returnDraftProblems(
        picked: [fresh],
        reason: ReturnReason.spoiled,
        detail: '상했어요',
        photos: 1,
      ),
      isEmpty,
    );
  });
}
