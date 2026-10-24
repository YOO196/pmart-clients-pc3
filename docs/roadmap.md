# 클라이언트 단계 계획 `[제안]`

백엔드 단계(architecture-design.md §8)에 맞춘다. 백엔드는 2026-10-23 현재 스캐폴딩만(전 엔드포인트 501)이므로 **C0~C2는 목 모드로 진행**하고, 서비스가 구현되는 순서대로 `local` 연동으로 바꾼다.

| 단계 | 목표 | 산출물 | 완료 기준 |
|---|---|---|---|
| **C0 기반** | 저장소·도구·공통 계층 | git 저장소, pub workspace + npm workspace, `contracts.lock`, `gen_api`(Dart/TS), `pmart_core`(헤더·Idempotency·Problem·CommandResponse·ResultResolver·토큰 갱신·429), `pmart_ui`(테마·UiState 7종), 4개 앱 빈 셸(`PMART_ENV` 전환), 웹 MSW | `flutter analyze`·`flutter test`·`tsc`·`vitest` 통과, 목 모드로 각 앱 기동 |
| **C1 고객 판매 루프 (목)** | 둘러보기 → 장바구니 → 주문서 → 결제 → 주문 상세·추적 → 취소 | customer_app: 로그인·주소·홈·검색·상품·장바구니·슬롯·주문서·결제(BR-01 전까지 목)·주문·추적·취소 | 결제 불명·재진입·가격 재견적·부분 품절 시나리오 위젯 테스트 |
| **C2 현장 루프 (목)** | 피킹 → 패킹 → 배차 요청 → 라이더 수락 → QR 인계 → 전달 완료 | mfc_app 피킹·패킹·배차요청, rider_app 운행·제안·수행·인계·전달·도움요청 | 인계 fence 불명·부분 인계·오프라인 재전송 테스트 |
| **C3 관리자 1차** | 운영 관제·승인·사건·CS | backoffice: 내 할 일, 통합 조회, 승인함, 사건함, 실시간 배송·포장 인계, 클레임 심사, MFC 관리자 | ComposedView 신선도·UNKNOWN_RESULT 처리 테스트 |
| **C4 실서버 연동** | 백엔드 구현분부터 `local` 연동 | 서비스별 연동 체크리스트, 계약 diff 반영 | 실제 게이트웨이 경유 E2E(로컬) |
| **C5 공급 루프 (백엔드 2단계)** | 입고·적치·공급 요청, 간선기사앱, SCM/TMS 관제 | mfc_app 입고, driver_app, backoffice 공급·간선 관제 | — |
| **C6 확장 (백엔드 3단계)** | 쿠폰·프로모션, 리뷰 사진, AI 등 | — | — |

## 선행 결정 (사용자)
1. ~~앱 구성(Flutter 3 + React 1, MFC 앱 통합) 승인 — ADR-0001~~ 승인 2026-10-24
2. ~~스택 승인(Riverpod·go_router·dio / Vite 8·Tailwind 4·daisyUI 5·React Router·TanStack Query·openapi-fetch·MSW·카카오 지도) — ADR-0001~~ 승인 2026-10-24
3. ~~`pmart-clients` git 저장소 초기화~~ 완료(사용자). 원격 저장소는 미정
4. `backend-requests.md` 의 높음 항목(BR-01, 02, 03, 05, 06, 07)을 백엔드 담당에 전달
