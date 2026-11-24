# PC 3 다음 세션 이어받기 — MFC 백오피스 웹 (2026-11-24 작성)

> 새 세션은 이 파일부터 읽고 "바로 할 일"부터 시작한다. `2026-11-21-next-session.md` 를 대신한다(그 파일의 "지킬 것"·"알아 둘 함정"은 그대로 유효 — 아래에 옮김).
> 답은 늘 한국어로 한다. 규칙은 `CLAUDE.md`·`docs/operations/pc-split.md` 를 따른다.

## 시작할 때 보낼 말 (복사용)
```
docs/worklog/mfc-backoffice/2026-11-24-next-session.md 읽고 이어서 해. 먼저 git fetch 로 main·배포 상태와 내 PR 을 보고, 백엔드 회신 새로 온 것 있는지 확인한 다음 "바로 할 일" 1번부터.
```

## 읽는 순서
1. 이 파일.
2. `CLAUDE.md` — 절대 규칙(백엔드 읽기만, 계약에 없는 API 추측 금지 → 목 + 요청서, 서버 확정만 확정 표시, flutter test 메모리 규칙).
3. `docs/worklog/mfc-backoffice/2026-11-23.md` — 지난 세션 일지(피킹 bucket·주문·매출 실값·배송 통계·시험 간헐 실패).
4. `docs/apps/mfc-backoffice-web.md` — 메뉴별 화면(§4-0~4-15, 배송 통계는 4-4b 앞 줄).
5. 백엔드 회신(읽기만): `../pmart-backend/docs/handoff/clients/mfc-backoffice/` 새 파일.
6. 메모리 `pr-flow-pc1-merge`·`this-pc-is-pc3-mfc`·`no-subagents`.

## 지난 세션(2026-11-23)에 한 것 — 모두 main 에 들어감
| PR | 내용 | main 커밋 |
|---|---|---|
| #387 | 짧은 화면 번호(ADR-0085) — mfc_app·백오피스 라이더 `R4829`, 배송 `D…` | 03687011 |
| #388 | 피킹 지표 `bucket=HOUR|DAY|WEEK|MONTH` — 피킹 줄·결품 "시간" 칸 실서버에서도 | 33657554 |
| #396 | 대시보드 주문·매출 실서버 값(order 0.20.0 O-11) — 사용자 결정 "센터 관리자에게 연다, 자기 센터만" | 958e869f (배포됨) |
| #467 | 배송 현황 "배송 통계" 탭(execution `/delivery-metrics`·dispatch `/metrics/dispatch`, PC 5 요청) + 대시보드 "오늘 숫자 넷" 첫 findBy 5초 | 49ef7d71 (**2026-11-24 현재 배포 전**, 실서버 802f9773) |

