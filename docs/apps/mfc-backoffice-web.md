# MFC 백오피스 웹 (`web/mfc-backoffice`)

- 사용자: 센터 관리자(`MFC_SUPERVISOR`) — 자기 센터(`centers`)만. 현장 작업자(`MFC_WORKER`)는 PDA 앱(`apps/mfc_app`)을 쓴다.
- 근거: 백엔드 요청 `../pmart-backend/docs/handoff/clients/mfc-backoffice/2026-11-15-request-mfc-backoffice.md`. 메뉴·API 정본은 `pmart-backend/docs/architecture/backoffice-role-menus.md` §3, 계약 `contracts/openapi/mfc-*.yaml`.
- 기본 백오피스(`web/backoffice`)에는 MFC 메뉴를 넣지 않는다(백엔드 요청 2026-11-15 cs-rider-menus §0).
- 상태(2026-11-15): **기반만**(앱 뼈대·로그인·센터 고르기·메뉴 자리). 메뉴 화면은 모두 "준비 중". 목 모드로 확인, LAN 배포·실서버 확인은 아직.

## 1. 앱과 로그인

| 항목 | 값 |
|---|---|
| 스택 | 다른 두 백오피스와 같다(Vite + TS 7, React Router, TanStack Query, openapi-fetch, MSW, daisyUI) |
| 로그인 | employee-auth-service, `app=mfc-backoffice`, SSO — `@pmart/web-core` 직원 로그인(세션별 HttpOnly refresh 쿠키·CSRF, 탭이 다시 보일 때 세션 확인). 비밀번호는 받지 않는다 |
| 주소 | 개발 `http://localhost:5175`(`npm run dev -w web/mfc-backoffice`), LAN `https://192.168.0.40:8445`(빌드 `npm run build:lan -w web/mfc-backoffice` → PC 1 백엔드가 `lan.sh publish-mfc-backoffice <dist>`) |
| `X-Source-System` | `mfc-backoffice-web` |
| 생성 타입 | `src/api/generated/`(커밋 안 함): center-master, mfc-capacity·fulfillment·inbound·inventory·location·quality — `npm run gen:api -w web/mfc-backoffice`(백오피스 생성물에서 복사) |

## 2. 센터
- 고를 수 있는 센터 = `GET /employee-auth/sessions/current` 응답의 `centers`(employee-auth 0.6.0, 2026-11-16 — 토큰을 풀지 않는다. 승인·회수 직후 토큰과 다르면 응답을 따른다).
- 주소에 센터를 넣는다: `/c/<mfcId>/<메뉴>`. 첫 화면은 맡은 첫 센터의 첫 메뉴(작업자).
- 센터가 하나면 고르지 않고 이름만 보인다. 둘 이상이면 위에서 고르고, 바꾸면 같은 메뉴의 다른 센터로 간다.
- 이름은 center-master `GET /centers?type=MFC` 에서 붙인다(전체 센터 — 세션 centers 와 겹치는 것만). 못 불러오면 센터 코드로만 보이고 안내한다(센터 목록은 비지 않는다).
- 주소의 센터가 세션 centers 에 없으면 "이 센터 권한이 없습니다" + 맡은 센터 링크. 맡은 센터가 없으면(예: 센터 없는 `OPERATOR_ADMIN`) 안내만, 메뉴 없음.

## 3. 역할
- `MFC_WORKER` 만 있는 계정: "센터 관리자만 쓰는 화면입니다"(메뉴 없음).
- `MFC_SUPERVISOR` 가 없는 그 밖 역할 + 센터: 막지 않고 안내만. 판정은 서버가 API 마다(403 → "이 센터 권한이 없습니다"). mfc API 는 `OPERATOR_ADMIN` 을 따로 통과시키지 않는다(백엔드 §2-1).

## 4. 메뉴 (`src/app/nav.ts`)

| 묶음 | 메뉴 | 경로 | 화면 | 서버 API 가 아직 없는 것(백엔드 §2-1) |
|---|---|---|---|---|
| 인력 | 작업자 | `workers` | 준비 중 | — |
|  | 배정 | `assignments` | 준비 중 | 배정 추천 계획 목록 |
| 작업 | 작업 현황 | `tasks` | 준비 중 | 확인 필요 포장 목록·확인(지금은 작업자만 — 백엔드 결정 대기) |
|  | 이동·보충 | `moves` | 준비 중 | — |
|  | 입고 | `inbound` | 준비 중 | 입고 예정(TRF, 계약만), 초기 보유 센터별 수령 대기 목록, 회수품·공급 요청 목록 |
| 재고·품질 | 재고 | `inventory` | 준비 중 | 센터 전체 재고 목록(상품 코드 없이), 실사 세션 목록 |
|  | 품질 | `quality` | 준비 중 | 해제 승인 대기·폐기·검수 목록, 품질 사고(계약만) |
| 센터 | 위치(칸) | `locations` | 준비 중 | — |
|  | 운영 제한 | `restrictions` | 준비 중 | — |

- "준비 중" 화면은 그 메뉴에서 서버 API 가 있는 기능과 없는 기능을 나눠 보인다. 화면을 만들면 `nav.ts` 의 `ready` 를 true 로 바꾸고 이 표를 고친다.
- 기존 화면 요청서는 그대로 쓴다: 입고 B1~B4, 피킹·포장, 근무 기본값·배정 계획(백엔드 handoff `archive/2026-11-07-clients-request-mfc-*`, `backoffice/2026-11-09-clients-notice-*`).

## 5. 목 모드
- 목 계정: 센터 관리자(MFC 1곳 `MFC-BSN-01`), 센터 관리자(MFC 2곳 `MFC-BSN-01`·`MFC-SEL-01`), 현장 작업자, 운영 관리자(센터 없음). `src/mocks/db.ts`.
- 목 핸들러는 지금 로그인(employee-auth)과 `GET /centers` 만 있다. 메뉴 화면을 만들 때 그 계약의 목을 더한다.
