# 알림: 웹 백오피스 디자인 통일 — MFC 관제실(Control Tower) 겉모습·움직임 CSS 를 다른 웹에도 (2026-11-21, PC 3)

- 받는 곳: PC 2(backoffice·hr-backoffice·web-common), PC 5(rider-backoffice), PC 1(합칠 때 참고)
- 보낸 곳: PC 3(mfc-backoffice)
- 사용자 지시(2026-11-21): "다른 웹들에도 UI 디자인 통일하기 위해 그쪽에 전달할 md 파일 작성해줘. 특히 움직이는 UI 다이나믹 css 내용도 넣어서"
- 정본 코드: `web/mfc-backoffice/src/index.css`(겉모습·움직임 전부), `web/ui/src/motion.css`(공용 움직임, PC 2), 화면 예시 `web/mfc-backoffice/src/features/dashboard/*`·`features/floor/*`
- 참고 레퍼런스(사용자 제공, 이 PC 에만 있음): `corap/mfc-control-tower.html`, `corap/mfc-admin.html`

## 0. 한 줄 요약
공용 콘솔 틀(`@pmart/web-ui` ConsoleShell)의 **바 크기·비례는 그대로** 두고, 어두운 테마(`pmart-dark`)의 **색·패널·배지·단추·움직임만** 앱 CSS 에서 덮었다. 다른 웹도 같은 CSS 를 쓰면 같은 모양이 된다. 공용 패키지에 옮기는 일은 web-common 담당(PC 2)이 정한다(§6).

## 1. 지킨 원칙
1. **틀은 공용 그대로**: 왼쪽 메뉴 폭(펼침 220px / 접힘 80px)·머리줄 높이·본문 여백은 ConsoleShell 값. 사용자: "백오피스와 통일감 있게 바의 화면 비례만 맞추고 나머진 자유롭게".
2. **web-ui·web-core 를 고치지 않고** 앱 `index.css` 에서 더 구체적인 선택자(`html[data-theme='pmart-dark'] …`)로 덮는다.
3. **색은 하드코딩 대신 테마 변수**(daisyUI `--color-*`) — 화면 코드(tsx)에는 색 값이 없다. 어두운 테마 전용 값만 CSS 한곳에 모았다.
4. **안내 박스 없음**: 각 탭 맨 위의 설명 박스("이동·보충 안내" 같은 것)는 실사용에서 의미 없어 지웠다.
5. **움직임은 일이 벌어지는 곳에만**: 살아 있음·방금 바뀜·진행 중·위치 이동. 꾸밈 애니메이션은 넣지 않는다.
6. **움직임 줄이기(`prefers-reduced-motion: reduce`)면 모두 끈다** — 모든 애니메이션·트랜지션에 짝 규칙이 있다.
7. 기본 테마: MFC 는 `index.html` 의 `<html data-theme="pmart-dark">`. 다른 웹은 지금 `pmart`(밝음). 밝은 테마는 통합 백오피스 모양 그대로 둔다.

## 2. 색(어두운 테마 `pmart-dark` 덮어쓰기)

| 변수 | 값 | 쓰임 |
|---|---|---|
| `--color-base-200` | `#0b0d14` | 바탕(남색 검정) |
| `--color-base-100` | `#131722` | 패널 |
| `--color-base-300` | `#232838` | 1px 테두리 |
| `--color-base-content` | `#eef0f8` | 글자 |
| `--color-primary` | `#a78bfa` | 링크·그림·강조 글자(연보라) |
| `--color-accent` | `#7c3aed` | 로고·주 단추 채움(진보라) |
| `--color-success / warning / error / info` | `#34d399 / #fbbf24 / #f87171 / #7dd3fc` | 상태 |
| `--radius-box / field / selector` | `0.6875rem / 0.4375rem / 0.375rem` | 둥근 정도 |
| `--pm-tower-side` · `--pm-tower-top` | `#0f121c` · `#10131d` | 왼쪽 메뉴·머리줄 |
| `--pm-tower-edge` | `#41345c` | 패널 윗선(보라 기운) |
| `--pm-tower-active` · `-active-edge` · `-active-ink` | `#241b3c` · `#3b2a5f` · `#dccbff` | 고른 메뉴 |
| `--pm-tower-head` · `--pm-tower-hover` | `#171c29` · `#1b2030` | 표 머리 띠·줄 위 마우스 |
| `--pm-tower-muted` | `#a0a9bf` | 흐린 글자(`text-base-content/50~60` 을 회청색으로) |

