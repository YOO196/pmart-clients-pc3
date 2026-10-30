import 'package:dio/dio.dart';
import 'package:pmart_api_auth/pmart_api_auth.dart' as auth;
import 'package:pmart_core/pmart_core.dart';

/// 비회원 장바구니 토큰(`typ=GUEST`)의 refresh 보관 키. 회원 토큰과 따로 둔다.
const guestRefreshKey = 'pmart.guest.refreshToken';

/// `POST /auth/guest-sessions`(토큰 없이). 기기마다 비회원 주체와 토큰 쌍을 받는다(ADR-0022).
typedef GuestSessionStarter = Future<AuthTokens> Function();

GuestSessionStarter guestSessionStarter({
  required String baseUrl,
  required String sourceSystem,
  required DeviceIdProvider deviceId,
  HttpClientAdapter? adapter,
}) {
  // 인증 인터셉터를 거치지 않는 별도 Dio(토큰 없이 부르는 공개 경로).
  final dio = Dio(BaseOptions(baseUrl: baseUrl));
  if (adapter != null) dio.httpClientAdapter = adapter;
  final logins = auth.PmartApiAuth(dio: dio).getLoginsApi();
  return () async {
    final res = await pmartGuard(
      () async => logins.startGuestSession(
        idempotencyKey: IdempotencyKey.generate().value,
        xSourceSystem: sourceSystem,
        xDeviceId: await deviceId.get(),
      ),
    );
    final pair =
        res.data?.tokens ??
        (throw const ContractViolationFailure('비회원 세션 tokens 없음'));
    return AuthTokens(
      accessToken: pair.accessToken,
      refreshToken: pair.refreshToken,
    );
  };
}

/// 비회원 장바구니 요청 전에 비회원 세션을 보장한다.
///
/// 저장된 비회원 refresh token 이 있으면 그대로 두고(401 이면 인증 인터셉터가 갱신한다),
/// 둘 다 없을 때만 새 세션을 시작한다. 동시에 여러 요청이 와도 한 번만 시작한다.
/// 토큰을 잃거나 30일이 지나 갱신이 거절되면 다음 요청에서 새 세션을 만든다(이전 비회원 장바구니는 되찾지 않는다).
final class GuestSessionInterceptor extends Interceptor {
  GuestSessionInterceptor({required this.tokens, required this.start});

  final TokenStore tokens;
  final GuestSessionStarter start;
  Future<void>? _starting;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      if (tokens.accessToken == null &&
          await tokens.readRefreshToken() == null) {
        await (_starting ??= _start().whenComplete(() => _starting = null));
      }
      handler.next(options);
    } on PmartFailure catch (f) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          error: f,
        ),
      );
    }
  }

  Future<void> _start() async => tokens.save(await start());
}
