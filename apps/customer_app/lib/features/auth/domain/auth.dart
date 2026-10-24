import 'package:flutter/foundation.dart';
import 'package:pmart_core/pmart_core.dart' show AuthTokens;

enum SocialProvider { kakao, naver, apple, google }

/// CHECKOUT 이면 로그인 뒤 장바구니 병합 확인으로 돌아간다(일반 로그인은 자동 병합 없음).
enum LoginPurpose { general, checkout }

/// 로그인 시도 1회의 결과.
@immutable
sealed class LoginOutcome {
  const LoginOutcome();
}

/// 이용 가능 회원. 토큰은 저장 후 버린다(로그에 남기지 않는다).
final class LoginMember extends LoginOutcome {
  const LoginMember({
    required this.accountId,
    required this.tokens,
    this.newAccount = false,
    this.cartMergeConfirm = false,
  });

  final String accountId;
  final AuthTokens tokens;
  final bool newAccount;

  /// 서버가 장바구니 병합 확인을 요구함(purpose=CHECKOUT).
  final bool cartMergeConfirm;
}

/// 필수 동의 대기.
final class LoginNeedsConsent extends LoginOutcome {
  const LoginNeedsConsent({
    required this.authRequestId,
    required this.requiredConsents,
  });

  final String authRequestId;

  /// 서버가 준 필요한 동의 항목(형식은 BR-20 확인 중이라 그대로 보존).
  final List<String> requiredConsents;
}

/// 실패가 잦아 잠시 제한됨(423 AUTH_RESTRICTED). 남은 시간은 서버 값.
final class LoginRestricted extends LoginOutcome {
  const LoginRestricted({this.retryAfterSeconds});

  final int? retryAfterSeconds;
}

/// 원인증 결과 확인 중. 같은 키 재전송 또는 authRequestId 조회로 해소한다.
final class LoginUnknown extends LoginOutcome {
  const LoginUnknown({this.authRequestId});

  final String? authRequestId;
}

/// 고객이 제공자 화면에서 취소함. 실패 횟수에 넣지 않는다(서버 판정). 원래 화면으로 돌아간다.
final class LoginCancelled extends LoginOutcome {
  const LoginCancelled();
}

/// 제공자 장애(PROVIDER_UNAVAILABLE). 다시 시도할 수 있다.
final class LoginProviderUnavailable extends LoginOutcome {
  const LoginProviderUnavailable();
}

/// 제공자 검증 실패(PROVIDER_REJECTED) 또는 구매 불가 계정 등.
final class LoginRejected extends LoginOutcome {
  const LoginRejected(this.code);

  final String code;
}

abstract final class AuthProblemCode {
  static const restricted = 'AUTH_RESTRICTED';
  static const providerRejected = 'PROVIDER_REJECTED';
  static const providerUnavailable = 'PROVIDER_UNAVAILABLE';
  static const requiredConsentMissing = 'REQUIRED_CONSENT_MISSING';
  static const accountNotPurchasable = 'ACCOUNT_NOT_PURCHASABLE';
}

/// 앱의 현재 로그인 상태.
@immutable
sealed class Session {
  const Session();
}

final class GuestSession extends Session {
  const GuestSession();
}

final class MemberSession extends Session {
  const MemberSession(this.accountId);

  final String accountId;
}
