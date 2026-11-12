# ADR-0003 인사팀 백오피스를 별도 웹 앱으로 두고, 웹 공통 코드는 공유 패키지로 뺀다

- 상태: 승인 (2026-11-13, 사용자 결정)
- 관련: ADR-0001 결정 1(React SPA 는 `web/backoffice` 하나)을 **보완**한다. 백엔드 ADR-0056, 백엔드 handoff `2026-11-13-clients-request-hr-backoffice.md`

## 배경
- 직원 로그인이 employee-auth-service 로 바뀌면서(2026-11-12) 백오피스의 운영자 계정 화면을 내렸고, 직원 등록은 hr-service(인사팀)로 옮겨 갔다.
- 사용자 지시: "인사팀 백오피스 하나 더 추가할 거야"(2026-11-12), 백엔드에 "별도 인사팀 백오피스 앱, SSO 켬"(2026-11-13), "공통 코드는 공유 패키지로 해줘"(2026-11-13).

## 결정
1. 인사팀 화면은 `web/backoffice` 의 메뉴가 아니라 **별도 SPA `web/hr-backoffice`** 로 만든다(출처·employee-auth 앱 이름·`X-Source-System` 이 다르다). 스택은 백오피스와 같다.
2. 두 웹 앱이 같이 쓰는 코드는 npm workspace 의 공유 패키지에 둔다. 빌드 없이 소스(`src/index.ts`)를 앱이 직접 묶는다.
   - `web/core`(`@pmart/web-core`): 실패 분류·`pmartFetch`·멱등키·폴링·토큰 보관·직원 로그인(employee-auth). React 없음. Dart 의 `pmart_core` 에 해당.
   - `web/ui`(`@pmart/web-ui`): UiState 표시(`QueryState`)·명령 결과(`Feedback`·`useCommand`)·공통 문구·직원 로그인 문구. Dart 의 `pmart_ui` 에 해당.
3. 공유 패키지에 **앱 이름을 넣지 않는다.** 앱마다 다른 값(`X-Source-System`, employee-auth 앱 이름, sessionStorage 키, Problem code → 문구 표)은 앱이 넘긴다(`commandParamsFor`, `createEmployeeAuth`, `createSessionPersistence`, `UiTextProvider`).
4. 앱 전용으로 남기는 것: 생성 타입으로 만든 API 클라이언트(`src/api/client.ts`), 화면 모델, 화면·문구, 세션 컨텍스트·로그인 화면(백오피스는 auth-service 로그인 방식도 갖고 있어 모양이 다르다).

## 결과
- 로그인·갱신·SSO 로그아웃 로직은 한 벌이다. 한 곳을 고치면 두 앱에 같이 반영된다.
- Tailwind 는 공유 패키지의 클래스를 자동으로 읽지 않는다 → 각 앱의 `index.css` 에 `@source "../../ui/src";` 를 둔다.
- `tools/web-tools/gen-api.mjs` 는 생성 타입을 백오피스에 만들고, 다른 패키지가 쓰는 계약만 그 패키지의 `generated/` 로 복사한다(core = `employee-auth`, hr-backoffice = `hr`·`center-master`).
- 검증 명령은 패키지마다 돌린다: `npm run typecheck|lint|test -w web/<core|ui|backoffice|hr-backoffice>`.
- 세션 컨텍스트·로그인 화면은 앱마다 따로라, 그 부분(약 200줄)은 두 앱에 비슷한 코드가 있다. 백오피스의 auth-service 로그인을 걷어내는 시점에 공유 패키지로 합칠 수 있다.
