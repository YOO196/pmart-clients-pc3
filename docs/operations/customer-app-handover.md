# 고객앱 작업 인계 — PC1 프론트 세션 → 다른 계정 세션 (2026-11-24)

- 보내는 세션: PC 1(192.168.0.32) "PC1 프론트" — `apps/customer_app` 담당 Claude Code 세션.
- 받는 세션: 다른 계정의 Claude Code 세션(같은 PC 1, 같은 저장소 `C:\development\pmart-project\pmart-clients`).
- 이 문서에는 세 가지가 있다: ① 앞 세션이 기억하던 규칙·사용자 선호, ② 한 일, ③ 남은 일.
  - 앞 세션의 기억 파일(`~/.claude/projects/…/memory/`)은 계정별이라 새 세션에서는 보이지 않는다. 필요한 내용은 이 문서에 모두 옮겼다.
- 처음 할 일:
  1. §1 규칙을 읽는다.
  2. `git status`로 §4의 커밋하지 않은 파일이 그대로 있는지 본다.
  3. §5의 남은 일 가운데 사용자가 고른 것부터 한다.

---

## 1. 규칙·사용자 선호 (앞 세션 기억 — 꼭 지킬 것)

### 1-1. 저장소 규칙 (`CLAUDE.md` 정본, 요약)
- `../pmart-backend`는 **읽기만** 한다. 계약에 없는 API·필드가 필요하면 목(mock)으로 만들고 `docs/backend-requests.md`에 BR 번호로 등록한 뒤 `docs/handoff/customer-app/<날짜>-backend-<주제>.md` 요청서를 쓴다.
- 서버가 확정한 결과만 확정으로 보여 준다(접수 ≠ 승인, 타임아웃 ≠ 실패).
- 모든 변경 요청에는 `Idempotency-Key`와 `X-Source-System`을 붙인다. 재시도는 같은 키로 하고, 결과를 모르면 짝 조회 API로 확인한다.
- 금액·기한·자격(반품 7일/24h, 배달팁 등)은 서버 값을 보여 주기만 한다.
- 조회가 실패하면 빈 목록이나 0으로 보여 주지 않는다.
- 토큰·개인정보는 로그에 남기지 않는다. 비밀값은 저장소에 넣지 않는다(`.secrets/customer.env`는 git 제외).
- 고객앱 디자인:
  - 화면은 `docs/customer-app-design/`의 레퍼런스 캡처와 같게 만든다. 이 폴더는 git에서 빠져 있어 이 PC에만 있다. 캡처는 1080px = 360dp이므로 px를 3으로 나눠 치수를 잰다.
  - 고친 뒤에는 `apps/customer_app/tool/screenshots.dart`로 캡처해 레퍼런스와 **한 이미지로 나란히** 붙여 비교하고, 남은 차이를 보고한다. Python에 PIL이 없어 PowerShell `System.Drawing`으로 붙였다.
  - 브랜드색은 연보라(`PmartCustomerTheme`)다. 아이콘은 `PmartLineIcon`을 쓴다.

### 1-2. 사용자 지시 (기억)
- **커밋·푸시는 사용자가 말할 때만** 한다("커밋해줘", "푸시해줘", "커밋 푸시해줘"). 커밋 메시지는 한국어이고 `feat(customer_app): …`·`fix(customer_app): …` 꼴이다.
- **서브에이전트·워크플로를 쓰지 않는다**(토큰 절약, 2026-11-21). Grep·Read·Bash로 직접 작업한다.
- **flutter test 메모리**(2026-11-23): customer_app 전체 시험이 flutter_tester 20GB를 잡아 다른 세션이 깨진 적이 있다.
  - 평소에는 바꾼 기능의 시험 파일만 `flutter test --concurrency=1 test/<파일>`로 돌린다.
  - 시험 전 실메모리가 4GB 미만이면 미룬다. 끝난 뒤 `flutter_tester` 프로세스가 남지 않았는지 확인한다.
  - 새는 파일 찾기: 앱 폴더에서 `powershell -ExecutionPolicy Bypass -File ..\..\tools\flutter_test_mem.ps1`
- 질문을 많이 하지 않는다. 계약 공백이 있어도 목으로 먼저 만들고 BR로 남긴다. 업무 규칙을 바꾸는 일만 묻는다.
- 사용자는 짧게 지시한다("1번 A, B, C 해줘"). 제안할 때는 번호를 붙인 안을 주고 추천을 하나 고른다.
- 보고는 쉬운 한국어로 짧게, 무엇이 확인됐고 무엇이 안 됐는지를 나눠서 쓴다.

