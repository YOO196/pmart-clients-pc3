# 문의 만족도를 답변한 직원별로 보기 요청 (관리자 — 개인 성과 측정·관리)

보낸 앱: backoffice (PC 2)
받는 백엔드 영역: platform (case-service — 문의 만족도 0.15.0 이어서)

- 근거: 사용자 2026-11-24 결정 — "문의 만족도에서 고객이 만족도를 남겼을 때 그 문의를 답변한 직원에게 개별적으로 평점을 줄 수 있게(지금 전체 평점은 그대로 두고)", "직원마다 평점을 볼 수 있게 하고 고객 개인정보는 가리는 식으로, **관리자가 개인의 성과 측정 및 관리 목적**".
- **바뀌는 결정**: 2026-11-17 의 "만족도는 상담원 평가·제재에 쓰지 않고 관리자만 모아 본다 — 상담원별·문의별로 나누지 않는다"(case `GET /inquiries/satisfaction-summary` 설명, 업무 원문 Commerce §14.2)를 사용자가 바꿨다. 관리자만 본다는 점은 그대로다.
- 지금 없는 것:
  1. 답변(`Inquiry.replies[]`)에 **누가 답했는지가 없다** — replyId·authorType(AGENT·RIDER)·body·createdAt 뿐이다.
  2. 만족도 모아 보기는 기간 전체 숫자 하나뿐이다(`answeredCount`·`ratedCount`·`scoreSum`·`averageScore`·`byScore`).

## 요청
1. **답변한 직원 기록**: `Inquiry.replies[]` 의 AGENT 답변에 `authorId`(운영자 ID)를 넣어 주세요. 이름은 화면이 hr `employee-labels` 로 붙인다.
2. **직원별 만족도 모아 보기**(OPERATOR_ADMIN 만): 예) `GET /inquiries/satisfaction-summary/by-agent?answeredFrom&answeredTo`(지금 요약과 같은 기간 규칙 — 답변 시각 [from, to), 92일까지) →
   `items[]: { agentId, answeredCount(분모), ratedCount(분자), scoreSum, averageScore(남긴 건 0 이면 null), byScore{"1".."5"} }`.
   지금 `GET /inquiries/satisfaction-summary`(전체)는 그대로 둔다.
3. **직원 한 명의 평가 목록**(OPERATOR_ADMIN 만, 쪽 넘김): `agentId` 로 그 직원이 답한 문의의 만족도 — `{ inquiryId, inquiryNumber 또는 표시 번호, score, comment, ratedAt, answeredAt }`.
   **고객 개인정보는 넣지 않는다**(고객 ID·이름·연락처 없이). comment 에 고객이 개인정보를 쓸 수 있으니, 있으면 서버가 가린 값으로(전화번호·메일 같은 모양 가림) 주면 좋겠다 — 어렵다면 알려 주세요(화면에서 가리는 것으로 대신할지 정한다).

## 정해 줄 것(백엔드 의견 부탁)
- **한 문의에 여러 직원이 답했을 때 누구 몫인가**: 화면 쪽 제안은 "만족도를 남기기 직전 마지막 AGENT 답변을 쓴 직원" 한 명. 모든 답변자에게 나눠 주는 방식이 낫다면 회신에 적어 주세요(사용자에게 다시 묻는다).
- 상담원 접수(STAFF_INTAKE)·라이더 문의는 지금처럼 빼는지.
- 이미 쌓인 답변(authorId 없음)은 "답변자 모름"으로 묶을지, 기록에서 되살릴 수 있는지.

## 받은 뒤 화면
- 문의 만족도 화면(지금 전체 평점·점수별 그대로)에 "직원별" 표 — 직원(이름·사번), 답변 수, 남긴 수/답변 수, 평균, 점수별. 분모 0 은 N/A, 조회 실패는 0 으로 보이지 않게.
- 직원 줄을 누르면 그 직원이 받은 평가 목록(문의 번호·점수·한 줄 의견·시각) — 고객 정보 없음.
- 관리자(OPERATOR_ADMIN)만. 상담원 본인에게는 보이지 않는다(사용자가 따로 정하기 전까지).
