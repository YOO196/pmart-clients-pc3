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

## 2-1. 임시 백오피스: 상품·콘텐츠·가격·승인·센터 취급 (2026-10-30)
근거: `../pmart-backend/docs/handoff/2026-10-30-clients-notice-temp-backoffice-api.md`(기준 `86e156e`). 위 표의 #3·#4 를 bff 없이 원서비스 경로로 먼저 만든다.

| 메뉴 | 경로 | API |
|---|---|---|
| 로그인 | `/login` | auth `POST /auth/operator-logins`(Idempotency-Key 없음, `X-Device-Id`). 실패 `LOGIN_FAILED`·`ACCOUNT_LOCKED` |
| 내 세션 | `/session` | `GET /auth/sessions/current`, `POST /auth/password-changes`(204), `POST /auth/logouts` |
| 운영자 계정 | `/operators` | `GET`·`POST /operator-accounts`, `PUT …/{id}`(X-Expected-Version), `POST …/{id}/password-resets` — OPERATOR_ADMIN. 센터는 center-master `GET /centers` 목록에서 다중 선택(`CenterPicker`), 목록에 없는 기존 ID 는 "(목록에 없음)"으로 유지 |
| 승인함·상세 | `/approvals`, `/approvals/:id` | approval `GET /approvals`, `GET /approvals/{id}`, `POST …/decisions`(APPROVE·REJECT 만) |
| 카테고리 트리 | `/categories` | product `GET /categories/tree`, `…/filters`, `POST /category-tree-versions`. 카테고리 추가는 `categories.json`(`POST /category-tree-additions`) 또는 seed-v1 zip(`POST /category-tree-addition-uploads`, multipart) — 결과·승인 흐름 동일(2026-11-03 회신) |
| 상품 등록 | `/products/drafts/new`, `/products/drafts/:id` | `/product-drafts*` → 제출 준비 → 승인 요청. 대표 카테고리는 노출 목록에 자동 포함(화면은 "대표" 배지로 맨 앞, 전송은 `primaryCategoryId` + 나머지 `categoryIds` — 서버가 대표를 맨 앞에 합친다) |
| 상품 일괄 | `/products/import`, `/products/import/:id` | `/product-import-batches*`, id-map 내려받기. 제출 뒤 "승인 요청 현황"(`BatchApprovals`, 상품·콘텐츠·가격 공통): `GET /approvals?targetRef=…ImportBatch:{batchId}` 로 승인 상세 링크·심사 상태, 아직 안 올렸으면 배치 조회의 `pendingSubmission.approvalRequest`(가격은 `approvalRequest`)로 "승인 요청" 버튼(BR-41 회신). 탭 저장소 없음. 유효·오류 수와 "유효 행 제출 준비" 활성은 응답 `drafts[]` 에서 직접 센다(서버 `validCount` 는 업로드 때 값, BR-38). 행 `registration` NEW/UPDATE 를 "구분"으로(UPDATE = 기존 상품의 새 버전, 상품 ID 링크·SKU 유지), UPDATE 가 있으면 제출 전 안내. 승인 상세도 행 attributes 로 같은 표시(BR-39 회신) |
| 상품 조회·판매 상태 | `/products`, `/products/:id` | `GET /products`, `/skus`, `/barcodes`, `POST …/sale-state-changes` + 짝 조회 |
| 콘텐츠 등록·일괄 | `/contents/drafts/*`, `/contents/import/*` | `/content-drafts*`, 이미지 업로드, `/content-import-batches*` |
| 가격 | `/prices?sku=` | `GET /prices/{sku}`(PRICE_NOT_SET = 미설정), `/price-versions/{sku}`, PRICE 변경 요청, `POST /price-version-applications` + 짝 조회 |
| 가격 일괄 등록 | `/prices/import`, `/prices/import/:id` | pricing `/price-import-batches*`(2026-11-03 안내): 같은 seed-v1 zip 업로드 → 서버가 묶음 가격으로 행을 채움(화면은 zip 을 풀지 않음) → 행 `PUT …/lines/{seedProductId}`(고치기·되돌리기·빼기, `X-Expected-Version`) · `POST …/refreshes`(다시 대조) → `POST …/submissions`(공통 효력 시각, 잠김) → 응답 `approvalRequest` 그대로 PRICE 승인 요청 한 건 → 승인 뒤 `GET` 으로 행별 `result`. 상품 일괄 등록 승인(SKU 발급) 뒤에만 가능 |
| 센터 취급 | `/handlings?type=&center=` | `/mfcs/{id}/sku-handlings`·`/cdcs/{id}/sku-handlings`, `…/sku-handling-batches` |