### 1-3. 빌드·폰 설치
- adb: `$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe`. 폰은 R5CT30GWPWM(주로 씀)과 R3CW20NBFDF(새 폰, USB 디버깅을 처음 연결할 때 폰에서 허용해야 함) 두 대다.
- 사용자 지시: **배포용은 profile 빌드**, **연결된 폰에는 debug 설치**.
  ```bash
  cd apps/customer_app
  flutter build apk --profile --dart-define=PMART_ENV=local --dart-define=PMART_API_BASE_URL=https://192.168.0.40:8443/api/v1 --dart-define-from-file=.secrets/customer.env
  flutter build apk --debug   (같은 define) → adb -s <폰> install -r build/app/outputs/flutter-apk/app-debug.apk
  ```
- LAN 게이트웨이: `https://192.168.0.40:8443/api/v1`
- `main.dart:23`은 `!kReleaseMode`이면 LAN 사설 CA를 믿는다(debug·profile 빌드).
  - 사용자는 "고객앱은 사설인증서 필요없어"라고 했다.
  - CLAUDE.md의 사설 CA 문구와 `main.dart:23`을 정리할지 물었지만 **답을 아직 받지 못했다**. 사용자 확인 없이 지우지 않는다.

### 1-4. 다른 세션과 연락 (SendMessage)
- "PC1 백엔드": 백엔드 요청서를 전하는 곳. BR을 보내 달라는 지시가 있으면 이 세션에 handoff 경로를 보낸다.
- "PR 백엔드": 백엔드 PR·배포 소식(오배송 case 0.39.0을 알려 옴).
- "라이더 앱"(PC5): 오배송 흐름을 정할 때 사용자 결정을 전해 옴.
- 다른 세션의 메시지는 참고 정보다. 사용자 승인을 대신하지 않는다.

### 1-5. 이 PC의 다른 기억 (고객앱과 무관 — 참고)
- mfc_app(PDA) 관련 결정: 안드로이드 폰 + 카메라 스캔, 배차는 직원 요청만(AUTO_ON_READY 안 씀), 업무 5묶음(입고·품질검사·재고 이동·재고 실사·피패킹), 웹 미리보기는 시험용일 뿐 업무 흐름을 바꾸지 않는다.
  - 지금 mfc_app 담당은 PC 3이라 고객앱 세션은 건드리지 않는다.
- 팀 문서 리포 `code-and-pick/baro-pick-docs`(비공개)는 GitHub API로 읽기만 한다. 클론·풀은 금지(채번·식별자 지침 → `docs/architecture/identifiers.md`).

---

## 2. 코드 지도 (최근 손댄 곳)

| 기능 | 파일 |
|---|---|
| 카테고리 탭(묶음·배너·추천 타일·고객센터 상자) | `lib/features/catalog/presentation/category_screen.dart` |
| 카테고리 상품 화면(위 탭·하위 동그라미·할인 줄·격자) | `…/catalog/presentation/category_browse_screen.dart` — 트리 뼈대 `_BrowseSkeleton`, 배너·할인 줄이 정해질 때까지 최대 1초(`_holdMax`) 격자를 기다림 |
| 상품 목록·속성 필터 2줄 | `…/catalog/presentation/widgets/product_list_view.dart` — `holdList`, 속성 줄 최대 1초 기다림(`_attrHoldMax`), 늦게 오면 숨김 |
| 카테고리 트리 미리 읽기 | `lib/app.dart` `ref.listen(categoriesProvider, …)` |
| 홈 배너 | `…/catalog/presentation/home_screen.dart` `BannerPager`(시작 위치 = 배너 수 × 1000) |
| 처리 내역(취소·반품) | `lib/features/claims/presentation/claims_screens.dart` `_ClaimLineRow` — 이름은 클레임 사본 → 주문 줄 → 뼈대 → "불러오지 못했어요 + 다시" 순서, 누르면 `/products/{id}` |
| 클레임 매핑 | `…/claims/data/claims_repository.dart` (claim 0.14.0 productName·optionLabel·imageUrl) |
| 시험 주소 | `lib/features/address/domain/address.dart` `DevTestAreas.all`(목포·세종 한누리대로 2130·춘천 중앙로 1·부산 남구 용소로 45) |
| 반품·교환 신청(만드는 중) | `…/claims/domain/return_request.dart`, `…/claims/data/return_request_repository.dart` |

