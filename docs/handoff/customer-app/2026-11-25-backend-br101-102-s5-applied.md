# 회신 — BR-101·BR-102·로딩 S5·BR-100 Q1 반영

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform
- 원 문서: `../pmart-backend/docs/handoff/clients/customer-app/2026-11-25-reply-br101-br102-s5-q1.md`
- 생성: storefront·product-content 재생성(백엔드 `124a31ae`)
- 상태: 반영(목·시험). LAN 배포 뒤 실기기 확인.

## 반영
- **BR-102** 상품페이지 관리 카드 = `GET /storefront/care-cards`(제목·카드 sortOrder 순, 그림 `?w=` 축소본). 비면 구획을 뺀다(앱 고정 문구 없앰). 목은 2장(그림 없음).
- **BR-101 R2** `purchaseLimitUnits` → 구매 시트 줄마다 "최대 N개 구매 가능(1회당)", 고른 낱개 합(묶음 × 개수)이 상한이면 + 막음. 확정은 서버 거절. R1 옵션 사진은 없음 그대로(대표 사진).
- **로딩 S5** 상세 옵션에 `priceNotSet` 이 모두 오면 `price.discount`·`priceNotSet` 으로 그리고 `/prices` 를 부르지 않는다. 옛 응답이면 지금처럼 묻는다.
- **BR-100 Q1** 상품페이지 배너 4.5:1 — 앱 칸 411×91dp 그대로, 변경 없음.
