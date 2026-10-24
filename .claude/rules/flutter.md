---
paths:
  - "apps/**"
  - "packages/**"
  - "pubspec.yaml"
  - "**/*.dart"
---

# Flutter 규칙

## 버전·의존성
- Flutter 3.47.5 / Dart 3.13.4 (2026-10-24 설치본). `environment.sdk` 를 고정한다.
- 루트 `pubspec.yaml` 이 pub workspace. 각 패키지는 `resolution: workspace`.
- 스택: Riverpod(상태), go_router(라우팅), dio(HTTP), flutter_secure_storage. 요청 없이 다른 상태관리·라우터·HTTP 라이브러리를 추가하지 않는다.
- 새 패키지는 pub.dev 최신 안정판을 확인하고 추가 사유를 worklog에 적는다. 앱 간 공유 의존성 버전은 맞춘다.

## 구조
- `lib/features/<feature>/{data,domain,presentation}`. 화면 위젯은 Repository 인터페이스에만 의존하고, `api`/`mock` 구현은 `PMART_ENV`(`--dart-define`)로 고른다.
- 공통 연동은 `pmart_core`, 공통 위젯·테마는 `pmart_ui`. 앱끼리 서로 import 하지 않는다.
- 생성 코드(`packages/pmart_api/lib/src/generated`, `*.g.dart`, `*.freezed.dart`)는 수정하지 않는다.

## 화면
- 모든 비동기 화면은 `UiState` 7종(LOADING/READY/EMPTY/PARTIAL/ERROR/FORBIDDEN/RESULT_UNKNOWN)을 구분해 그린다.
- 명령 버튼은 진행 중 비활성. 앱 재시작 후 진행 중 명령을 원결과 조회로 복구한다.
- 시각은 UTC로 받아 Asia/Seoul로 표시. 금액은 정수 KRW, 천 단위 구분.
- 문구는 `intl`/ARB로 관리(1차 한국어). 화면 코드에 사용자 문구를 직접 쓰지 않는다.

## 현장 단말 (rider/mfc/driver)
- 현장 실적·스캔·사진은 Idempotency-Key와 함께 로컬 큐에 내구 저장 후 전송. 큐 상태(전송 대기/확정 대기/반영/거절/확인 중)를 화면에 보인다.
- 하드웨어 스캐너는 어댑터 인터페이스 뒤에 둔다(카메라 스캔과 교체 가능).

## 검증
- 변경한 패키지에서 `flutter analyze` 와 `flutter test` 를 실행한 뒤 보고한다.