상태 표시는 `UiState`/`UiStateView`/`uiStateOf` 패턴을 쓴다. 명령 결과는 `CommandDone`/`CommandRejected`/`CommandUnknown`이고, 재시도에는 같은 `IdempotencyKey`를 쓴다. 생성 클라이언트는 `dart tools/gen_api.dart --only=<서비스>`로 만들고 `contracts.lock`을 갱신한다.

---

## 3. 한 일 (2026-11-24, main `27a770f1`까지 푸시됨)

| 커밋 | 내용 |
|---|---|
| `bd43ace7` | 카테고리 화면에 늦게 끼어들던 줄을 고침(트리 뼈대·앱 시작 때 미리 읽기·배너/할인 줄 기다림). 처리 내역의 SKU 대신 안내 문구(BR-92 요청). 세종·춘천·부산 남구 시험 주소 추가 |
| `bc9d3445` | 배너가 첫 장이 아닌 곳(5번째)부터 보이던 것을 고침 |
| `447faac5` | BR-92: 처리 내역 품목 이름·사진을 클레임 사본에서 먼저 씀(claim 0.14.0). BR-93 주문 줄 이름 채우기 요청·회신 기록 |
| `98c70d26` | 처리 내역 품목(사진·이름)을 누르면 상품 상세로 감 |
| `27a770f1` | 속성 필터 2줄이 상품보다 늦게 끼어들던 것을 고침(최대 1초 격자 뼈대). 사용자가 말한 "2줄"은 속성 필터 줄이었다 |

백엔드 요청·회신:
- **BR-92** 반영(claim 0.14.0).
- **BR-93**: 백엔드가 R1만 함 — 주문 줄 18개, 클레임 줄 12개 이름 채움.
- **BR-94** 반영(product-service 0.6.0, 트리 v13 — LAN에서 직접 확인).
  - 맛있는것 13: 밥·도시락 → 라면·면 → 국·탕·찌개 → 분식·야식 → 쌀·잡곡·견과 → 정육·수산·계란 → 음료·커피·생수 → 주류 → 빵·떡·잼 → 아이스크림 → 우유·유제품 → 햄·어묵·통조림 → 유기농·친환경.
  - 편리한것 1: 문구·사무용품.
  - 노드 76개, 숨김 0. 앱은 `exposed != false`만 그리므로 바꿀 것이 없다. 앱을 다시 켜야 새 트리가 보인다.
- **오배송(ADR-0086, R-16)**: case 0.39.0이 LAN에 배포됨(백엔드 main `29396219`). 회신 `../pmart-backend/docs/handoff/clients/customer-app/2026-11-24-reply-misdelivery-inquiry-choice.md`. 고객앱은 아직 구현하지 않았다(§5-2).

폰 확인을 마친 것(11-24): 처리 내역 상품명, 카테고리 제목 왼쪽 여백, 홈 타일·배너로 들어가기, 배너 시작 위치, 시험 주소 버튼.

---

## 4. 커밋하지 않은 파일 (사용자가 "커밋해줘" 하면 같이 넣는다)

```
 M apps/customer_app/lib/features/claims/data/mock_claims_repository.dart   # takenQtyByLine·fileCustomerReturn (반품·교환 목)
 M docs/backend-requests.md                                                 # BR-94 → 반영
 M docs/worklog/customer-app/2026-11-24.md                                  # BR-94 결과·오배송 회신 기록
?? apps/customer_app/lib/features/claims/data/return_request_repository.dart
?? apps/customer_app/lib/features/claims/domain/return_request.dart
?? docs/handoff/customer-app/2026-11-24-backend-category-sections-order.md  # BR-94 요청서
?? docs/handoff/customer-app/2026-11-24-backend-misdelivery-screen-design.md # 오배송 화면 설계·Q1~Q7
?? docs/operations/customer-app-handover.md                                  # 이 문서
```
- 반품·교환 코드 두 파일은 `flutter analyze`를 통과했지만 아직 어느 화면에도 연결하지 않았다. 반품·교환 화면까지 만든 뒤 한 커밋으로 넣는 편이 낫다. 문서만 먼저 커밋하라고 하면 나눠도 된다.

---

## 5. 남은 일 (우선순위 순)

