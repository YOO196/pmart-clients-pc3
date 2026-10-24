import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/cart/data/cart_repository.dart';
import 'package:customer_app/features/cart/data/mock_cart_repository.dart';
import 'package:customer_app/features/cart/domain/cart_summary.dart';
import 'package:customer_app/features/cart/presentation/cart_screen.dart';

import 'support/app_harness.dart';

final class _FailingRepository implements CartRepository {
  @override
  Future<CartSummary> summary(String cartId) async =>
      throw const NetworkFailure(DioExceptionType.connectionError);
}

void main() {
  setUpAll(initPmartFormatting);

  testWidgets('장바구니 탭에서 요약이 보인다', (t) async {
    await t.pumpWidget(
      testApp([
        cartRepositoryProvider.overrideWithValue(
          MockCartRepository(latency: Duration.zero),
        ),
      ]),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('장바구니'));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('cart-summary')), findsOneWidget);
    expect(find.textContaining('담은 상품 2종'), findsOneWidget);
    expect(find.textContaining('23,960원'), findsOneWidget);
  });

  testWidgets('조회 실패는 빈 장바구니가 아니라 오류로 보인다', (t) async {
    await t.pumpWidget(
      testApp([cartRepositoryProvider.overrideWithValue(_FailingRepository())]),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('장바구니'));
    await t.pumpAndSettle();

    expect(find.text('담은 상품이 없어요'), findsNothing);
    expect(find.text('정보를 불러오지 못했어요'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });
}
