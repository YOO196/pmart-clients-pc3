# PMart Clients

PMart 퀵 커머스의 클라이언트 앱 저장소입니다. Flutter 모바일 앱(고객·라이더·MFC 현장)과 React 백오피스 웹을 한 저장소에서 공통 코드와 함께 관리합니다.
백엔드는 [pmart-backend](https://github.com/code-and-pick/pmart-backend)(Spring Boot 마이크로서비스)이며, API 계약 정본은 [`contracts/openapi/`](https://github.com/code-and-pick/pmart-backend/tree/main/contracts/openapi)입니다. 프로젝트 전체 소개는 조직 페이지 [code-and-pick](https://github.com/code-and-pick)에 있습니다.

## 앱

### 📱 고객 앱
장보기·검색·장바구니·쿠폰·결제(토스페이먼츠)·주문/배송 조회·리뷰·AI 상담 — Flutter(Android)

- 코드: [`apps/customer_app`](apps/customer_app)

<!-- [대표 사진] docs/images/readme/customer-app.png 를 올린 뒤 아래 줄의 주석을 푼다 -->
<!-- <img src="docs/images/readme/customer-app.png" width="260" alt="고객 앱"> -->

### 🛵 라이더 앱
출근·배차 수락·픽업 인계(QR)·길 안내·전달 사진·정산 — Flutter(Android)

- 코드: [`apps/rider_app`](apps/rider_app)
- 시뮬레이터: [pmart-rider-simulation](https://github.com/code-and-pick/pmart-rider-simulation)

<!-- [대표 사진] docs/images/readme/rider-app.png -->
<!-- <img src="docs/images/readme/rider-app.png" width="260" alt="라이더 앱"> -->

### 📦 MFC 앱
MFC 현장 피킹·포장·인계, 입고·적치, 재고 실사 · DC 직원 현장 작업(피킹·분배·검품·상차) — Flutter(PDA)

- 코드: [`apps/mfc_app`](apps/mfc_app)
- 시뮬레이터: [pmart-mfc-simulation](https://github.com/code-and-pick/pmart-mfc-simulation)

<!-- [대표 사진] docs/images/readme/mfc-app.png -->
<!-- <img src="docs/images/readme/mfc-app.png" width="260" alt="MFC 앱"> -->

### 🏭 DC 앱
중앙 물류센터(CDC) 운영 — 입고·적치·보충·출고 작업·재고·품질 — React 백오피스 웹 + 현장 시뮬레이터

- 백오피스 웹: [`web/cdc-backoffice`](web/cdc-backoffice)
- 시뮬레이터: [pmart-cdc-simulation](https://github.com/code-and-pick/pmart-cdc-simulation)

<!-- [대표 사진] docs/images/readme/dc-app.png -->
<!-- <img src="docs/images/readme/dc-app.png" width="640" alt="DC 앱"> -->

### 🖥️ 백오피스 앱 (웹 5종)
본사·센터 운영자용 React 웹 — 한 번 로그인으로 오간다(SSO)

| 웹 | 코드 |
|---|---|
| 통합 백오피스 | [`web/backoffice`](web/backoffice) |
| MFC 백오피스 | [`web/mfc-backoffice`](web/mfc-backoffice) |
| CDC 백오피스 | [`web/cdc-backoffice`](web/cdc-backoffice) |
| 라이더 운영 백오피스 | [`web/rider-backoffice`](web/rider-backoffice) |
| 인사 백오피스 | [`web/hr-backoffice`](web/hr-backoffice) |

<!-- [대표 사진] docs/images/readme/backoffice.png -->
<!-- <img src="docs/images/readme/backoffice.png" width="640" alt="백오피스 앱"> -->

## 공통 코드
| 폴더 | 내용 |
|---|---|
| [`packages/pmart_core`](packages/pmart_core) | Flutter 공통 — HTTP·토큰·멱등 키·오류(Problem Details)·환경 설정 |
| [`packages/pmart_ui`](packages/pmart_ui) | Flutter 공통 UI |
| [`packages/pmart_api`](packages/pmart_api) | 백엔드 OpenAPI 계약에서 만든 API 코드(`contracts.lock` 에 계약 판 기록) |
| [`web/core`](web/core) · [`web/ui`](web/ui) | 웹 공통 — 인증·API·UI |

## 문서
- 작업 규칙: `CLAUDE.md`
- 아키텍처·스택·API 연동: `docs/architecture/client-architecture.md`
- 앱별 화면·규칙: `docs/apps/`
- 단계 계획: `docs/roadmap.md`
- 백엔드 요청 목록: `docs/backend-requests.md`

---

<div align="center">

**동성인재개발교육원** — https://www.dshrd.or.kr/

지도: 서성원 훈련 교사

</div>
