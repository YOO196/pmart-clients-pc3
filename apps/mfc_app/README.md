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

## 브라우저로 보기 (목 모드, 화면 확인용)
```bash
cd apps/mfc_app && flutter build web --dart-define=PMART_ENV=mock
cd build/web && python -m http.server 8686   # http://localhost:8686
```
안드로이드 폰 크기(412×915dp) 틀 안에 그린다. 웹에서는 카메라 스캔·네트워크 프린터가 안 된다(입력칸·라벨 미리보기로 확인).

## 목 모드에서 해 볼 것
- 메인: 업무 3개 중 **입고는 잠김**(목 작업자에게 입고 자격 없음) → 누르면 "권한이 없어요". 검수·피패킹은 고를 수 있다.
- 피패킹 → 작업 준비 완료 → 안내 한 장 → 확인 → 서버가 준 작업(먼저 진행 중인 패킹, 끝나면 피킹) → 작업 시작.
- 피킹: 그릭요거트 `8801115220015` 가 맞는 상품, 서울우유 `8801115114154` 는 다른 상품(거절 안내 확인용). 바코드 이미지가 없으면 입력칸에 직접 넣어도 된다.
- 패킹: 스캔 → 밀봉 → 포장의 "라벨 출력"(기본은 화면 미리보기) → 예상 포장 시간 넣고 배차 요청.
- 검수: 목에 작업이 없어 "지금 할 작업이 없어요".
- 인계 확인·프린터 설정: 메인 아래 메뉴. 포장 QR 스캔칸에 `PKG:pkg-chk-1:1`. 프린터는 네트워크 프린터 → 프린터 IP(같은 Wi-Fi) → 시험 라벨(ZPL 라벨 프린터).
