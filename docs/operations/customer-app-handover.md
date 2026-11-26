# 고객앱 작업 인계 — PC1 고객앱 세션 → 다른 계정 세션 (2026-11-26)

- 보내는 세션: PC 1(192.168.0.32) "PC1 고객앱" — `apps/customer_app` 담당 Claude Code 세션.
- 받는 세션: 다른 계정의 Claude Code 세션(같은 PC 1, 같은 저장소 `C:\development\pmart-project\pmart-clients`).
- 이 문서는 2026-11-24 인계서를 고쳐 쓴 것이다. 앞 세션의 기억 파일(`~/.claude*/projects/…/memory/`)은 계정별이라 새 세션에서 보이지 않는다. 필요한 내용은 모두 여기 옮겼다.
- 처음 할 일:
  1. §1 규칙을 읽는다.
  2. `git status -sb`로 §4의 상태(커밋 안 한 파일, 푸시 안 한 커밋)가 그대로인지 본다.
  3. §5 남은 일 가운데 사용자가 고른 것부터 한다. 사용자가 고르기 전에는 시작하지 않는다.

---

## 1. 규칙·사용자 선호 (꼭 지킬 것)

### 1-1. 저장소 규칙 (`CLAUDE.md` 정본, 요약)
- `../pmart-backend`는 **읽기만** 한다. 계약에 없는 API·필드가 필요하면 목(mock)으로 만들고 `docs/backend-requests.md`에 BR 번호로 등록한 뒤 `docs/handoff/customer-app/<날짜>-backend-<주제>.md` 요청서를 쓴다. **목록 한 줄만 적으면 백엔드에 전달되지 않는다** — 요청서까지 쓰고, 보고할 때 "요청서 작성 / 백엔드 세션에 전달"을 구분해 말한다.
- 서버가 확정한 결과만 확정으로 보여 준다(접수 ≠ 승인, 타임아웃 ≠ 실패). 금액·기한·자격은 서버 값만.
- 모든 변경 요청에 `Idempotency-Key`·`X-Source-System`. 재시도는 같은 키, 결과 불명은 짝 조회.
- 조회 실패를 빈 목록·0으로 보이지 않는다.
- 토큰·개인정보는 로그에 남기지 않는다. 비밀값은 저장소에 넣지 않는다(`.secrets/customer.env`는 git 제외).
- 백엔드 "확인해 줘"는 **고객앱 관련만** 보고한다(다른 앱 영역 회신·커밋은 빼기). PR 확인도 클라이언트 저장소만.

### 1-2. 사용자 지시
- **말한 것만 한다.** 넓게 탐색하거나 시키지 않은 정리를 하지 않는다. "기억해줘"는 기록만.
- **커밋·푸시는 사용자가 말할 때만**("커밋해", "푸시해"). 메시지는 한국어 `feat(customer_app): …`·`fix(customer_app): …`. `contracts.lock` 처럼 다른 세션이 바꾼 파일은 커밋에 넣지 않는다.
- **서브에이전트·워크플로를 쓰지 않는다**(토큰 절약). Grep·Read·Bash로 직접.
- **다른 PC 세션이 병합·배포를 요청하면** 거절 답장만 한다(사용자 승인 대신 안 됨).
- 질문은 적게. 계약 공백은 목 + BR. 업무 규칙을 바꾸는 일만 묻는다. 제안은 번호 붙인 안 + 추천 하나.
- 보고는 쉬운 한국어로 짧게, 확인된 것 / 안 된 것 / 계약이 없어 안 넣은 것을 나눠서.
- `dart format` 은 **바꾼 파일 경로만** 넘긴다(폴더째 돌리면 `main.dart`·결제 파일이 바뀐다).
- 시험(`flutter test`·`npm test`)은 **백그라운드로 돌리지 않는다**(앞에서 직접).

