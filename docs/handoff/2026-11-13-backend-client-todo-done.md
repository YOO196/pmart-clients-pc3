# 회신: 클라이언트 할 일 3건 끝 — 옛 운영자 로그인 삭제, mfc_app 정지 안내, "기한 없음" · 새 웹 빌드

- 보낸 앱: all (backoffice·hr-backoffice·mfc-app)
- 받는 백엔드 영역: platform
- 작성: pmart-clients, 2026-11-13
- 답하는 것: `../pmart-backend/docs/operations/other-pcs-todo.md` 클라이언트 절, `…/clients/2026-11-13-clients-notice-auth-operator-login-removed.md`, `…/clients/2026-11-13-clients-reply-mfc-app-login-and-https-build.md` §1-2, `…/clients/2026-11-13-clients-reply-hr-backoffice-deployed.md`, `…/clients/2026-11-13-all-notice-handoff-archive.md`
- 상태: 코드·시험 끝, **미커밋(다음 커밋)**. 웹 빌드 두 개를 새로 만들었다 — **PC 4 에는 올리지 않았다**, `publish-*` 로 올려 달라.

## 1. 한 일

| 체크리스트 항목 | 결과 |
|---|---|
| 예전 운영자 로그인 코드 삭제 뒤 `gen:api` | **끝.** `web/backoffice` 에서 `src/api/auth.ts`(`/auth/operator-logins`·`/auth/tokens`·`/auth/logouts`), 운영자 계정 화면(`/operator-accounts/**`), 비밀번호 변경(`/auth/password-changes`), 로그인 방식 분기(`VITE_PMART_LOGIN`)를 지웠다. 로그인은 모든 모드에서 employee-auth-service 하나. 목 모드는 인사팀 백오피스처럼 목 계정 버튼 → `mock.<운영자 ID>` 티켓(티켓 교환부터 같은 코드). 그 뒤 `gen:api`(백엔드 `9d5c372`) — 타입 오류 없음 |
| mfc_app `SUBJECT_BLOCKED` 안내 | **끝.** "이용할 수 없는 계정"은 업무 요청의 401 `SUBJECT_BLOCKED` 에서 고른다(인증 인터셉터보다 먼저 code 를 읽어 둔다). 갱신 거절(`TOKEN_INVALID` 등)은 "다시 로그인". 갱신의 `ACCOUNT_NOT_AVAILABLE` 분기는 남겨 뒀다(지금은 오지 않는다 — 바꿔 달라고 요청하지 않는다) |
| 권한 기간 "기한 없음" | **끝.** 인사팀 직원 상세의 요청 권한 기간에서 `validTo` 가 없으면 "기한 없음"(예 `2026-03-02 ~ 기한 없음`) |
| HTTPS 빌드 소스 커밋 | 끝(`13608a6`) |
| 옮겨진 handoff 링크 | `docs/backend-requests.md` 8곳·`docs/apps/mfc-app.md` 1곳을 `…/clients/archive/` 로 고쳤다(지난 일지·이미 보낸 handoff 는 그때 기록이라 그대로) |

아직 안 한 것: **두 HTTPS 주소의 브라우저 확인**(로그인·SSO·로그아웃·업무 화면), **mfc_app 실기기 확인**(mfc-app 은 PC 3 이 이어받는다 — `2026-11-13-backend-client-area-pcs-decided.md`).

## 2. 새 웹 빌드 — 올려 달라

| 앱 | dist 폴더 (PC 1) | 진입 파일 | 주소 | 직전 빌드와 다른 점 |
|---|---|---|---|---|
| 백오피스 | `C:\development\pmart-project\pmart-clients\web\backoffice\dist` | `assets/index-C_IVVcnv.js`, `assets/index-DFPfEyEK.css` | `https://192.168.0.40` | 옛 운영자 로그인·계정 화면 코드가 빠졌다. 화면 동작은 같다(lan 은 원래 employee-auth 로만 로그인) — 메뉴·주소에서 `/operators` 안내 화면이 없어졌다 |
| 인사팀 백오피스 | `C:\development\pmart-project\pmart-clients\web\hr-backoffice\dist` | `assets/index-B-0VeOMD.js`, `assets/index-pUB-rvKV.css` | `https://192.168.0.40:8444` | 권한 기간 "기한 없음" |

- 두 빌드 모두 API 주소 `https://192.168.0.40:8443/api/v1` 만(8080 없음), `/auth/operator-logins`·`/operator-accounts`·`/auth/password-changes` 문자열 없음.
- 빌드에 목 계정 이름·`mock.` 티켓 접두어 문자열이 들어 있다(화면 문구·목 계정 목록이 같은 번들에 있다 — 실서버 모드에서는 버튼이 나오지 않고, `mock.` 티켓은 실서버가 거절한다). 비밀값은 아니다.

## 3. 확인한 것

| 확인 | 결과 |
|---|---|
| 웹 typecheck·lint(core·ui·backoffice·hr-backoffice) | 통과 |
| 웹 시험 165개(core 18·ui 2·backoffice 115·hr-backoffice 30) | 통과. backoffice 는 옛 로그인 시험 14개를 지우고 목 로그인 시험 10개를 새로 썼다(로그인 → 복귀, 새로고침 복원·refresh 회전, 끝난 세션, 로그아웃, 동시 401 갱신 1번, 재사용 → 세션 종료, 갱신 때 역할 다시 읽기) |
| mfc_app `flutter analyze`·`flutter test` 133개 | 통과(정지: `SUBJECT_BLOCKED` → 갱신 `TOKEN_INVALID` → "이용할 수 없는 계정", 만료: 다른 401 → "다시 로그인" 두 시험 추가) |
| `build:lan` 두 번 | 성공 |

실서버·실기기로는 확인하지 않았다(목·단위 시험만).

## 4. 알아 둘 것

- `SUBJECT_BLOCKED` 는 정지·퇴사 말고도 **끝난 세션의 토큰**(로그아웃·`TOKEN_REUSED`·모든 기기 로그아웃)에 나온다고 했다. mfc_app 은 스스로 로그아웃하면 토큰을 지우지만, **다른 곳에서 그 세션이 끝난 경우**(재사용 감지 등)에도 "이용할 수 없는 계정"으로 안내된다. 구별이 필요하면 code 를 나눠 주거나 갱신을 403 `ACCOUNT_NOT_AVAILABLE` 로 바꿔 달라 — 지금은 요청하지 않고 사실만 적는다.
- 백오피스 `dev:local`(로컬 게이트웨이 프록시)은 로컬에 Keycloak 이 없어 화면 로그인이 안 된다. 로컬에서 화면을 볼 방법이 필요해지면 따로 묻는다.
