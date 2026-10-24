import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';

import 'package:customer_app/features/checkout/data/checkout_repository.dart';
import 'package:customer_app/features/checkout/domain/checkout.dart';
import 'package:customer_app/shared/providers.dart';

void main() {
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
    expect(adapter.requests.single.headers['Idempotency-Key'], 'k-1');
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
}