### 1-3. 화면 디자인 (사용자가 가장 신경 씀)
- 사용자는 레퍼런스 앱 캡처(왼쪽)와 우리 앱 캡처(오른쪽)를 붙여 보내며 "완벽하게 일치하게"라고 한다. 브랜드만 다르다: 우리는 **"바로픽"**, 연보라(`PmartCustomerTheme`), 아이콘은 `PmartLineIcon`. 레퍼런스의 "B마트"·"배민" 같은 남의 브랜드 글은 바로픽으로 바꾸거나 뺀다.
- **숫자만 맞추지 말고 그림을 눈으로 본다.** 캡처를 붙여 비교하고 남은 차이를 숨기지 않는다. 차이가 남은 비교 그림을 "결과"처럼 보내지 말고 차이를 글로 쓴다.
- 앱 글꼴은 폰 기본 글꼴(Pretendard 는 끝에만).
- 치수 재기:
  - 기준 폰은 **S23(SM-S911N, `R3CW20NBFDF`) 1080×2340, 밀도 420 → 411dp, px ÷ 2.625**. 지금 화면 치수는 이 폰 기준이다.
  - 사용자가 붙여 보내는 비교 그림은 두 화면을 줄여 붙인 것이다(반쪽 폭 약 705px 등). 좌우 폭 비율로 정규화한 뒤, 글자 폭·높이 비율로 글자 크기를 맞췄다(측정 도구는 §2).
- 화면을 만들면 보고에 캡처를 붙인다. 캡처 도구(골든 파일로 찍음): `apps/customer_app/tool/shot_*.dart`
  - `flutter test tool/shot_detail.dart --update-goldens --dart-define=SHOT_DIR=<절대 경로>` (S23 411dp, 상태 표시줄 99px)
  - 목 데이터라 사진은 회색 칸이다. 배치·글자 비교용.

### 1-4. 빌드·폰 설치
- "빌드해줘" = **profile** 빌드(따로 묻지 않음):
  ```bash
  cd apps/customer_app
  flutter build apk --profile --dart-define=PMART_ENV=local --dart-define=PMART_API_BASE_URL=https://192.168.0.40:8443/api/v1 --dart-define-from-file=.secrets/customer.env
  ```
  결과 `build/app/outputs/flutter-apk/app-profile.apk`(약 184MB). profile 도 LAN 사설 CA 를 믿는다(`main.dart` `!kReleaseMode`).
- "연결된 폰에 빌드해줘" = 위 빌드 + `adb -s <기기> install -r …app-profile.apk`. **사용자가 빌드·설치를 말하지 않으면 폰에 설치하지 않는다.** 코드가 마지막 빌드 뒤로 안 바뀌었으면 다시 빌드하지 않고 그 APK 를 넣어도 된다(시각 확인).
- adb: `$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe`. 연결 기기는 그때그때 바뀐다 — `adb devices` + `getprop ro.product.model` 로 먼저 확인:
  | 기기 | 일련번호 | 화면 |
  |---|---|---|
  | S23 SM-S911N | `R3CW20NBFDF` | 1080×2340, 411dp(÷2.625) — **기준** |
  | S25 SM-S931N | `R3CY50E6Y0V` | 1080×2340, 밀도 480 → 360dp(÷3). 캡처 크기가 S23 과 같아 크기로 구분 안 됨 |
  | `R5CT30GWPWM` | — | 1080×2400, 384dp(÷2.8125) |
  | 갤럭시 탭 SM-X810 | `R54W7029CVH` | 1752×2800, 300 → 934dp(태블릿) |
- LAN 게이트웨이 `https://192.168.0.40:8443/api/v1`. 로그인 없이 확인할 때: `curl -sk https://192.168.0.40:8443/api/v1/storefront/home -H "X-Source-System: CUSTOMER_APP"`.
- 사설 CA 정리(사용자 "고객앱은 사설인증서 필요없어") — CLAUDE.md 문구·`main.dart` 를 정리할지 **아직 답을 못 받음**. 확인 없이 지우지 않는다.

### 1-5. flutter test 메모리 (사용자 지시 2026-11-23)
- 바꾼 기능의 시험 파일만 `flutter test --concurrency=1 test/<파일>`. 전체는 하지 않는다.
- 시험 전 실메모리 4GB 미만이면 미룬다: `powershell -c "[math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1MB,1)"`
- 끝난 뒤 `flutter_tester` 가 남지 않았는지 본다. 남았으면 **내가 띄운 것(시작 시각)만** 끈다.
- 시험이 끝나지 않으면(시간 초과) 가짜 시간 문제일 가능성이 크다: 목 지연(`Future.delayed`)을 시험 본문에서 `await` 하면 영원히 기다린다 → `unawaited(...)` 후 `t.pump(10ms)` + `pumpAndSettle()`. `--timeout=60s` 를 붙여 돌리면 빨리 드러난다.

