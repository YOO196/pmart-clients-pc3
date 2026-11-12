# mfc_app 직원 로그인 — 구현·LAN 확인 결과와 회신

- 작성: pmart-clients, 2026-11-13
- 답하는 것: `../pmart-backend/docs/handoff/clients/2026-11-13-clients-request-mfc-app-employee-login.md` §6
- 상태: **구현 끝(미커밋 → 다음 커밋)**. 목·단위·화면 시험과 LAN 실서버 확인은 했고, **실기기(PDA) 확인은 아직** — 연결된 Android 기기·에뮬레이터가 없다.

## 1. 구현한 것 (`apps/mfc_app`)

| 항목 | 내용 |
|---|---|
| 로그인 | 버튼 하나 → Custom Tab 으로 `GET /employee-auth/logins?app=mfc&deviceId&codeChallenge&codeChallengeMethod=S256&returnUri=pmart-mfc://login` → 딥링크 복귀 → `POST /employee-auth/tokens`(`Idempotency-Key`·`X-Source-System: mfc-app`·`X-Device-Id`, 본문 `{ticket, codeVerifier}`) |
| verifier | 로그인 한 번 동안 메모리에만(저장·로그 없음). 실패하면 같은 티켓을 다시 보내지 않고 로그인을 다시 한다 |
| 기기 ID | 기존 `DeviceIdProvider` 값 그대로 — 로그인 시작·티켓 교환·갱신이 같은 값 |
| 갱신 | `POST /employee-auth/tokens/refresh`. 401 에서만 부르고, 동시 요청은 공통 인터셉터가 한 번으로 모은다(single-flight). 회전된 값으로 바로 바꿔 둔다 |
| 세션 종료 | 갱신 401 → 토큰 삭제 → 로그인 화면. `ACCOUNT_NOT_AVAILABLE` 이면 "이용할 수 없는 계정", 그 밖은 "로그인이 끝났어요(30분 무활동·시간 만료)" |
| 앱 재시작 | 보관한 refresh 로 한 번 갱신해 세션을 되살린다(되살리는 동안 로그인 화면을 보이지 않는다). 네트워크 오류면 보관은 두고 로그인 화면 |
| 로그아웃 | 메인의 로그아웃 버튼(확인 한 번) → `POST /employee-auth/logouts {allDevices:false}` → 토큰 삭제. 서버가 실패해도 지운다. `idpLogoutUri` 는 쓰지 않는다 |
| 권한 승인 대기 | 역할이 비어 있으면 메인에 "아직 권한이 없어요" 안내 |
| 오류 안내 | 복귀 `?error=` 5종, 티켓 교환 401·403 `ACCOUNT_NOT_AVAILABLE`·응답 없음, 로그인 창 닫음 — 코드로만 고른다 |
| Android | `AndroidManifest.xml` 에 `pmart-mfc://login` 인텐트 필터(flutter_web_auth_2 `CallbackActivity`). 디버그 빌드에만 평문 HTTP 허용(customer_app 과 같다) |

토큰 보관은 지금처럼 access = 메모리, refresh = 보안 저장소(Android Keystore).

## 2. 질문에 대한 답

1. **막히는 것**: 없다.
   - Custom Tab·딥링크: `flutter_web_auth_2` 5.1.0 을 새로 넣었다(Custom Tab 을 열고 콜백 스킴으로 돌아온 주소를 돌려준다 — WebView 아님). `crypto` 3.0.8(SHA-256)도 넣었다.
   - 갱신 동시성: 기존 `pmart_core` `PmartAuthInterceptor` 의 single-flight 를 그대로 쓴다(시험: 동시 3건 401 → 갱신 1번).
2. **게이트웨이 주소**: 지금처럼 **`http://192.168.0.40:8080`** 로 둔다. `https://…:8443` 로 옮기려면 앱에 사용자 CA 허용(network-security-config)이 필요한데, 출시 빌드 방침(HTTPS 인증서)이 정해질 때 같이 하는 게 낫다. 로그인 화면(Keycloak)은 Custom Tab 이 HTTPS 로 연다 — PDA 에 LAN 루트 CA 설치는 필요하다.
3. **실기기 확인**: 아직 못 했다(아래 §4).

## 3. LAN 실서버 확인 (PC 1, 계정 `claude-mfc-wrk`)

실기기가 없어, **앱의 로그인 코드(`ApiAuthRepository`·갱신 함수) 그대로**를 PC 에서 돌리고 Custom Tab 자리만 헤드리스 Chrome 이 맡았다(로그인 시작 주소를 열어 Keycloak 에 로그인 → 302 `pmart-mfc://login?ticket=…` 를 잡아 앱 코드에 넘김).

| 확인 | 결과 |
|---|---|
| 로그인 → 티켓 교환 200, 역할 `MFC_WORKER`·센터 `MFC-SEED-01`, 토큰 클레임 = 응답 | 통과 |
| `GET /employee-auth/sessions/current` 200, `app=mfc` | 통과 |
| 직원 토큰으로 게이트웨이 통과(401 아님) | 통과(시험 경로가 없는 주소라 404 — 업무 API 자체는 확인하지 않았다) |
| 복원: 보관한 refresh 로 갱신 200, refresh 회전 | 통과 |
| 이미 쓴 refresh 재사용 → 401(세션 종료), 그 뒤 새 refresh 도 401 | 통과 |
| 같은 브라우저 프로필로 다시 로그인 → **비밀번호를 다시 묻는다**(SSO 없음) | 통과 |
| 로그아웃 → 토큰 삭제, 쓰던 refresh 로 갱신 401 | 통과 |

- 시험 계정 비밀번호는 `deploy/lan/.secrets/keycloak-staff-passwords.tsv` 를 스크립트가 읽었다(출력·기록 안 함). 시험이 만든 세션 2개는 재사용 감지·로그아웃으로 끝났다.

## 4. 확인하지 못한 것 — 실기기가 있어야 한다

- Custom Tab 이 실제로 열리고 `pmart-mfc://login` 딥링크로 앱에 돌아오는 것(디버그 APK 빌드와 매니페스트의 인텐트 필터까지만 확인).
- PDA 에 LAN 루트 CA 설치 뒤 Keycloak 화면이 경고 없이 열리는 것.
- 무활동 30분 뒤 갱신 401 → 로그인 화면, 정지 즉시 401 `SUBJECT_BLOCKED` → 로그인 화면(로직은 단위 시험으로만 확인).
- 로그인 뒤 실제 작업 화면(업무 API)이 직원 토큰으로 도는 것.

디버그 APK: `flutter build apk --debug --dart-define=PMART_ENV=local --dart-define=PMART_API_BASE_URL=http://192.168.0.40:8080/api/v1` → `apps/mfc_app/build/app/outputs/flutter-apk/app-debug.apk`.

## 5. 부탁

- PDA 에 설치할 LAN 루트 CA 파일(`pmart-lan-root-ca.crt`)을 전달해 달라(실기기 확인 때 쓴다).
- 갱신이 정지·퇴사로 거절될 때의 code 가 `ACCOUNT_NOT_AVAILABLE` 이 맞는지 확인해 달라 — 그 code 일 때만 "이용할 수 없는 계정"으로 안내하고, 다른 code 는 "다시 로그인"으로 안내한다.
