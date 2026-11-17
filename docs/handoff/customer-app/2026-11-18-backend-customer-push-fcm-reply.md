# [pmart-clients → pmart-backend] 회신: 고객앱 휴대폰 푸시(FCM) — 앱 반영 끝, 실기기 확인 남음 (2026-11-18)

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform (notification-service)
- 원 문서: `../pmart-backend/docs/handoff/clients/customer-app/2026-11-17-request-customer-push-fcm.md`(notification 0.4.1, ADR-0067)
- 대체: 우리 질문서 `docs/handoff/archive/2026-11-17-backend-customer-push-fcm.md` — Q1~Q5·Q7 은 원 문서로 답이 됐다. 남은 질문은 아래 §3 두 개.

## 1. 고객앱이 한 것

| 요청서 | 앱 | 커밋 |
|---|---|---|
| 1. Firebase 프로젝트 | `apps/customer_app/android/app/google-services.json`(git 제외). 11-17 은 `pmart-42b37`. `pmart-123` 으로 합치면 이 파일만 바꾼다(코드에 프로젝트 ID 없음) | — |
| 2. Gradle | `settings.gradle.kts` 에 `com.google.gms.google-services` 4.6.0 `apply false`. **차이: `app/build.gradle.kts` 는 `google-services.json` 이 있을 때만 플러그인을 건다**(요청서는 항상). 파일이 없는 PC·CI 에서도 빌드되게 — 그때 앱은 푸시 없이 돈다 | `7cbe1f2` |
| 3. 패키지·초기화·권한 | `firebase_core` 5.2.0·`firebase_messaging` 17.1.0. `Firebase.initializeApp()` 은 앱 시작이 아니라 **회원이 됐을 때**(로그인·세션 복원) 부른다. 그다음 알림 권한(Android 13+) | `7cbe1f2` |
| 4. 토큰 등록·갱신·해제 | 로그인 뒤 `getToken()` → `PUT /me/push-tokens/{deviceId}`(본문 `token`·`platform: ANDROID`, `Idempotency-Key`·`X-Source-System`, 결과 불명이면 같은 키로 한 번 더). `onTokenRefresh` 때 다시 PUT. 로그아웃은 회원 토큰을 지우기 **전에** `DELETE`, 그 뒤 단말 토큰도 버림. 비회원은 등록하지 않음. 토큰 값은 로그·오류 문구에 남기지 않음 | `7cbe1f2` |
| 푸시를 누르면 | `data` 의 `destinationType`·`destinationRef` 로 알림함과 같은 화면 — ORDER → 주문 상세, DELIVERY → 배송 현황, REFUND·CLAIM → 클레임 처리 내역, INQUIRY → 내 문의. 목적지가 없거나 모르는 값이면 `notificationId` 의 알림 상세, 그것도 없으면 알림함. 앱을 보고 있을 때 온 푸시는 알림함(안 읽음 수)을 다시 읽음 | 이 커밋 |
| 5. Google 로그인 | 로그인 대상은 계속 빌드 값 `googleServerClientId`(`.secrets/customer.env`) — LAN APK 빌드 명령은 그대로 | — |

- `REDELIVERY_PAYMENT_REQUIRED`(목적지 ORDER) 푸시는 주문 상세로 간다. 다시 배송비 결제 화면은 주문 상세 아래(`/orders/{orderId}/redelivery-payments/{redeliveryPaymentId}`)라 주문 상세에서 들어간다(푸시 `data` 에 결제 ID 가 없다) — 결제 화면으로 바로 가야 하면 알려 주세요.
- 푸시를 눌러 연 알림은 앱이 읽음으로 바꾸지 않는다(알림함에서 그 알림을 누를 때만 `…/read`). 바꿔야 하면 알려 주세요.

## 2. 확인

- 목 모드: `flutter analyze` 문제 없음, `flutter test` 413개 통과(푸시 시험 13개 — 등록·갱신·권한 거부·불명 재시도·로그아웃 순서·푸시 data → 화면).
- 디버그 APK 빌드 성공(11-17, `google-services.json` 넣고 — 매니페스트에 `POST_NOTIFICATIONS`·FCM 서비스 들어감).
- **실기기는 아직**(폰 연결 대기): Firebase 콘솔 테스트 메시지 수신 → 로그인 뒤 `GET /me/push-tokens` 에 단말 → 주문 취소·배송 출발 때 푸시, 주문 확정은 알림함에만 → Google 로그인 그대로. 하면 이 문서에 결과를 덧붙인다.

## 3. 남은 질문 — 답 받음(2026-11-18)

백엔드 회신 `../pmart-backend/docs/handoff/clients/customer-app/2026-11-18-reply-customer-push-q6-q8.md`.

| # | 질문 | 답 |
|---|---|---|
| Q6 | `pmart.notification.push-token.max-devices` 가 LAN 에 설정돼 있나(요청서는 "5대까지") — 없으면 PUT 이 422 `CONFIG_REQUIRED` | **있다 — 5**(공통 설정, LAN 적용). 6번째 단말은 등록 성공, 가장 오래 갱신 안 된 단말을 서버가 지운다. 앱 고칠 것 없음 |
| Q8 | 서버가 받는 값은 FCM 등록 토큰만인가, Firebase 설치 ID(FID)도 되나 | **지금은 `getToken()`(등록 토큰) 유지.** FID(`register()`)로 옮길 땐 백엔드가 서버를 `fid` 칸으로 먼저 고치고 실기기 확인 뒤 알림 → 고객앱·라이더앱을 같이 옮긴다. 앱 고칠 것 없음 |

- 함께 받은 소식: 2026-11-18 Firebase 를 `pmart-123` 으로 합침 → 고객앱은 새 `google-services.json` 으로 다시 빌드(할 일 28), 옛 프로젝트 단말 토큰은 로그인 뒤 앱이 다시 등록.
- 이 문서는 실기기 확인(§2) 결과를 덧붙인 뒤 `archive/` 로 옮긴다.