공통 흐름: 정본 "제출 준비" 응답의 `approvalRequest` → approval `POST /change-requests` → `…/submissions`(approvalId). 두 요청 키는 사용자 행위 키 하나에서 만든다(`{key}:cr`, `{key}:submit`). 판매중지·가격은 화면이 변경 요청 본문을 직접 만든다(handoff §4.3·§4.5).
승인 뒤 정본 반영은 비동기라 승인 상세에서 1초 간격·최대 30회 폴링하고, 끝나지 않으면 "아직 확인되지 않음 + 다시 확인"으로 둔다.
토큰(ADR-0018): access·refresh 모두 탭 메모리(새로고침 = 재로그인, localStorage 금지). 401 → pmartFetch single-flight 로 `POST /auth/tokens` 한 번(회전된 refresh 로 즉시 교체) → 원 요청 재전송. `TOKEN_INVALID`·`TOKEN_REUSED`·`SESSION_EXPIRED` 면 토큰을 지우고 로그인 화면(`/login?from=`). 갱신 결과 불명이면 같은 refresh 를 다시 보내지 않는다(재사용으로 세션이 끊김). `X-Device-Id` 는 탭마다 UUID(refresh 도 탭 메모리라 충분).
실행 모드: `dev`(목) / `dev:local`(Vite 프록시 → localhost:8080, 첫 관리자 admin / pmart-local) / `dev:lan`·`build:lan`(게이트웨이 `http://192.168.0.40:8080/api/v1` 직접, 브라우저는 `http://192.168.0.40` 으로 연다. 이름 `d603-16` 은 다른 PC 에서 IPv6 링크 로컬로 풀려 안 열림 — 2026-11-06).
막힌 것: 이미지 인증(BR-25), 초안 목록(BR-26), 센터 목록(center-master 다음 작업 → 센터 ID 입력).

## 2-2. 업무 도우미 (정책·업무 절차 질의응답, 2026-11-04, BR-46 / 계약 1.1.0 반영 2026-11-06)
- 경로 `/assistant`(질문·답변·내 질문 목록), `/assistant/answers/:answerId`(답변 다시 보기). 코드 `src/features/assistant/`.
- 읽기 전용. 주문·재고·환불·승인 변경 버튼, AI 자동 실행 없음. 메뉴는 숨기지 않고 권한은 서버 판정(403·404).
- 계약 `ai-assistant-service.yaml` 1.1.0(ADR-0036). 화면은 `AssistantPort` 뒤에 둔다. 서비스가 LAN 에 배포되지 않아(BR-46 #13 보류) 목 모드만 `draftMock`(계약 모양, "서버 LAN 배포 전" 표시), local·LAN 빌드는 호출하지 않고 "연결 전" 안내. 배포 안내가 오면 생성 타입 + pmartFetch 어댑터를 끼운다.
- 질의 `POST /assistant/policy-questions`: 새 전송 = 새 Idempotency-Key. 결과 불명(타임아웃·503 `DEPENDENCY_UNAVAILABLE`·응답 유실)과 202 `PROCESSING` 은 같은 키·같은 질문으로만 재확인(계약: 같은 키 = 같은 답). 답을 받은 질문을 그대로 다시 보내지 않는다(질문을 고치거나 "새 질문"). 403·409·422 `CONFIG_REQUIRED` 는 거절로 확정.
- 표시: 답변·근거 본문은 일반 텍스트(HTML·마크다운 해석 없음). 기준선(`BASELINE_EXTRACTIVE`·`BASELINE_HASH`)이면 "품질 미검증" 안내. 인용은 지위(authority 6종)·생애(ACTIVE 외만 표시, 대체 문서·대체 제안)·구현 기록(날짜 기준, 현재 구현 보장 아님)을 따로, 저장소 상대 경로·절·문서 버전·기준일·색인 시점(스냅샷·revision·커밋 안 된 변경)·근거 본문(접기). 상대 경로가 아니면 가린다. 링크 없음(1차에 문서 열람 API 없음).
- 상태: `NO_GROUNDING`·`REALTIME_DATA_REQUIRED`·`OUT_OF_SCOPE`·`FORBIDDEN_SCOPE` 는 각자 안내(서버 안내 문장 함께) ≠ 오류. 상태 확인(health) 경로는 게이트웨이에 없어 응답 코드로만 구분.
- 내 질문 목록 `GET /assistant/question-history`(최근 순, 커서 "더 보기"). 질문 원문은 서버가 저장하지 않아 `answerPreview` 로 구분. 조회 실패는 오류로(빈 목록 아님). 질의 뒤 목록 다시 조회.
- 답변 다시 보기 `GET /assistant/policy-questions/{answerId}`: 202 처리 중이면 "다시 확인", 404·409 는 오류로.
- 계정 전환·로그아웃: 이전 계정의 `['assistant', owner]` 캐시 삭제, 화면 상태 새로 시작.

## 3. 기술 메모
- 개발: Vite 프록시 `/api → http://localhost:8080` (CORS 없음, BR-04). 목은 MSW.
- 모든 목록은 커서 페이지(`size`, `cursor`). 표·필터 상태는 URL 쿼리에 둔다(공유·새로고침 복원).
- 명령 버튼은 제출 중 비활성 + 같은 `Idempotency-Key` 재시도. `reason` 입력 필수 명령은 폼에서 강제.

## 4. `[결정 필요]`
BO-Q01(운영자 IAM·로그인·추가 인증), Q02(역할·범위), Q06(승인함↔원승인 연결), Q07(재심사·승인선), Q19(신선도 임계·SLA), Q20(개인정보 열람·다운로드·보존), Q21(대량 변경 상한·양식), Q22(지표 정의), Q03/Q04(상품·가격 실행 정본), Q05(권역 중첩). 카카오 지도 앱 키 발급·허용 도메인.
