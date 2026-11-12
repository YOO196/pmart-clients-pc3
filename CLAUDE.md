# CLAUDE.md — PMart Clients

PMart(퀵 커머스: 도심 MFC 기반 즉시·예약 배달)의 **클라이언트 앱** 저장소. Flutter 모바일 앱 3개 + React SPA 1개.
백엔드(`../pmart-backend`, Spring Boot MSA)는 **다른 계정의 Claude Code가 담당**한다. 이 저장소에서는 백엔드를 읽기만 한다.

## 앱 구성 `[확정 2026-10-24, ADR-0001]`
Flutter 앱은 **Android 만** 개발한다. iOS 는 중단(`ios/` 는 두되 손대지 않음) — ADR-0002 (2026-10-30).

| 앱 | 기술 | 사용자 | 1차 범위 | 문서 |
|---|---|---|---|---|
| `apps/customer_app` | Flutter (Android) | 고객 | 1단계 | `docs/apps/customer-app.md` |
| `apps/rider_app` | Flutter (Android) | 라이더 | 1단계 | `docs/apps/rider-app.md` |
| `apps/mfc_app` | Flutter (Android PDA 우선) | MFC 점원(피킹·패킹·인계·입고·실사) | 1단계 | `docs/apps/mfc-app.md` |
| `web/backoffice` | React SPA (Vite + TS) | 본사·센터 운영자 | 1단계 | `docs/apps/backoffice-web.md` |
| (예약) `apps/driver_app` | Flutter | 간선기사(TMS) | 2단계 | `docs/apps/driver-app.md` |

## 구조
```
apps/                 # Flutter 앱 (앱마다 독립 패키지)
packages/             # Dart 공유 패키지 (pub workspace)
  pmart_api/          #   contracts/openapi → 생성 클라이언트 (생성물은 커밋하지 않음)
  pmart_core/         #   HTTP·인증·멱등키·Problem·CommandResponse·결과 조회 폴링·기기 ID
  pmart_ui/           #   디자인 시스템·공통 위젯·상태 표시(UI_* 7종)
web/backoffice/       # React SPA (npm workspace)
tools/                # 계약 동기화·코드 생성 스크립트
docs/                 # 설계 정본 (아래 문서 지도)
```
세부 구조·스택은 `docs/architecture/client-architecture.md`.

## 문서 지도
- 클라이언트 아키텍처·스택·API 연동 패턴: `docs/architecture/client-architecture.md`
- 앱별 화면·규칙: `docs/apps/*.md`
- **백엔드에 요청할 계약 공백**: `docs/backend-requests.md` — 계약에 없는 API가 필요하면 추측해서 만들지 말고 여기에 적는다
- **백엔드와 주고받는 문서(handoff)**: 요청·추가 질문은 `docs/handoff/<날짜>-backend-<주제>.md` 에 새 파일로 쓴다. 백엔드 회신은 `../pmart-backend/docs/handoff/<날짜>-clients-<주제>.md` 에서 읽는다(읽기 전용).
- 단계 계획: `docs/roadmap.md`
- 결정 기록: `docs/adr/`
- 작업 일지: `docs/worklog/` (형식은 `docs/worklog/README.md`)

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