### 5-1. 반품·교환 앱 신청 — A안 (사용자: "A로 해줘 일단 목업과 백엔드요청서만", "저녁에 작업하자")
- 결정: 고객이 앱에서 반품·교환 클레임을 **직접 접수**하고, 처리는 서버와 상담원이 한다.
  - 지금 계약(claim 0.2.0, ADR-0060 결정 2)은 인계 뒤 반품을 고객센터에서만 받는다. 그래서 ADR 변경 요청이 필요하다.
- 범위: **목 화면 + BR-95 요청서만** 만든다. 화면 디자인은 "여태까지 한거로 맞춰줘", 즉 지금 앱의 카드·간격·버튼과 맞춘다.
- 레퍼런스: `docs/customer-app-design/12. 반품·교환 (배송완료)`
- 이미 만든 것:
  - `return_request.dart`: `ReturnRequestType`, `ReturnReasonGroup`(변심·실수 / 상품문제 / 배달문제), `ReturnReason` 13개, `ReturnableLine`(신청 가능 수량·변심 가능·신선보장), `UnavailableLine`, `ReturnEligibility`(배달팁 서버 값·회수 주소), `ReturnRequestDraft`, `returnDetailMax=200`, `returnPhotosMax=3`, `returnDraftProblems()`(문제 사유면 상세 이유·사진 필수, 변심이면 변심 불가 품목을 고를 수 없음).
  - `return_request_repository.dart`:
    - 인터페이스 `eligibility`·`submit`.
    - `UnavailableReturnRequestRepository`(실서버용 — 신청 불가를 답하고, submit은 422 `UNSUPPORTED_ACTION`).
    - `MockReturnRequestRepository`: 주문 목의 전달 수량을 쓰고, P-0003·P-0004를 신선식품으로 보며, 배달팁 9,000을 흉내 낸다. 같은 키로 다시 보내면 같은 클레임을 준다.
    - `wireReason`: 앱 이유 → 계약 ClaimReason.
  - `mock_claims_repository.dart`: `takenQtyByLine(orderId)`, `fileCustomerReturn(...)`(변심이면 FEE_PENDING — 지금 처리 내역의 회수비 결제로 바로 이어짐).
- 남은 것:
  1. provider: 목 env는 `MockReturnRequestRepository`(주문·클레임 목 인스턴스 공유), local은 `UnavailableReturnRequestRepository`.
  2. 신청 명령 컨트롤러: 같은 키로 재시도하고 결과를 모르면 `CommandUnknown`을 유지한다(중복 접수를 막는 잠금).
  3. ARB 문구(접두 `rr`) 추가 → `flutter gen-l10n`.
  4. 화면 ①: 진입 화면 "어떤 처리를 원하세요?"(반품 / 교환, 자격이 없으면 흐리게 + 고객센터 문의).
  5. 화면 ②: 신청서.
     - 품목: 체크·수량 조절, "교환 제한"·"신선보장" 표시, 신청할 수 없는 상품은 펼치기 안에 흐리게.
     - 이유 탭 + 라디오. 상세 이유 0/200, 사진 최대 3장(문제 사유면 필수).
     - 방법: 라이더 회수·재배달. 변심이면 배달팁 서버 값을 보이고, 회수지·라이더 요청사항은 시트로 받는다.
     - 결제 정보, 아래 신청 버튼.
     - 뒤로 가기에 "교환 신청을 취소할까요?" 확인.
     - 접수하면 처리 내역(클레임 상세)으로 보낸다. 접수는 승인이 아니다.
  6. 라우트 `/orders/:orderId/return-exchange`. 주문 상세 [반품·교환] 버튼을 여기로 연결한다(지금은 `/support/inquiries/new` 환불 문의로 감).
  7. 시험(바꾼 파일만, §1-2 메모리 규칙). 캡처를 레퍼런스 12와 나란히 비교한다.
  8. **BR-95 요청서** `docs/handoff/customer-app/<날짜>-backend-customer-return-exchange.md`와 `backend-requests.md` 줄. 넣을 내용:
     - 고객 RETURN/EXCHANGE 접수(`POST /claims` channel CUSTOMER_APP 허용, ADR-0060 결정 2 변경).
     - 품목별 신청 자격 조회: 신청 가능 수량, 변심 가능, 신선보장, 품목별 반품 기한(일반 7일·신선 24h).
     - 사진 올리기 API, 라이더 요청사항(회수·재배달), 이유 대응(CHANGE_OF_MIND·ADDRESS_ERROR·NOT_AS_ADVERTISED·DEFECT·DAMAGED_IN_DELIVERY·WRONG_ITEM·MISSING_ITEM), 회수비(배달팁) 금액 견적.
