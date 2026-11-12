# [pmart-clients → pmart-backend] 회신: 백오피스 로그인 employee-auth 전환 — 구현함(LAN 배포 전), 요청서와 다르게 만든 점 (2026-11-12)

- 관련: 백엔드 요청 `docs/handoff/clients/2026-11-12-clients-request-backoffice-employee-auth-login.md`, ADR-0056, 계약 `employee-auth-service.yaml` 0.1.0
- **사용자 결정(2026-11-12)**: 요청을 수락한다. 운영자 계정 화면은 내린 상태로 둔다. 인사팀용 백오피스를 따로 하나 더 추가한다(§4).
- **상태: 구현·목 검증까지 끝났고, LAN 배포와 실제 로그인 확인은 아직이다.** 요청서 §7-1 의 "배포 회신"은 배포·실로그인 확인 뒤에 따로 보낸다 — **이 문서를 4단계(Keycloak 주소 변경) 시작 신호로 쓰지 말아 달라.**

## 1. 만든 것

`web/backoffice` 의 `lan` 빌드가 employee-auth 로 로그인한다(미커밋, `build:lan` 성공).

| 항목 | 구현 |
|---|---|
| 로그인 시작 | `/login` 의 "직원 계정으로 로그인" 버튼 → 브라우저 이동 `GET {게이트웨이}/api/v1/employee-auth/logins?app=backoffice&deviceId=…&codeChallenge=…&codeChallengeMethod=S256&returnUri=<출처>/auth/callback` |
| 복귀 경로 | **`/auth/callback`** — 허용 목록 그대로 쓴다(요청서 §7-2: 다른 경로 필요 없음). 11-11 의 `/login/callback` 은 없앴다 |
| 티켓 교환 | `POST /employee-auth/tokens` `{ticket, codeVerifier}` + `Idempotency-Key`·`X-Source-System`·`X-Device-Id`. 교환 뒤 주소창에서 ticket 을 지우고 verifier 를 지운다. 실패하면 같은 티켓을 다시 보내지 않고 다시 로그인 |
| 갱신 | API 가 401 을 주면 `POST /employee-auth/tokens/refresh` 한 번(한 곳에서만, 응답의 새 refresh 로 바로 교체). `TOKEN_INVALID`·`TOKEN_REUSED` → 로그인 화면. 응답을 잃으면 같은 refresh 를 다시 보내지 않는다 |
| 로그아웃 | `POST /employee-auth/logouts` `{allDevices:false}` → 토큰 삭제(서버 응답이 실패해도 이 탭은 지운다) |
| 내 세션 | `GET /employee-auth/sessions/current`. `roles` 가 비면 "권한 승인 대기" 안내 |
| 오류 안내 | 복귀 `?error=` 5종, `TICKET_INVALID`, 403 `ACCOUNT_NOT_AVAILABLE` 을 코드별 문구로 |
| 지운 것 | 11-11 의 Keycloak 직접 로그인(공개 클라이언트 `pmart-backoffice` 사용 코드, 빌드 모드 `lan-keycloak`). 백오피스는 Keycloak 주소·client_id 를 갖지 않는다 |

LAN 게이트웨이에 직접 확인한 것(curl, 2026-11-12 밤): 위 주소 형식으로 로그인 시작 **302**(Keycloak 인가 주소로), 허용 목록 밖 `returnUri` **400**, `POST /employee-auth/tokens` CORS 사전 요청 **200**(출처 `http://192.168.0.40`, 헤더 `content-type, idempotency-key, x-device-id, x-source-system` 허용).

## 2. 요청서와 다르게 만든 점과 이유

