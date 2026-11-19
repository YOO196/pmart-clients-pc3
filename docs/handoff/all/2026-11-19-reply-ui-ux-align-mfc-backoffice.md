# 회신 — 직원 웹 UI·UX 맞추기 지침(MFC 백오피스)

보낸 앱: mfc-backoffice (PC 3)
받는 앱: backoffice·web-common (PC 2)
원 문서: `docs/handoff/all/2026-11-19-request-ui-ux-align.md`
날짜: 2026-11-19

## 반영한 것 (PR `mfc-backoffice/wing-look`)
- 1 겉모습: `data-skin="wing"`(연회색 바탕·파랑 하나·얇은 테두리·큰 제목·넉넉한 표), 진행 단계 흰 선 체크, 왼쪽 메뉴 파란 채움·흰 글자·P 배지.
- 2 목록: 숫자 카드(가로형, 서버 목록으로 셈 — 넘치면 "N건 이상", 실패 "?"), 안내 상자, 검색 칩 접기, 다 끝났어요 띠(서버 성공 0건만), '/' 검색 칸, 최근 봄(이름은 화면 표기만), 내 보기.
- 3 상세: 이전·n/N·다음([ ]), 미리보기 Enter, 제목 띠, 진행 단계.
- 4 움직임: 숫자 빛남·▲▼, 새 줄, 기한 15분 안 숨쉬기 — 움직임 줄이기면 끔.
- 5 화면 틀: 탭 제목(약속 초과 출고 수 — 운영판과 같은 조회), 끊김 띠, 쳐서 찾는 고르기(담당 바꾸기 작업자, 초성).
- 6 화면 번호: 목록에서 시스템 ID·끝 8자리를 뺐고, 상세에 시스템 번호 칸을 두었다. 포장 라벨 번호가 응답에 없어 백엔드에 요청했다(`mfc-backoffice/2026-11-19-backend-display-labels.md`).
- 적용 화면과 하지 않은 것: `docs/apps/mfc-backoffice-web.md` §4-13.

## 공용(web-ui)으로 올리기 — 동의
- 지침 0 의 나눔에 동의한다. 기다리지 않고 사본으로 먼저 했고, 파일 첫 줄에 "사본: web/backoffice/…"를 적었다. 올라오면 바꿔 낀다.
- 먼저 필요한 순서:
  1. `SearchSelect` + `useFloatingPanel` (이미 web-ui)
  2. `StatCard`·`StatStrip`·`GuideBox`·`AllDone`·`SearchPanel(summary)`
  3. `ProgressSteps`
  4. `StickyTitle`
  5. `motion`
  6. 겉모습 CSS
- 부탁:
  - MFC 목록은 조회 단추 없이 고르는 즉시 거른다. 그래서 `SearchPanel` 에 "조회 단추 없음" 선택이 있으면 좋다. 지금 사본은 `SearchBar` 다.
  - 처음 펼칠지 정하는 값(`startOpen`)도 있으면 좋다. 화면 기본값(예: "대기")이 칩에 보일 때 쓴다.
  - `StatCard` 는 `onClick`(주소 쿼리 대신 거르기 함수)도 받으면 좋다.
- '/' 키는 `main form[data-search]` 를 찾는다. 공용으로 올릴 때 `data-list-part="top"` 과 같은 표시로 맞추면 한쪽을 고치겠다.
