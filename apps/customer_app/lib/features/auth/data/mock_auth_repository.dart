import 'package:pmart_api_auth/pmart_api_auth.dart' as auth;
import 'package:pmart_core/pmart_core.dart';

import '../domain/auth.dart';
import 'auth_repository.dart';

/// 목 제공자. [cancelled] 제공자는 고객 취소, [down] 은 제공자 장애로 끝난다.
final class MockSocialTokenSource implements SocialTokenSource {
  MockSocialTokenSource({this.cancelled = const {}, this.down = const {}});

  final Set<SocialProvider> cancelled;
  final Set<SocialProvider> down;

  @override
  Future<SocialCredential?> obtain(SocialProvider provider) async {
    if (down.contains(provider)) throw const SocialProviderDown();
    if (cancelled.contains(provider)) return null;
    // 목은 제공자 창 없이 바로 성공한다. 실제 계정이 아님을 이름으로 드러낸다.
    return SocialCredential(
      'mock-provider-token-${provider.name}',
      accountLabel: 'mock-${provider.name}@pmart.invalid',
    );
  }
}

/// 목 구현. 제공자별로 다른 결과를 낸다(계약 AuthResult JSON → 생성 모델 → 같은 변환).
/// - 카카오: 기존 회원
/// - 네이버: 새 계정, 필수 동의 대기 → 동의 후 회원
/// - [restricted] 제공자(기본 애플, 화면에는 없음): 로그인 제한(423)
/// - 구글: 첫 시도는 결과 불명, 같은 키 재전송 시 회원
base class MockAuthRepository implements AuthRepository {
  MockAuthRepository({
    this.latency = const Duration(milliseconds: 300),
    this.restricted = const {SocialProvider.apple},
    this.restoredAccountId,
  });

  final Duration latency;
  final Set<SocialProvider> restricted;

  /// 앱 시작 때 복원될 계정(null 이면 저장된 세션 없음).
  final String? restoredAccountId;

  @override
  Future<String?> currentAccountId() async {
    await _wait();
    return restoredAccountId;
  }

  static const accountId = 'acct-mock-1';
  static const requiredConsents = [
    'TERMS_OF_SERVICE:2026-10',
    'PRIVACY_POLICY:2026-10',
    'AGE_OVER_14:2026-10',
  ];

  final _byKey = <String, Map<String, Object?>>{};
  final _byRequest = <String, Map<String, Object?>>{};
  int _seq = 0;

  /// 받은 로그인 요청 키(재전송이 같은 키인지 확인용).
  final loginKeys = <String>[];

  Future<void> _wait() => Future<void>.delayed(latency);

  Map<String, Object?> _member(
    String authRequestId, {
    bool newAccount = false,
    bool merge = false,
  }) => {
    'authRequestId': authRequestId,
    'state': 'AUTH_MEMBER',
    'accountId': accountId,
    'newAccount': newAccount,
    'tokens': {
      'accessToken': 'mock-access',
      'refreshToken': 'mock-refresh',
      'accessTokenExpiresAt': '2026-10-24T10:00:00Z',
    },
    'nextAction': merge ? 'CART_MERGE_CONFIRM' : 'NONE',
  };

  LoginOutcome _out(Map<String, Object?> json) =>
      authResultToOutcome(auth.AuthResult.fromJson(json));

  @override
  Future<LoginOutcome> login(
    SocialProvider provider,
    String providerToken, {
    required LoginPurpose purpose,
    required IdempotencyKey key,
  }) async {
    await _wait();
    loginKeys.add(key.value);
    final previous = _byKey[key.value];
    if (previous != null) return _out(previous);
    final id = 'auth-${++_seq}';
    final merge = purpose == LoginPurpose.checkout;
    if (restricted.contains(provider)) {
      return authFailureToOutcome(
        const ProblemFailure(
          Problem(
            status: 423,
            code: AuthProblemCode.restricted,
            raw: {'retryAfterSeconds': 600},
          ),
        ),
      );
    }
    switch (provider) {
      case SocialProvider.kakao:
        return _out(_byKey[key.value] = _member(id, merge: merge));
      case SocialProvider.naver:
        final json = {
          'authRequestId': id,
          'state': 'AUTH_CONSENT',
          'accountId': accountId,
          'newAccount': true,
          'requiredConsents': requiredConsents,
          'nextAction': 'COMPLETE_CONSENT',
        };
        _byRequest[id] = json;
        return _out(_byKey[key.value] = json);
      case SocialProvider.apple:
      case SocialProvider.google:
        // 서버는 처리했지만 응답을 잃은 경우. 같은 키 재전송이면 원결과가 온다.
        _byKey[key.value] = _member(id, merge: merge);
        return authFailureToOutcome(
          UnknownResultFailure(requestId: key.value, httpStatus: 503),
        );
    }
  }

  @override
  Future<LoginOutcome> lookup(String authRequestId) async {
    await _wait();
    final json = _byRequest[authRequestId];
    if (json == null) return const LoginUnknown();
    return _out(json);
  }

  @override
  Future<LoginOutcome> completeWithConsents(
    String authRequestId,
    List<String> consents, {
    required IdempotencyKey key,
  }) async {
    await _wait();
    final missing = requiredConsents.where((c) => !consents.contains(c));
    if (missing.isNotEmpty) {
      return const LoginRejected(AuthProblemCode.requiredConsentMissing);
    }
    final json = _member(authRequestId, newAccount: true);
    _byRequest[authRequestId] = json;
    return _out(json);
  }
}
