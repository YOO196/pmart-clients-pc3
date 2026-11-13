# 다른 PC 가 읽을 문서 — 경로·파일 이름 (2026-11-13)

PC 1 이 아닌 PC(사람·Claude)가 이 저장소(`pmart-clients`)를 다룰 때 **어떤 문서를 어떤 순서로** 읽는지 모은 지도. 백엔드의 같은 지도는 `pmart-backend/docs/operations/other-pcs-docs.md`.

- 경로는 저장소 셋(`pmart-backend`·`pmart-clients`·`pmart-mfc-simulation`)을 같은 부모 폴더의 형제로 둔 것을 기준으로, **저장소 이름부터** 적는다.
- 읽기 전에 두 저장소 모두 `git pull origin main`.
- 문서가 새로 생기거나 경로가 바뀌면 PC 1 이 이 표를 고친다.

## 1. 모든 PC — 먼저 이 순서로

| 순서 | 파일 | 내용 |
|---|---|---|
| 1 | `pmart-clients/CLAUDE.md` | 저장소 규칙(절대 규칙)·앱 구성·문서 지도·명령어 |
| 2 | `pmart-backend/docs/operations/other-pcs-todo.md` | **PC 별 지금 할 일 체크리스트** — "모든 다른 PC 공통" 절과 "클라이언트(pmart-clients)" 절 |
| 3 | `pmart-backend/docs/operations/dev-on-other-pcs.md` | 방법: 저장소 위치·gh 설치·포크 PR 순서, 직원 토큰 받는 법, LAN 시험 계정·비밀번호 파일, 바뀐 주소 |
| 4 | `pmart-clients/docs/operations/pc-split.md` | PC 별 역할·폴더 구조·앱 영역(customer-app·mfc-app·rider-app·backoffice·hr-backoffice·web-common)·일지·handoff 규칙·포크 → PR·PC 마다 다시 만들 것 |
| 5 | `pmart-clients/docs/worklog/README.md` | 일지 쓰는 법 — 자기 앱 영역 폴더 `docs/worklog/<앱 영역>/YYYY-MM-DD.md`(2026-11-14 부터) |
| 6 | `pmart-clients/docs/architecture/client-architecture.md` | 스택·구조·API 연동 패턴(코드를 고치기 전에) |

백엔드 저장소의 규칙(`pmart-backend/CLAUDE.md`, `pmart-backend/docs/operations/pc-split.md`)은 백엔드도 같이 맡는 PC 가 백엔드 지도(`other-pcs-docs.md`)를 따라 읽는다.

## 2. PC 별로 더

클라이언트 쪽에서 확정된 담당은 **PC 1 = customer-app 위주**, **PC 2 = backoffice(로그인 마무리 뒤 시작)** 둘이다(`pc-split.md` §1). PC 3·4·5 는 클라이언트 앱 영역을 맡는다고 정해진 것이 없다 — 아래는 그 PC 의 백엔드 영역과 **맞닿는 클라이언트 문서**(화면 쪽 사정을 알아야 할 때 읽는다).

| PC(백엔드 영역) | 클라이언트 앱 영역 | 파일 |
|---|---|---|
| **PC 1**(platform) | customer-app 위주 + 다른 PC 가 맡기 전의 전부 | `pmart-clients/docs/apps/customer-app.md`, 레퍼런스 캡처 `pmart-clients/docs/customer-app-design/`(git 제외 — PC 1 에만 있다), 메모 대신 이 문서들 |
| **PC 2**(backoffice, 로그인 마무리 뒤) | backoffice·hr-backoffice·web-common(web-common 을 옮길지는 시작할 때 정한다) | `pmart-clients/docs/apps/backoffice-web.md`, `pmart-clients/docs/apps/hr-backoffice-web.md`, `pmart-clients/docs/adr/0003-hr-backoffice-and-web-shared-packages.md`(웹 공통 패키지 구조), `pmart-clients/.claude/rules/react-web.md`. 인수인계 문서는 아직 없다 — 영역을 나눌 때 `pmart-clients/docs/operations/backoffice-handover.md` 를 만든다(백엔드는 `docs/backoffice/HANDOVER.md`) |
| **PC 3**(mfc) | 미정(관련: mfc-app) | `pmart-clients/docs/apps/mfc-app.md`, `pmart-clients/.claude/rules/flutter.md` |
| **PC 4**(rag, 시작 전) | 미정(관련: 백오피스 질문 화면, 고객 앱 채팅 — 화면 아직 없음) | `pmart-clients/docs/apps/backoffice-web.md`, `pmart-clients/docs/apps/customer-app.md` |
| **PC 5**(delivery) | 미정(관련: rider-app) | `pmart-clients/docs/apps/rider-app.md`, `pmart-clients/.claude/rules/flutter.md` |

