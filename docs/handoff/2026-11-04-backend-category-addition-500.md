# [pmart-clients → pmart-backend] 카테고리 추가: 이미 있는 카테고리만 올리면 500 INTERNAL_ERROR (BR-48) (2026-11-04)

- 관련: `contracts/openapi/product-service.yaml` `POST /category-tree-additions`·`POST /category-tree-addition-uploads`(모두 이미 있으면 **422 NOTHING_TO_ADD**), `services/product-service/.../application/CategoryTreeService.java`(154행 `NOTHING_TO_ADD`). 읽은 백엔드 HEAD `b409385`.
- 증상(백오피스 LAN, 2026-11-04): 카테고리 트리 화면 "없는 카테고리만 추가"에서 발효 트리에 이미 있는 카테고리만 담긴 파일을 올리면 응답이 **500 `INTERNAL_ERROR`**. 계약대로면 422 `NOTHING_TO_ADD` 여야 한다.
- 클라이언트는 이 요청을 다시 보내 재현하지 않았다(운영자 토큰이 필요하고, 성공하면 트리 초안이 생기는 변경 요청). 올린 파일이 zip 인지 JSON 인지, 문의 번호(traceId)는 사용자가 따로 전달한다.

## 요청
1. 이미 있는 카테고리만 올렸을 때 500 이 나는 원인 확인(서버 로그, 위 문의 번호). 코드상 `CategoryTree.withAdditions` 뒤 `addedIds` 가 비면 422 를 던지므로, 그 앞(묶음 읽기·멱등 처리·트리 복사 등)에서 다른 예외가 났을 가능성.
2. 계약대로 **422 `NOTHING_TO_ADD`** 로 응답. 같은 id·다른 이름 등 충돌은 **400 `CATEGORY_CONFLICT`**.

## 클라이언트 현황
- `NOTHING_TO_ADD` → "추가할 카테고리가 없어요(모두 이미 있어요). 바로 상품 일괄 등록으로 넘어가면 돼요."(기존)
- 이번에 추가: 이 화면에서 `INTERNAL_ERROR` 가 오면 "요청이 거절됐어요 / INTERNAL_ERROR" 대신 "서버가 카테고리 추가를 처리하지 못했어요(서버 오류) … 문의 번호를 백엔드에 알려 주세요"와 문의 번호. 다른 화면의 `INTERNAL_ERROR` 도 "서버에서 처리하지 못했어요(서버 오류)"로.
- 서버가 422 로 고치면 클라이언트 변경 없이 "추가할 카테고리가 없어요"가 보인다.
