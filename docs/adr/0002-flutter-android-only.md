# ADR-0002 Flutter 앱은 Android 만 개발한다

- 상태: 승인 (2026-10-30, 사용자 결정)
- 관련: ADR-0001 결정 1(앱 구성은 그대로), `docs/architecture/client-architecture.md` §2

## 배경
- 사용자 지시(2026-10-30): "iOS는 이제 개발 멈추고 Flutter 앱 개발시 안드로이드 개발을 말하는 거야."

## 결정
1. `customer_app`·`rider_app`·`mfc_app`(·2단계 `driver_app`)의 개발·빌드·검증 대상은 Android 하나다.
2. iOS 전용 작업(번들 ID·서명·`Info.plist` 권한 문구·APNs·App Store 등록·iOS 빌드 확인)은 하지 않는다.
3. `ios/` 폴더와 이미 있는 코드는 지우지 않고 그대로 둔다(되돌릴 때 다시 만들지 않도록). 고치지도 않는다.
4. 플랫폼 설정·식별자·서명 지문 등은 Android 기준으로만 정한다(예: 디버그 SHA-1, `applicationId`).

## 결과
- 푸시는 FCM(Android)만 본다(BR-09).
- 고객앱 로그인 화면에서 애플 로그인 버튼을 뺐다(사용자 결정 2026-10-30). 계약 enum `APPLE` 과 저장소 매핑은 남긴다.
- 고객앱 `applicationId` 는 `com.pmart.customer_app` 그대로 쓴다(사용자 결정 2026-10-30).
- iOS 를 다시 시작하면 이 ADR 을 새 ADR 로 대체한다.
