/// 실행 환경. `--dart-define=PMART_ENV=mock|local` 로 고른다.
///
/// `dev`/`prod` 는 배포 환경이 정해지면 추가한다(client-architecture §6).
enum PmartEnv {
  mock,
  local;

  static PmartEnv fromDefine() =>
      parse(const String.fromEnvironment('PMART_ENV', defaultValue: 'mock'));

  static PmartEnv parse(String value) => switch (value) {
    'mock' => PmartEnv.mock,
    'local' => PmartEnv.local,
    _ => throw ArgumentError.value(value, 'PMART_ENV', 'mock 또는 local'),
  };
}

/// 환경별 API 기준 주소.
///
/// Android 에뮬레이터에서는 호스트 PC 가 `10.0.2.2` 로 보이므로 호출 측이 알려 준다.
String apiBaseUrl(PmartEnv env, {bool androidEmulator = false}) =>
    switch (env) {
      // 목 모드는 네트워크를 쓰지 않는다. Repository 목 구현이 응답한다.
      PmartEnv.mock => 'http://mock.invalid/api/v1',
      PmartEnv.local =>
        androidEmulator
            ? 'http://10.0.2.2:8080/api/v1'
            : 'http://localhost:8080/api/v1',
    };
