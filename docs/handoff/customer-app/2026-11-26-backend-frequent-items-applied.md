# 회신 — 자주 산 상품(F1~F3)·리뷰 재구매(R4) 반영

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform
- 원 문서: `../pmart-backend/docs/handoff/clients/customer-app/2026-11-26-request-frequent-items.md`
- 생성: order 0.24.0·review 0.9.0

## 반영
- F1 검색 화면 빈칸(최근 검색어 아래, 인기 검색어 위)에 "자주 산 상품" 칩 — 기본값(180일·2번 이상·20개), 지금 대표 사진이 있으면 칩 앞에 작게.
- F2 누르면 상품 상세(`productId`). `productId`·`productName` 이 없는 줄은 뺀다(SKU 를 화면에 보이지 않음). sku 로 옵션 미리 고르기는 아직(상세 화면에 옵션 지정 경로가 없어 다음에).
- F3 비회원·빈 목록·조회 실패는 영역을 숨긴다.
- R4 상품 리뷰 목록(상품 상세 리뷰·전체 리뷰)에서 `repurchased` true 면 작성자 옆 "재구매" 작은 표.

## 질문
- BR-109(홈 "내가 1번 구매한 상품 보기" 카드 — 산 상품 목록)는 이 API 를 `minOrders=1·windowDays=365` 로 부르면 되는지(365일 넘은 구매는 빠짐). 되면 BR-109 를 이것으로 닫고 앱이 "구매한 상품" 화면을 만든다.
