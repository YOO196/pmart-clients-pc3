import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';
import 'package:pmart_ui/pmart_ui.dart' show initPmartFormatting;

import 'package:customer_app/features/address/domain/address.dart'
    show EntranceMethod;
import 'package:customer_app/features/checkout/data/checkout_repository.dart';
import 'package:customer_app/features/checkout/domain/checkout.dart';
import 'package:customer_app/features/payment/data/payment_repository.dart';
import 'package:customer_app/features/payment/domain/payment.dart';
import 'package:customer_app/features/checkout/presentation/delivery_select_screen.dart'
    show windowText;
import 'package:customer_app/shared/providers.dart';

void main() {
  setUpAll(initPmartFormatting);
  late FakeAdapter adapter;

  ApiCheckoutRepository repo(FakeReply Function(int index) reply) {
    adapter = FakeAdapter((_, i) async => reply(i));
    return ApiCheckoutRepository(
      createPmartDio(
        baseUrl: 'http://test.invalid/api/v1',
        sourceSystem: sourceSystem,
        tokens: TokenStore(MemoryKeyValueStore()),
        refresher: (_) async => null,
        adapter: adapter,
        delay: (_) async {},
      ),
    );
  }

  test('슬롯 조회의 date 는 YYYY-MM-DD 로 보낸다', () async {
    await repo((_) => const FakeReply(200, body: {'slots': <Object?>[]}))
        .slots('MFC-1', '2026-10-25');

    expect(adapter.requests.single.uri.queryParameters['date'], '2026-10-25');
  });

  test('초안 생성 본문의 arrivalWindow.date 는 YYYY-MM-DD 다', () async {
    await repo(
      (_) => const FakeReply(
        201,
        body: {'draftId': 'd-1', 'version': 1, 'nextAction': 'WAIT'},
      ),
    ).createDraft(
      const DraftRequest(
        purchaseIntentId: 'pi-1',
        lines: [DraftLine(cartItemId: 'ci-1', sku: 'E-00000001', quantity: 2)],
        shoppingAddressId: 'addr-1',
        mode: DeliveryMode.scheduled,
        window: ArrivalWindow(date: '2026-10-25', start: '13:00', end: '14:00'),
        outOfStock: OutOfStockPreference.cancelOutOfStockOnly,
      ),
      key: IdempotencyKey('k-1'),
    );

    final body = jsonDecode(
      adapter.requests.single.data as String,
    ) as Map<String, dynamic>;
    expect(body['arrivalWindow'], {
      'date': '2026-10-25',
      'start': '13:00',
      'end': '14:00',
    });
    expect(body['deliveryMode'], 'SCHEDULED');
    expect(body['outOfStockPreference'], 'CANCEL_OOS_ONLY');
    // 봉투 없이 받기는 제공하지 않는다(봉투값은 서버가 늘 청구).
    expect(body.containsKey('bagOptOut'), isFalse);
    expect(adapter.requests.single.headers['Idempotency-Key'], 'k-1');
  });

  test('결제 진입 501 UNSUPPORTED_ACTION 은 결과 불명이 아니라 확정 거절이다(⑥ 전)', () async {
    final start =
        await repo(
          (_) => FakeReply.problem(
            501,
            problemBody('UNSUPPORTED_ACTION', status: 501),
          ),
        ).startCheckout(
          'd-1',
          expectedVersion: 2,
          acceptedQuoteVersion: 1,
          key: IdempotencyKey('k-1'),
        );

    expect(
      start,
      isA<CheckoutRejected>().having(
        (r) => r.code,
        'code',
        'UNSUPPORTED_ACTION',
      ),
    );
  });

  test('결제 진입 422 RE_QUOTE_REQUIRED 는 재견적, 타임아웃은 불명이다', () async {
    final r = repo(
      (i) => i == 0
          ? FakeReply.problem(
              422,
              problemBody('RE_QUOTE_REQUIRED', status: 422),
            )
          : const FakeReply.transport(DioExceptionType.receiveTimeout),
    );
    Future<CheckoutStart> start(String k) => r.startCheckout(
      'd-1',
      expectedVersion: 2,
      acceptedQuoteVersion: 1,
      key: IdempotencyKey(k),
    );

    expect(await start('k-1'), isA<CheckoutReQuote>());
    expect(await start('k-2'), isA<CheckoutUnknown>());
    final body = jsonDecode(
      adapter.requests.first.data as String,
    ) as Map<String, dynamic>;
    expect(body['acceptedQuoteVersion'], 1);
    expect(body['paymentMethod'], 'TOSS_PAYMENTS');
  });

  test(
    '배송 방식은 GET /delivery-options(mfcId·itemAmount)로 묻고 서버 판정을 그대로 옮긴다',
    () async {
      final options = await repo(
        (_) => const FakeReply(
          200,
          body: {
            'mfcId': 'MFC-SEED-01',
            'options': [
              {
                'mode': 'SINGLE',
                'availability': 'UNAVAILABLE',
                'unavailableReason': 'NIGHT_TIME',
              },
              {
                'mode': 'BUNDLED',
                'availability': 'UNKNOWN',
                'unavailableReason': 'LOOKUP_FAILED',
              },
              {
                'mode': 'SCHEDULED',
                'availability': 'AVAILABLE',
                'eta': {'state': 'NOT_SET'},
                'deliveryTip': {
                  'base': 3000,
                  'applied': 0,
                  'reason': 'OVER_30000',
                },
                'earliestSlot': {
                  'date': '2026-10-31',
                  'start': '09:00',
                  'end': '10:00',
                },
              },
            ],
          },
        ),
      ).options('MFC-SEED-01', itemAmount: 32000);

      final uri = adapter.requests.single.uri;
      expect(uri.path, '/api/v1/delivery-options');
      expect(uri.queryParameters, {
        'mfcId': 'MFC-SEED-01',
        'itemAmount': '32000',
      });
      final [single, bundled, scheduled] = options;
      expect(single.available, isFalse);
      expect(single.reason, UnavailableReason.nightTime);
      // 조회 실패는 "불가"가 아니라 모름이다.
      expect(bundled.availability, OptionAvailability.unknown);
      expect(bundled.reason, UnavailableReason.lookupFailed);
      expect(scheduled.available, isTrue);
      expect(scheduled.eta?.notSet, isTrue);
      expect(scheduled.tip?.applied, 0);
      expect(scheduled.tip?.reason, TipReason.over30000);
      expect(
        scheduled.earliestSlot,
        const ArrivalWindow(date: '2026-10-31', start: '09:00', end: '10:00'),
      );
    },
  );

  test('배달 안내 값(order 0.22.0 BR-96): 최소 주문 VALUE 만 숫자로, NOT_SET 은 null(0 아님), 배달팁 구간·운영 시간', () async {
    final options = await repo(
      (_) => const FakeReply(
        200,
        body: {
          'mfcId': 'MFC-BJG-01',
          'serviceHours': {'start': '08:00', 'end': '24:00'},
          'options': [
            {
              'mode': 'SINGLE',
              'availability': 'AVAILABLE',
              'minOrderAmount': {'state': 'VALUE', 'value': 15000},
              'deliveryTip': {
                'base': 4000,
                'applied': 4000,
                'reason': 'STANDARD',
                'tiers': [
                  {'fromAmount': 30000, 'tip': 0},
                  {'fromAmount': 0, 'tip': 4000},
                ],
              },
            },
            {
              'mode': 'BUNDLED',
              'availability': 'AVAILABLE',
              'minOrderAmount': {'state': 'NOT_SET'},
            },
          ],
        },
      ),
    ).options('MFC-BJG-01', itemAmount: 12000);
    final [single, bundled] = options;
    expect(single.minOrderAmount, 15000);
    expect(single.tipTiers, [
      (fromAmount: 30000, tip: 0),
      (fromAmount: 0, tip: 4000),
    ]);
    expect(single.serviceHours, (start: '08:00', end: '24:00'));
    expect(bundled.minOrderAmount, isNull);
    expect(bundled.tipTiers, isNull);
    expect(bundled.serviceHours, (start: '08:00', end: '24:00'));
  });

  test('초안의 막는 사유(blockers)·부족액·첫 구매 상태를 서버 순서·값 그대로 옮긴다', () async {
    final draft = await repo(
      (_) => const FakeReply(
        200,
        body: {
          'draftId': 'd-1',
          'version': 2,
          'nextAction': 'REVIEW',
          'quote': {
            'quoteVersion': 1,
            'itemAmount': 9000,
            'minOrderSatisfied': false,
            'minOrderAmount': 15000,
            'minOrderShortfall': 6000,
            'deliveryTipBase': 4000,
            'firstPurchaseBenefit': 'EXPECTED',
          },
          'blockers': [
            {'code': 'MIN_ORDER_AMOUNT'},
            {'code': 'SLOT_REQUIRED'},
          ],
        },
      ),
    ).getDraft('d-1');

    expect(draft.blockers, [
      DraftBlocker.minOrderAmount,
      DraftBlocker.slotRequired,
    ]);
    expect(draft.quote?.minOrderShortfall, 6000);
    expect(draft.quote?.minOrderAmount, 15000);
    expect(draft.quote?.deliveryTipBase, 4000);
    expect(draft.quote?.firstPurchase, FirstPurchaseBenefit.expected);
  });

  test(
    '초안의 배송지 사본(delivery.shippingAddress)을 옮기고, 없으면 null 이다(BR-37)',
    () async {
      final withCopy = await repo(
        (_) => const FakeReply(
          200,
          body: {
            'draftId': 'd-1',
            'version': 1,
            'status': 'DRAFT',
            'nextAction': 'REVIEW',
            'delivery': {
              'deliveryMode': 'SINGLE',
              'shoppingAddressId': 'addr-1',
              'shippingAddress': {
                'roadAddress': '부산광역시 부산진구 중앙대로 708',
                'detailAddress': '101동 1001호',
                'postalCode': '47296',
                'receiverName': '홍길동',
                'receiverPhone': '01012345678',
                'entranceMethod': 'PASSWORD',
                'entranceNote': '#1234',
                'geo': {'lat': 35.1577, 'lng': 129.0599},
                'capturedAt': '2026-11-02T07:10:00Z',
              },
            },
          },
        ),
      ).getDraft('d-1');

      final a = withCopy.shippingAddress!;
      expect(a.roadAddress, '부산광역시 부산진구 중앙대로 708');
      expect(a.receiverName, '홍길동');
      expect(a.receiverPhone, '01012345678');
      expect(a.entranceMethod, EntranceMethod.password);
      expect(a.entranceNote, '#1234');
      expect(a.lat, 35.1577);
      expect(a.capturedAt, DateTime.utc(2026, 11, 2, 7, 10));

      final without = await repo(
        (_) => const FakeReply(
          200,
          body: {
            'draftId': 'd-0',
            'version': 1,
            'status': 'DRAFT',
            'nextAction': 'REVIEW',
            'delivery': {
              'shoppingAddressId': 'addr-1',
              'shippingAddress': null,
            },
          },
        ),
      ).getDraft('d-0');
      expect(without.shippingAddress, isNull);
    },
  );

  test('결제위젯 설정 GET /payment-widget-config 를 옮기고, 422 CONFIG_REQUIRED 는 오류다(BR-34)', () async {
    ApiPaymentRepository payments(FakeReply reply) {
      adapter = FakeAdapter((_, _) async => reply);
      return ApiPaymentRepository(
        createPmartDio(
          baseUrl: 'http://test.invalid/api/v1',
          sourceSystem: sourceSystem,
          tokens: TokenStore(MemoryKeyValueStore()),
          refresher: (_) async => null,
          adapter: adapter,
          delay: (_) async {},
        ),
      );
    }

    final cfg = await payments(
      const FakeReply(
        200,
        body: {
          'provider': 'TOSS_PAYMENTS',
          'clientKey': 'test_gck_x',
          'customerKey': 'CU-3f2a9c1e-7b4d-4e8a-9c21-5d6f0a1b2c3d',
        },
      ),
    ).widgetConfig();
    expect(adapter.requests.single.uri.path, '/api/v1/payment-widget-config');
    expect(cfg.provider, PgProvider.tossPayments);
    expect(cfg.clientKey, 'test_gck_x');
    expect(cfg.customerKey, 'CU-3f2a9c1e-7b4d-4e8a-9c21-5d6f0a1b2c3d');
    // 키는 toString 에 나오지 않는다(로그 금지).
    expect(cfg.toString(), isNot(contains('test_gck_x')));
    expect(cfg.toString(), isNot(contains('CU-3f2a')));

    await expectLater(
      payments(
        const FakeReply.problem(422, {
          'type': 'about:blank',
          'title': 'config',
          'status': 422,
          'code': 'CONFIG_REQUIRED',
        }),
      ).widgetConfig(),
      throwsA(
        isA<ProblemFailure>().having(
          (f) => f.problem.code,
          'code',
          'CONFIG_REQUIRED',
        ),
      ),
    );
  });

  test('결제 진입 뒤 초안: PAY 면 결제창 정보, 실패면 checkoutFailure 를 옮긴다(⑥ 안내)', () async {
    final pay = await repo(
      (_) => const FakeReply(
        200,
        body: {
          'draftId': 'd-1',
          'version': 3,
          'status': 'PAYMENT_PENDING',
          'nextAction': 'PAY',
          'orderId': 'ORD-1',
          'payment': {
            'paymentAttemptId': 'pay-abc123',
            'amount': 16880,
            'orderName': 'PMart 장보기 2개 상품',
            'provider': 'TOSS_PAYMENTS',
            'pgOrderId': 'pay-abc123',
            'clientKey': 'test_ck_x',
            'expiresAt': '2026-10-31T03:10:00Z',
          },
        },
      ),
    ).getDraft('d-1');

    expect(pay.next, DraftNext.pay);
    expect(pay.awaitingCheckout, isFalse);
    expect(pay.payment?.pgOrderId, 'pay-abc123');
    expect(pay.payment?.amount, 16880);
    expect(pay.payment?.expiresAt, DateTime.utc(2026, 10, 31, 3, 10));

    final failed = await repo(
      (_) => const FakeReply(
        200,
        body: {
          'draftId': 'd-1',
          'version': 4,
          'status': 'DRAFT',
          'nextAction': 'REVIEW',
          'checkoutFailure': {
            'step': 'RESERVE_INVENTORY',
            'code': 'INSUFFICIENT_STOCK',
          },
        },
      ),
    ).getDraft('d-1');

    expect(failed.payment, isNull);
    expect(failed.awaitingCheckout, isTrue);
    expect(failed.checkoutFailure?.code, CheckoutProblemCode.insufficientStock);
  });

  test('LAN 실제 응답: 예약 슬롯 끝이 24:00 이어도 읽고 표시한다', () async {
    final options = await repo(
      (_) => const FakeReply(
        200,
        body: {
          'evaluatedAt': '2026-10-30T13:05:36.47056Z',
          'mfcId': 'MFC-SEED-01',
          'options': [
            {
              'availability': 'AVAILABLE',
              'deliveryTip': {
                'applied': 3000,
                'base': 3000,
                'reason': 'STANDARD',
              },
              'earliestSlot': {
                'date': '2026-10-30',
                'end': '24:00',
                'start': '23:00',
              },
              'eta': {
                'effectiveFrom': null,
                'policyVersion': null,
                'state': 'NOT_SET',
                'value': null,
              },
              'mode': 'SCHEDULED',
              'unavailableReason': null,
            },
          ],
        },
      ),
    ).options('MFC-SEED-01', itemAmount: 9000);

    final o = options.single;
    expect(o.eta?.notSet, isTrue);
    expect(o.tip?.applied, 3000);
    // 24:00 은 다음 날 0시로 읽는다.
    expect(windowText(o.earliestSlot!), '오후 11:00~오전 12:00');
  });
}
