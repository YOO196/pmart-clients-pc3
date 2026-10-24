# PMart 클라이언트 아키텍처

문서 버전 0.1 · 2026-10-24 · 상태: **설계안** (코드 미작성)
표기: `[백엔드 확정]` 백엔드 계약·문서가 정한 것 / `[제안]` 이 문서의 선택(사용자 확인 대기) / `[결정 필요]` 팀 결정 대기.

---

## 1. 출발점: 백엔드 현황 (2026-10-23 기준, `../pmart-backend/docs/worklog/2026-10-23.md`)

| 항목 | 상태 | 클라이언트 영향 |
|---|---|---|
| 서비스 | 31개 서비스 + api-gateway **스캐폴딩만**. 업무 엔드포인트는 전부 `501 UNSUPPORTED_ACTION` | 1차 개발은 **계약 기반 목(mock)** 으로 진행. 실서버 연동은 서비스 구현 순서에 맞춘다 |
| 계약 | OpenAPI 3.1 51개(`contracts/openapi`), 상태표 9개(`contracts/states`) | 클라이언트 모델·경로는 계약에서 생성 |
| 게이트웨이 | `:8080`, `/api/v1/**` 라우팅, JWT 검증(auth JWKS), Redis 처리율 제한(429 `RATE_LIMITED` + `Retry-After`), `X-Request-Id` 발급, `/api/v1/internal/**` 차단 | 모든 앱은 게이트웨이만 호출. 429 재시도 처리 필요 |
| 공개 경로 | 14개(`pmart.gateway.public-paths`): 소셜 로그인 3, 토큰 갱신, 비회원 배송지, 검색 3, 전시 4, 토스 웹훅 | 비회원 둘러보기 가능 범위가 이것으로 정해짐 |
| 인증 | auth-service: 서비스 토큰(JWKS)만 구현. 고객 소셜 로그인·refresh 회전은 **계약만**(501). 쿠키/CSRF 방식 `[팀 확인 필요]` | 1차는 Bearer 토큰. 게이트웨이가 `Cookie` 헤더를 제거하므로 쿠키 세션은 현재 불가 |
| CORS | 게이트웨이에 설정 없음 | 웹은 개발 시 Vite 프록시. 운영은 같은 출처 배포 또는 CORS 추가 요청(`backend-requests.md` BR-04) |

## 2. 앱 구성 `[확정 2026-10-24, ADR-0001]`

비즈니스 문서의 단말 목록(architecture-design.md §2: 고객앱 / 라이더앱 / 점원앱(PDA) / 간선기사앱 / 관리자 웹)을 그대로 따른다.

| 앱 | 플랫폼 | 이유 |
|---|---|---|
| customer_app | Flutter iOS/Android | 고객 모바일. 토스 결제·소셜 로그인·푸시 |
| rider_app | Flutter iOS/Android | 카메라(QR·전달 사진)·GPS 백그라운드 위치·외부 지도앱 |
| mfc_app | Flutter Android(PDA) | 바코드 스캐너·라벨 프린터. 점원앱·PDA·패킹앱을 **역할별 메뉴로 한 앱에** 둔다 |
| driver_app | Flutter | 2단계(TMS 활성 시). 라이더와 ID·가용성을 공유하지 않으므로 별도 앱 |
| backoffice | React SPA | 넓은 화면의 표·비교·승인함. 관리자 화면(MFC 관리자 현황 포함) |

고객용 웹·MFC 관리자 전용 웹·TMS 관제 웹은 만들지 않는다(2026-10-24 확정). MFC 관리자 화면은 backoffice 안에 권한·센터 범위로 둔다. 고객 웹은 사업 요구가 생기면 SPA를 추가한다.

## 3. 저장소 구조 `[제안]`

```
pmart-clients/
├── CLAUDE.md, README.md
├── pubspec.yaml                 # Dart pub workspace 루트 (workspace: apps/*, packages/*)
├── package.json                 # npm workspaces 루트 (web/*)
├── contracts.lock               # 코드 생성에 쓴 pmart-backend 커밋 SHA·생성 시각
├── apps/
│   ├── customer_app/  rider_app/  mfc_app/      (driver_app/ 2단계)
├── packages/
│   ├── pmart_api/gen/<service>/ # OpenAPI 생성 Dart 클라이언트, 서비스마다 패키지 하나 (pmart_api_<service>, .gitignore). C0 확정
│   ├── pmart_core/              # 아래 §5 공통 연동 계층
│   └── pmart_ui/                # 테마·공통 위젯·UiState 표시·금액/시각 포맷
├── web/
│   └── backoffice/              # Vite + React + TS
├── tools/
│   ├── gen_api.dart             # 계약 → Dart 생성
│   └── (web) openapi-typescript 스크립트는 web/backoffice/package.json
└── docs/
```

