import 'package:flutter/foundation.dart';

/// 토스 결제창 진입 정보(계약 `OrderDraft.payment`, `nextAction=PAY` 일 때만).
///
/// `clientKey` 는 공개 키라 서버 응답으로 받는다. 로그에 남기지 않는다.
@immutable
class PaymentEntry {
  const PaymentEntry({
    required this.clientKey,
    required this.pgOrderId,
    required this.amount,
    required this.orderName,
    this.paymentAttemptId,
    this.expiresAt,
  });

  final String clientKey;

  /// 결제창의 orderId 이자 승인 요청의 orderId. 가공하지 않는다.
  final String pgOrderId;
  final String? paymentAttemptId;
  final int amount;
  final String orderName;

  /// 이 시각이 지나면 결제창을 열지 않는다(재고·슬롯 점유 만료 — 그 뒤 승인은 거절된다).
  final DateTime? expiresAt;

  @override
  String toString() => 'PaymentEntry($pgOrderId)';
}

enum PgProvider { tossPayments, unknown }

/// 결제위젯 설정(`GET /payment-widget-config`, BR-34). 로그인 세션마다 한 번 받아 재사용한다.
///
/// `customerKey` 는 지금 회원 accountId 와 같다(결제 명세 D6). 받은 값을 가공하지 않고,
/// 두 키 모두 로그·분석 이벤트에 넣지 않는다.
@immutable
class PaymentWidgetConfig {
  const PaymentWidgetConfig({
    required this.provider,
    required this.clientKey,
    required this.customerKey,
  });

  final PgProvider provider;
  final String clientKey;
  final String customerKey;

  @override
  String toString() => 'PaymentWidgetConfig(${provider.name})';
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

  /// 결제 실패 확인. 이번 결제 시도는 끝났고, 주문서에서 새로 결제 진입해야 한다.
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

  /// 다시 결제(주문서로 돌아가 새 키로 결제 진입)를 허용하는지. 결과 불명·복구·환불 중에는 절대 허용하지 않는다.
  bool get canRetryPayment => phase == PaymentPhase.failed;

  /// 주문서로 돌아가야 하는 실패(재고·여력 확보 실패, 결제 가능 시간 지남 등).
  bool get fromCheckout =>
      failureCode != null && failureCode != 'USER_CANCELLED';
}

/// 승인 요청(`POST /payment-confirmations`) 결과. accepted 도 결제 완료가 아니다(주문 확정은 초안 조회로).
enum AuthSubmitResult { accepted, rejected, unknown }