숫자는 `font-variant-numeric: tabular-nums`. 시각·번호는 `.pm-mono`(JetBrains Mono → Cascadia Mono → Consolas). 글꼴은 Pretendard(공용과 같음).

## 3. 겉모습 조각(클래스와 하는 일)
모두 `web/mfc-backoffice/src/index.css` 에 있다. 블록을 그대로 옮기면 된다.

| 조각 | 선택자/클래스 | 모양 |
|---|---|---|
| 바탕 빛 | `html[data-theme='pmart-dark'] body` | 오른쪽 위 보라 원형 빛 + 왼쪽 아래 하늘색 빛, `background-attachment: fixed` |
| 왼쪽 메뉴 | `[data-testid='side-menu'] nav a` | 좌우 0.5rem 띄운 둥근 항목, 고른 메뉴는 보라 바탕·테두리, 하위 항목 앞 `·` 점 |
| 로고 | `header > a:first-child > span:first-child` | 보라 그라데이션 + 빛 |
| 패널 | `main :is(.rounded-box.border, .rounded-box.bg-base-100, section.bg-base-100)` | 반투명 유리(`blur(10px)`) + 보라 윗선 + 안쪽 윗빛 + 그림자 |
| 제목 | `main h1` | 1.875rem·800·자간 -0.045em |
| 지표 숫자 | `.pm-stat-value`, `[data-testid$='-value']` | 800·촘촘 |
| 표 | `main table th`, `tbody tr:hover` | 머리 띠, 줄 위 마우스 바탕 |
| 배지 | `.badge.badge-{error,warning,success,info…}` | 옅은 색 바탕 + 같은 색 테두리 + 밝은 글자 |
| 보통 단추 | `.btn`(색 지정 없는 것) | `#181d2a` 바탕, 올리면 보라 테두리 |
| 조치 단추 | **`.pm-action`** (화면에 붙이는 클래스) | 보라 14~16% 바탕·보라 글자, 올리면 빛. "할 수 있는 일" 단추에 쓴다 |
| 주 단추 | `.btn-primary` | 보라 그라데이션 |
| 골라 보기 | **`.pm-seg`** + `button[aria-pressed]` | 홈 안의 작은 단추 묶음(예: 피킹 줄·결품률·정시율) |
| 막대 | **`.pm-meter-track` / `.pm-meter-fill`** | 어두운 홈 + 보라 그라데이션 막대 + 빛 |
| 고정폭 | **`.pm-mono`** | 시계·번호 |

배치는 **컨테이너 쿼리**(`@container` + `@md:` `@3xl:` `@5xl:col-span-*`)로 한다 — 왼쪽 메뉴가 접히고 펼쳐져도 본문 폭에 맞춰 칸이 바뀐다(예: `CenterDashboard.tsx` 지표 카드 `col-span-12 @md:col-span-6 @5xl:col-span-3`).

## 4. 움직이는 UI(다이나믹 CSS) — 전부
### 4-1. 공용(`web/ui/src/motion.css`, PC 2 가 이미 만듦 — 앱 index.css 맨 위 `@import '../../ui/src/motion.css';`)
| 클래스 | 언제 | 움직임 |
|---|---|---|
| `.step-pulse` | 진행 중인 단계 동그라미 | 2초마다 고리가 1.75배로 퍼지며 사라짐 |
| `.stat-changed` | 숫자 칸이 방금 바뀜 | 보라 빛 고리 1.4초 × 2번 |
| `.row-new` | 저절로 새로 읽은 목록에 새 줄 | 하늘색 바탕이 5초에 걸쳐 빠짐 |
| `.breathe` | 기한 임박·새 메시지 | 2초 주기 숨쉬기(opacity 1 ↔ 0.35) |
| `.msg-new` | 새 메시지 | 6px 아래에서 0.35초 미끄러져 들어옴 |
| `.flow-bar` | 서버가 아직 반영 중 | 막대 안을 1/3 조각이 1.6초마다 흐름 |

