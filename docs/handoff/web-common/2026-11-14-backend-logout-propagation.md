# 회신: 탭이 다시 보일 때 세션 확인(로그아웃 전파) 반영 · 새 웹 빌드

- 보낸 앱: web-common (backoffice·hr-backoffice 둘 다 쓰는 `web/core`)
- 받는 백엔드 영역: platform
- 작성: pmart-clients, 2026-11-14
- 답하는 것: `../pmart-backend/docs/handoff/clients/web-common/2026-11-14-web-common-request-logout-propagation.md`
- 계약: `employee-auth-service.yaml` 0.4.0 — API 모양이 그대로라 `gen:api` 는 다시 하지 않았다(`contracts.lock` 은 `9e3801a` 그대로)
- 상태: 코드·시험 끝, **미커밋**. 웹 빌드 두 개를 새로 만들었다 — **PC 4 에는 올리지 않았다.** `publish-*` 로 올려 달라.
- **실서버·브라우저 확인은 하지 않았다**(목·단위 시험만).

## 1. 요청 §2 항목별

| 요청 | 반영 |
|---|---|
| 1. 보이게 될 때 한 번 | `document` 의 `visibilitychange` 에서 `visibilityState === 'visible'` 이고 세션(access token)이 있으면 `GET /employee-auth/sessions/current` 한 번. Bearer 만, 쿠키 없음(`credentials` 기본값) |
| 2. 200 | 아무것도 하지 않는다 |
| 3. 401 | 따로 만든 처리가 없다 — 다른 API 와 같은 `pmartFetch` 의 401 처리다: 갱신 한 번(single-flight) → 거절되면 이 탭의 세션·보관을 지운다 → 로그인 화면 → silent → `LOGIN_REQUIRED` 면 버튼 |
| 4. 네트워크 오류·5xx | 버린다(세션 그대로, 안내 없음) |
| 5. 30초 | 마지막 확인 뒤 30초 안이면 부르지 않는다. 세션이 없어 건너뛴 것은 세지 않는다 |

알아 둘 것:
- 가려질 때(`hidden`)는 부르지 않는다. 창 포커스(`focus`)는 보지 않는다 — 요청대로 `visibilitychange` 만. 그래서 **두 앱을 창 둘에 나란히 띄워 둔 경우**(둘 다 계속 보임)는 이 확인이 돌지 않고 다음 API 호출 때 알게 된다.
- 로그인 화면으로 간 뒤의 silent 는 지금 규칙 그대로다: 세션이 있던 탭은 silent 표시가 지워져 있어 한 번 확인하고, 로그아웃된 것이면 `LOGIN_REQUIRED` → 버튼.
- 가려던 경로(쿼리 포함)는 로그인 뒤 돌아갈 곳으로 보존된다. 입력 중이던 폼 내용은 보존하지 않는다(다른 401 과 같다).

## 2. 새 웹 빌드 — 올려 달라

| 앱 | dist 폴더 (PC 1) | 진입 파일 | 주소 |
|---|---|---|---|
| 백오피스 | `C:\development\pmart-project\pmart-clients\web\backoffice\dist` | `assets/index-DpNQsmR7.js`, `assets/index-DFPfEyEK.css` | `https://192.168.0.40` |
| 인사팀 백오피스 | `C:\development\pmart-project\pmart-clients\web\hr-backoffice\dist` | `assets/index-CBdEBq5M.js`, `assets/index-pUB-rvKV.css` | `https://192.168.0.40:8444` |

- 두 빌드 모두 API 는 `https://192.168.0.40:8443/api/v1` 만. CSS 는 앞 빌드와 같다.
- 올리는 순서 제약 없음(서버 0.4.0 은 이미 LAN 에 있고, 이 빌드가 새로 부르는 API 는 없다).

## 3. 아직 안 한 것 — 올린 뒤 같이 확인

- 요청 §3: 같은 브라우저 인사팀 탭 + 백오피스 탭 → 백오피스 로그아웃 → 인사팀 탭으로 돌아가면 로그인 화면. 다른 브라우저(시크릿 창)의 같은 직원 세션은 그대로.
- 앞 회신(`2026-11-14-backend-refresh-cookie-silent-login.md`) §4 의 브라우저 확인도 그대로 남아 있다.
