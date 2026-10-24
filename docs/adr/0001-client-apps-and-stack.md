# ADR-0001 클라이언트 앱 구성과 기술 스택

- 상태: 승인 (2026-10-24, 사용자 승인)
- 관련: `docs/architecture/client-architecture.md` §2·§4, 백엔드 `docs/architecture/architecture-design.md` §2

## 배경
- 사용자 지시: 이 계정은 PMart 클라이언트(Flutter 앱 + React SPA)를 담당한다.
- 백엔드 설계의 단말: 고객앱, 라이더앱, 점원앱(PDA), 간선기사앱, 관리자 웹. 백엔드는 1단계(판매 루프)부터 활성화한다.

## 결정
1. Flutter 앱: `customer_app`, `rider_app`, `mfc_app`(점원·PDA·패킹을 역할별 메뉴로 통합). `driver_app` 은 백엔드 2단계에 추가.
2. React SPA: `web/backoffice`(관리자 웹, MFC 관리자 화면 포함).
3. 단일 저장소: Dart pub workspace + npm workspaces. 공유 Dart 패키지 `pmart_api`(생성), `pmart_core`, `pmart_ui`.
4. Flutter 스택: Riverpod, go_router, dio, flutter_secure_storage, openapi-generator `dart-dio`.
5. 웹 스택: Vite + TypeScript, React Router, TanStack Query, openapi-typescript + openapi-fetch, MSW, Vitest, Playwright. 빌드·스타일·UI는 Vite 8 + TypeScript 7 + Tailwind CSS 4 + daisyUI 5 (사용자 확정 2026-10-24, 확정 시점 최신: vite 8.3.5, typescript 7.0.2, tailwindcss 4.3.3, daisyui 5.7.50).
6. 지도(backoffice 실시간 배송 관제): 카카오 지도 JavaScript API. 키는 환경변수로 주입하고 커밋하지 않는다.
7. 범위 밖: 고객 웹, MFC 관리자 전용 웹, TMS 관제 웹(MFC 관리자 화면은 backoffice에 포함). PDA 기종은 나중에 결정하고, 스캐너는 어댑터로 감싼다.
8. 계약 코드 생성물은 커밋하지 않고, 생성 기준 백엔드 커밋을 `contracts.lock` 에 기록.

## 대안
- MFC 앱 분리(PDA앱/패킹앱 별도): 단말·사용자가 같아 배포·로그인이 중복된다. 역할 메뉴로 충분.
- 관리자 웹을 Flutter Web으로: 표·대량 데이터 화면에 React 생태계가 낫고, 사용자 지시가 React SPA.
- 생성물 커밋: 빌드는 쉬워지나 백엔드와 규칙이 다르고 diff 소음이 크다.

## 결과
- 공통 연동 규칙(멱등·불명 결과·Problem)을 Dart와 TS 두 번 구현해야 한다. 규칙 정본은 client-architecture.md §5 하나로 둔다.