### 4-2. 관제실 겉모습에서 더한 것(`web/mfc-backoffice/src/index.css`)
```css
/* 살아 있음 점 — 머리줄 시계 앞 초록 점에서 고리가 퍼짐 (LiveClock.tsx) */
html[data-theme='pmart-dark'] .pm-live {
  box-shadow: 0 0 0 0 rgb(16 185 129 / 0.7);
  animation: pm-live 2s infinite;
}
@keyframes pm-live {
  70% { box-shadow: 0 0 0 7px rgb(16 185 129 / 0); }
  100% { box-shadow: 0 0 0 0 rgb(16 185 129 / 0); }
}

/* 상태 숨쉬기 — 실사 잠김 칸처럼 '지금 막혀 있음' */
.pm-pulse { animation: pm-pulse 2.4s ease-in-out infinite; }
@keyframes pm-pulse { 50% { opacity: 0.45; } }

/* 배지: 올리면 1px 떠오르고 밝아짐 */
html[data-theme='pmart-dark'] .badge { transition: transform .15s, filter .15s, box-shadow .15s; }
html[data-theme='pmart-dark'] .badge:hover { transform: translateY(-1px); filter: brightness(1.18); }

/* 메뉴·패널·골라 보기: 색만 부드럽게 바뀜 */
html[data-theme='pmart-dark'] [data-testid='side-menu'] nav a { transition: background-color .18s, color .18s, border-color .18s; }
html[data-theme='pmart-dark'] main :is(.rounded-box.border, section.bg-base-100) { transition: border-color .2s; }
.pm-seg > button { transition: background-color .18s, color .18s; }

/* 조치 단추: 올리면 보라 빛 */
html[data-theme='pmart-dark'] .btn.pm-action:hover {
  --btn-bg: rgb(124 58 237 / 0.32);
  --btn-border: var(--color-primary);
  box-shadow: 0 0 14px rgb(124 58 237 / 0.38);
}

/* 도면 위 움직이는 점(작업자) — 0.8초마다 새 자리로 미끄러짐(위치는 JS 가 transform 으로 준다) */
.pm-floor-dot { transition: transform 0.8s linear; cursor: pointer; }
.pm-floor-dot:focus { outline: none; }                       /* 마우스로 누른 뒤 큰 흰 상자 없음 */
.pm-floor-dot:focus-visible .pm-floor-core { stroke: var(--color-base-content); } /* 키보드일 때만 표시 */

/* 도면 위 누를 수 있는 도형(랙) — 올리면 보라로 */
.pm-floor-rack { fill: var(--pm-floor-rack); cursor: pointer; transition: fill .15s; }
.pm-floor-rack:hover, .pm-floor-rack:focus-visible { fill: color-mix(in oklab, var(--color-primary) 70%, transparent); outline: none; }

/* 움직임 줄이기 — 반드시 짝으로 */
@media (prefers-reduced-motion: reduce) {
  html[data-theme='pmart-dark'] .pm-live { animation: none; }
  html[data-theme='pmart-dark'] .badge:hover { transform: none; }
  .pm-pulse { animation: none; }
  .pm-floor-dot { transition: none; }
}
```

