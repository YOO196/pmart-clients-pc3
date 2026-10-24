---
paths:
  - "packages/pmart_core/**"
  - "packages/pmart_api/**"
  - "apps/*/lib/features/*/data/**"
  - "web/backoffice/src/api/**"
  - "web/backoffice/src/mocks/**"
  - "tools/**"
---

# API 연동 규칙

정본: `docs/architecture/client-architecture.md` §5. 계약 정본: `../pmart-backend/contracts/openapi/`.

## 계약
- 경로·필드·enum은 생성 코드에서만 가져온다. 문자열 경로·필드명을 손으로 만들지 않는다.
- 계약에 없는 것이 필요하면 `docs/backend-requests.md` 에 BR 항목을 추가하고, 목에서만 쓰며 코드에 `// BR-xx` 를 남긴다.
- 계약을 다시 생성하면 `contracts.lock` 의 백엔드 SHA를 갱신하고 diff 영향을 worklog에 적는다.
- `../pmart-backend` 는 읽기 전용이다.

## 요청
- 변경 요청은 `pmart_core`(웹은 `src/api`)의 명령 헬퍼로만 보낸다. 헬퍼가 `Idempotency-Key`·`X-Source-System`·`X-Expected-Version` 을 붙인다.
- 키는 사용자 행위 단위로 만들어 상태에 보관한다. 재시도·재전송은 같은 키, 새 클릭은 새 키.
- 자동 재시도는 `retryable=true` 또는 429(`Retry-After`)일 때만. 비멱등 경로를 키 없이 재시도하지 않는다.

## 응답
- `CommandResponse.status` 4값을 모두 처리한다. `ACCEPTED` 를 성공 문구로 표시하지 않는다.
- 오류 분기는 Problem `code` 로만. `title`/`detail`/HTTP 메시지 문자열 비교 금지.
- 타임아웃·5xx·`UNKNOWN_RESULT` 는 `ResultResolver`(짝 조회)로. 실패로 확정하지 않는다.
- 조회 실패를 빈 값·0으로 바꾸지 않는다. `PolicyValue` `NOT_SET` 은 "미설정"으로 표시.
- 화면에 생성 DTO를 그대로 쓰지 않고 `domain` 모델로 변환한다(계약 변경이 화면 전체로 번지지 않게).

## 보안·로그
- 토큰·`providerToken`·`paymentKey`·주소 원문·전화번호를 로그·분석·크래시 리포트에 남기지 않는다. HTTP 로깅 인터셉터는 헤더·본문을 마스킹한다.
- 비밀값(PG 시크릿, 소셜 앱 시크릿)은 클라이언트에 두지 않는다. 공개 키(토스 `clientKey`)는 서버 응답으로 받는다.
