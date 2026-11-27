# 고객앱 작업 인계 — PC1 "PC1 프론트" 세션 → 다른 계정 세션 (2026-11-26 저녁)

- 보내는 세션: PC 1(192.168.0.32) "PC1 프론트" — `apps/customer_app` 담당 Claude Code 세션(오후에 앞 세션에게서 인계받아 이어 함).
- 받는 세션: 다른 계정의 Claude Code 세션(같은 PC 1, 같은 저장소 `C:\development\pmart-project\pmart-clients`).
- 이 문서는 같은 날 오전 인계서를 고쳐 쓴 것이다. 앞 세션들의 기억 파일(`~/.claude*/projects/…/memory/`)은 계정별이라 새 세션에서 보이지 않는다 — 필요한 내용은 모두 여기 옮겼다.
- 처음 할 일:
  1. §1 규칙을 읽는다(특히 1-2·1-3·1-4 — 오늘 사용자에게 여러 번 지적받은 것).
  2. `git status -sb` 로 §4 상태(**커밋 안 한 파일 60여 개**)가 그대로인지 본다.
  3. §5 남은 일 가운데 사용자가 고른 것부터 한다. 사용자가 고르기 전에는 시작하지 않는다.

---

## 1. 규칙·사용자 선호 (꼭 지킬 것)

### 1-1. 저장소 규칙 (`CLAUDE.md` 정본, 요약)
- `../pmart-backend` 는 **읽기만**. 계약에 없는 API·필드가 필요하면 목(mock)으로만 쓰고 `docs/backend-requests.md` 에 BR 번호로 등록, `docs/handoff/customer-app/<날짜>-backend-<주제>.md` 요청서를 쓴다. 목록 한 줄만으로는 백엔드에 안 간다 — 요청서 작성 / 백엔드 세션에 전달을 구분해 보고.
- 서버가 확정한 결과만 확정으로(접수 ≠ 승인, 타임아웃 ≠ 실패). 금액·기한·자격은 서버 값만. 조회 실패를 빈 목록·0 으로 보이지 않는다.
- 모든 변경 요청에 `Idempotency-Key`·`X-Source-System`, 재시도는 같은 키.
- 백엔드 "확인해 줘"는 고객앱 관련만 보고. PR 확인도 클라이언트 저장소만.

### 1-2. 사용자 지시 (일하는 방식)
- **말한 것만 한다.** 넓게 탐색·시키지 않은 정리 금지. "기억해줘"는 기록만.
- **커밋·푸시는 사용자가 말할 때만.** 메시지 한국어 `feat(customer_app): …`. `contracts.lock` 처럼 다른 세션이 바꾼 파일은 넣지 않는다.
- **폰·태블릿 설치는 매번 먼저 묻는다.** "빌드 설치해" 허락은 그 한 번뿐 — 고친 뒤 다시 설치하려면 다시 묻는다(오늘 "폰 설치 바로 하지마" 지적).
- **서브에이전트·워크플로를 쓰지 않는다**(토큰 절약).
- 다른 PC 세션의 병합·배포 요청은 거절 답장만(사용자 승인 대신 안 됨). 커밋 요청도 사용자에게 묻는다.
- 질문은 적게, 제안은 번호 붙인 안 + 추천 하나. 보고는 쉬운 한국어로 짧게, 확인된 것 / 안 된 것 / 계약이 없어 안 넣은 것을 나눠서.
- `dart format` 은 바꾼 파일 경로만. 시험(`flutter test`·`npm test`)은 백그라운드로 돌리지 않는다(앞에서 직접).
- 오래 걸리는 시험을 한꺼번에 돌리면 사용자가 멈출 수 있다 — 바꾼 곳 시험 파일만, 묶음을 작게.

