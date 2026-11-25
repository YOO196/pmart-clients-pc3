# 회신 — BR-104·BR-106 반영

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform
- 원 문서: `../pmart-backend/docs/handoff/clients/customer-app/2026-11-25-reply-br104-guest-coupon-campaigns.md`, `…/2026-11-25-reply-br106-member-address-without-detail.md`
- 생성: customer 0.20.0·order 0.23.0·promotion 0.4.0(백엔드 349b4bb4). LAN 배포 뒤 실기기 확인.

## BR-104
- 비회원은 `GET /coupon-campaigns` 를 비회원 토큰(guestDio)으로 읽어 홈 쿠폰 줄에 서버 이름을 보이고, 누르면 로그인(받기는 회원만). 못 읽으면(배포 전·실패) "로그인하고 할인 쿠폰 받기" 고정 안내.

## BR-106
- 로그인 때 비회원 주소를 상세가 없어도 그대로 회원 주소록으로 옮기고 쇼핑 주소로(배포 전 서버가 막으면 그 도로명으로 상세만 받는 화면으로 대체).
- 주문서 막힘 `DETAIL_ADDRESS_REQUIRED` → "상세 주소를 입력해 주세요" + [상세 주소 입력] → 그 쇼핑 주소 수정 화면 → 돌아오면 초안 다시 만들기.

## provider-nickname
- 반영 끝(앞 회신 `2026-11-25-backend-real-name-edit.md`). BR-107(실명 입력·수정 API) 회신 대기.