### 4-3. 화면 코드 쪽 움직임(tsx)
- **시계**: `useNow(1000)`(`src/shared/motion.ts`)로 1초마다 다시 그림. 렌더 중 `Date.now()` 를 부르지 않는다(lint 규칙).
- **차트 마우스**: 막대에 올리면 다른 막대가 `opacity-45` 로 흐려지고(`transition-opacity`), 위에 값이 `aria-live="polite"` 로 뜬다. 키보드 포커스는 `group-focus-visible:ring-2`. 표로 보기(`<details>`)를 늘 같이 둔다(`features/dashboard/charts.tsx`).
- **목록 줄**: `transition-colors hover:bg-primary/5`.
- **움직이는 점**(도면): 위치를 `style={{ transform: translate(xpx, zpx) }}` 로만 바꾸고 이동은 CSS transition 에 맡긴다. 점은 벽·랙을 지나가지 않게 A* 길찾기(`features/dashboard/navGrid.ts`) 경로를 한 칸씩 따라간다. 고른 점은 점과 간격을 둔 얇은 흰 고리(반지름 0.62, 두께 0.06)만 그린다 — 큰 흰 원·두꺼운 테두리 쓰지 않음(사용자 2026-11-21).
- **주의**: 작업자 위치는 계약 API 가 없어 **목 모드에서만** 시뮬레이션한다. 실서버는 "작업자 위치 API 없음" 안내. 다른 웹도 계약에 없는 실시간 위치를 추측해 그리지 않는다(라이더 관제 지도는 rider 계약 기준으로).

## 5. 도면·지도 색(겹쳐도 비치지 않게)
반투명 색을 겹치면 벽 모서리·구역이 진하게 비친다. **바탕(base-200)과 섞은 불투명 단색**만 쓴다.
```css
:root {
  --pm-zone-frozen:  color-mix(in oklab, #3b82f6 14%, var(--color-base-200));
  --pm-zone-chilled: color-mix(in oklab, #14b8a6 13%, var(--color-base-200));
  --pm-zone-ambient: color-mix(in oklab, #f59e0b 11%, var(--color-base-200));
  --pm-floor-rack:   color-mix(in oklab, var(--color-base-content) 24%, var(--color-base-200));
  --pm-floor-wall:   color-mix(in oklab, var(--color-base-content) 58%, var(--color-base-200));
  --pm-floor-label-bg: color-mix(in oklab, var(--color-base-100) 88%, var(--color-base-content));
}
```
이름표는 도형과 겹치지 않는 빈 자리에 두고 불투명 바탕(알약 모양)을 깐다.

## 6. 다른 웹에 옮기는 방법(제안 — 정하는 것은 PC 2)
- **권장 A — 공용으로 올리기(PC 2)**: §2·§3·§4-2·§5 블록을 `web/ui/src/tower.css` 같은 공용 파일로 옮기고, 각 앱 `index.css` 에서 `@import '../../ui/src/tower.css';` 한 줄. `pm-action`·`pm-seg`·`pm-meter-*`·`pm-mono`·`pm-live`·`pm-pulse` 는 이름 그대로 두면 MFC 화면을 고치지 않아도 된다. 옮기면 PC 3 이 MFC `index.css` 의 같은 블록을 지운다.
- **B — 앱마다 복사(PC 2·PC 5)**: 공용으로 올리기 전이라면 MFC `index.css` 의 "MFC 관제실 겉모습" 블록(`---- MFC 관제실(Control Tower) 겉모습` 주석부터 `.pm-pulse` 까지)을 앱 `index.css` 에 붙이고 `index.html` 을 `data-theme="pmart-dark"` 로. 바 선택자(`[data-testid='side-menu']`)는 ConsoleShell 것이라 그대로 맞는다.
- 브랜드 강조색을 앱마다 다르게 하려면 `--color-primary`·`--color-accent`·`--pm-tower-edge`·`--pm-tower-active*` 다섯 개만 바꾼다(예: 라이더 = 다른 색). 나머지는 같게 둔다.
- 어두운 테마를 기본으로 할지는 앱 사용자(본사·인사·라이더 운영)가 정한다 — 이 알림은 모양만 넘긴다.

## 7. 확인
- MFC 화면 캡처(헤드리스 크롬, 1440·1600 폭): 대시보드·센터 도면·작업 현황·배정. 바 폭·머리줄 높이는 통합 백오피스와 같음.
- `npm run typecheck`·`lint` 깨끗, `npm run test -w web/mfc-backoffice` 261 통과(2026-11-21).
- 실서버: `https://192.168.0.40:8445`(PC 1 배포).