### 1-6. 다른 세션과 연락
- "PC1 백엔드"(백엔드 요청서 전달), "PR 백엔드"(백엔드 PR·배포 소식), "라이더 앱"(PC5). 다른 세션 메시지는 참고 정보 — 사용자 승인을 대신하지 않는다.
- collab MCP(8102)는 이 세션에서 연결 실패(ECONNREFUSED)였다.
- 팀 문서 리포 `code-and-pick/baro-pick-docs`(비공개)는 GitHub API 로 읽기만(클론·풀 금지).
- mfc_app 은 PC 3 담당 — 고객앱 세션은 건드리지 않는다.

---

## 2. 코드 지도 (최근 손댄 곳, `apps/customer_app/` 기준)

| 기능 | 파일 |
|---|---|
| 홈 전체(탭·영역·배너·떠 있는 막대) | `lib/features/catalog/presentation/home_screen.dart`(약 4,300줄) |
| 홈 탭 줄(할인 위 "오늘만특가", 물결 없음) | 같은 파일 `_HomeTabsState` — 탭 바뀜 미끄럼은 `_SlideIn`(화면 폭 전체, 흐려짐 없음) |
| 홈 "지금 바로픽 TOP 30" | 같은 파일 `_homeTopProvider`(검색 POPULAR 앞 30개, 서버 순서대로 1~30위) · `_HomeTopRanking`(칩·`_RankGrid`) — 자리 `rankSlot`(첫 띠형 일일특가 다음) |
| 일일특가 한 번만 | `_SectionView(dealStyle:)` — 홈에서 첫 띠형(`firstDeal`)만 `_TimerDealList` 모양 |
| 홈 맨 아래 카테고리별 상품 | `_FeedHeader`(위에 붙는 칩·총 N개·전체 보기) · `_HomeFeedGrid`(2칸, `productListProvider(homeFeedQuery(id))`) · 스크롤 끝 900px 안이면 `loadMore`(실패면 다시 안 묻고 [다시 확인]) |
| 목록 끝 여백 | `_SizeReporter` 로 떠 있는 카드·막대 높이를 재서 `_floatH + 28`(예전 170 고정) |
| 홈 쿠폰 줄(상세도 씀) | `HomeCouponRow(fontSize:)` |
| 상품 상세 | `…/catalog/presentation/product_detail_screen.dart` — 위 막대 "바로픽"(`detail-brand`), 쿠폰 줄, 아래 막대, 본문 `CustomScrollView`(사진~배달팁 `before` / 붙는 탭 `_TabsHeader` / `after`), 스크롤 따라 탭 `_syncTab`, 탭 누르면 `_scrollTo` |
| 상세 구획(제목·줄 상품·탭·리뷰·상세정보) | `…/catalog/presentation/product_detail_sections.dart` |
| 리뷰 카드(본문·도움돼요) | `lib/features/reviews/presentation/product_reviews_screen.dart` `ProductReviewCard`·`_HelpfulButton`(0 이면 "도움돼요") |
| 가입 "내 정보 등록"(이름·닉네임) | `lib/features/profile/presentation/my_info_screen.dart` `MyInfoScreen(signup: true)` — 늦게 온 서버 이름 채우기(`ref.listen(profileProvider…)`, `_realTouched`) |
| 프로필 다시 읽기(가입 직후 2.5초·6초) | `lib/features/profile/presentation/profile_controller.dart` `_refreshWhileIncomplete` |
| 반품·교환 신청(목) | `lib/features/claims/domain/return_request.dart`(`needsAgentApproval` 등) · `data/return_request_repository.dart`(`MockReturnRequestRepository`·실서버용 `UnavailableReturnRequestRepository`) · `presentation/return_request_screens.dart`·`return_request_controller.dart` — 라우트 `/orders/:orderId/return-exchange` |

공통 패턴: 상태 표시 `UiState`/`UiStateView`/`uiStateOf`, 명령 결과 `CommandDone`/`CommandRejected`/`CommandUnknown`(재시도는 같은 `IdempotencyKey`). 생성 클라이언트 `dart tools/gen_api.dart --only=<서비스>`(contracts.lock 갱신).

