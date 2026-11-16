# CLAUDE.md — PMart Clients

PMart(퀵 커머스: 도심 MFC 기반 즉시·예약 배달)의 **클라이언트 앱** 저장소. Flutter 모바일 앱 3개 + React SPA 2개.
백엔드(`../pmart-backend`, Spring Boot MSA)는 **다른 계정의 Claude Code가 담당**한다. 이 저장소에서는 백엔드를 읽기만 한다.

## 앱 구성 `[확정 2026-10-24, ADR-0001 · 인사팀 백오피스 추가 2026-11-13, ADR-0003]`
Flutter 앱은 **Android 만** 개발한다. iOS 는 중단(`ios/` 는 두되 손대지 않음) — ADR-0002 (2026-10-30).

| 앱 | 기술 | 사용자 | 1차 범위 | 문서 |
|---|---|---|---|---|
| `apps/customer_app` | Flutter (Android) | 고객 | 1단계 | `docs/apps/customer-app.md` |
| `apps/rider_app` | Flutter (Android) | 라이더 | 1단계 | `docs/apps/rider-app.md` |
| `apps/mfc_app` | Flutter (Android PDA 우선) | MFC 점원(피킹·패킹·인계·입고·실사) | 1단계 | `docs/apps/mfc-app.md` |
| `web/backoffice` | React SPA (Vite + TS) | 본사·센터 운영자 | 1단계 | `docs/apps/backoffice-web.md` |
| `web/hr-backoffice` | React SPA (Vite + TS) | 인사팀(`HR_ADMIN`) — 직원 등록·계정 발급·정지/퇴사 | 구현·LAN 배포(`https://192.168.0.40:8444`, 2026-11-13) | `docs/apps/hr-backoffice-web.md` |
| `web/mfc-backoffice` | React SPA (Vite + TS) | 센터 관리자(`MFC_SUPERVISOR`) — 작업자·배정·작업·입고·재고·품질·위치·운영 제한 | 기반만(2026-11-15, 메뉴 화면은 PC 2 — 2026-11-16) — LAN `https://192.168.0.40:8445` | `docs/apps/mfc-backoffice-web.md` |
| (예약) `apps/driver_app` | Flutter | 간선기사(TMS) | 2단계 | `docs/apps/driver-app.md` |

## 구조
```
apps/                 # Flutter 앱 (앱마다 독립 패키지)
packages/             # Dart 공유 패키지 (pub workspace)
  pmart_api/          #   contracts/openapi → 생성 클라이언트 (생성물은 커밋하지 않음)
  pmart_core/         #   HTTP·인증·멱등키·Problem·CommandResponse·결과 조회 폴링·기기 ID
  pmart_ui/           #   디자인 시스템·공통 위젯·상태 표시(UI_* 7종)
web/core/             # 웹 공유 패키지 @pmart/web-core (HTTP 규약·실패 분류·멱등키·토큰·직원 로그인)
web/ui/               # 웹 공유 패키지 @pmart/web-ui (UiState 표시·명령 결과·공통 문구)
web/backoffice/       # React SPA (npm workspace)
web/hr-backoffice/    # React SPA — 인사팀 백오피스 (npm workspace)
web/mfc-backoffice/   # React SPA — MFC 백오피스(센터 관리자) (npm workspace)
tools/                # 계약 동기화·코드 생성 스크립트
docs/                 # 설계 정본 (아래 문서 지도)
```
세부 구조·스택은 `docs/architecture/client-architecture.md`.