앱 내부 구조(Flutter):
```
lib/
├── main.dart, app.dart          # 환경(PMART_ENV) 선택, ProviderScope, 라우터
├── features/<feature>/
│   ├── data/                    # Repository 구현 (api | mock)
│   ├── domain/                  # 화면용 모델·상태 (생성 DTO를 그대로 UI에 노출하지 않음)
│   └── presentation/            # 화면·위젯·컨트롤러
└── shared/
```

## 4. 기술 스택 `[확정 2026-10-24, ADR-0001]` (버전은 스캐폴딩 시점에 pub.dev / npm 최신 안정판을 확인해 고정)

### Flutter
| 영역 | 선택 | 비고 |
|---|---|---|
| SDK | Flutter 3.47.5 / Dart 3.13.4 (이 PC 설치본) | `environment.sdk` 고정 |
| 모노레포 | Dart pub workspace | 별도 도구(melos)는 필요해질 때 |
| 상태관리 | Riverpod | 앱 전체 하나만 |
| 라우팅 | go_router | 딥링크(알림 → 화면), 로그인 리다이렉트 |
| HTTP | dio | 인터셉터: 인증·헤더·Problem·429·재시도 |
| API 생성 | openapi-generator `dart-dio` (Java 21 있음) | 생성 결과가 3.1 스펙에서 부족하면 수기 DTO로 대체 검토 |
| 보안 저장 | flutter_secure_storage | refresh token·기기 ID |
| 스캔 | mobile_scanner(카메라) / PDA 하드웨어 스캐너는 키보드 웨지·브로드캐스트 인텐트 어댑터 | 단말 기종 `[결정 필요]` — 나중에 결정. 기종 확정 전에는 카메라·키보드 웨지 어댑터로 개발 |
| 위치 | 백그라운드 위치 플러그인 | 전송 주기 `[결정 필요]` |
| 결제 | 토스페이먼츠 결제 SDK(주문서형) | 진입 정보 API 부재 → BR-01 |
| 소셜 로그인 | 카카오·네이버·애플·구글 SDK | 앱 키 발급 `[결정 필요]` |
| 푸시 | FCM/APNs | notification-service 채널 `[결정 필요]` |

