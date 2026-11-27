<div align="center">

<sub>[동성인재개발교육원](https://www.dshrd.or.kr/) · 클라우드 AI기반 마이크로서비스 풀스택(리액트/자바) 개발</sub>

# PMart Clients

**고객 · 라이더 · MFC 현장 앱과 운영 백오피스 웹 — 한 저장소에서**

<img src="https://img.shields.io/badge/Flutter-3.47-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter 3.47">
<img src="https://img.shields.io/badge/Dart-3.13-0175C2?style=flat-square&logo=dart&logoColor=white" alt="Dart 3.13">
<img src="https://img.shields.io/badge/Riverpod-3-00B4AB?style=flat-square" alt="Riverpod 3">
<img src="https://img.shields.io/badge/React-19-20232A?style=flat-square&logo=react&logoColor=61DAFB" alt="React 19">
<img src="https://img.shields.io/badge/TypeScript-7-3178C6?style=flat-square&logo=typescript&logoColor=white" alt="TypeScript 7">
<img src="https://img.shields.io/badge/Vite-8-646CFF?style=flat-square&logo=vite&logoColor=white" alt="Vite 8">
<img src="https://img.shields.io/badge/TanStack_Query-5-FF4154?style=flat-square&logo=reactquery&logoColor=white" alt="TanStack Query 5">
<img src="https://img.shields.io/badge/Tailwind_CSS-4-06B6D4?style=flat-square&logo=tailwindcss&logoColor=white" alt="Tailwind CSS 4">

[서버(pmart-backend)](https://github.com/code-and-pick/pmart-backend) &nbsp;·&nbsp; [API 계약](https://github.com/code-and-pick/pmart-backend/tree/main/contracts/openapi) &nbsp;·&nbsp; [프로젝트 소개(code-and-pick)](https://github.com/code-and-pick)

</div>

<br>

PMart 는 동네 MFC(도심 소형 물류센터)에서 바로 꺼내 배달하는 퀵 커머스입니다. 고객이 주문하면 MFC 작업자가 PDA 로 피킹·포장하고, 라이더가 받아 배달합니다. 이 저장소에는 그 사람들이 손에 쥐는 화면이 모두 있습니다 — Flutter 모바일 앱 3개와 React 백오피스 웹 5개, 그리고 둘이 함께 쓰는 공통 코드.

API 코드는 손으로 쓰지 않습니다. 백엔드의 OpenAPI 계약에서 Dart·TypeScript 클라이언트를 만들어 쓰고, 어느 계약 판으로 만들었는지 `contracts.lock` 에 남깁니다.

## 앱

### 📱 고객 앱
장보기·검색·장바구니·쿠폰·결제(토스페이먼츠)·주문/배송 조회·리뷰·AI 상담 — Flutter(Android)

- 로그인: Google · 카카오 · 네이버
- 주소를 정하면 배달 가능한 MFC 를 찾아 그 센터의 상품·가격·재고로 보여 줍니다
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

- 바코드·QR 스캔으로 위치와 상품을 확인합니다
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

### 🖥️ 백오피스 (웹 5종)
본사·센터 운영자용 React 웹입니다. 한 번 로그인하면 다섯 웹을 오갈 수 있고(SSO), 메뉴는 직원 역할에 따라 달라집니다.

| 웹 | 쓰는 사람 | 코드 |
|---|---|---|
| 통합 백오피스 | 본사 운영자 — 주문·고객·상품·승인·문의·대시보드 | [`web/backoffice`](web/backoffice) |
| MFC 백오피스 | 센터 관리자 — 작업자·배정·작업·입고·재고·품질 | [`web/mfc-backoffice`](web/mfc-backoffice) |
| CDC 백오피스 | DC 관리자 — 출고 관제·이관·작업·재고·실사·발주 | [`web/cdc-backoffice`](web/cdc-backoffice) |
| 라이더 운영 백오피스 | 라이더 운영·지원센터 — 관제·라이더·배송 | [`web/rider-backoffice`](web/rider-backoffice) |
| 인사 백오피스 | 인사팀 — 직원 등록·계정 발급·정지/퇴사 | [`web/hr-backoffice`](web/hr-backoffice) |

<!-- [대표 사진] docs/images/readme/backoffice.png -->
<!-- <img src="docs/images/readme/backoffice.png" width="640" alt="백오피스 앱"> -->

## 공통 코드

| 폴더 | 내용 |
|---|---|
| [`packages/pmart_core`](packages/pmart_core) | Flutter 공통 — HTTP·토큰·멱등 키·오류(Problem Details)·결과 조회·환경 설정 |
| [`packages/pmart_ui`](packages/pmart_ui) | Flutter 공통 UI |
| [`packages/pmart_api`](packages/pmart_api) | 백엔드 OpenAPI 계약에서 만든 Dart API 코드 |
| [`web/core`](web/core) · [`web/ui`](web/ui) | 웹 공통 — 로그인·API·UI |

## 기술 스택

| 분야 | 사용 기술 |
|---|---|
| 모바일 | Flutter 3.47 · Dart 3.13 · Riverpod 3 · go_router · dio · mobile_scanner · Firebase Messaging |
| 웹 | React 19 · TypeScript 7 · Vite 8 · React Router · TanStack Query 5 · Tailwind CSS 4 · openapi-fetch |
| 결제·지도·로그인 | 토스페이먼츠 결제위젯 · 카카오맵 · Google / 카카오 / 네이버 로그인 |
| 시험 | flutter test · Vitest + MSW(목 서버) |

## 시작하기

Flutter 3.47, Node 24 가 필요합니다. clone 한 뒤 API 코드부터 만듭니다(백엔드 저장소를 옆 폴더에 둡니다).

```bash
# Flutter
dart tools/gen_api.dart                 # 계약 → packages/pmart_api (처음 한 번, 몇 분 걸림)
flutter pub get
cd apps/customer_app && flutter run --dart-define=PMART_ENV=mock   # 서버 없이 목 데이터로

# 웹
npm install
npm run gen:api -w web/backoffice       # 계약 → src/api/generated
npm run dev -w web/backoffice           # 목 모드(MSW)
npm run test -w web/backoffice
```

다른 웹도 같은 스크립트를 씁니다 — `-w web/hr-backoffice`, `-w web/mfc-backoffice`, `-w web/rider-backoffice`, `-w web/cdc-backoffice`.

## 저장소 구성

```
apps/         Flutter 앱 — customer_app · rider_app · mfc_app
packages/     Dart 공유 패키지 — pmart_core · pmart_ui · pmart_api
web/          React 웹 — backoffice · mfc · cdc · rider · hr 백오피스, core · ui
tools/        API 코드 생성 · 웹 도구
docs/         아키텍처 · 앱별 화면과 규칙 · 백엔드 요청
```

## 문서

- 아키텍처·스택·API 연동: [`docs/architecture/client-architecture.md`](docs/architecture/client-architecture.md)
- 앱별 화면과 규칙: [`docs/apps/`](docs/apps/)
- 단계 계획: [`docs/roadmap.md`](docs/roadmap.md)
- 백엔드에 보낸 요청: [`docs/backend-requests.md`](docs/backend-requests.md)

## 팀

| 이름 | 맡은 화면 |
|---|---|
| 배희지 | 고객 앱, 로그인·세션 공통 코드 |
| 윤서영 | 라이더 앱, 라이더 백오피스 |
| 이유현 | MFC 앱, MFC 백오피스 |
| 이종근 | 통합·인사 백오피스, 웹 공통 코드 |

서버 담당까지 넣은 전체 팀 구성은 [code-and-pick](https://github.com/code-and-pick#팀) 에 있습니다.

---

<div align="center">

<sub><a href="https://www.dshrd.or.kr/">동성인재개발교육원</a></sub>

</div>