## 문서 지도
- 클라이언트 아키텍처·스택·API 연동 패턴: `docs/architecture/client-architecture.md`
- 앱별 화면·규칙: `docs/apps/*.md`
- **백엔드에 요청할 계약 공백**: `docs/backend-requests.md` — 계약에 없는 API가 필요하면 추측해서 만들지 말고 여기에 적는다
- **PC 나눠 작업하기(PC 별 역할·폴더 구조·앱 영역·일지·handoff 규칙)**: `docs/operations/pc-split.md` — 여러 PC 가 이 저장소를 함께 고친다. 앱 영역은 customer-app·mfc-app·rider-app·backoffice·hr-backoffice·web-common. 클라이언트 담당: PC 1 = customer-app·로그인/세션/토큰 코드, **PC 2 = backoffice·hr-backoffice·mfc-backoffice·web-common(2026-11-16 부터, 인계서 `docs/operations/backoffice-handover.md`)**, PC 3 = mfc-app, PC 5 = rider-app. PC 1(192.168.0.32)만 원본 main 에 넣고 다른 PC 는 포크 → PR. 여럿이 고치는 문서(`backend-requests.md`·`contracts.lock` 등)는 PC 1 이 합칠 때 몰아서 고친다. 저장소는 `pmart-backend`·`pmart-clients`·`pmart-mfc-simulation` 을 같은 부모 폴더의 형제로 둔다.
- **다른 PC 가 읽을 문서 지도**(읽는 순서·PC 별 문서·필요할 때 볼 것·시작할 때 보낼 말): `docs/operations/other-pcs-start-here.md`
- **백엔드와 주고받는 문서(handoff)**: 요청·추가 질문은 `docs/handoff/<앱 영역>/<날짜>-backend-<주제>.md`(여러 앱이면 `docs/handoff/all/`)에 새 파일로 쓰고, 첫머리에 `보낸 앱:` 과 `받는 백엔드 영역:`(platform·mfc·delivery)을 적는다. 끝난 문서는 `docs/handoff/archive/` 로 옮긴다(규칙·열린 문서 목록 `docs/handoff/README.md`). 백엔드 회신은 `../pmart-backend/docs/handoff/clients/<날짜>-<받는 앱 영역|all>-<종류>-<주제>.md` 에서 읽는다(읽기 전용, 2026-11-13 까지는 `…-clients-…`, 끝난 것은 그 아래 `archive/`).
- 단계 계획: `docs/roadmap.md`
- 결정 기록: `docs/adr/`
- 작업 일지: `docs/worklog/<앱 영역>/<날짜>.md` (2026-11-14 부터 앱 영역별 폴더, 형식은 `docs/worklog/README.md`)

## 백엔드 정본 (읽기 전용 참조)
- REST 계약: `../pmart-backend/contracts/openapi/*.yaml` (+ `_common.yaml`). **클라이언트 모델·경로의 정본.**
- 상태표: `../pmart-backend/contracts/states/*.md`
- 확정 정책: `../pmart-backend/docs/business/overview.md` §4
- 업무 원문: `../pmart-backend/docs/business/*-business-logic.md`. 충돌 시 우선순위는 `docs/business/domain-map.md` §3
- 게이트웨이 라우팅·공개 경로: `../pmart-backend/platform-services/api-gateway/src/main/resources/application.yml`
- 백엔드 진행 상황: `../pmart-backend/docs/worklog/`

## 상세 규칙 (작업 영역에 따라 자동 로드)
- API 연동(공통): `.claude/rules/api-integration.md`
- Flutter: `.claude/rules/flutter.md`
- React: `.claude/rules/react-web.md`
- 테스트: `.claude/rules/testing.md`

## 고객앱 디자인 기준 `[사용자 지시 2026-11-11]`
- 고객앱(`apps/customer_app`) 화면은 `docs/customer-app-design/` 의 레퍼런스 캡처와 **같게** 만든다(배치·크기·간격·굵기·아이콘 모양). 폴더는 git 제외라 이 PC에만 있다.
- 화면을 만들거나 고치기 전에 해당 캡처를 먼저 연다. 캡처는 1080px 폭 = 360dp 이므로 px ÷ 3 으로 치수를 잰다.
- 고친 뒤에는 같은 폭(360dp)으로 캡처해(`apps/customer_app/tool/screenshots.dart`) 레퍼런스와 **한 이미지로 나란히 붙여** 비교하고, 남은 차이를 숨기지 않고 보고한다. 따로 열어 보고 "비슷하다"고 하지 않는다.
- 예외: 브랜드색은 연보라(`PmartCustomerTheme`). 1차 제외 기능(쿠폰·프로모션·할인 배너·찜·재입고 알림 등, `docs/apps/customer-app.md`)은 레퍼런스에 있어도 넣지 않는다. 계약에 없는 그림·필드는 추측해 만들지 않는다.
- 아이콘은 얇은 선 아이콘(`pmart_ui` 의 `PmartLineIcon`)을 쓴다. 기본 Material 아이콘으로 대신하지 않는다.

