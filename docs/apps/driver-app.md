# 간선기사앱 (driver_app, Flutter) — 2단계 예약

백엔드 2단계(공급 루프: CDC → TMS → MFC)에서 활성. 그 전에는 만들지 않는다.
근거: `../pmart-backend/docs/business/TMS-business-logic.md`(T), 계약 `transport-execution-service`.

## 범위 (T L60, L337, L510-562, L642, L667)
- 기사 권한: 본인 운행 확인, 도착·출발·인계·사고 증빙 등록만. 다른 운행 변경·MFC 검수·재고 처리 금지.
- 지시서 `GET /trips/{tripId}/instructions`: 최신 버전만 유효, 구버전은 "실행 불가" 표시, 수신·확인 추적.
- 정차 흐름: 도착(`…/stops/{stopId}/arrivals`) → 하차 시작(`…/unloading-starts`) → 화물 스캔·원구성 대조 → 실수량·파손·봉인 → 인계 증빙(`…/handovers`, 사진·봉인·서명) → 출차(`…/stops/{stopId}/departures`). 출발 전 대조 `…/pre-departure-checks`, 실제 출발 `…/departures`, 사건 `…/incidents`, 종료 `…/physical-ends`.
- 정차 상태: `PLANNED / ARRIVED / WAITING / UNLOADING / HANDOVER_PENDING / HANDOVER_RECORDED / DEPARTED`. 도착 버튼·GPS는 수량 인수 증거가 아니다.
- 오프라인: 현장 사실을 원 실행 ID로 내구 저장, 재연결 후 같은 키로 전송. 전송 실패를 미전달로 보고 재인계하지 않음.
- 라이더와 ID·가용성을 공유하지 않는다(별도 앱·역할).

## `[결정 필요]`
기사 로그인(BR-02), 배정 방식(직접 배정 vs 수락)과 응답 기한(T L802), 휴게 한도, 업로드(BR-07).
