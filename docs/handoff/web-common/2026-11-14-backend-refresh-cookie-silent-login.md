# 회신: refresh 쿠키(Signed Double-Submit CSRF) + 조용한 로그인 확인(silent) 반영 · 새 웹 빌드

- 보낸 앱: web-common (backoffice·hr-backoffice 둘 다 쓰는 `web/core`)
- 받는 백엔드 영역: platform
- 작성: pmart-clients, 2026-11-14
- 답하는 것: `../pmart-backend/docs/handoff/clients/web-common/2026-11-13-web-common-request-refresh-cookie.md`, `…/web-common/2026-11-13-web-common-request-silent-login.md`
- 계약: `employee-auth-service.yaml` 0.3.0 (`gen:api`, 백엔드 `9e3801a`)
- 상태: 코드·시험 끝, **미커밋**. 웹 빌드 두 개를 새로 만들었다 — **PC 4 에는 올리지 않았다.** `publish-*` 로 올리고 `refresh-cookie` 를 켜 달라.
- **실서버·브라우저 확인은 하지 않았다**(목·단위 시험만). 요청 §4 의 확인 항목은 빌드를 올리고 설정을 켠 뒤에 해야 한다 — 아래 §4.

## 1. refresh 쿠키 — 요청 §3 항목별

| 요청 | 반영 |
|---|---|
| 1. credentials | `POST /employee-auth/tokens`(티켓 교환), `POST /employee-auth/tokens/refresh/{sessionId}`, `POST /employee-auth/logouts` 세 호출만 `credentials: 'include'`. 다른 API 는 그대로(Bearer, 쿠키 없음). 본문 갱신 `POST /employee-auth/tokens/refresh` 도 쿠키 없이 |
| 2. 저장 | `refreshTransport = COOKIE` 면 sessionStorage 에 `sessionId`·`deviceId` 만. `BODY` 면 지금처럼 `refreshToken`·`deviceId`. `refreshTransport` 가 없는 응답(0.3.0 전)은 본문에 refresh token 이 있으면 BODY 로 본다 |
| 3. 갱신 | `document.cookie` 의 `__Secure-pmart_ea_csrf_{sessionId}` 값을 `X-CSRF-Token` 으로. `X-Device-Id`·`Idempotency-Key`·`X-Source-System`, 본문 없음. single-flight 그대로(pmartFetch 한 곳) |
| 4. 결과 불명 | 쿠키 갱신이 응답 없이 끝나거나(연결 오류·타임아웃) 본문 없는 5xx·`UNKNOWN_RESULT`·`DEPENDENCY_UNAVAILABLE` 이면 다시 보내지 않고 세션 끝으로 본다 → silent 로그인 |
| 5. F5 | sessionStorage 의 `sessionId` 로 쿠키 갱신 먼저 → 실패하면 보관을 지우고 silent 로그인 → 그래도 없으면 로그인 버튼 |
| 6. CSRF 쿠키 없음·403 `CSRF_INVALID` | 이 탭의 세션을 버리고 silent 로그인. CSRF 쿠키가 없으면 갱신 요청 자체를 보내지 않는다 |
| 7. 로그아웃 | 서버 호출이 실패해도 이 탭의 `sessionId` 를 지운다. `idpLogoutUri` 이동은 그대로 |
| 8. 로컬 개발 | 코드 변경 없음(같은 코드). 로컬 게이트웨이로는 확인하지 않았다 |

알아 둘 것:
- **쿠키 갱신에서 서버가 사유를 알려 준 거절 중 위 표에 없는 것**(예: 429, 4xx 의 다른 code)은 세션을 끊지 않고 그 요청만 실패로 둔다(다음 401 때 다시 갱신한다). 이런 응답에서는 refresh 쿠키가 쓰이지 않았다고 가정했다 — 아니라면 알려 달라.
- 목 서버(MSW)는 `refreshTransport: BODY` 로 답한다(서비스 워커가 HttpOnly 쿠키를 심지 못한다). 쿠키 방식은 시험에서 가짜 응답·가짜 `document.cookie` 로 본다.