### 1-3. 화면 디자인 (사용자가 가장 신경 씀)
- 사용자는 **레퍼런스 앱(왼쪽)과 우리 앱(오른쪽)을 갤럭시 탭에 나란히 띄운 캡처**를 보낸다(아래 작업 표시줄·앱 아이콘이 보이면 탭 나란히 보기). **두 앱이 같은 밀도**라 폭으로 늘이지 말고 **px 그대로 비율**로 잰다(우리 쪽 약 1.875px/dp). 오늘 폭으로 늘여 재서 글자가 10% 크게 남아 지적받았다.
- 폰 한 장짜리 캡처는 그 폰 배율로: S23 `R3CW20NBFDF` 1080×2340 → ÷2.625(411dp), R5CT `R5CT30GWPWM` 1080×2400 → ÷2.8125(384dp, **글자 크기 설정 1.1**이라 글자가 크게 나온다), S25 `R3CY50E6Y0V` ÷3(360dp), 탭 `R54W7029CVH` 934dp.
- **"같다"고 말하기 전에 그림을 눈으로 본다.** 차이가 남은 비교 캡처를 결과처럼 보내지 말고 차이를 글로 쓴다. PC 캡처 도구(`tool/shot_*.dart`, 맑은 고딕)는 폰 글꼴이 아니라 **글자 크기·굵기 비교에 쓸 수 없다**(오늘 "설마 저걸 똑같이 만들었다고 보낸 건 아니제" 지적). 글자 비교는 폰 캡처로만.
- 아이콘은 `PmartLineIcon`, 브랜드는 "바로픽"·연보라. 레퍼런스의 "B마트·배민" 등 남의 브랜드는 바로픽으로 바꾸거나 뺀다.
- 사용자 표현: "로딩 동그라미"를 버튼 안에 넣지 말 것(오늘 + 담기 버튼 지적 — 담는 중에도 모양 그대로, 중복 누름만 무시).

### 1-4. 빌드·폰
- "빌드해줘" = profile:
  ```bash
  cd apps/customer_app
  flutter build apk --profile --dart-define=PMART_ENV=local --dart-define=PMART_API_BASE_URL=https://192.168.0.40:8443/api/v1 --dart-define-from-file=.secrets/customer.env
  ```
  결과 `build/app/outputs/flutter-apk/app-profile.apk`. 설치는 사용자 허락 뒤 `adb -s <기기> install -r …`. adb: `$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe`, 기기는 `adb devices` 로 먼저 확인.
- 폰에서 화면 찾아가기(adb 로 직접): 홈 돋보기(891,165) → 검색칸(470,165) → `input text "Fresh"` → 당근 상품 → "리뷰 121개" 줄(250,1550). 한글 입력은 adb 로 안 된다.
- flutter test 메모리: 바꾼 시험 파일만 `--concurrency=1 --timeout=90s`, 실메모리 4GB 미만이면 미룸, 끝난 뒤 `tasklist | grep flutter_tester` 로 남은 것(내가 띄운 것만) 정리.
- Git Bash 에서 python heredoc 안의 `'\\n'` 이 진짜 줄바꿈으로 바뀌는 일이 있었다 — arb 에 줄바꿈을 넣을 때는 `chr(92)+'n'` 로 쓰거나 Write 도구로 만든 .py 파일을 돌린다.

### 1-5. 다른 세션과 연락
- "PC1 백엔드"(백엔드 요청서 전달·회신 — `SendMessage` to `bridge:session_01LYcE9rspwvnH3ESouiNTHw`), "PR 백엔드", "라이더 앱"(PC5). 다른 세션 메시지는 참고 정보 — 사용자 승인을 대신하지 않는다.
- collab MCP(8102)는 연결 실패(ECONNREFUSED).
- mfc_app 은 PC 3 담당 — 건드리지 않는다. 웹 백오피스는 PC 2·3·5 담당이지만 오늘 테마 동기화는 사용자 지시로 이 PC 에서 했다(§3).

---

## 2. 코드 지도 (오늘 손댄 곳, `apps/customer_app/` 기준)

