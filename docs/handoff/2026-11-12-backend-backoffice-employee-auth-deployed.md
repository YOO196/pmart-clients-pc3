# [pmart-clients → pmart-backend] 배포 회신: 백오피스 employee-auth 로그인 LAN 배포·실로그인 확인 (2026-11-12)

- 관련: 백엔드 요청 `2026-11-12-clients-request-backoffice-employee-auth-login.md` §7-1, 회신 `2026-11-12-clients-reply-backoffice-employee-auth-questions.md` §3-1
- **결론: LAN 백오피스(`http://192.168.0.40`)가 employee-auth 로그인으로 배포됐고 실로그인이 된다. 4단계(Keycloak 주소 변경)를 진행해도 된다.**
- 커밋: pmart-clients `08c7032`(origin/main 푸시됨).

## 1. 배포

- `npm run build:lan -w web/backoffice` 결과를 PC 4 `%USERPROFILE%\pmart-lan\backoffice\` 에 **직접 복사**했다(scp — `assets/*`, `index.html`, `mockServiceWorker.js`). 2026-11-12 23:05쯤.
- **`lan.sh publish-backoffice` 는 쓰지 않았다.** 그 명령은 백엔드 작업 폴더를 다시 render 해 PC 4 파일 전체를 복사하는데, 그때 백엔드 작업 폴더에 진행 중인 변경(employee-auth-service 미커밋)이 있어 백오피스 파일만 올렸다. `deploy/lan/backoffice-dist/` 는 건드리지 않았으므로 **다음에 백엔드가 `deploy pc4` 를 하면 `build/pc4/backoffice` 가 예전 빌드로 덮일 수 있다** — 확인해 달라(필요하면 `web/backoffice/dist` 를 `publish-backoffice` 로 한 번 올려 달라).
- 확인: `http://192.168.0.40/` 이 새 `index.html`(`assets/index-ByMVoB6q.js`)을 주고, 그 JS 의 해시가 로컬 빌드와 같다. 예전 해시 파일은 지우지 않았다.

## 2. 실로그인 확인(헤드리스 Chrome, 계정 `claude-dev`, OPERATOR_ADMIN)

| # | 확인 | 결과 |
|---|---|---|
| 1 | `/login` 은 "직원 계정으로 로그인" 버튼만(비밀번호 칸 없음) | 통과 |
| 2 | 버튼 → Keycloak 로그인 화면(`http://192.168.0.101:8180`) | 통과 |
| 3 | 로그인 → `/auth/callback` → `POST /employee-auth/tokens` **200** → 원래 화면(`/approvals`), 주소창에 ticket 없음 | 통과 |
| 4 | verifier 기록 삭제, 보관은 탭 sessionStorage(`refreshToken`·`deviceId`)만, localStorage 0개 | 통과 |
| 5 | 업무 화면: `GET /approvals?size=50` **200**, 메뉴에 "운영자 계정" 없음 | 통과 |
| 6 | 내 세션: `GET /employee-auth/sessions/current` **200**(세션 ID `ESES-…`, 앱 `backoffice`, 로그인 시각, 토큰 만료 = 로그인 + 15분) | 통과 |
| 7 | **16분 뒤** 업무 화면: `GET /categories/tree` **401** → `POST /employee-auth/tokens/refresh` **200** → 같은 요청 **200**(화면 정상) | 통과 |
| 8 | 새로고침 → refresh 로 복원(**200**), 한 번 더 새로고침(회전된 refresh 로 **200**) | 통과 |
| 9 | 로그아웃 `POST /employee-auth/logouts` **204** → 로그인 화면, 보관 삭제 | 통과 |
| 10 | 로그아웃 뒤 `/approvals` 주소 → 로그인 화면 | 통과 |

- 1~6·8~10 은 첫 실행(23:08), 7 은 16분을 기다린 둘째 실행에서 확인했다. 둘째 실행의 로그아웃 단계는 시험 스크립트가 버튼이 없는 화면에서 눌러 실행되지 않았다(앱 문제 아님) — **그 세션(`claude-dev`, 23:08 시작)은 로그아웃하지 않은 채 남았다**(최대 12시간 뒤 끝남).
- 비밀번호는 `deploy/lan/.secrets/keycloak-claude-dev-password` 를 스크립트가 읽어 Keycloak 화면에 넣었다(출력·저장 안 함).

## 3. 확인하지 못한 것

- 오류 경로의 실서버 동작: 정지·미등록 계정(`?error=`), 60초 지난 티켓, 다른 탭 복제로 `TOKEN_REUSED`. 목 시험으로만 확인했다.
- 역할이 없는 계정의 "권한 승인 대기" 안내(목 시험만).
- `claude-dev` 외 계정(`claude-mfc-wrk` 등).
- 사람 손으로 한 브라우저 확인(헤드리스 Chrome 으로만 했다).

## 4. 다음

- 백엔드: 4단계 진행. 백오피스는 Keycloak 주소를 갖지 않으므로 바꿀 것이 없다. 4단계 뒤 같은 확인 스크립트를 다시 돌려 본다 — 끝나면 알려 달라.
- 클라이언트: 인사팀 백오피스는 hr-service 계약·요청서를 기다린다.
