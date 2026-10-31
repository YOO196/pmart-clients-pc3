import 'package:dio/dio.dart';
import 'package:pmart_api_payment/pmart_api_payment.dart' as api;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;
import '../domain/payment.dart';

/// 결제창 결과를 서버에 넘긴다(payment-service checkout 태그, ADR-0020).
/// 결제창 진입 정보는 초안 조회(`OrderDraft.payment`)로 받는다.
abstract interface class PaymentRepository {
  /// `POST /payment-confirmations` — orderId(=pgOrderId)·paymentKey·amount 만 보낸다.
  /// 응답을 놓치면([AuthSubmitResult.unknown]) 다시 보내지 않고 조회로 확인한다.
  Future<AuthSubmitResult> submitAuth(
    PgAuthenticated auth, {
    required IdempotencyKey key,
  });

  /// `POST /payment-authorization-failures` — 결제창 실패·취소를 보관한 orderId 로 알린다.
  /// 서버가 이번 시도의 재고·슬롯을 바로 푼다. 실패해도 결과 판단은 초안 조회로 한다.
  Future<void> reportAuthFailure(
    PaymentEntry entry,
    String errorCode, {
    required IdempotencyKey key,
  });
}

/// 토스 결제창이 사용자 취소로 돌려주는 코드.
const tossUserCancelCode = 'PAY_PROCESS_CANCELED';

final class ApiPaymentRepository implements PaymentRepository {
  ApiPaymentRepository(Dio dio)
    : _api = api.PmartApiPayment(dio: dio).getCheckoutApi();

  final api.CheckoutApi _api;

  @override
  Future<AuthSubmitResult> submitAuth(
    PgAuthenticated auth, {
    required IdempotencyKey key,
  }) async {
    try {
      final res = await pmartGuard(
        () => _api.confirmPayment(
          idempotencyKey: key.value,
          xSourceSystem: sourceSystem,
          confirmPaymentRequest: api.ConfirmPaymentRequest(
            orderId: auth.pgOrderId,
            paymentKey: auth.paymentKey,
            amount: auth.amount,
          ),
          extra: commandOptions(key).extra,
        ),
      );
      return switch (res.data?.stage) {
        null => AuthSubmitResult.unknown,
        api.PaymentStage.CONFIRM_FAILED ||
        api.PaymentStage.AUTH_FAILED ||
        api.PaymentStage.CANCELED_BY_USER ||
        api.PaymentStage.EXPIRED => AuthSubmitResult.rejected,
        // 승인·진행 중·불명·보류는 모두 "넘겼다". 주문 확정 여부는 초안 조회로만 본다.
        _ => AuthSubmitResult.accepted,
      };
    } on UnknownResultFailure {
      return AuthSubmitResult.unknown;
    } on ProblemFailure catch (f) {
      return switch (f.problem.code) {
        // 이미 다른 paymentKey 로 진행 중인 결제다. 결과는 조회로 본다.
        'PAYMENT_KEY_MISMATCH' => AuthSubmitResult.accepted,
        // AMOUNT_MISMATCH·RESERVATION_EXPIRED·INVALID_STATE·404 — 승인하지 않았다.
        _ => AuthSubmitResult.rejected,
      };
    }
  }

  @override
  Future<void> reportAuthFailure(
    PaymentEntry entry,
    String errorCode, {
    required IdempotencyKey key,
  }) async {
    await pmartGuard(
      () => _api.reportAuthorizationFailure(
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        reportAuthorizationFailureRequest:
            api.ReportAuthorizationFailureRequest(
              orderId: entry.pgOrderId,
              errorCode: errorCode,
            ),
        extra: commandOptions(key).extra,
      ),
    );
  }
}

/// 토스 결제창.
abstract interface class PgLauncher {
  Future<PgReturn> launch(PaymentEntry entry);
}

/// 실서버용 자리. 토스 결제위젯 SDK 를 붙이기 전에는 결제창을 열 수 없다고 돌려준다.
/// (서버에는 인증 실패로 알려 이번 시도의 재고·슬롯을 바로 푼다.)
final class UnconnectedPgLauncher implements PgLauncher {
  const UnconnectedPgLauncher();

  static const code = 'PG_SDK_NOT_CONNECTED';

  @override
  Future<PgReturn> launch(PaymentEntry entry) async => const PgFailed(code);
}

/// 목 결제창. [next] 결과를 돌려준다(기본: 인증 성공).
final class MockPgLauncher implements PgLauncher {
  MockPgLauncher({this.next});

  PgReturn? next;
  int launches = 0;

  @override
  Future<PgReturn> launch(PaymentEntry entry) async {
    launches++;
    final result =
        next ??
        PgAuthenticated(
          paymentKey: 'mock-payment-key-$launches',
          pgOrderId: entry.pgOrderId,
          amount: entry.amount,
        );
    next = null;
    return result;
  }
}