## Commands
```bash
# Flutter (Flutter 3.47.5 / Dart 3.13.4 확인됨)
dart tools/gen_api.dart                           # 계약 → packages/pmart_api/gen/<service> 생성 (clone 직후 pub get 보다 먼저, ~6분)
dart tools/gen_api.dart --only=cart,order         # 일부 서비스만
flutter pub get                                   # 루트 workspace
cd apps/customer_app && flutter run --dart-define=PMART_ENV=mock   # 에뮬레이터면 --dart-define=PMART_ANDROID_EMULATOR=true
flutter analyze && flutter test                   # 앱/패키지 디렉터리에서 (packages/pmart_core·pmart_ui, apps/*)

# React (Node 24 / npm 11 확인됨)
npm install                                       # 루트 workspace (web/*)
npm install --prefix tools/web-tools              # TS 5 도구(타입 생성·ESLint). TS 7 과 같은 설치에 둘 수 없다
npm run gen:api -w web/backoffice                 # 계약 → src/api/generated (커밋 안 함)
npm run dev -w web/backoffice                     # 목 모드(MSW). 실서버는 dev:local (게이트웨이 프록시)
npm run typecheck -w web/backoffice               # TS 7
npm run lint -w web/backoffice                    # ESLint (tools/web-tools 의 TS 5)
npm run test -w web/backoffice                    # Vitest + MSW
# 다른 웹 패키지도 같은 스크립트: -w web/hr-backoffice (dev 는 포트 5174), -w web/mfc-backoffice (5175), -w web/core, -w web/ui (typecheck·lint·test)
```
실행 전 경로와 스크립트 존재를 확인한다. 검증은 목 모드만 쓴다(백엔드 도커 사용 안 함).

## 절대 규칙
- `../pmart-backend` 의 파일을 수정하지 않는다. 계약 변경이 필요하면 `docs/backend-requests.md` 에 적고 사용자에게 보고한다.
- 계약에 없는 엔드포인트·필드를 추측해 호출하지 않는다. 필요한 동안에는 목(mock)으로만 쓰고 `backend-requests.md` 에 등록한다.
- **서버가 확정한 결과만 화면에 확정으로 보여준다.** `ACCEPTED` ≠ 성공, 결제창 복귀 ≠ 결제 승인, 스캔 ≠ 인계, 타임아웃 ≠ 실패.
- 모든 변경 요청에 `Idempotency-Key`·`X-Source-System` 을 붙이고, 재시도는 **같은 키**로 한다. 불명 결과는 짝 조회 API로 해소한다.
- 금액·기한·자격(반품 7일/24h, 리뷰 14일, 최소주문, 배달팁)은 서버 값을 표시만 한다. 클라이언트 계산으로 확정하지 않는다.
- 조회 실패를 0·빈 목록·정상으로 표시하지 않는다. 미설정(`NOT_SET`)을 0/무제한으로 바꾸지 않는다.
- 토큰·개인정보·PG 값·출입 비밀번호를 로그·크래시 리포트·분석 이벤트에 남기지 않는다. 비밀값을 저장소·빌드 설정에 넣지 않는다.
- 요청 없이 새 프레임워크·상태관리 라이브러리를 추가하거나 주 버전을 올리지 않는다. 스택은 `client-architecture.md` 를 따른다.
- 실행하지 않은 빌드·테스트를 통과했다고 보고하지 않는다. 작업은 `docs/worklog/` 에 기록한다.
- 비즈니스 문서에 없는 규칙은 추측하지 말고 질문한다.
