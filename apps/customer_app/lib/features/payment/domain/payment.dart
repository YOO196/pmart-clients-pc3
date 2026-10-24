import 'package:flutter/foundation.dart';

/// 토스 결제창 진입 정보(BR-01 설계안: `nextAction=PAY` 인 초안의 `checkout`). 필드 이름은 계약 반영 후 확정.
///
/// `clientKey` 는 공개 키라 서버 응답으로 받는다. 로그에 남기지 않는다.
@immutable
class PaymentEntry {
  const PaymentEntry({
    required this.clientKey,
    required this.pgOrderId,
    required this.amount,
    required this.orderName,
    this.expiresAt,
  });

  final String clientKey;
  final String pgOrderId;
  final int amount;
  final String orderName;
  final DateTime? expiresAt;

  @override
  String toString() => 'PaymentEntry($pgOrderId)';
}

/// 결제창에서 돌아온 결과. 어느 것도 "주문 완료"가 아니다.
@immutable
sealed class PgReturn {
  const PgReturn();
}

/// 인증 성공으로 돌아옴. [paymentKey] 는 로그 금지.
final class PgAuthenticated extends PgReturn {
  const PgAuthenticated({
    required this.paymentKey,
    required this.pgOrderId,
    required this.amount,
  });

  final String paymentKey;
  final String pgOrderId;
  final int amount;

  @override
  String toString() => 'PgAuthenticated($pgOrderId)';
}

/// 고객이 결제창을 닫았다.
final class PgCancelled extends PgReturn {
  const PgCancelled();
}

/// 결제창이 실패로 돌려보냈다(카드 거절 등).
final class PgFailed extends PgReturn {
  const PgFailed(this.code);

  final String code;
}

/// 앱이 결과를 받지 못했다(앱 종료·복귀 유실). 서버 조회로만 판단한다.
final class PgNoReturn extends PgReturn {
  const PgNoReturn();
}

/// 고객에게 보이는 결제 진행 단계(C 1599~ 결제 진행 문구).
enum PaymentPhase {
  /// 결제 준비 중(진입 정보 대기)
  preparing,

  /// 결제 인증 중(결제창)
  authenticating,

  /// 결제 결과 확인 중(서버 승인·주문 확정 대기). "다시 결제" 없음.
  confirming,

  /// 주문 완료(서버가 orderId 와 확정 상태를 줬다)
  done,

  /// 결제 실패 확인(다시 결제 가능)
  failed,

  /// 결제 승인·주문 복구 중(MISMATCH 등). "다시 결제" 없음.
  recovering,

  /// 취소·환불 확인 중. "다시 결제" 없음.
  refunding,
}

@immutable
class PaymentFlowState {
  const PaymentFlowState({
    required this.phase,
    this.orderId,
    this.failureCode,
    this.entry,
    this.stillChecking = false,
  });

  final PaymentPhase phase;
  final String? orderId;
  final String? failureCode;
  final PaymentEntry? entry;

  /// 확인을 여러 번 했지만 아직 결론이 없다. "다시 확인"만 보인다.
  final bool stillChecking;

  /// 다시 결제를 허용하는지. 결과 불명·복구·환불 중에는 절대 허용하지 않는다.
  bool get canRetryPayment => phase == PaymentPhase.failed;
}

/// 결제 인증 결과 전달(BR-01 설계안: payment-service 고객용 명령) 결과.
enum AuthSubmitResult { accepted, rejected, unknown }
