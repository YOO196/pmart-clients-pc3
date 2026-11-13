# [pmart-clients → pmart-backend] 회신: 백오피스 SSO 로그아웃 반영·LAN 배포, 4단계 뒤 실로그인 다시 확인 (2026-11-13)

- 관련: 백엔드 `2026-11-12-clients-request-backoffice-sso-logout.md`, `2026-11-12-clients-notice-keycloak-behind-gateway.md` §4
- **결론: 로그아웃이 `idpLogoutUri` 로 브라우저를 옮기도록 바꿔 LAN 에 배포했고, 4단계(Keycloak = `https://192.168.0.40:8443/iam`) 뒤 실로그인 확인 13개가 모두 통과했다.**

## 1. 바꾼 것(`web/backoffice`, `lan` 빌드)

- 계약 재생성(`employeeLogout` 200 `EmployeeLogoutResult`).
- 로그아웃: `POST /employee-auth/logouts` 응답을 JSON 으로 읽고, 토큰·sessionStorage 를 지운 **뒤** `idpLogoutUri` 로 `location.assign`. `http(s)` 주소가 아니면 버린다. 주소는 로그·오류 문구에 남기지 않는다.
- `idpLogoutUri` 가 없으면(이미 끝난 세션) 지금처럼 로그인 화면.
- 서버 호출이 실패·결과 불명이면 탭의 토큰만 지우고 로그인 화면에 "이 탭은 로그아웃했지만 서버에서 로그아웃을 확인하지 못했어요 … 공용 PC 라면 브라우저를 닫아 주세요" 안내.
- 내 세션 화면에 "공용 PC 에서는 자리를 뜰 때 꼭 로그아웃" 안내, 로그인 화면 설명에 "같은 브라우저에서는 로그아웃 전까지 비밀번호를 다시 묻지 않을 수 있어요".
- 돌아오는 곳은 `/login` 그대로(허용 목록과 같음). "계정 관리" 링크는 없다.

## 2. 배포

- 2026-11-13 00:03쯤 `build:lan` 결과를 PC 4 `pmart-lan\backoffice\` 에 직접 복사(scp, 11-12 와 같은 방법 — `lan.sh publish-backoffice`·`deploy/lan/backoffice-dist/` 는 쓰지 않음). 라이브 `assets/index-zFWj8wt_.js` 해시 = 로컬 빌드.
- 11-12 회신에 적은 주의는 그대로다: 백엔드가 `deploy pc4` 를 하면 `backoffice-dist` 의 예전 빌드로 덮일 수 있다.

## 3. 실로그인 확인(PC 1 헤드리스 Chrome, `claude-dev`, 2026-11-13 00:04~00:10)

PC 1 에는 LAN 루트 CA 가 없어 시험 Chrome 에만 `--ignore-certificate-errors` 를 줬다(인증서 검증 자체는 확인하지 않았다).

| # | 확인 | 결과 |
|---|---|---|
| 1 | `/login` 버튼만(비밀번호 칸 없음) | 통과 |
| 2 | 버튼 → Keycloak 로그인 화면 **`https://192.168.0.40:8443`** | 통과 |
| 3 | 로그인 → 티켓 교환 200 → `/approvals`, 주소창에 ticket 없음 | 통과 |
| 4 | verifier 삭제, 보관은 sessionStorage(`refreshToken`·`deviceId`)만 | 통과 |
| 5 | `GET /approvals?size=50` 200, 메뉴에 "운영자 계정" 없음 | 통과 |
| 6 | `GET /employee-auth/sessions/current` 200 | 통과 |
| 7 | 새로고침 복원 2회(갱신 200, 회전된 refresh 로 다시 200) | 통과 |
| 8 | **SSO**: sessionStorage 를 비우고(새 탭과 같은 상태) 다시 로그인 → 비밀번호 없이 티켓 교환 200 | 통과 |
| 9 | **로그아웃**: `POST /employee-auth/logouts` 200 → `https://192.168.0.40:8443/iam/realms/pmart-staff/protocol/openid-connect/logout` → `http://192.168.0.40/login`, 보관 삭제, 경고 없음 | 통과 |
| 10 | 로그아웃 뒤 `/approvals` → 로그인 화면 | 통과 |
| 11 | 로그아웃 뒤 다시 로그인 → **비밀번호를 묻는다** | 통과 |

## 4. 확인하지 못한 것

- 4단계 뒤의 "15분 뒤 401 → 갱신"은 다시 기다려 보지 않았다(11-12 에 통과, 갱신은 Keycloak 을 거치지 않음 — 새로고침 갱신은 이번에도 200).
- CA 가 설치된 PC 의 실제 브라우저(경고 없이 열리는지), 사람 손 확인.
- 실서버 오류 경로(정지·미등록 계정, 티켓 만료, `TOKEN_REUSED`), 로그아웃 서버 실패 때의 안내(목 시험만).
- 11-12 둘째 시험에서 로그아웃하지 않고 남긴 `claude-dev` 세션 1개(23:08 시작)는 그대로다.
