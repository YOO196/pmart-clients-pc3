import 'package:pmart_core/pmart_core.dart';

import '../domain/payment.dart';

/// 결제 진입 정보·인증 결과 전달. BR-01(보류) — 계약에 고객용 경로가 아직 없다.
abstract interface class PaymentRepository {
  /// 결제창 진입 정보. 서버가 아직 준비하지 않았으면 null(다시 조회).
  Future<PaymentEntry?> entry(String draftId);

  /// 결제창 인증 결과를 서버에 넘긴다. 승인은 서버가 토스에 요청한다.
  /// 같은 [key] 재전송은 같은 결과를 돌려줘야 한다(설계안 가정).
  Future<AuthSubmitResult> submitAuth(
    PgAuthenticated auth, {
    required IdempotencyKey key,
  });
}

/// 실서버 구현 자리. BR-01 이 계약에 반영되기 전에는 호출할 경로가 없다.
final class ApiPaymentRepository implements PaymentRepository {
  const ApiPaymentRepository();

  @override
  Future<PaymentEntry?> entry(String draftId) async =>
      // BR-01: `OrderDraft` 에 `checkout` 이 없다.
      throw const ContractViolationFailure('BR-01 결제 진입 정보 경로 없음');

  @override
  Future<AuthSubmitResult> submitAuth(
    PgAuthenticated auth, {
    required IdempotencyKey key,
  }) async =>
      // BR-01: 결제 인증 결과 전달 명령이 없다.
      throw const ContractViolationFailure('BR-01 결제 인증 전달 경로 없음');
}

/// 토스 결제창. 실제 SDK 는 BR-01(복귀 방식·딥링크)과 키 결정 뒤 붙인다.
abstract interface class PgLauncher {
  Future<PgReturn> launch(PaymentEntry entry);
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
