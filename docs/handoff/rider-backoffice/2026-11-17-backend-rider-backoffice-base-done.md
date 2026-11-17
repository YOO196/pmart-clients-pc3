# [pmart-clients → pmart-backend] 회신: 라이더 백오피스 뼈대·직원 로그인 — 들어간 커밋을 그대로 받음 (2026-11-17)

- 보낸 앱: rider-backoffice (PC 1 클라이언트 세션 — 뼈대·로그인)
- 받는 백엔드 영역: platform (PC 1), 참고 delivery (PC 5 — 메뉴 화면 담당)
- 원 문서: `../pmart-backend/docs/handoff/clients/rider-backoffice/2026-11-17-request-rider-backoffice.md`

## 1. 이미 들어간 커밋(756db67) — 사용자 결정

요청서 8행 "백엔드 세션이 pmart-clients main 에 뼈대를 직접 넣었다 — 되돌릴지 그대로 받을지는 사용자 확인 뒤".

- **사용자 2026-11-17 "그대로 받아"** — `756db67` 을 되돌리지 않는다. PC 1 클라이언트 세션이 검토했고 고칠 곳은 없었다.
- 앞으로는 규칙대로: 이 저장소 코드는 클라이언트 세션이 넣는다(백엔드 세션은 요청서만).

## 2. 검토 결과 (PC 1 클라이언트 세션, main `1adb25a` 기준)

| 요청서 항목 | 결과 |
|---|---|
| §1 로그인 — `app=rider-backoffice`, SSO, 복귀 `/auth/callback`, `X-Source-System rider-backoffice-web` | 맞음. `src/api/employeeAuth.ts`·`sessionPersistence.ts`·`src/app/SessionContext.tsx`·`src/features/session` 은 mfc-backoffice 뼈대와 앱 이름·보관 키·주석만 다르다(파일별로 나란히 비교) |
| §1 주소 — 개발 5176, LAN 게이트웨이 `https://192.168.0.40:8443/api/v1` | 맞음(`vite.config.ts`) |
| §1 볼 수 있는 사람 — `RIDER_OPS`·`OPERATOR_ADMIN`, 센터 고르기 없음, 그 밖 역할은 안내만 | 맞음(`src/app/nav.ts` `hasRiderAppRole`, `App.tsx` `MenuScope` — 막지 않고 안내, 판정은 서버) |
| §2 목 계정 — RIDER_OPS·OPERATOR_ADMIN·그 밖 역할 하나 | 맞음(`OP-rops-1`·`OP-admin-1`·`OP-cs-1`) |
| §2 메뉴 자리 4개(관제·라이더 찾기·배송 찾기·접수 건), 모두 "준비 중" | 맞음(`/control`·`/riders`·`/deliveries`·`/cases`) |
| §2 공통 — ESLint project 목록, `.gitignore`(generated), 앱 문서, `pc-split.md` | 들어 있음. `pc-split.md` §3 의 web-common 줄만 `1adb25a` 로 보탬(`tools/web-tools` 포함 PC 2 그대로) |

- 생성 타입: 뼈대는 `web/core` 의 employee-auth 만 쓴다. `tools/web-tools/gen-api.mjs` 복사 대상에는 아직 이 앱이 없다 — 메뉴 화면을 만들 때 PC 5 가 PC 2(web-common)에 요청해 더한다.

## 3. 시험 결과 (2026-11-17, 이 PC 에서 실행 — 목 모드)

- `npm run typecheck -w web/rider-backoffice` 통과, `npm run lint -w web/rider-backoffice` 통과, `npm run test -w web/rider-backoffice` 11개 통과.
- `npm run build:lan -w web/rider-backoffice` 성공 — 진입 파일 `index-CW6GFx5O.js`(요청서 7·8행의 LAN 8446 빌드 이름과 같다).
- 실서버 로그인(브라우저로 `https://192.168.0.40:8446` 에서 Keycloak 로그인 → 메뉴)은 **이 세션에서 눌러 보지 않았다.**

## 4. LAN 에 올릴 빌드

- 새로 올릴 것 없음 — 뼈대 코드는 `756db67` 그대로이고 그 뒤 커밋(`1adb25a`)은 문서만이다. LAN 8446 의 빌드가 지금 main 과 같다.

## 5. 그 뒤

- 메뉴·업무 화면(관제 포함)은 PC 5. 앱 문서 `docs/apps/rider-backoffice-web.md`, 일지 `docs/worklog/rider-backoffice/`.
- 기본 백오피스의 라이더 운영 화면을 이 앱으로 옮길지는 사용자 결정 전(`../pmart-backend/docs/delivery/rider-backoffice-plan.md`) — 그 전에는 `web/backoffice` 를 그대로 둔다.
