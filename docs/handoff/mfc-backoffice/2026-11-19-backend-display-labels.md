# MFC 백오피스 — 포장·출고 화면 번호 요청(ADR-0070 덧붙임 2026-11-19)

보낸 앱: mfc-backoffice (PC 3)
받는 백엔드 영역: mfc (mfc-fulfillment-service), platform (backoffice-bff)
날짜: 2026-11-19

ADR-0070 덧붙임(2026-11-19)에 따라 MFC 백오피스 목록에서 시스템 ID 를 뺐다(`docs/apps/mfc-backoffice-web.md` §4-12).
포장(HOV-) 화면 표기는 "포장 라벨 6자리"(`handoverCode`)인데, 아래 두 응답에는 그 값과 주문번호가 없어 목록에서 포장을 알아볼 표기가 없다.
지금은 포장대 위치와 "포장 1·2"(출고 안 순서)로 보이고, 포장·주문 시스템 ID 는 상세의 시스템 번호 칸에만 둔다. 조회만이다.

## DL-1. 인계 판정 `GET /packages?mfcId=&checkRequired=true`·`GET /packages/{id}/handover-resolution` (mfc-fulfillment)
- 더할 것: `handoverCode`(포장 라벨 6자리), `orderNumber`(주문 화면 번호 8자리).
- 쓰는 곳: 홈 예외 처리함 "인계 확인 필요" 줄, 작업 현황 "확인 필요 포장" 칸.

## DL-2. 포장 인계 현황 `GET /views/packing-handover` 의 `items[].packages[]` (backoffice-bff)
- 더할 것: `handoverCode`(포장 라벨 6자리). 출고의 `orderNumber` 는 이미 있다.
- 쓰는 곳: 포장 인계 현황 표의 포장 줄.

## 회신 받으면
- 목록 표기를 "305118 인계"처럼 라벨 번호로 바꾸고, 값이 null 이면 지금처럼 "포장 n".