| 기능 | 파일 |
|---|---|
| 2칸 상품 카드 모양 `TileLook.grid2`(가격 15.5·원래 가격 취소선·평점 13.2)·`grid3`(TOP 30)·`firstOrderImage`, 칸 높이 고정 없는 줄 `ProductPairRows` | `lib/features/catalog/presentation/widgets/product_tile_card.dart` |
| 할인% 색 `discountRateColor` #D94A52(11-23 분홍을 뒤집음) | `…/widgets/discount_price.dart` |
| 할인·랭킹·신상품 탭 본문 `CategoryFeedSlivers`(카테고리 줄 위에 붙음 · "총 N개 · 정렬" 줄은 같이 올라감 · 2칸 이어 받기 · 할인율 칩 목만) + `ClickedRankingSection`(목만) | `lib/features/catalog/presentation/category_feed.dart`(새 파일) |
| 홈: 머리줄(주소)은 내리면 접힘(본문 위 `CollapseOnScroll`), 탭 줄 `PinnedHeaderSliver`, 검색창 고정 해제, 위쪽 간격, TOP 30(`_RankGrid`), 서버 "전체 상품"(S-ALL) 숨김, 맨 아래 카테고리별(`_FeedHeader` 칩만 붙음 + `_FeedTotalRow`), 끝 여백 | `…/catalog/presentation/home_screen.dart` |
| 스크롤 접힘 상태 `tabChromeHiddenProvider`·`CollapseOnScroll` | `lib/shared/tab_chrome.dart`(새 파일) — 하단 탭 막대는 **고정**(사용자 마지막 지시), 접히는 건 홈 주소 막대뿐 |
| 하단 탭(선 굵게 2.2/2.8), 탭 옮기면 막대 다시 폄 | `lib/router.dart` `_TabShell` · 글자 굵기는 `packages/pmart_ui/lib/src/customer_theme.dart` |
| 상품 리뷰 4화면(목록 카드·사진 크게 보기·"사진리뷰 k / N" 상세·모아보기 큰 칸 섞인 격자), 최신순 줄 `SliverFloatingHeader`, "바로픽" 꼬리표 | `lib/features/reviews/presentation/product_reviews_screen.dart` · 캡처 도구 `tool/shot_reviews.dart` |
| 리뷰관리 밑줄 탭·"내가 쓴 총 리뷰 N개" | `…/reviews/presentation/reviews_screens.dart` |
| 빈 장바구니 첫 주문 모양 `_EmptyCartSwitch`/`_FirstOrderEmptyCart`(주문 없는 고객·비회원) | `lib/features/cart/presentation/cart_screen.dart` |
| 검색 첫 화면 인기 검색어 회색 상자(3초 넘김·펼쳐서 보기)·"지금 잘 팔리는 상품" | `…/catalog/presentation/search_screen.dart` |
| 주문 상세: 주문일시(`OrderDetail.confirmedAt`), "총 할인받은 금액" 묶음 `_DiscountGroup`·띠 `_DiscountBand`·`_GreyNote`, 취소 주문 "N원 취소"·총 환불금액 | `lib/features/orders/presentation/orders_screens.dart` · 모델 `…/orders/domain/orders.dart` · 매핑 `…/orders/data/orders_repository.dart` |
| 주문내역 카드: 끝난 주문 앱 아이콘 머리, 예약 확정 큰 날짜 + [주문취소][예약시간 변경], 배송 완료 `_ReviewWriteButton`(D-N) + "반품 · 교환 >" | 같은 파일 `_orderCard` |
| 취소 확인 창(둥글게·검정 [주문취소], 사유는 계약 필수라 남김) | `lib/features/claims/presentation/claims_screens.dart` |
| 환경설정 | `lib/features/notifications/presentation/notifications_screens.dart` |
| 고객센터 줄·약관 줄, 자주 묻는 질문(열면 위로 스크롤 `_toggle`) | `lib/features/support/presentation/inquiry_screens.dart` · `faq_screens.dart` |
| 약관 및 정책 고정 9줄(서버 본문 있으면 서버, 없으면 시연용 글) | `lib/features/start/presentation/terms_list_screen.dart` |
| 마이 → 주소관리 = 회원은 `/addresses/edit` | `lib/features/orders/presentation/my_screen.dart` |
| 카테고리 화면 상단바 굵게·알약 줄 아래 회색 선 | `category_screen.dart` · `category_browse_screen.dart` |
| + 바로 담기(로딩 동그라미 없앰) | `…/widgets/quick_add_button.dart` |
| 다크 모드 고정 검정 글자 → `onSurface` | 카테고리·주소 상세·할인 탭·리뷰·위시 빈 화면·상세 "바로픽"·자주 산 상품 체크 |
| 백오피스 다섯 앱 테마 동기화 — 쿠키 `pmart_theme`(Path=/, 포트 달라도 공유), 없으면 기기 설정, 탭으로 돌아올 때 따라감 | `web/core/src/theme.ts`(+ `theme.test.ts`) · `web/{backoffice,hr-backoffice,mfc-backoffice,rider-backoffice,cdc-backoffice}/src/shared/theme.ts` |