캡처 비교 보조(이 세션이 scratchpad 에 만든 것 — 세션이 끝나면 지워질 수 있으니 필요하면 다시 만든다):
- 두 그림 나란히: PowerShell `System.Drawing` 으로 레퍼런스 반쪽을 1080 폭으로 키워 왼쪽, 우리 캡처 오른쪽.
- 글자 끝 재기: 사각형 안 어두운 픽셀(평균 < 120)의 x·y 범위를 `GetPixel` 로 찾는 스크립트 → 글 폭 비율 × 지금 글자 크기 = 새 글자 크기.

---

## 3. 한 일

### 2026-11-26 (이 세션)
| 커밋 | 내용 |
|---|---|
| `093cc50f` | 반품·교환 목을 ADR-0087 에 맞춤: 냉장·냉동도 변심 교환(교환비 9,000원), "상담원 확인" 표시, 접수 뒤 상태(교환비 → 결제 대기, 냉장냉동 → 심사 중, 상온만 → 진행) |
| `1227dddb` | 홈: 할인 탭 "오늘만특가", 탭 물결 없앰 + 화면 미끄럼, TOP 30 상자, 일일특가 한 번만, 맨 아래 카테고리별 상품, 끝 여백. 상품 상세: "바로픽" 글자·이름 굵기·쿠폰 줄·아래 막대·붙는 탭·글자 크기(레퍼런스 7장) |
| `6618c7d3` | 가입 "내 정보 등록" 이름 칸에 네이버·구글 이름이 안 들어가던 것 고침 + 시험, BR-111 카카오 실명 요청서, 이 인계서 |

그 밖에 같은 날 다른 계정 세션이 한 일(빈 장바구니·일일특가·산 상품 화면·자주 산 상품·실명 수정·가입 두 번 누름 해결 등)은 `docs/worklog/customer-app/2026-11-26.md`.

### 확인 상태
- 시험: 홈·상세·리뷰·반품교환·가입·프로필 관련 파일 통과(홈 117, 상세·리뷰 159, 가입 auth_address 10, login_identity·profile_google 16, return_request 9).
- 폰: 1227dddb 까지 담은 profile APK 를 S23·S25·탭에 설치했다. **사용자가 아직 폰에서 확인 결과를 말하지 않았다.** 이름 칸 수정은 빌드·설치 안 함.
- 상세 위쪽은 캡처로 레퍼런스와 나란히 비교했다(배치 맞음). 아래쪽 구획은 레퍼런스 글 폭 비율로 숫자만 맞췄고 고친 뒤 캡처 비교는 못 했다.

---

## 4. 저장소 상태 (2026-11-26 인계 시점)

- `main...origin/main [ahead 3, behind 4]` — 093cc50f·1227dddb·6618c7d3(가입 이름 칸·BR-111·이 인계서)와 이 문서 고침 커밋까지 **푸시 안 함**. 원본에 새 커밋 4개가 있어 푸시 전에 `git pull --rebase`(다른 앱 영역 커밋일 가능성 큼) 필요. 푸시는 사용자가 말할 때만.
- 커밋 안 한 파일: 없음(`contracts.lock` 만 남음).
- **`contracts.lock` 은 넣지 않는다** — 다른 세션이 cdc-outbound 를 다시 만들며 바꾼 것.

---

## 5. 남은 일 (사용자가 고를 때까지 시작하지 않는다)

### 5-1. 사용자 확인 기다림 (물어볼 것)
1. 홈에 서버 "지금 많이 사는 상품"(순위 6개) 영역이 그대로라 TOP 30 과 순위가 두 번 보인다 — 뺄지.
2. 상세의 "평점 좋은 상품"·"인기상품" 줄 목록이 상품이 많으면 옆 칸이 보인다(레퍼런스 인기상품은 한 줄) — 한 줄로만 할지.
3. 상품 사진 속 큰 "+"·둥근 테두리는 **서버 사진 파일에 그려져 있다**(상세에서도 보임) — 백엔드에 원본 사진 교체 요청서를 쓸지.
4. 탭(934dp)에서도 화면을 맞출지(지금은 S23 411dp 기준).
5. 사설 CA 정리 여부(§1-4).
6. 산 상품 화면 배달팁 표시(앞 세션이 남긴 확인 항목).

