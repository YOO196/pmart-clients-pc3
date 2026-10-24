# 관리자 웹 (web/backoffice, React SPA)

근거: `../pmart-backend/docs/business/BackOffice-business-logic.md`(BO, v2.0 **제안**, BO-01~BO-28), ADR-0004, 계약 `backoffice-bff`(base `/api/v1/backoffice`), `approval-service`, `case-service`, `center-master-service`, `audit-service`, `auth-service`.
BO §7(≈L1492-1510)의 화면은 "업무 동선 제안"이다. 화면을 BO 번호마다 하나씩 만들지 않고 동선별로 묶는다.

## 1. 원칙 (모든 화면)
- **BackOffice는 거래 정본을 소유하지 않는다.** 화면은 원천 상태를 그대로 보여주고, 변경은 명령을 요청할 뿐이다.
- 금지 기능(BO §1.2 L92-101): 주문 상태 직접 변경, 재고 덮어쓰기, 강제 성공, 근거 없는 검증 생략, 임의 ADJ, 승인 없는 주소 변경·할인·보상, 재고/PG/배송완료 CSV 덮어쓰기. **버튼 자체를 만들지 않는다**(서버는 422 `UNSUPPORTED_ACTION`).
- 원천별 기준시각·신선도: `ComposedView{sources[], unavailableSources[], composedAt}`, `SourceStamp` 확인 등급 `DIRECT/COPY/UNKNOWN`, `AsOf.freshness` `CURRENT/STALE/UNAVAILABLE`. 값이 없으면 "미제공".
- 조회 실패·합산으로 숫자를 만들지 않음. 기준시각이 다른 `StampedQty` 끼리 합산 금지. 비율은 분자/분모 함께, 분모 0이면 N/A.
- 명령: bff `POST /commands/{targetService}/{command}`(본문 `{targetRef, reason, payload}`) → `CommandResponse`. ACCEPTED는 접수일 뿐. `UNKNOWN_RESULT` 는 `GET /commands/{targetService}/{command}/{requestId}` 로만 해소.
- 행위마다 권한 재검사(로그인·목록·상세·증빙 다운로드·개인정보 열람·제출·승인·실행·재처리·내보내기). 버튼 숨김은 편의일 뿐. 자기승인은 서버가 `FORBIDDEN`.
- 개인정보는 목록 기본 마스킹, 원문 열람은 목적·사건·사유 입력 후(BO-25). 다운로드는 받는 시점에 현재 권한 재검사.
- 승인 5축(요청/심사/실행/전달/사건)을 한 상태로 합치지 않는다. 문구: 심사 완료 / 실행 완료 / 전달 완료 / 이관 완료 / 사건 해결(BO §13.3). 일부 반영은 "승인됨/일부 적용".
- 미설정 값은 "미설정/보류"로 표시(0·무제한·자동승인으로 대체 금지). 화면 잠금 ≠ 원장 잠금. 사건은 시간 경과로 자동 종결되지 않음.

## 2. 동선별 화면 (1차 우선순위 순)

| # | 동선 | BO | API | 1차 |
|---|---|---|---|---|
| 1 | 로그인·내 할 일 | BO-28 | 로그인 없음(BR-02), `GET /auth/sessions/current`, bff `/views/metrics`, `/views/case-inbox`, `/views/approval-inbox` | ✔ |
| 2 | 통합 조회·CS 접수 | BO-11 | bff `/views/unified-lookup`(q, kind), case `POST /cs-intakes` | ✔ |
| 3 | 통합 승인함·상세·결정 | BO-10 | bff `/views/approval-inbox`, approval `/approvals/{id}`, `/decisions`(APPROVE/PARTIALLY_APPROVE/REJECT/REQUEST_EVIDENCE), `/re-reviews`, `/receipts` | ✔ |
| 4 | 변경 요청 작성(상품·가격·전시·권역·센터) | BO-03~07 | approval `POST /change-requests`, `/submissions`, `/withdrawals`; 원천 조회 product/pricing/product-content/center-master | ✔ |
| 5 | 사건함·의무 | BO-22, 23, 27 | bff `/views/case-inbox`, case `/cases*`, `/obligations*`, `/action-requests`, `/shift-handovers` | ✔ |
| 6 | 실시간 배송·포장 인계 관제 | BO-20 | bff `/views/live-delivery`(mfcId), `/views/packing-handover`(mfcId), case `/help-requests` | ✔ |
| 7 | 취소·환불·반품 심사 | BO-12~14 | claim `/claims*`, `POST /claims/{id}/decisions`(운영자) | ✔ |
| 8 | MFC 관리자(작업 배정·운영 제한) | M WK-02/09/10, BO-08 | mfc-capacity `/assignment-plans`, `/operation-restrictions` | ✔ |
| 9 | 품질·재고 조정·손실 | BO-15~17 | approval 유형별 + mfc-quality | 일부 |
| 10 | 센터 기준정보·캘린더 | BO-06 | center-master `/centers*` | ✔(조회) |
| 11 | 정책 참조 | BO-09 | approval `/policy-references` | ✔(조회) |
| 12 | 권한·대행·긴급 | BO-01/02 | 사용자용 조회 없음(BR-10) | 대기 |
| 13 | 감사·개인정보 접근 | BO-25 | audit `/audit-entries*` | ✔ |
| 14 | 대량 변경 | BO-26 | approval `/batch-changes*` (업로드 → 미리보기 → 승인 → 행별 결과) | 2차 |
| 15 | SCM 공급·간선 관제 | BO-18/19 | bff `/views/replenishment-status`, `/views/trip-control` | 2단계 |
| 16 | 수행료·운송비 이의 | BO-21 | 없음 | 미정 |

역할 표: BO §3.1(L126-141). 담당 그룹: CS / MFC_OPS / DELIVERY_OPS / SCM / FINANCE / QUALITY / SECURITY.
권한 거절 사유(auth): NO_ROLE, OUT_OF_CENTER_SCOPE, DELEGATION_EXPIRED, DELEGATION_SCOPE_EXCEEDED, NOT_OWNER, SELF_APPROVAL, PRINCIPAL_RESTRICTED, SESSION_INVALID — 사용자 문구로 매핑.

## 3. 기술 메모
- 개발: Vite 프록시 `/api → http://localhost:8080` (CORS 없음, BR-04). 목은 MSW.
- 모든 목록은 커서 페이지(`size`, `cursor`). 표·필터 상태는 URL 쿼리에 둔다(공유·새로고침 복원).
- 명령 버튼은 제출 중 비활성 + 같은 `Idempotency-Key` 재시도. `reason` 입력 필수 명령은 폼에서 강제.

## 4. `[결정 필요]`
BO-Q01(운영자 IAM·로그인·추가 인증), Q02(역할·범위), Q06(승인함↔원승인 연결), Q07(재심사·승인선), Q19(신선도 임계·SLA), Q20(개인정보 열람·다운로드·보존), Q21(대량 변경 상한·양식), Q22(지표 정의), Q03/Q04(상품·가격 실행 정본), Q05(권역 중첩). 카카오 지도 앱 키 발급·허용 도메인.