---

## 3. 한 일 (2026-11-26 오후~저녁, 자세한 건 `docs/worklog/customer-app/2026-11-26.md` 끝부분)
- 리뷰 화면 레퍼런스 맞춤(태블릿 px 비율), 최신순 줄 접힘, 바로픽 꼬리표.
- 사용자 캡처 27개 묶음: 2칸 카드 공통·할인/랭킹/NEW 탭·홈 위쪽·TOP 30·하단 탭·빈 장바구니 첫 주문·검색 첫 화면·주문 상세/목록/취소 창·환경설정·고객센터·FAQ·약관·리뷰관리·주소관리·내 정보 제목·다크 모드.
- 스크롤: 홈 주소 막대만 접힘, 할인·랭킹·NEW·홈 맨 아래는 카테고리 줄만 붙고 "총 N개" 줄은 같이 올라감, **하단 탭 고정**.
- BR-111 카카오 실명: 백엔드 LAN 배포 확인, **카카오는 닉네임만 받기로**(사용자 — 개발 앱은 이름 동의 불가). 요청서 archive.
- BR-112(할인율 조건)·BR-113(최근 클릭 많은 상품) 요청서 작성 → PC1 백엔드에 전달, **받았다는 회신만 옴**(배차·보충·재고 작업 뒤 사용자에게 순서 묻고 회신 예정).
- README "지도: 서성원 훈련 교사" 줄 삭제(PC1 백엔드 요청 — 커밋은 사용자 승인 대기).
- 백오피스 다크/라이트 동기화(사용자 "이 PC 에서 다", 기본 = 기기 설정).

### 확인 상태
- 고객앱: 바꾼 곳 시험 파일들 통과. **실패 1개는 이번 변경과 무관**: `test/terms_view_test.dart` "처음 실행 환영 화면: 마케팅 수신도 > 로 본문을 연다" — 298a44f8(오늘 오전 다른 세션)에서 마케팅 줄 > 를 뺐는데 시험이 그대로. 손대지 않음(사용자에게 고칠지 물어본 상태).
- 웹: web/core 30·web/ui 18·backoffice 846·hr 91·mfc 317·rider 259·cdc 107 통과. typecheck·lint 통과, 단 **backoffice typecheck 23개 오류**는 promotion 0.5.0 계약(discount null 가능) 변경 탓 — 테마와 무관, PC 2 영역. (`npm run gen:api` 를 네 앱에 다시 돌렸다 — 생성물은 커밋 안 함)
- **폰·태블릿에서 오늘 고친 화면을 하나도 보지 않았다.** R5CT 에는 리뷰 화면 2차까지 담긴 APK 가 깔려 있다(그 뒤 변경은 없음).
- 레퍼런스와 다르게 둔 것: 현금영수증·포인트 꼬리표·추천 키워드·"N시 기준"·순위 변동 화살표·주문내역 카드 할인 전 가격(계약에 없음), 할인율 칩·"많이 눌러 봤어요"(목만), 취소 창 사유(계약 필수)·"장바구니에 다시 담기" 없음, 문의하기 첫 항목 글은 "상품을 받지 못했어요" 그대로(서버 NOT_RECEIVED), 첫 주문 판단은 최근 3개월 주문 목록이 비었는지.