| # | 요청서 | 만든 것 | 이유 |
|---|---|---|---|
| D1 | `deviceId` 는 **localStorage** 에 한 번 만들어 계속 사용(§2-1) | **이 탭의 sessionStorage**. 탭마다 값이 다르고 탭을 닫으면 사라진다 | 클라이언트 규칙이 백오피스에서 localStorage 를 쓰지 않는다(공용 PC 에 값이 남지 않게, BR-03). refresh token 도 같은 자리(탭 sessionStorage)에 둔다. 로그인 시작 → 티켓 교환 → 갱신에는 같은 값을 보내므로 계약 조건(시작한 기기 ID)은 지킨다 |
| D2 | `X-Source-System: backoffice`(§2-4 예시) | **`backoffice-web`** | 백오피스가 다른 모든 API 에 보내는 값과 같게 했다(11-09 문의 답변 요청서도 `backoffice-web`). 한 앱이 두 값을 쓰면 감사 기록에서 같은 앱이 둘로 보인다 |
| D3 | `code_challenge` 는 Web Crypto `crypto.subtle.digest`(§2-1) | 보안 컨텍스트가 아니면 **순수 JS SHA-256**(표준 값·RFC 7636 예시로 시험) | LAN 백오피스는 `http://192.168.0.40` 이라 브라우저에 `crypto.subtle` 이 없다. HTTPS 가 되면 subtle 을 쓴다(자동) |
| D4 | access token 은 15분 — **만료 전에 갱신**(§3) | 만료 전에 미리 갱신하지 않고 **API 가 401 을 주면 그때 한 번 갱신**하고 원 요청을 다시 보낸다 | 기존 방식 그대로다(ADR-0018 때부터). 시계가 틀린 PC 에서도 서버 판정만 따른다. 갱신 호출이 한 곳이라 refresh 재사용이 생기지 않는다 |
| D5 | 여러 탭이 동시에 갱신하지 않게(§3) | 따로 막는 장치 없음 | D1 때문에 탭마다 로그인·세션·refresh 가 따로다(탭을 새로 열면 다시 로그인). 같은 refresh 를 두 탭이 쓰는 경우는 브라우저의 "탭 복제"뿐이고, 그때는 `TOKEN_REUSED` 로 다시 로그인하게 된다 |
| D6 | (요청서에 없음) | `mock`·`local` 빌드는 **auth-service 아이디·비밀번호 로그인 그대로** | 목 서버(MSW)는 302 로 Keycloak 화면을 흉내 낼 수 없어 개발·자동 시험은 예전 로그인으로 한다. LAN 에 배포되는 것은 `lan` 빌드뿐이다 |

D1·D5 로 생기는 차이: 한 직원이 탭을 여러 개 쓰면 **세션이 탭 수만큼** 생긴다.

## 3. 확인·질문

| # | 질문 |
|---|---|
| Q1 | D1(탭마다 다른 `deviceId`, 한 직원에게 세션 여러 개)이 employee-auth 쪽 제한(직원당 세션 수·기기 수)에 걸리는 것이 있나? |
| Q2 | D2 `X-Source-System: backoffice-web` 로 보내도 되나? `backoffice` 여야 하면 로그인 호출만 바꾼다 |
| Q3 | 직원 **표시 이름**을 받을 곳이 없다(티켓 교환 응답·직원 토큰·`sessions/current` 에 이름 없음). 지금은 메뉴에 운영자 ID(`OP-…`)를 보인다. 이름을 줄 계획이 있나(hr-service 이후)? |
| Q4 | `local` 빌드(로컬 백엔드)는 아직 auth-service `POST /auth/operator-logins` 를 쓴다. 로컬에서도 auth-service 의 OPERATOR 발급을 끌 예정이면 시기를 알려 달라 — 그 전에 `local` 도 employee-auth 로 바꾼다(복귀 주소 `http://localhost:5173/auth/callback` 은 허용 목록에 이미 있음) |

## 4. 계정 화면·인사팀 백오피스

- 운영자 계정 화면(`/operators`): `lan` 빌드에서 **메뉴에서 뺐고**, 주소로 들어가면 안내문만 보인다(`/operator-accounts` API 를 부르지 않음). 요청서 §4 대로다.
- **2026-11-11 에 보낸 요청(`2026-11-11-backend-keep-auth-service-operator-login.md`)의 R1·R2 는 LAN 기준으로 더 필요 없다** — LAN 백오피스는 auth-service 운영자 로그인·계정 API 를 쓰지 않는다. 그 문서의 Q1~Q3 도 회신하지 않아도 된다. (`local` 빌드는 Q4 참고.)
- 사용자 결정: **인사팀용 백오피스를 따로 추가한다.** hr-service 계약(`contracts/openapi`)과 요청서(ADR-0056 5단계)가 오면 시작한다. 계약 전에는 만들지 않는다.

## 5. 남은 것(클라이언트)

1. LAN 배포(`build:lan` 결과 → `lan.sh publish-backoffice`)와 `claude-*` 시험 계정 실로그인 확인(로그인 → 업무 화면 → 15분 뒤 갱신 → 로그아웃).
2. 확인되면 **배포 회신**을 새 문서로 보낸다(요청서 §7-1). 그 뒤 백엔드 4단계.
