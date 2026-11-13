# 다른 PC 에서 시작할 때 — 읽을 문서 목록 (2026-11-13)

PC 1 이 아닌 PC 에서 이 저장소를 맡는 사람·Claude 가 **처음 한 번** 읽는다. 내용은 각 문서에 있고, 여기는 어디에 무엇이 있는지만 모은다.

경로는 저장소 셋을 같은 부모 폴더에 형제로 둔 것을 기준으로 적는다(`pmart-backend`·`pmart-clients`·`pmart-mfc-simulation`). 백엔드 문서는 `git -C ../pmart-backend pull origin main` 으로 최신을 받아야 보인다.

## 1. 먼저 읽을 것 (순서대로)

| 순서 | 경로 | 내용 |
|---|---|---|
| 1 | `pmart-clients/CLAUDE.md` | 저장소 규칙(절대 규칙)·문서 지도·명령어 |
| 2 | `pmart-clients/docs/operations/pc-split.md` | PC 별 역할, 폴더 구조, 앱 영역, 일지·handoff 규칙, 포크 → PR 절차, PC 마다 다시 만들 것 |
| 3 | `pmart-backend/docs/operations/dev-on-other-pcs.md` | 다른 PC 에서 개발하는 법 — 포크·PR, LAN 시험 계정과 비밀번호 파일, 직원 토큰 받는 법, 바뀐 주소 |
| 4 | `pmart-backend/docs/operations/other-pcs-todo.md` | PC 별 할 일 체크리스트("클라이언트" 절이 이 저장소의 남은 일) |

## 2. 작업할 때 볼 것

| 경로 | 내용 |
|---|---|
| `pmart-clients/docs/worklog/README.md` | 작업 일지 형식과 위치(`docs/worklog/<앱 영역>/YYYY-MM-DD.md`, 2026-11-14 부터) |
| `pmart-clients/docs/apps/<앱>.md` | 맡은 앱의 화면·규칙 — `customer-app.md`·`mfc-app.md`·`rider-app.md`·`backoffice-web.md`·`hr-backoffice-web.md` |
| `pmart-clients/docs/architecture/client-architecture.md` | 스택·구조·API 연동 패턴 |
| `pmart-clients/.claude/rules/*.md` | 영역별 상세 규칙(API 연동·Flutter·React·테스트) |
| `pmart-clients/docs/backend-requests.md` | 백엔드에 요청한 계약 공백(BR 목록) — 고치는 것은 PC 1(`pc-split.md` §6) |
| `pmart-backend/docs/operations/pc-split.md` | 백엔드 영역 규칙 정본 — handoff 를 어느 백엔드 영역(platform·mfc·delivery)에 보낼지 고를 때 |
| `pmart-backend/contracts/openapi/*.yaml` | REST 계약 정본(읽기만) |

## 3. 백엔드 회신 — `pmart-backend/docs/handoff/clients/`

- 2026-11-14 부터 파일 이름이 `YYYY-MM-DD-<받는 앱 영역>-<종류>-<주제>.md` 다. **`*-<자기 앱 영역>-*` 와 `*-all-*`** 만 보면 된다. 2026-11-13 까지는 `…-clients-…`.
- 2026-11-13 에 온 것 중 지금도 유효한 것:

| 파일 | 내용 | 관련 앱 영역 |
|---|---|---|
| `2026-11-13-clients-notice-dev-on-other-pcs.md` | 다른 PC 개발 안내(위 §1-3 문서의 요약) | all |
| `2026-11-13-all-notice-area-split.md` | 영역 나누기 제안(받았다 — 회신 `pmart-clients/docs/handoff/2026-11-13-backend-area-split-reply.md`) | all |
| `2026-11-13-all-notice-area-plan-rag-backoffice.md` | rag·backoffice 영역 계획, 로그인 마무리 기준 | backoffice·hr-backoffice·web-common |
| `2026-11-13-clients-notice-auth-operator-login-removed.md` | auth-service 운영자 로그인·계정 관리 삭제 → 백오피스 옛 로그인 코드 삭제 요청(**아직 안 함**) | backoffice |
| `2026-11-13-clients-notice-backoffice-https-csp-logout.md` | HTTPS 주소, CSP 규칙(인라인 스크립트·외부 CDN 금지), 로그아웃 즉시 차단 | backoffice·hr-backoffice·all |
| `2026-11-13-all-reply-https-builds-published-http-closed.md` | HTTPS 빌드 올림·HTTP 닫음, 브라우저 확인 요청(**아직 안 함**) | backoffice·hr-backoffice |
| `2026-11-13-clients-reply-hr-backoffice-deployed.md` | 권한 기간 "기한 없음" 표시 요청(**아직 안 함**), 빌드는 백엔드가 올린다 | hr-backoffice |
| `2026-11-13-hr-backoffice-notice-webmail-separate.md` | 웹메일 로그인은 합치지 않는다 — 인사팀 화면 그대로 | hr-backoffice |
| `2026-11-13-clients-reply-mfc-app-login-and-https-build.md` | mfc_app 로그인 회신 — 정지 안내는 `SUBJECT_BLOCKED` 기준(**아직 안 함**), PDA 용 CA 파일 위치, 실기기 확인 대기 | mfc-app |

"아직 안 함" 표시는 2026-11-13 기준이다. 지금 상태는 `pmart-backend/docs/operations/other-pcs-todo.md` 의 클라이언트 절과 최근 작업 일지에서 확인한다.

## 4. 이 PC 에 처음 받았을 때 할 일

`pc-split.md` §2 "저장소에 없어서 PC 마다 다시 만들거나 받아야 하는 것" 과 `CLAUDE.md` "Commands" 를 따른다. 요약:

1. 저장소 셋을 형제 폴더로 받는다. gh 설치·로그인, 포크 remote 추가(`pc-split.md` §1).
2. `dart tools/gen_api.dart` → `flutter pub get`(Flutter 앱을 맡을 때).
3. `npm install`, `npm install --prefix tools/web-tools`, `npm run gen:api -w web/<앱>`(웹을 맡을 때).
4. LAN 시험이 필요하면 비밀번호 파일을 사용자에게 받는다(백엔드 `deploy/lan/.secrets/` 에만).
