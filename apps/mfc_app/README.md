# mfc_app

PMart MFC 현장앱(점원·PDA·패킹). 화면·규칙은 `docs/apps/mfc-app.md`.

## 안드로이드 기기에서 실행 (목 모드)
지금은 전용 PDA 대신 일반 안드로이드 기기를 쓴다(2026-11-10).

1. 기기: 설정 → 휴대전화 정보 → 빌드 번호 7번 → 개발자 옵션 → USB 디버깅 켜기. USB 로 PC 에 연결하고 "허용".
2. 확인: `flutter devices` 에 기기가 보여야 한다.
3. 실행 (저장소 루트에서 `dart tools/gen_api.dart`·`flutter pub get` 을 한 번 해 둔 뒤):
   ```bash
   cd apps/mfc_app
   flutter run --dart-define=PMART_ENV=mock
   ```
   APK 만 만들려면 `flutter build apk --debug --dart-define=PMART_ENV=mock` → `build/app/outputs/flutter-apk/app-debug.apk`.
4. 처음 카메라 버튼을 누르면 카메라 권한을 묻는다. 거절했으면 기기 설정 → 앱 → mfc_app → 권한에서 켠다.

## 목 모드에서 해 볼 것
- 피킹: 작업 `task-mock-1` → 시작 → 카메라로 상품 바코드. 목에서 맞는 상품은 그릭요거트 `8801115220015`, 서울우유 `8801115114154` 는 다른 상품(거절 안내 확인용). 바코드 이미지가 없으면 입력칸에 직접 넣어도 된다.
- 패킹: `task-mock-2` → 이어서 패킹 → 스캔 → 밀봉 → 포장의 "라벨 출력"(기본은 화면 미리보기).
- 인계 확인: 앱바 체크 아이콘 → 확인 필요 포장 2건 → "포장대에 있음/없음". 포장 QR 스캔칸에 `PKG:pkg-chk-1:1`.
- 프린터: 앱바 프린터 아이콘 → 네트워크 프린터 → 프린터 IP(같은 Wi-Fi) → 시험 라벨 출력. ZPL 을 받는 라벨 프린터여야 한다.
