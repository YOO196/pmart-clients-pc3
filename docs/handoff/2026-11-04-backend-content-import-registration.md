# [pmart-clients → pmart-backend] 콘텐츠 일괄 등록: 신규 / 기존 게시 콘텐츠 갱신 구분 (BR-44) (2026-11-04)

- 관련: `contracts/openapi/product-content-service.yaml` `POST /content-import-batches`, `GET /content-import-batches/{batchId}`(`items[].outcome`·`createdCount`·`updatedCount`), `ContentDraft`, `ContentApprovalRequestBody.lines[]`. 구현 `ContentDraftService`(seed upsert), `DraftStore.findOpen`·`findLatestPublished`. 읽은 백엔드 HEAD `4342c58`.
- 선례: BR-39(상품 초안 `registration` NEW/UPDATE·`existingProductId`·`existingSkus`, 2026-11-03 회신).
- 우선: 중간(고객 노출 결과는 맞음. 운영자가 승인 전에 "이미 게시된 콘텐츠를 덮어쓰는지"를 볼 수 없음).

## 현상 (코드 읽기, 2026-11-04)
- seed 업로드는 (sourceSystem, sourceKey) 로 **열린 초안**(`state IN ('DRAFT','SUBMITTED')`)을 찾는다.
  - 열린 초안이 있으면 → `UPDATED`(내용 같으면 `UNCHANGED`, 심사 중이면 `LOCKED`).
  - 없으면 → 최근 게시 초안(`findLatestPublished`)과 해시를 비교해 같으면 `UNCHANGED`, **다르면 새 초안을 만들고 `CREATED`**.
- 그래서 이미 게시(PUBLISHED)된 콘텐츠를 고쳐 다시 올린 행도, 한 번도 게시된 적 없는 행도 똑같이 `CREATED` 로 온다. `createdCount` 에도 함께 세진다.
- `ContentDraft` 에는 `contentVersion`(그 초안이 게시된 뒤의 버전)만 있고, "이 상품/원천 키에 이미 게시된 콘텐츠가 있다(v몇)"는 값이 없다. 승인 행(`lines[].attributes`)에도 없다.

## 영향
- 고객앱 결과는 문제없다 — 승인하면 같은 상품의 새 `contentVersion` 으로 게시되어 기존 게시본을 대체한다(새 상품이 생기지 않음).
- 백오피스는 업로드 결과·배치 표·승인 상세에서 "신규 콘텐츠"와 "기존 게시 콘텐츠 갱신"을 구분해 보여 줄 수 없다. 승인자는 고객에게 보이던 이름·이미지를 덮어쓰는지 모른 채 승인한다.
- 클라이언트 우회(행마다 고객용 `GET /products/{productId}/content` 로 200/404 확인)는 쓰지 않는다: 상품 승인 전 행은 `productId` 가 없고, 고객용 조회라 게시·미발효 차이를 놓치며, 행 수만큼 호출한다.

## 요청
BR-39 와 같은 방식으로 서버가 판단한 값을 달라.
1. `ContentDraft`(그리고 배치 `items[].draft`)에 `registration`: `NEW` | `UPDATE` — 같은 원천 키(또는 연결 상품)에 게시된 콘텐츠가 있으면 `UPDATE`.
2. `UPDATE` 면 기존 게시 정보: 예 `publishedContentVersion`(현재 게시 버전), 필요하면 `publishedDraftId`·`publishedAt`.
3. 승인 요청 본문 `lines[].attributes` 에도 같은 값(`registration`, 기존 게시 버전) — 승인 상세에서 보이게.
4. (선택) 배치 `items[].outcome` 의 `CREATED` 를 그대로 두되, 게시본이 있는 상태에서 새로 만든 초안을 구분하는 값(가칭 `CREATED_FROM_PUBLISHED`)이나 `createdCount` 와 별도 수 — 백엔드가 1번으로 충분하다고 보면 생략.
- 필드 이름·모양은 백엔드가 정하면 된다. 정해지면 계약을 갱신해 주면 백오피스가 생성 타입으로 반영한다.

## 백오피스 처리
- 지금: 변경 없음(계약에 없는 값이라 표시하지 않음).
- 회신 뒤: 콘텐츠 배치 표에 구분 열(신규 / 기존 콘텐츠 갱신 vN), 업로드 결과 안내, 승인 상세 행 표시 — 상품(BR-39)과 같은 모양.