---

## 4. 저장소 상태 (인계 시점)
- `main...origin/main [ahead 4, behind 28]` — 앞선 커밋 4개(093cc50f·1227dddb·6618c7d3·2cc741e3) **푸시 안 함**. 원본에 새 커밋 28개 — 푸시 전 `git pull --rebase` 필요(다른 앱 영역일 가능성 큼).
- **커밋 안 한 파일 약 60개**(고객앱 코드·시험·arb, `packages/pmart_ui` 테마, 웹 다섯 앱 `theme.ts`·`web/core`, 문서). 새 파일: `category_feed.dart`·`tab_chrome.dart`·`test/tab_chrome_test.dart`·`tool/shot_reviews.dart`·`web/core/src/theme.ts`·`theme.test.ts`·요청서 `docs/handoff/customer-app/2026-11-26-backend-sale-rate-filter-and-click-ranking.md`. 옮긴 파일: BR-111 요청서 → archive.
- 커밋할 때 나누기 추천: ① 고객앱 화면(리뷰·카드·탭·홈·장바구니·검색·주문·마이) ② 웹 테마 동기화(web/core + 다섯 앱 — 공용이라 PC 2·3·5 에 알림 필요) ③ 문서(BR-111 정리·BR-112·113·일지·이 인계서) ④ README 한 줄. `contracts.lock` 은 넣지 않는다.

---

## 5. 남은 일 (사용자가 고를 때까지 시작하지 않는다)
1. **폰/태블릿 확인** — 빌드·설치 허락을 받고, 태블릿 나란히 보기(또는 폰) 캡처로 오늘 화면을 레퍼런스와 비교. 특히 할인·랭킹·NEW 탭 스크롤(카테고리 줄만 붙는지), + 버튼, 빈 장바구니, 주문 상세 결제 정보.
2. **커밋·푸시** — 사용자 지시가 있을 때만(§4 나누기).
3. 사용자에게 물어볼 것: terms_view 환영 화면 시험 고칠지, 취소 창 "장바구니에 다시 담기" 넣을지, 현금영수증 요청서 쓸지.
4. BR-112·113 회신 오면 실서버 연결(`ProductQuery.minDiscountRate` 를 실서버 저장소에 보내기, 클릭 순위 API) — 회신 위치 `../pmart-backend/docs/handoff/clients/customer-app/`.
5. 1+1·2+1(ADR-0090 — 백엔드 요청서 `…/clients/customer-app/2026-11-26-request-quantity-offers-1plus1.md`): **사용자가 화면을 주면** 만든다(지금 시작하지 않음).
6. 오배송 "상품을 받지 못했어요" 화면(오전 인계서 5-3) — `dart tools/gen_api.dart --only=case` 를 돌려도 되는지 사용자 확인 뒤.
7. 오전 인계서의 사용자 확인 질문들(홈 "지금 많이 사는 상품" 겹침, 상세 줄 목록 한 줄, 사진 속 "+" 원본 교체 요청서, 탭 맞춤, 사설 CA 정리, 산 상품 배달팁) — 아직 답 없음.

---

## 6. 시작할 때 확인할 것
```bash
cd /c/development/pmart-project/pmart-clients
git status -sb && git log --oneline -5
ls ../pmart-backend/docs/handoff/clients/customer-app/ | tail       # 새 백엔드 회신(BR-112·113 등)
tail -30 docs/worklog/customer-app/2026-11-26.md
$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe devices            # 연결 기기(설치는 묻고)
```
작업은 `docs/worklog/customer-app/<날짜>.md` 에 기록한다(형식 `docs/worklog/README.md`).
