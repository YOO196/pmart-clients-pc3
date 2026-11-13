# [pmart-clients → pmart-backend] BR-05 추가 질문: 작업 시작(`POST /tasks/{taskId}/starts`)의 503 처리

- 회신 대상: `pmart-backend/docs/handoff/2026-10-24-clients-reply-high.md` 의 BR-05
- 기준 커밋: pmart-backend `e817184`, `contracts/openapi/mfc-fulfillment-service.yaml`
- 클라이언트 상태: BR-05 를 `AGREED`(`e817184`, 서비스 빌드 미검증)로 기록했다. 목 구현은 현재 계약으로 진행한다.

## 질문 배경
아래 세 곳의 설명이 서로 맞지 않는다.
- `startTask` 설명: "유효 담당은 … 동기 조회로 판정한다. 조회 불가면 503 으로 거절하고 시작하지 않는다."
- 503 응답은 `_common.yaml#/components/responses/DependencyUnavailable` 를 참조하고, 그 설명은 "DEPENDENCY_UNAVAILABLE / UNKNOWN_RESULT (원결과 조회로 해소)"이다.
- `TaskStart.outcome` 은 `STARTED / REJECTED` 뿐이다(`e817184` 에서 `UNKNOWN` 이 빠졌다).

계약만 보면 클라이언트는 503 을 "확실히 시작 안 됨"으로 받아야 하는지, "결과 불명"으로 받아야 하는지 정할 수 없다. 이게 정해져야 `mfc_app` 의 작업 시작 재시도와 화면 표시(재시도 버튼인지 "확인 중"인지)를 확정할 수 있다.

## 질문
1. **503 의 의미**: `POST …/starts` 가 503 이면 항상 "시작하지 않음(확정)"인가? 아니면 `code: UNKNOWN_RESULT` 인 503(점유는 기록됐는데 응답만 실패한 경우 등)도 올 수 있는가? 둘 다 올 수 있다면 Problem 의 `code` 값으로 구분하면 되는가?
2. **짝 조회**: 503 으로 끝난 요청은 `GET /tasks/{taskId}/starts/{requestId}` 로 조회되는가?
   - 조회된다면 어떤 `outcome`·`rejectCode` 로 나오는가?
   - 조회되지 않는다면(404) 클라이언트는 404 를 "서버가 이 키를 받지 못했거나 판정을 남기지 않음 = 시작 안 됨"으로 해석해도 되는가?
3. **같은 키 재전송**: 503 을 받은 뒤 같은 `Idempotency-Key` 로 다시 보내면 담당을 다시 판정하는가? 아니면 처음의 503 결과를 그대로 돌려주는가? 후자라면 새 키로 다시 보내야 하는지도 알려 달라.

## 클라이언트 처리안 (회신 전 목 구현 기준)
- `DEPENDENCY_UNAVAILABLE` 이면 "시작 안 됨"으로 보고, 같은 키로 재시도할 수 있게 한다.
- `UNKNOWN_RESULT` 이거나 응답 자체가 없으면 "확인 중"으로 표시한다. 그 뒤 짝 조회와 `GET /tasks/{taskId}` 의 `activeStart` 로 확정한다. 확정 전에는 피킹 화면으로 넘어가지 않는다.
- 회신 내용이 이와 다르면 회신에 맞춰 바꾼다.
