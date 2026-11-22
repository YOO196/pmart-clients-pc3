# PC 3 다음 세션 이어받기 — MFC 백오피스 웹 (2026-11-21 저녁 작성)

> 새 세션은 이 파일부터 읽고 "바로 할 일"부터 시작한다.
> 답은 늘 한국어로 한다. 규칙은 `CLAUDE.md`·`docs/operations/pc-split.md` 를 따른다.

## 시작할 때 보낼 말 (복사용)
```
docs/worklog/mfc-backoffice/2026-11-21-next-session.md 읽고 이어서 해. 먼저 git fetch 로 main 과 내 PR 상태를 보고, 백엔드 회신 새로 온 것 있는지 확인한 다음 "바로 할 일" 1번부터.
```

## 읽는 순서
1. 이 파일 — 지금 상태·바로 할 일·지킬 것.
2. `CLAUDE.md` — 절대 규칙(백엔드 읽기만, 계약에 없는 API 추측 금지 → 목 + 요청서, 서버 확정만 확정 표시).
3. `docs/apps/mfc-backoffice-web.md` §4-15 — 오늘 만든 실시간 관제(대시보드·센터 도면)·관제실 겉모습 정리. 그 밖 메뉴는 §4-0~4-14.
4. `docs/worklog/mfc-backoffice/2026-11-21.md` — 오늘 일지(사용자 말 그대로·결정·확인 방법). 길면 맨 아래 절들부터.
5. 백엔드 회신(읽기만): `../pmart-backend/docs/handoff/clients/mfc-backoffice/` 의 2026-11-21 파일들
   - `2026-11-21-reply-hourly-and-order-metrics.md` — **아직 화면에 반영 안 함**(바로 할 일 2·3)
   - `2026-11-21-reply-dispatch-cancel-lines.md` — 반영 끝(`features/delivery/DispatchCancel.tsx`, lines 없이 보냄)
6. 열린 요청서: `docs/handoff/mfc-backoffice/2026-11-21-backend-*.md`(작업자 위치·시간대 지표·센터 주문 지표).
7. 필요할 때: `docs/operations/2026-11-21-notice-web-ui-tower-design.md`(다른 웹에 넘긴 디자인·움직임 CSS), 메모리 `pr-flow-pc1-merge`·`this-pc-is-pc3-mfc`.

## 내 담당 (PC 3)
- `web/mfc-backoffice`(+ `apps/mfc_app`). 공용 웹 `web/ui`·`web/core` 는 PC 2 — 고치지 말고 요청.
- 형제 저장소: `../pmart-backend`(읽기만), `../pmart-mfc-simulation`(도면 배치 참고, 읽기만).

## PR·배포 흐름 (꼭)
- 브랜치를 원격 `pc3`(YOO196/pmart-clients-pc3)에 푸시 → `gh pr create -R code-and-pick/pmart-clients -H YOO196:<브랜치>`.
- PC 1 이 커밋을 cherry-pick 해 main 에 넣고 PR 을 **닫는다**(merge 아님). 닫힌 PR 브랜치에 더 올리지 말고 새 브랜치로.
- 강제 푸시는 막혀 있다 → main 위로 rebase 한 것은 **새 이름 브랜치**(`…-pr`)로 푸시.
- 실서버 반영 확인: `curl -sk https://192.168.0.40:8445/version.txt` 첫 줄 커밋이 바뀌면 배포된 것. 사용자는 "배포되면 알려줘"를 자주 한다 → 1분 간격 확인을 백그라운드로 돌리고 알린다.
- 커밋·푸시·PR 은 사용자가 시킬 때만.