- 같이 볼 질문: 사용자가 "배송 완료 4일이 지났는데 반품·교환 버튼이 뜬다"고 했다. 기한은 서버 값으로만 막아야 하므로 BR-95의 품목별 기한에 넣는다.

### 5-2. 오배송 "상품을 받지 못했어요" (계약 나옴 — 구현은 사용자 지시를 기다림)
- 설계: `docs/handoff/customer-app/2026-11-24-backend-misdelivery-screen-design.md`
  - D1: 배달 중·일부 도착·배달 완료에 진입 → 확인 화면(레퍼런스 9-2 3-3. 통화·실시간 상담 버튼은 계약에 없어 뺌).
  - D2: 문의 상세의 선택 카드.
  - D3: 진행은 서버 상태 그대로 보인다.
- 회신 요점(case 0.39.0):
  - 접수: `POST /inquiries {category: DELIVERY, orderId, deliveryIssue: NOT_RECEIVED, body(필수)}`. `deliveryId`가 없으면 서버가 최근 전달 완료 배송을 고른다.
  - 응답에 `misdelivery`(state AWAITING_CHOICE·CHOSEN, options, deadlineAt, resolution, chosenByType CUSTOMER·STAFF·AUTO, autoResolved)가 붙는다. 없으면 일반 상담 문의다.
  - 대화: `GET/POST /inquiries/{id}/messages`. senderType은 SUPPORT·CUSTOMER·RIDER·SYSTEM이고, systemKind는 MISDELIVERY_CHOICE_REQUEST·CHOSEN이다. 버튼은 `misdelivery` 구조 값으로 그린다.
  - 고르기: `POST /inquiries/{id}/misdelivery-choices {resolution: RESHIP|REFUND}` → 200 Inquiry. 거절 코드:
    - 409 MISDELIVERY_ALREADY_CHOSEN
    - 409 MISDELIVERY_CHOICE_EXPIRED(상세를 다시 읽는다)
    - 404 MISDELIVERY_NOT_FOUND
    - 400 VALIDATION_FAILED
  - 5시간 안에 고르지 않으면 서버가 자동으로 REFUND한다. 새 푸시는 없다.
  - 목록 줄의 `misdeliveryState`·`misdeliveryDeadlineAt`으로 "고르기 기다림 · HH:mm까지" 꼬리표를 단다.
  - 고객 이어 쓰기 거절: 409 INQUIRY_CLOSED, 403 ACCOUNT_RESTRICTED, 422 BLOCKED_WORDS.
  - 한계: 이 판 배포 전에 만들어진 배송은 선택 흐름이 열리지 않고 상담원 문의가 된다.
- 시작하면: `dart tools/gen_api.dart --only=case`(contracts.lock 갱신) → 목 → 화면 → 시험.

### 5-3. 폰 확인 (사용자가 하나씩 함 — 폰이 연결되면 debug 설치)
- 11-24에 고쳤지만 폰에서 아직 보지 못한 것:
  - 속성 필터 줄 기다림.
  - 처리 내역 품목을 누르면 상품 상세.
  - BR-94 카테고리 묶음·순서(앱을 다시 켠 뒤).
- 11-23 것: 검색 결과·필터 깜박임(초안 16), 찜 격자(07), 주문 상세 ⊕·알림, 문의(17·18), FAQ 의견, 리뷰 신고, CU-7 제한 안내.
- 홈 팝업·배너·쿠폰: LAN 시험 데이터 4개가 **승인 대기**다(LD-31bba49a·AP-7a5607cd). 사용자가 승인해야 앱에 보인다.

### 5-4. 정리
- 폰 확인이 끝나면 BR-85~91과 lan-seed handoff를 `docs/handoff/archive/`로 옮기고, `docs/handoff/README.md`와 `backend-requests.md`의 상태를 고친다.
- 사설 CA 정리 여부를 사용자에게 다시 묻는다(§1-3).
- 메모리를 쌓는 시험 파일 찾기(`tools/flutter_test_mem.ps1`)는 아직 하지 않았다.

---

## 6. 시작할 때 확인할 것
```bash
git status --short && git log --oneline -5
ls ../pmart-backend/docs/handoff/clients/customer-app/ | tail   # 새 회신
cat docs/worklog/customer-app/2026-11-24.md | tail -20
```
작업은 `docs/worklog/customer-app/<날짜>.md`에 기록한다(형식 `docs/worklog/README.md`).
