# [pmart-clients → pmart-backend] 통합 승인함(bff) 미구현(BR-40)·제출한 배치의 승인 요청 재조회(BR-41) (2026-11-03)

- 관련: `contracts/openapi/backoffice-bff.yaml` `GET /views/approval-inbox`, `services/backoffice-bff/.../ViewsController.java`; `contracts/openapi/product-service.yaml` `POST /product-import-batches/{batchId}/submissions`, `GET /product-import-batches/{batchId}`, `ProductDraft.approvalId`; approval-service `GET /approvals`, `POST /change-requests/{id}/submissions`.
- 우선: 둘 다 중간. 백오피스는 우회해 두었고, 운영자가 실제로 겪은 문제다(2026-11-03 LAN).

## 1. BR-40 통합 승인함(bff) 이 501

### 현상
- 백오피스 메뉴 "통합 승인함(bff)" 이 `GET /api/v1/views/approval-inbox` 를 읽는데, `ViewsController` 가 `implements ViewsApi {}` 로 비어 있어 계약 인터페이스 default 가 501 을 돌려준다. 다른 `views/*` 도 같다.
- 운영자: "승인함에 승인하는 버튼·화면 없음." 승인·반려 버튼은 승인 상세(`/approvals/{approvalId}`) 에 있고, 메뉴 "승인함"(`/approvals`, approval-service 목록) 에서 상세로 들어갈 수 있다. bff 승인함에서는 목록 자체가 안 온다.

### 백오피스 처리
- bff 승인함 행의 `dossierId` 를 `/approvals/{dossierId}` 링크로 바꿔 두었다(approval 표의 키가 승인 ID 라고 보고).

### 요청
- (a) `GET /views/approval-inbox` 구현. 항목의 `dossierId` 가 approval-service 승인 ID 와 같은지 알려 달라(다르면 `approvalId` 를 항목에 넣어 달라).
- (b) 구현이 멀면 그렇다고 알려 달라. 그때까지 백오피스가 "통합 승인함(bff)" 메뉴를 숨긴다.

## 2. BR-41 제출한 배치의 승인 요청 본문·승인 ID 를 다시 읽을 수 없음

### 현상
- `POST /product-import-batches/{batchId}/submissions` 응답에만 `approvalRequest` 가 있다. 배치가 SUBMITTED 가 되면 같은 경로는 422 `NOTHING_TO_SUBMIT`(`DRAFT`+`VALID` 행이 없음) 이고, 같은 Idempotency-Key 재전송만 같은 응답을 준다.
- 운영자가 `approvalRequest` 를 approval-service 에 올려 승인 ID 를 받아도, 그 ID 는 초안·배치에 기록되지 않는다. `ProductDraft.approvalId` 는 `ApprovalApplier` 가 반영(APPLIED/REJECTED) 할 때만 채운다(`DraftStore` UPDATE 두 곳).
- 그래서 제출 뒤 승인 상세에 다녀오거나 새로고침하면 백오피스가 "승인 요청" 버튼·"승인 상세 보기" 를 잃었다. 승인 요청을 올리기 전에 화면을 떠나면 본문을 되찾을 수 없어, 배치는 잠긴 채 승인 요청만 빠진다.

### 백오피스 처리 (2026-11-03 반영)
- 제출한 배치 화면에 "승인 요청 현황": `GET /approvals?type=PRODUCT&size=50` 에서 `targetRef === productImportBatch:{batchId}`(`ProductDraftService.BATCH_PREFIX`) 인 건을 찾아 승인 상세 링크·심사 상태를 보인다.
- 제출 응답의 `approvalRequest` 와 올린 `approvalId` 를 그 탭의 sessionStorage 에 둔다. 한계: 탭을 닫으면 사라지고, PRODUCT 승인이 50건을 넘으면 목록에서 못 찾는다(그때는 승인 목록 링크 안내).

### 요청 (택1 또는 조합)
- (a) `GET /product-import-batches/{batchId}` 응답에 마지막 제출 결과(`submittedDraftIds`·`excludedDraftIds`·`approvalRequest`)와, 올려졌으면 `approvalId` 를 넣는다. 백오피스는 sessionStorage 를 버리고 이 값을 쓴다.
- (b) approval-service 가 변경 요청 제출(`POST /change-requests/{id}/submissions`) 때 정본 서비스에 알려 초안·배치의 `approvalId` 를 바로 채운다(지금은 반영 때만). 백오피스는 `drafts[].approvalId` 로 링크를 만든다.
- (c) 최소한 `GET /product-import-batches/{batchId}/submissions` 같은 조회로 마지막 제출 응답을 다시 읽게 한다.
- 콘텐츠 일괄 등록(`content-import-batches`)·가격 일괄 등록(`price-import-batches`) 도 같은 구조면 함께.

## 3. 참고
- 백오피스 변경 파일: `web/backoffice/src/features/products/ProductImportPage.tsx`(`BatchApprovals`), `batchApprovalStore.ts`, `features/approvals/ApprovalInboxPage.tsx`.