- PC 2 "내 정보" 메뉴(#403·#404)는 390px 폭으로 확인해 문제없다고 PC 2 에 알림.
- PC 5 회신(#467): 두 통계 API 모두 센터 직원 허용 — mfcId 필수·토큰 센터 권한, delivery-metrics 최대 31일. 라이더 번호는 `RiderLabel` 이 rider display-names 로 채움 → 고칠 것 없음.
- 시험 간헐 실패: 대시보드 "오늘 숫자 넷"은 파일 첫 시험이라 전체 실행 부하에서 기본 1초를 넘겼다(시각 무관). 다른 첫 시험도 같은 증상이 나오면 첫 기다림만 늘린다.

## 바로 할 일
1. **#467 배포 확인** — `curl -sk https://192.168.0.40:8445/version.txt` 첫 줄이 49ef7d71 을 포함(`git merge-base --is-ancestor 49ef7d71 <그 커밋>`)하면 배포. 배포되면 LAN 에서 배송 현황 › 배송 통계 탭이 열리는지·숫자가 오는지 본다(센터 관리자 계정은 사용자에게 받거나 사용자가 확인).
2. **대시보드 주문·매출 실값 확인** — 센터 관리자 계정으로 LAN 대시보드를 본다(아직 못 함, 계정 없음). PC 1 이 MFC-SEED-01 에서 주문 58건·1,508,970원을 확인해 줌.
3. **"피킹 줄" 이름** — 사용자 "일단 기다려봐". 사용자가 다시 말할 때까지 바꾸지 않는다(대안 "피킹 상품 수(개)" 냈음).
4. 대시보드 배치 — 추이 패널이 길어 왼쪽 센터 도면 패널 아래가 빈다.
5. 관제실 CSS 정리 — 공용 `web/ui/src/tower.css` 와 MFC `src/index.css` 중복 블록 정리(MFC 만의 도면·차트·`--pm-cat-*` 은 남김), 캡처로 전후 비교.
6. 정시 배송 시간 칸(DD-6, PC 5)·작업자 위치 API 가 생기면 시뮬레이션을 지우고 실제 값으로.
7. 이 PC 에 11-20 부터 남은 `flutter_tester`(PID 1480)가 있었다 — 자동 종료가 막혀 사용자에게 `! taskkill /PID 1480 /F` 를 부탁해 둠. 남아 있는지 확인.

## PR·배포 흐름 (꼭)
- 원격 `pc3`(YOO196/pmart-clients-pc3)에 푸시 → `gh pr create -R code-and-pick/pmart-clients -H YOO196:<브랜치>`.
- PC 1 이 cherry-pick 해 main 에 넣고 PR 을 **닫는다**. 닫힌 PR 브랜치에 더 올리지 말고 새 브랜치로. 강제 푸시 막힘.
- 생성 타입: backend `origin/main` 의 `contracts` 를 `git archive` 로 scratchpad 에 풀고 `PMART_CONTRACTS_DIR` 로 `npm run gen:api -w web/mfc-backoffice`, 뒤에 `git checkout -- contracts.lock`(PC 1 이 합칠 때 고침).
- 커밋·푸시·PR 은 사용자가 시킬 때만. 다른 에이전트(서브에이전트)는 쓰지 않는다.

## 목업·캡처
- 목업 사이트 `http://localhost:4176/c/MFC-BSN-01/dashboard` — `npx vite build --mode mock --outDir <dir> --emptyOutDir` 뒤 `npx vite preview --mode mock --outDir <dir> --port 4176 --strictPort`(web/mfc-backoffice 에서, 백그라운드). 세션이 바뀌면 꺼져 있을 수 있다 → 다시 띄운다.
- 캡처는 헤드리스 크롬 CDP 스크립트(세션 scratchpad `shots.mjs`, 없어졌으면 다시 만든다). Git Bash 에서는 `MSYS_NO_PATHCONV=1` 로 돌린다.

## 지킬 것
- 계약에 없는 값은 목에서만 시뮬레이션 + 실서버는 "API 없음" 안내 + 백엔드 요청서.
- 목업 먼저, 사용자가 "PR 해"라고 하면 그때 PR. 레퍼런스는 충실히, 만든 뒤 캡처로 직접 나란히 보고 판단.
- 색은 테마 변수로, 움직임은 `prefers-reduced-motion` 짝, 차트 색은 dataviz 팔레트 검사 통과값.
- 강제 푸시·PC 2 영역(`web/ui`·`web/core`) 수정·백엔드 수정 금지. 토큰·개인정보 로그 금지.
- 시험은 실제로 돌린 것만 통과라고 말한다(`npm run typecheck|lint|test -w web/mfc-backoffice`, 지금 280 통과).
- flutter test 는 `--concurrency=1` 또는 파일별, 실메모리 4GB 미만이면 미루고, 끝나면 남은 `flutter_tester` 확인.

## 알아 둘 함정
- 칸(위치)이 수천 개 — `features/dashboard/floorQueries.ts` `fetchAllLocations` 로 끝까지.
- 목 서비스 워커가 멈추면 "조회 실패"가 무더기 → `keepMocking` 이 다시 붙임.
- Bash 긴 heredoc 따옴표가 깨진다 → scratchpad 파이썬 스크립트로 고친다.
- `exactOptionalPropertyTypes` — 선택 속성은 조건부 펼침, 또는 `x?: T | undefined`.
- 렌더 중 `Date.now()` 금지(lint) → `useNow`.
- 목 날짜: 요일(일요일 줄 없음)·새벽(수요 곡선 0) 경계에서 시험이 갈렸다 → 날짜에 기대는 시험은 오늘·요일을 계산해 기대값을 낸다.
