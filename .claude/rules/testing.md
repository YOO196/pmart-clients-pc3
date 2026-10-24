---
paths:
  - "**/test/**"
  - "**/integration_test/**"
  - "web/**/*.test.ts"
  - "web/**/*.test.tsx"
  - "web/**/e2e/**"
---

# 테스트 규칙

## 반드시 테스트할 시나리오 (업무 규칙의 핵심)
- 명령 결과 4값(ACCEPTED/APPLIED/REJECTED/UNKNOWN_RESULT)과 타임아웃 → 짝 조회로 해소, 같은 Idempotency-Key 재사용.
- 결제: 결제창 복귀만으로 완료 화면이 뜨지 않음, `PAYMENT_UNKNOWN` 중 재결제 버튼 없음, 재진입 시 원시도 조회.
- 견적 만료(`RE_QUOTE_REQUIRED`) → 전후 금액 비교·재동의.
- 늦게 도착한 응답(쇼핑 주소·계정 변경 후)이 화면을 덮지 않음.
- 조회 실패가 0·빈 목록으로 표시되지 않음.
- 현장: QR 인계 fence 불명, 부분 인계, 오프라인 큐 재전송(같은 키), `VERSION_CONFLICT` 거절.

## 작성
- Flutter: 단위(`test/`)·위젯 테스트. 목 Repository와 계약 픽스처 사용. 실서버 연동은 `integration_test/`(로컬 백엔드 필요, 기본 실행에서 제외).
- Web: Vitest + Testing Library + MSW. E2E는 Playwright(목 모드 기본).
- 픽스처는 계약 스키마를 따른다. 계약에 없는 필드를 넣지 않는다.

## 보고
- 실행하지 않은 테스트를 통과했다고 보고하지 않는다. 테스트를 삭제·skip해서 통과시키지 않는다.