## 지금 상태 (2026-11-21 18시 무렵)
- 실서버 `https://192.168.0.40:8445` = `fe513a4b` — 여기까지 들어감: 관제실 겉모습(#347), 대시보드 B안·도면(#348), 센터 도면 메뉴(#351), 추이 그래프 끌기·기간 바(#355), 시간·일·주·월·1년·주문/매출(목)·결품 사유 막대(#359).
- **이번 PR(이 파일과 함께)**: 브랜치 `mfc/floor-panel-1121-pr` — 센터 도면 랙 선택 모양(보라, 큰 흰 테두리 없앰)·랙 칸 패널(칸 수·상품·재고·LOT·유통기한)·작업자 패널 정보, 대시보드 실사 잠김·닫힘 배지를 끝까지 셈, 목 서비스 워커 다시 연결(`keepMocking`), 앱 문서 §4-15, 이 파일. 배포 확인은 다음 세션이 이어서.
- 목업 사이트(사용자가 보는 것): `http://localhost:4176/c/MFC-BSN-01/dashboard`
  - 띄우기: `npx vite build --mode mock --outDir <scratchpad>/mfc-web-mock-b --emptyOutDir` 뒤 `npx vite preview --mode mock --outDir <같은 곳> --port 4176 --strictPort`(web/mfc-backoffice 에서, 백그라운드). 세션이 바뀌면 서버가 꺼져 있을 수 있다 → 다시 띄운다.
  - 바꾼 뒤에는 다시 빌드하면 된다(미리보기 서버는 그대로). 사용자 탭은 새로고침해야 새 코드 — 새로고침하면 목 로그인·목 데이터가 처음으로.
- 화면 확인: 헤드리스 크롬 CDP 스크립트로 캡처해 직접 본다(사용자가 "직접 보고 비교"를 요구). 예전 스크립트는 세션 scratchpad 에 있었다(없어졌으면 다시 만든다 — 목 로그인 단추 "센터 관리자(MFC 1곳)" 누르고 메뉴 링크로 옮겨 다니며 `Page.captureScreenshot`).

## 바로 할 일
1. ~~PR 배포 확인~~ — #364 main 반영·실서버 `cacc8f6a` 확인(2026-11-21 저녁).
2. ~~**피킹 지표 bucket 반영**~~ — 끝(브랜치 `mfc/picking-bucket-1123`, 일지 맨 아래 절). 아래는 기록용.(백엔드 회신 1, mfc-fulfillment 0.33.0 — LAN 배포 뒤): `GET /metrics/picking-lines?bucket=HOUR|DAY|WEEK|MONTH`.
   - `npm run gen:api -w web/mfc-backoffice` 로 타입 갱신 → `CenterDashboard.tsx` `fetchPicking` 이 단위에 맞는 bucket 으로 읽게(1년은 한 번에, 92일 나눠 읽기 정리). 피킹 줄·결품 막대의 "시간" 칸을 **실서버에서도** 켠다(지금은 목에서만 하루 합을 곡선으로 나눔 — `hourShare`).
   - 주의: 정시율 시간 칸은 아직 없음(DD-6, PC 5) → 정시율만 "시간" 끔. 주문·매출은 3번.
   - 목 핸들러(`mocks/taskHandlers.ts` picking-lines)에 bucket·hour 도 넣고 시험 고치기.
3. **주문·매출 지표는 사용자 결정 대기** — 백엔드가 order-service(PC 1) O-11 로 넘김. 센터 관리자(MFC_SUPERVISOR)에게 주문·매출을 열지 **사용자가 정해야** 한다(지금은 OPERATOR_ADMIN 만, 2026-11-18 O-8). 사용자에게 물어서 PC 1·백엔드에 전달. 열리기 전까지 주문·매출은 목 시뮬레이션(`orderSim.ts`) 그대로.
4. **"피킹 줄" 이름** — 사용자 "피킹 작업 수라고 하면 되잖아" → 같은 화면 "지금 작업"의 피킹 N건(작업 수)과 겹친다고 말했고, 대안 "피킹 상품 수(개)"를 냄. 사용자 답: **"일단 기다려봐"** — 사용자가 다시 말할 때까지 바꾸지 않는다.
5. 대시보드 배치: 추이 패널(주문 보기)이 길어져 왼쪽 센터 도면 패널 아래가 비어 보인다 — 다음에 손볼 수 있다고 말해 둠.
6. 관제실 CSS 정리: PC 2 가 공용 `web/ui/src/tower.css` 를 만들었다. MFC `src/index.css` 의 같은 블록(관제실 겉모습)과 겹치는지 보고, 공용을 `@import` 하고 MFC 쪽 중복은 지운다(MFC 만의 것 — 도면·차트·`--pm-cat-*` 은 남김). 바꾼 뒤 캡처로 전후 비교.
7. 정시 배송 시간 칸(DD-6, PC 5)·작업자 위치 API 가 생기면 시뮬레이션을 지우고 실제 값으로.

## 지킬 것 (오늘 사용자에게 들은 것 포함)
- 계약에 없는 값은 **목에서만 시뮬레이션** + 실서버는 "API 없음" 안내 + 백엔드 요청서(`docs/handoff/mfc-backoffice/<날짜>-backend-<주제>.md`, 첫머리 보낸 앱·받는 영역).
- 목업 먼저, 사용자가 "실서버에 올려줘/PR 해"라고 하면 그때 PR.
- 레퍼런스를 줄 때는 **충실히** 따르고, 만든 뒤 캡처로 **직접 나란히 보고** 판단한다("최선이냐고" 지적받음).
- 바(왼쪽 메뉴·머리줄) 크기·비례는 통합 백오피스와 같게. 탭 맨 위 설명 상자는 넣지 않는다.
- 움직임은 일이 벌어지는 곳에만, `prefers-reduced-motion` 짝 규칙 필수. 차트 색은 dataviz 팔레트 검사(`validate_palette.js`) 통과값.
- 색은 테마 변수로(하드코딩 금지 — 예외는 `index.css` 의 테마 변수 정의).
- 강제 푸시·PC 2 영역 수정·백엔드 수정 금지. 토큰·개인정보 로그 금지.
- 시험·lint·typecheck 는 실제로 돌린 것만 통과라고 말한다(`npm run typecheck|lint|test -w web/mfc-backoffice`, 지금 270 통과).

## 알아 둘 함정
- 칸(위치)이 수천 개 — 목록 첫 쪽(200)만 세면 숫자가 모자란다. `features/dashboard/floorQueries.ts` `fetchAllLocations` 로 거르기와 함께 끝까지.
- 목 서비스 워커가 브라우저에 의해 멈추면 목이 끊겨 "조회 실패"가 무더기로 뜬다 → `keepMocking` 이 다시 붙임(최대 20초, 창을 누르면 바로).
- Bash 에서 긴 heredoc 안의 따옴표가 자주 깨진다 → 고칠 내용은 scratchpad 의 파이썬 스크립트 파일로 쓰고 실행.
- `exactOptionalPropertyTypes` — 선택 속성은 조건부 펼침(`...(x ? { k: x } : {})`).
- 렌더 중 `Date.now()` 금지(lint) → `useNow`.
