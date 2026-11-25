# 요청 — 게이트웨이: CORS 에 Last-Event-ID, 재고 이력 경로 열기

보낸 앱: mfc-backoffice (PC 3)
받는 백엔드 영역: platform (api-gateway — PC 1 pmart-config·LAN 배포)
날짜: 2026-11-25
상태: 요청

## 1. CORS 허용 헤더에 `Last-Event-ID`
- 재고 실시간(mfc-inventory 0.46.0 `GET /stock-stream`, SSE)은 끊겼다 다시 붙을 때 `Last-Event-ID` 로 이어 받는다(보관 1시간).
- LAN 화면(:8445)은 게이트웨이(:8443)와 출처가 달라 사전 요청(preflight)을 거치는데, 게이트웨이 CORS 허용 헤더에 `Last-Event-ID` 가 없어(2026-11-24 확인) 보내면 막힌다.
  그래서 화면은 지금 같은 출처일 때만 보내고, LAN 에서는 다시 붙을 때마다 `ready(resumed false)` → **재고 조회를 전부 다시 읽는다**(서버 30분마다 닫음·네트워크 끊김마다).
- 바라는 것: 게이트웨이 CORS `allowedHeaders` 에 `Last-Event-ID` 추가. 화면은 넣어 주시면 같은 출처 조건을 풀어 늘 보낸다(`web/mfc-backoffice/src/features/stock-stream/useStockStream.tsx` `resume`).

## 2. 재고 이력 경로
- mfc-inventory 0.48.0 `GET /api/v1/mfcs/{mfcId}/stock-ledger`(백엔드 #470, #465 위) — 병합·배포 때 게이트웨이 라우트·허용 목록에 넣어 주세요(MFC 백엔드 세션 말 "PC1 게이트웨이 경로 추가 뒤").
- 화면: 재고 이력 탭 clients #537, LOT 추적 탭(같은 경로를 `lotId` 로). 둘 다 이 경로가 열려야 실서버에서 확인할 수 있다.
- 같은 때 열려 있는지 확인 부탁: `GET /api/v1/mfcs/{mfcId}/lot-resolutions`(0.21.0) — LOT 추적이 LOT 번호로 LOT 을 찾을 때 쓴다.
