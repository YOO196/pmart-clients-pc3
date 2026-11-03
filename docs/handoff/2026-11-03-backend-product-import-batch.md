# [pmart-clients → pmart-backend] 상품 일괄 등록 배치: 유효 수 갱신(BR-38)·등록된 seed 상품 ID 재업로드 검사(BR-39) (2026-11-03)

- 관련: `contracts/openapi/product-service.yaml` `POST /product-import-batches`, `GET /product-import-batches/{batchId}`, `PUT /product-drafts/{draftId}`, `POST /product-import-batches/{batchId}/submissions`, `GET …/id-map`. 구현 `ProductDraftService`, `DraftStore`, `DraftRules`.
- 우선: BR-38 중간(백오피스가 우회해 표시 중), BR-39 중간(중복 등록이 실제로 날 수 있음).

## 1. BR-38 배치의 `validCount`·`invalidCount` 가 행 수정 뒤 갱신되지 않음

### 현상 (LAN, 2026-11-03)
- seed-v1 zip 을 올리면 행 대부분이 중량·보관 방식이 없어 INVALID 로 검증된다(`WEIGHT_REQUIRED`·`STORAGE_TYPE_REQUIRED`). 배치 요약은 "유효 0".
- 운영자가 행의 빠진 값을 채워 `PUT /product-drafts/{draftId}` 로 저장하면 그 행은 다시 검증돼 `validationState=VALID` 가 된다.
- 그런데 `GET /product-import-batches/{batchId}` 의 `validCount` 는 여전히 0, `invalidCount` 는 올릴 때 값 그대로다. 행 목록(`drafts[]`)만 VALID 로 바뀌어 온다.
- 코드: `ProductDraftService.uploadBatch` 만 `DraftStore.updateBatchCounts` 를 부른다. `ProductDraftService.update`(PUT)는 `drafts.replaceInput` 으로 행만 바꾸고 배치 수는 손대지 않는다. 제출(`submitBatch`)·반영(`ApprovalApplier`) 뒤에도 마찬가지다.

### 영향
- 백오피스는 `validCount === 0` 이면 "유효 행 제출 준비"를 잠갔다. 올릴 때 전부 INVALID 였던 배치는 행을 고쳐 VALID 가 되어도 제출할 수 없었다.
- 제출 자체는 `submitBatch` 가 행을 직접 보고 `DRAFT`+`VALID` 만 잠그므로 서버 동작은 맞다. 요약 수만 틀린다.

### 백오피스 처리 (2026-11-03 반영)
- 요약 줄의 유효·오류 수와 제출 버튼 활성을 응답 `drafts[]` 에서 직접 센다. 행 목록이 없을 때만 서버 수를 쓴다.

### 요청 (택1)
- (a) 초안 수정·제출·반영 뒤 배치의 `validCount`·`invalidCount`(필요하면 `productCount`)를 다시 센다. 또는 `GET` 때 행에서 계산해 돌려준다.
- (b) 계약 설명에 "업로드 때 검증 결과. 이후 행을 고쳐도 갱신하지 않는다. 현재 수는 `drafts[]` 로 센다"라고 적는다. 백오피스는 지금 방식 유지.
- 콘텐츠 일괄 등록 배치(`content-import-batches`)도 같은 구조면 함께.

## 2. BR-39 이미 등록된 seed 상품 ID 를 다시 올리면 새 초안이 생김

### 현상 (코드 읽기, 2026-11-03)
- 업로드는 (sourceSystem, seedProductId) 로 초안을 upsert 한다(계약 설명대로). 그런데 `DraftStore.findOpen` 은 `state IN ('DRAFT','SUBMITTED')` 만 찾는다.
- 승인 반영이 끝난 초안은 `APPLIED` 라 "열린 초안"이 아니다. 같은 seed 상품 ID 를 다시 올리면 기존 상품에 연결되지 않고 **새 DRAFT 가 생긴다.**
- 업로드 검증(`DraftRules`)은 바코드만 본다: 빈 바코드(`BARCODE_EMPTY`), 초안 안 중복(`BARCODE_DUPLICATED_IN_DRAFT`), 다른 활성 SKU 가 쓰는 바코드(`BARCODE_CONFLICT`). seed 상품 ID 가 이미 상품으로 등록됐는지는 보지 않는다.

### 영향
- 바코드가 있는 상품은 `BARCODE_CONFLICT` 로 INVALID 가 되어 막힌다.
- 바코드가 없는 상품은 새 초안이 VALID 로 통과한다. 제출·승인하면 같은 상품이 한 번 더 등록되어 상품 ID·SKU 가 하나 더 발급된다. id-map 의 seedProductId → 상품 짝도 둘이 된다.
- 운영자가 같은 seed 묶음을 다시 올리는 일은 흔하다(일부 행을 고쳐 재업로드, 콘텐츠·가격 묶음과 같은 파일 재사용).

### 요청
- 업로드 검증에 "이 seed 상품 ID 는 이미 상품 {productId} 로 등록됨" 검사를 넣어 달라. 처리 방식은 백엔드가 정하면 된다. 예:
  - (a) INVALID 문제 코드(가칭 `SOURCE_KEY_ALREADY_APPLIED`, `detail` 에 productId·sku)로 표시한다. 코드 값만 알려 주면 백오피스가 문구를 붙인다.
  - (b) 기존 상품의 수정 초안으로 upsert 한다(이 경우 승인 종류·`identityKey` 처리 방식을 알려 달라).
- 콘텐츠 일괄 등록도 같은 구조면 함께.

## 3. 백오피스 쪽 상태
- BR-38: 행 기준 집계로 우회 반영(`web/backoffice/src/features/products/ProductImportPage.tsx` `batchCounts`). 서버가 수를 고치기 시작해도 화면 변경 없음.
- BR-39: 변경 없음. 서버 검증 결과를 표시만 한다. 새 문제 코드가 생기면 `messages.ts` `reason` 에 문구를 추가한다.