### 2-1. 지난 작업 일지

2026-11-13 까지의 일지는 `pmart-clients/docs/worklog/YYYY-MM-DD.md`(바로 아래, **모든 앱이 한 파일에 섞임**)다. `## ` 제목에서 자기 앱 항목을 찾거나 `grep -il "<앱·폴더 이름>" docs/worklog/2026-*.md` 로 찾는다. 2026-11-14 부터는 `docs/worklog/<앱 영역>/`.

| 앱 영역 | 볼 날짜 | 무엇 |
|---|---|---|
| backoffice·hr-backoffice·web-common | 11-12, **11-13** | 직원 로그인(employee-auth-service)·SSO 로그아웃, 웹 공통 패키지 분리, 인사팀 백오피스 구현·LAN 배포, HTTPS 빌드 |
| mfc-app | **11-13** | 직원 로그인(Custom Tab·딥링크·갱신·로그아웃) — 실기기 확인 전 |
| customer-app | 11-10, 11-11 | 화면을 레퍼런스 캡처에 맞추는 작업(브랜드색 연보라) |
| 전체 | 11-13 | PC 나눠 작업하기 규칙 |

### 2-2. handoff — 앱 영역별 관련 파일

- 백엔드가 보낸 것: `pmart-backend/docs/handoff/clients/`(남은 것만 — 처리 끝난 것은 그 아래 `archive/`, 기준·목록 `archive/README.md`). 2026-11-14 부터는 파일 이름의 `<받는 앱 영역>` 으로 고른다(`*-<자기 앱 영역>-*`, `*-all-*`).
- 클라이언트가 보낸 것: `pmart-clients/docs/handoff/`, 상태표 `pmart-clients/docs/backend-requests.md`(BR 번호).

| 앱 영역 | 백엔드가 보낸 것(`pmart-backend/docs/handoff/clients/`) | 클라이언트가 보낸 것(`pmart-clients/docs/handoff/`) |
|---|---|---|
| backoffice | `2026-11-13-clients-notice-auth-operator-login-removed.md`(옛 운영자 로그인 코드 삭제 — **아직 안 함**), `2026-11-13-clients-notice-backoffice-https-csp-logout.md`(HTTPS 주소·CSP 규칙·로그아웃 즉시 차단), `2026-11-13-all-reply-https-builds-published-http-closed.md`(HTTPS 빌드 올림 — 브라우저 확인 **아직 안 함**), `2026-11-12-clients-request-backoffice-employee-auth-login.md`, `2026-11-12-clients-request-backoffice-sso-logout.md`, `2026-11-09-clients-request-backoffice-role-menus.md`, `2026-11-09-clients-request-customer-inquiry-page.md` | `2026-11-12-backend-backoffice-employee-auth-login-reply.md`, `2026-11-13-backend-backoffice-sso-logout-deployed.md`, `2026-11-13-backend-web-https-lan-builds.md` |
| hr-backoffice | `2026-11-13-clients-request-hr-backoffice.md`, `2026-11-13-clients-reply-hr-backoffice-questions.md`, `2026-11-13-clients-reply-hr-backoffice-deployed.md`(권한 기간 "기한 없음" 표시 — **아직 안 함**), `2026-11-13-hr-backoffice-notice-webmail-separate.md` | `2026-11-13-backend-hr-backoffice-contract-questions.md`, `2026-11-13-backend-hr-backoffice-lan-deployed.md` |
| mfc-app | `2026-11-13-clients-request-mfc-app-employee-login.md`, `2026-11-13-clients-reply-mfc-app-login-and-https-build.md`(정지 안내는 `SUBJECT_BLOCKED` 기준 — **아직 안 함**, PDA 용 CA 위치, 실기기 확인 대기), 2026-11-07~09 의 `…-mfc-…`·`…-shelf-life-…`·`…-pda-…`·`…-plan-…` 파일들 | `2026-11-13-backend-mfc-app-employee-login-reply.md`, `2026-11-10-backend-dispatch-manual-only.md`, `2026-11-10-backend-pda-work-areas.md` |
| rider-app | `2026-11-10-clients-notice-rider-google-login.md` | 아직 없음 |
| customer-app | `2026-10-31-clients-notice-delivery-and-order-draft.md`, `2026-11-09-clients-request-customer-chat-assistant.md`(채팅 — 화면 아직 없음) | `docs/backend-requests.md` 의 고객앱 BR 항목 |
| 전체(all) | `2026-11-13-clients-notice-dev-on-other-pcs.md`, `2026-11-13-all-notice-area-split.md`, `2026-11-13-all-notice-area-plan-rag-backoffice.md`, `2026-11-13-all-notice-area-pcs-decided.md`(backoffice = PC 2, rag = PC 4), `2026-11-13-all-notice-handoff-archive.md` | `2026-11-13-backend-area-split-reply.md` |