## 2. 조용한 로그인 확인(silent) — 요청 §2 항목별

| 요청 | 반영 |
|---|---|
| 1. 열 때 한 번 | 세션 없이 로그인 화면에 닿으면(업무 주소로 열어도 로그인 화면으로 간다) 버튼을 보이기 전에 `silent=true` 로 로그인 시작. PKCE·deviceId·returnUri 는 버튼과 같다. F5 복원(쿠키 갱신)이 있으면 그것이 끝난 뒤에 |
| 2. 복귀 | `ticket` → 교환하고 가려던 화면. `error=LOGIN_REQUIRED` → 오류 문구 없이 로그인 버튼. 그 밖의 error → 지금처럼 안내 + "다시 로그인" |
| 3. 되풀이 방지 | 이 탭 sessionStorage 표시(`pmart.<앱>.login.silent`). silent 를 시작할 때·로그아웃할 때 표시하고, **티켓 교환에 성공해 세션이 생기면 지운다**(그 세션이 끝난 뒤 한 번 더 확인할 수 있게 — 쿠키 요청의 "세션 끝남 → silent 로그인"). `LOGIN_REQUIRED` 뒤·로그아웃 직후에는 버튼만 |
| 4. 깜빡임 | 확인하는 동안 "로그인 확인 중…" |
| 5. 딥링크 | 가려던 경로(쿼리 포함)를 보존한다. `LOGIN_REQUIRED` 뒤 버튼으로 로그인해도 그 경로로 간다 |

- 목 모드에는 Keycloak 이 없어 silent 를 하지 않는다(목 계정 버튼 그대로).
- sessionStorage 를 쓸 수 없는 브라우저에서는 silent 를 하지 않는다(되풀이를 막을 수 없어서).

## 3. 새 웹 빌드 — 올려 달라

| 앱 | dist 폴더 (PC 1) | 진입 파일 | 주소 |
|---|---|---|---|
| 백오피스 | `C:\development\pmart-project\pmart-clients\web\backoffice\dist` | `assets/index-C3tIw2he.js`, `assets/index-DFPfEyEK.css` | `https://192.168.0.40` |
| 인사팀 백오피스 | `C:\development\pmart-project\pmart-clients\web\hr-backoffice\dist` | `assets/index-Ch12cCuR.js`, `assets/index-pUB-rvKV.css` | `https://192.168.0.40:8444` |

- 두 빌드 모두 API 는 `https://192.168.0.40:8443/api/v1` 만.
- **올리는 순서에 주의**: 이 빌드는 티켓 교환·로그아웃을 `credentials: 'include'` 로 부른다. 게이트웨이가 그 경로에 두 출처의 자격 증명 CORS(`credentialed-origins`)를 열어 둔 상태여야 로그인이 된다(`api-gateway-lan.yml` 에 값이 있는 것은 봤다 — LAN 에 배포됐는지는 모른다). `refresh-cookie` 를 켜기 전(BODY 응답)에도 이 빌드는 지금 방식으로 동작하게 만들었다.
- silent 도 이 빌드부터 쓴다 — employee-auth-service 0.2.0 이상이 LAN 에 있어야 한다(없으면 `silent` 를 모르는 서버가 로그인 화면을 띄울 것이다 — 확인하지 않았다).

## 4. 아직 안 한 것 — 올린 뒤 같이 확인

요청 §4 의 항목은 하나도 실서버로 보지 않았다.
- 같은 앱 탭 두 개가 각자 15분 넘게 갱신, 백오피스(443)·인사팀(8444) 동시 사용, 갱신 중 F5, 탭 닫고 새 탭(silent), 한 탭 로그아웃 뒤 다른 탭.
- 개발자 도구: refresh 쿠키 HttpOnly·`document.cookie` 에 안 보임, CSRF 쿠키 이름이 세션마다 다름.
- CSP·CORS 오류 0.
- silent: 인사팀 백오피스 로그인 뒤 새 탭에서 백오피스 → 버튼 없이 들어가는지, 로그아웃 뒤에는 버튼이 보이는지.
