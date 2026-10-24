import 'package:dio/dio.dart';

import 'idempotency.dart';

/// dio `Options.extra` 에 넣는 PMart 전용 값의 키.
abstract final class PmartExtra {
  static const idempotencyKey = 'pmart.idempotencyKey';
  static const expectedVersion = 'pmart.expectedVersion';

  /// 인증 헤더를 붙이지 않는 공개 경로(소셜 로그인 시작 등).
  static const public = 'pmart.public';

  /// 처리율 제한·재시도 인터셉터가 센 재시도 횟수.
  static const attempt = 'pmart.attempt';

  /// 401 뒤 토큰 갱신 후 다시 보낸 요청인지.
  static const retriedAfterRefresh = 'pmart.retriedAfterRefresh';
}

/// 변경 요청용 Options. 멱등 키는 필수다.
Options commandOptions(
  IdempotencyKey key, {
  int? expectedVersion,
  Options? base,
}) {
  final options = base ?? Options();
  return options.copyWith(
    extra: {
      ...?options.extra,
      PmartExtra.idempotencyKey: key,
      PmartExtra.expectedVersion: ?expectedVersion,
    },
  );
}

/// 공개 경로용 Options. 인증 헤더를 붙이지 않는다.
Options publicOptions({Options? base}) {
  final options = base ?? Options();
  return options.copyWith(extra: {...?options.extra, PmartExtra.public: true});
}

bool isMutation(RequestOptions o) => switch (o.method.toUpperCase()) {
  'GET' || 'HEAD' || 'OPTIONS' => false,
  _ => true,
};