"아직 안 함" 은 2026-11-13 기준이다. 지금 상태는 `pmart-backend/docs/operations/other-pcs-todo.md` 의 클라이언트 절과 최근 일지에서 확인한다.

## 3. 필요할 때

| 파일·폴더 | 언제 |
|---|---|
| `pmart-clients/docs/backend-requests.md` | 계약에 없는 API·필드가 필요할 때(추측해 만들지 않는다) — BR 상태표. 다른 PC 는 직접 고치지 않고 일지·PR 설명에 적는다(`pc-split.md` §6) |
| `pmart-clients/docs/handoff/` | 백엔드에 요청·질문·회신을 보낼 때 — `YYYY-MM-DD-<앱 영역>-backend-<주제>.md`, 첫머리 `보낸 앱`·`받는 백엔드 영역`(`pc-split.md` §5) |
| `pmart-backend/contracts/openapi/*.yaml`, `_common.yaml` | REST 계약 정본 — 모델·경로를 확인할 때(읽기만) |
| `pmart-backend/contracts/states/*.md` | 상태표(주문·배송 등 상태 이름과 전이) |
| `pmart-backend/platform-services/api-gateway/src/main/resources/application.yml` | 게이트웨이 라우팅·공개 경로 |
| `pmart-backend/docs/business/overview.md` §4, `pmart-backend/docs/business/*-business-logic.md` | 확정 정책·업무 원문(없는 규칙은 사용자에게 묻는다) |
| `pmart-backend/docs/adr/0056-staff-login-employee-auth-service-and-hr-service.md`, `pmart-backend/docs/architecture/auth/employee-auth-structure.md` | 직원 로그인 구조 — 웹 두 앱·mfc_app 로그인을 고칠 때 |
| `pmart-backend/docs/adr/0057-lan-dev-https-private-ca.md`, `pmart-backend/deploy/lan/tls/pmart-lan-root-ca.crt` | LAN HTTPS·루트 CA(PDA·폰에 설치할 파일) |
| `pmart-backend/deploy/lan/checks/staff_auth.py` | LAN 직원 토큰 받는 스크립트 |
| `pmart-clients/docs/adr/` | 클라이언트 결정 기록(0001 앱 구성, 0002 Android 만, 0003 인사팀 백오피스·웹 공통 패키지) |
| `pmart-clients/docs/roadmap.md` | 단계 계획 |
| `pmart-clients/.claude/rules/api-integration.md`·`flutter.md`·`react-web.md`·`testing.md` | 영역별 상세 규칙(해당 폴더를 고칠 때 자동으로 읽힌다) |
| `pmart-clients/contracts.lock` | 생성 코드가 기준으로 삼은 백엔드 커밋 |

## 4. 다른 PC 에 시작할 때 보낼 말

> `pmart-backend` 와 `pmart-clients` 를 둘 다 `git pull origin main` 한 뒤, `pmart-clients/CLAUDE.md` → `pmart-backend/docs/operations/other-pcs-todo.md` 순서로 읽고 내 PC 절과 클라이언트 절의 체크리스트대로 진행해 줘. 읽을 문서 지도는 `pmart-clients/docs/operations/other-pcs-start-here.md`.