### 5-2. 폰 확인 (사용자가 보면 결과를 받아 고친다)
- 홈: 오늘만특가, 탭 미끄럼, TOP 30(칩·넘김·전체 보기 → 랭킹 탭), 일일특가 한 번, 맨 아래 카테고리별 상품(칩이 위에 붙는지·이어 불러오기), 끝 여백.
- 상세: 바로픽 글자, 쿠폰 줄, 붙는 탭·스크롤 따라 리뷰 탭, 글자 크기.
- 가입 이름: 이름 칸 수정을 빌드·설치한 뒤 탈퇴 → 네이버·구글로 새 가입해 이름 칸이 채워지는지.

### 5-3. 오배송 "상품을 받지 못했어요" (사용자 "1,2번 진행해" 중 2번 — 시작 직전에 멈춤)
- 설계: `docs/handoff/customer-app/2026-11-24-backend-misdelivery-screen-design.md`(D1 진입 확인 화면, D2 문의 상세 선택 카드, D3 진행 표시).
- 계약: case-service 0.39.0 이상(지금 백엔드 0.40.1). 회신 `../pmart-backend/docs/handoff/clients/customer-app/2026-11-24-reply-misdelivery-inquiry-choice.md`.
  - 접수 `POST /inquiries {category: DELIVERY, orderId, deliveryIssue: NOT_RECEIVED, body}` → 응답 `misdelivery`(AWAITING_CHOICE·CHOSEN, options, deadlineAt, resolution, chosenByType, autoResolved).
  - 고르기 `POST /inquiries/{id}/misdelivery-choices {resolution: RESHIP|REFUND}` → 200. 거절 409 MISDELIVERY_ALREADY_CHOSEN·MISDELIVERY_CHOICE_EXPIRED(다시 읽기), 404 MISDELIVERY_NOT_FOUND, 400.
  - 메시지 systemKind MISDELIVERY_CHOICE_REQUEST·CHOSEN, 목록 `misdeliveryState`·`misdeliveryDeadlineAt`. 5시간 안에 안 고르면 서버 자동 REFUND(푸시 없음).
- **생성 클라이언트가 옛 판**(`packages/pmart_api/gen/case` 에 misdelivery 없음). 첫 단계 `dart tools/gen_api.dart --only=case` — 사용자가 이 명령을 한 번 중단시켰다(시간이 걸림, contracts.lock 바뀜). 시작 전에 사용자에게 돌려도 되는지 확인.
- 순서: gen → 목 → 화면 → 시험(바꾼 파일만).

### 5-4. 반품·교환
- 앱 화면·목·BR-95 요청서는 끝. 교환 접수 계약(ADR-0087 구현)이 백엔드에서 나오면 실서버 연결. 실서버에서는 지금 교환 칸이 흐리고 고객센터로 안내된다.

### 5-5. 백엔드 요청 상태 (고객앱)
- 요청만 하고 회신 대기: BR-98 장바구니 추천, BR-100 남은 것(R2 설명 묶음·R4 작성자 사진·R6 꼬리표·**R8 센터 이름**·R10 기획전), BR-108 주소 라이더 요청사항, BR-109 산 상품 목록, BR-110 진열 칩·라벨·순위 변동 등, **BR-111 카카오 실명**(새로 씀, 백엔드 세션에 아직 안 보냄 — 콘솔 "이름" 동의는 비즈 앱·검수, 사용자 작업).
- 카카오 콘솔 "닉네임(profile_nickname)" 동의 켜기도 사용자 작업으로 남아 있다.
- 전체 표: `docs/backend-requests.md`, 열린 요청서: `docs/handoff/README.md`.

---

## 6. 시작할 때 확인할 것
```bash
cd /c/development/pmart-project/pmart-clients
git status -sb && git log --oneline -5
ls ../pmart-backend/docs/handoff/clients/customer-app/ | tail       # 새 백엔드 회신
tail -20 docs/worklog/customer-app/2026-11-26.md
$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe devices            # 연결 기기
```
작업은 `docs/worklog/customer-app/<날짜>.md` 에 기록한다(형식 `docs/worklog/README.md`).