### React (backoffice)
| 영역 | 선택 |
|---|---|
| 빌드 | Vite 8 (`vite@^8.3.5`, `@vitejs/plugin-react@^6.1.2`, Node ^20.19 \|\| >=22.12) + TypeScript 7 (`typescript@^7.0.2`, strict). 호환 주의(2026-10-24 npm 기준): `openapi-typescript@7.13.0` 은 peer `typescript ^5.x`, `typescript-eslint@8.72.0` 은 peer `<6.1.0` 이라 TS 7을 아직 지원하지 않음 — C0에서 실제 설치·동작으로 확인하고 대응을 정한다 |
| 라우팅 | React Router |
| 서버 상태 | TanStack Query |
| API 타입 | openapi-typescript + openapi-fetch (계약 → 타입, 런타임 경량) |
| 목 | MSW (계약 예시·픽스처 기반) |
| 스타일 | Tailwind CSS 4 (`tailwindcss@^4.3.3` + `@tailwindcss/vite@^4.3.3`, CSS 우선 설정: `@import "tailwindcss";`, `tailwind.config.js`·PostCSS 없음) |
| UI 컴포넌트 | daisyUI 5 (`daisyui@^5.7.50`, CSS 플러그인: `@plugin "daisyui";`). 데이터 그리드는 없어 표는 daisyUI `table` 클래스로 시작하고, 정렬·가상 스크롤이 필요해지면 헤드리스 표 라이브러리 추가를 따로 결정 |
| 지도 | 카카오 지도 JavaScript API(`dapi.kakao.com` SDK 스크립트 로드, 실시간 배송 관제 #6). 근거: 백엔드 `Delivery-business-logic.md` L103 "React 화면 + 카카오 지도 API". React 래퍼 라이브러리는 쓰지 않고 `src/shared/map` 어댑터로 감싼다(래퍼 추가는 별도 결정). JavaScript 키는 `VITE_KAKAO_MAP_KEY` 환경변수로 주입하고 저장소에 넣지 않는다. 앱 키 발급·허용 도메인 등록 `[결정 필요]` |
| 테스트 | Vitest + Testing Library, E2E Playwright |

## 5. 공통 연동 계층 (`pmart_core` / `web/backoffice/src/api`)

백엔드 공통 규약(`contracts/README.md` §1, `_common.yaml`)을 한 곳에서 구현하고 화면 코드는 이것만 쓴다.

### 5.1 요청 헤더
| 헤더 | 규칙 |
|---|---|
| `Authorization: Bearer` | 공개 경로 외 전부 |
| `Idempotency-Key` | **모든 변경 요청 필수.** 사용자 행위 1회 = 키 1개. 재전송·재시도는 같은 키. 새 클릭은 새 키 |
| `X-Source-System` | `customer-app` / `rider-app` / `mfc-app` / `backoffice-web` (값 확정은 BR-08) |
| `X-Expected-Version` | 상태 변경 시 화면이 본 aggregate `version` |
| `X-Device-Id` | 고객 앱: 소셜 로그인·비회원 장바구니/배송지. 설치 시 생성해 보안 저장소에 보관 |
| `traceparent` | 게이트웨이가 발급하므로 클라이언트는 보내지 않는다. 응답의 `X-Request-Id`·Problem `traceId` 를 오류 화면·로그에 표시 |

### 5.2 응답 해석
- **`CommandResponse.status`**: `ACCEPTED`(접수만) / `APPLIED`(반영) / `REJECTED` / `UNKNOWN_RESULT`. `nextAction`(`QUERY_RESULT`, `RE_QUOTE`, `WAIT_FENCE` …)을 따른다.
- **오류는 RFC 9457 Problem** (`application/problem+json`): `code` 로 분기한다(`title`/`detail` 문자열로 분기 금지). `retryable` 이 true일 때만 자동 재시도.
- 공통 코드별 기본 처리:

| code | 처리 |
|---|---|
| `VALIDATION_FAILED` | `details[]` 를 필드 오류로 표시 |
| `FORBIDDEN` | `UI_FORBIDDEN`. 사유 코드(NO_ROLE, OUT_OF_CENTER_SCOPE …)가 있으면 표시 |
| `VERSION_CONFLICT` | 최신 재조회 후 사용자에게 변경 내용 확인 |
| `IDEMPOTENCY_CONFLICT` | 클라이언트 결함. 오류 보고(같은 키에 다른 본문) |
| `INVALID_STATE` | 최신 상태 재조회, 가능한 행동만 노출 |
| `CONFIG_REQUIRED` | "설정 대기 중" 안내. 0/무제한으로 대체 금지 |
| `UNKNOWN_RESULT`, `DEPENDENCY_UNAVAILABLE`, 타임아웃 | `UI_RESULT_UNKNOWN` → 짝 조회 폴링(§5.3). **실패로 확정하지 않음** |
| `RATE_LIMITED`(429) | `Retry-After` 만큼 대기 후 같은 키로 재시도 |

### 5.3 결과 불명 해소 (`ResultResolver`)
1. 변경 요청이 타임아웃·5xx·`UNKNOWN_RESULT` → 같은 `Idempotency-Key` 로 계약의 짝 조회(`GET …/requests/{requestId}`, `…/change-requests/{requestId}` 등)를 호출한다.
2. 조회도 불명이면 화면은 "확인 중"을 유지하고 사용자가 같은 행위를 다시 실행하지 못하게 한다(결제·취소·인계·실적).
3. 백엔드가 서버 측 재조회 일정(1분×5→상신→15분)을 운영하므로 **앱이 같은 일정을 흉내 내지 않는다.** 앱은 화면이 열려 있는 동안 짧은 간격 폴링 + 재진입 시 재조회만 한다.
4. 앱 재시작에 대비해 진행 중인 명령(`requestId`, 대상, 시각)을 로컬에 저장하고, 시작 시 원결과를 조회한다.

### 5.4 화면 상태 (모든 앱 공통, Commerce D.6)
`UI_LOADING / UI_READY / UI_EMPTY(정상 조회 0건만) / UI_PARTIAL / UI_ERROR / UI_FORBIDDEN / UI_RESULT_UNKNOWN`.
- 늦게 온 응답은 요청 당시 컨텍스트(계정·쇼핑 주소·MFC·버전)가 현재와 다르면 버린다.
- 조회 사본(`AsOf.freshness` = `CURRENT/STALE/UNAVAILABLE`)은 신선도를 함께 표시한다.

### 5.5 시간·금액
- API 시각은 UTC ISO-8601. 표시는 Asia/Seoul. 기한 판정은 서버 값만 사용(기기 시각으로 판정 금지).
- 금액은 정수 KRW. 클라이언트에서 합산·환불액을 계산해 확정 표시하지 않는다(견적·환불은 서버 응답 그대로).

### 5.6 인증
- 고객: 소셜 SDK → `POST /auth/social-logins`(`provider`, `providerToken`, `purpose`) → `state` 별 분기(`AUTH_MEMBER` 토큰 수령 / `AUTH_CONSENT` 동의 후 `completions` / `AUTH_UNKNOWN` 원인증 조회 / 423 `AUTH_RESTRICTED` 대기 시간 표시).
- 토큰 갱신 `POST /auth/tokens`(refresh 회전, 재사용 감지 시 세션 폐기 → 로그인 화면). 동시 401에 갱신은 1회만(single-flight).
- 세션·역할 `GET /auth/sessions/current` 의 `principalType`·`roles`·`centerScope` 로 메뉴를 구성하되, **버튼 숨김은 권한 보장이 아니다**(서버가 행위마다 재검사).
- 라이더·점원·운영자 로그인 API는 계약에 없다 → BR-02. 그 전까지는 목 로그인.
- 웹(backoffice) 토큰 보관: 쿠키/CSRF 결정 전까지 access token은 메모리, refresh 처리 방식은 BR-03 결정 후 확정.

### 5.7 실시간
- 배송 ETA·진행: `GET /deliveries/{id}/stream`(SSE). 브라우저 `EventSource` 는 헤더를 못 붙이므로 웹은 fetch 기반 SSE, Flutter는 스트리밍 HTTP. 끊기면 `GET /deliveries/{id}/eta` 로 대체.
- 서버 확정 상태만 표시하고, 위치 단절은 "위치 확인 중"으로 표시(배송 실패 아님).

### 5.8 오프라인·현장 단말 (rider/mfc/driver)
- 현장 사실(스캔·실적·사진)은 **원 실행 ID(Idempotency-Key)와 함께 내구 저장** 후 전송한다. 재연결 시 같은 키로 재전송.
- 로컬 임시 저장 상태를 "완료"로 표시하지 않는다("전송 대기"/"확정 대기"로 구분).
- 옛 배정 버전으로 보낸 실적은 서버가 `VERSION_CONFLICT` 로 거절 → 대사 화면으로.
- 권한 캐시 신선도를 확인할 수 없으면 오프라인에서 허용을 추정하지 않는다.

## 6. 환경
| `PMART_ENV` | API | 용도 |
|---|---|---|
| `mock` | 앱 내 목 Repository(Flutter) / MSW(웹) | 백엔드 미구현 기간의 기본 |
| `local` | `http://localhost:8080/api/v1` (Android 에뮬레이터는 `10.0.2.2`) | 백엔드 `deploy/local` + 서비스 로컬 기동 |
| `dev`/`prod` | `[결정 필요]` | 배포 환경 미정 |

목은 **계약 스키마를 따르는 픽스처**로만 만든다. 계약에 없는 필드는 목에도 넣지 않는다(필요하면 BR 등록 후 `// BR-xx` 표시).

## 7. 계약 동기화
1. `../pmart-backend` 의 현재 커밋 SHA를 `contracts.lock` 에 기록하고 생성한다(Dart: `tools/gen_api.dart`, TS: `npm run gen:api -w web/backoffice`).
2. 생성물 diff로 바뀐 엔드포인트·스키마를 확인하고 영향 화면을 worklog에 적는다.
3. 백엔드 계약이 바뀌었는데 클라이언트가 아직 따라가지 못했으면 `contracts.lock` 이 그 사실을 드러낸다.

## 8. 품질
- Flutter: `flutter analyze`(lints 엄격), 단위·위젯 테스트, 골든은 디자인 확정 후.
- Web: `tsc --noEmit`, ESLint, Vitest, Playwright(핵심 흐름).
- CI는 백엔드와 같은 Jenkins를 쓸지 `[결정 필요]`.
