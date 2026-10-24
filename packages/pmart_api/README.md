# pmart_api — 계약 생성 클라이언트

`../pmart-backend/contracts/openapi/*.yaml` 에서 서비스마다 Dart 패키지를 하나씩 생성한다.

- 위치: `gen/<service>/` (패키지 이름 `pmart_api_<service>`, 예: `pmart_api_cart`)
- 생성물은 커밋하지 않는다(`.gitignore`). 생성에 쓴 백엔드 커밋은 루트 `contracts.lock` 에 남는다.
- 대상 서비스 목록과 앱 대응은 `tools/gen_api.dart` 의 `services` 에 있다.
- 외부 클라이언트가 부르지 않는 경로(`/internal`, `/webhooks`, `/actuator`)는 생성 전에 걸러낸다.

## 생성
```bash
# 저장소 루트에서. 새로 clone 했으면 flutter pub get 보다 먼저 실행한다
# (루트 workspace 가 gen/* 를 포함하므로 생성 전에는 pub get 이 실패한다).
dart tools/gen_api.dart                  # 전체 (약 5~6분, build_runner 포함)
dart tools/gen_api.dart --only=cart,order
```

## 쓰는 법
- Dio 는 `pmart_core` 의 `createPmartDio` 로 만든 것을 넘긴다. 헤더·멱등 키·401·429 처리는 거기서 한다.
- 화면에 생성 DTO 를 그대로 쓰지 않는다. 각 앱 `features/<f>/data` 에서 `domain` 모델로 바꾼다.
- 오류 응답(`…400Response` 같은 생성 타입)은 쓰지 않고 `pmart_core` 의 `PmartFailure`/`Problem` 으로 처리한다.

## 생성기 보정
- openapi-generator 7.26.0 `dart-dio`(json_serializable)는 기본값이 있는 인라인 enum 을 컴파일되지 않게 만든다.
  `tools/gen_api.dart` 의 `_fixEnumDefaults` 가 생성 직후 고친다(현재 auth `SocialLoginRequest.purpose`, storefront `PublishLayoutRequest.scope`).
- OpenAPI 3.1 지원은 생성기에서 beta 다. 계약이 바뀌면 생성 후 각 패키지에서 `dart analyze` 로 오류가 없는지 본다.
