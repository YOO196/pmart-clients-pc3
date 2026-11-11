# [pmart-clients → pmart-backend] 요청: 백오피스 운영자 로그인 auth-service 유지 + Keycloak 함께 운영 (2026-11-11)

- 관련: 백엔드 요청 `docs/handoff/clients/2026-11-11-clients-request-backoffice-keycloak-login.md`, ADR-0054 결정 D·L
- **사용자 결정(2026-11-11)**: "백오피스 기존 것을 유지하면서 Keycloak 을 운영한다."
  - 백오피스 로그인 화면은 **지금 그대로(auth-service 아이디·비밀번호 → `POST /auth/operator-logins`)**.
  - 백오피스 **운영자 계정 화면(`/operator-accounts` 목록·생성·수정·비밀번호 초기화)도 유지**한다. 결정 L("직원 계정은 Keycloak 관리 화면에서")로 화면을 내리지 않는다.
  - Keycloak(Realm `pmart-staff`)도 함께 운영한다. 사용자가 시험 계정을 Keycloak 관리 화면에서 만들었다.

## 요청

| # | 요청 | 이유 |
|---|---|---|
| R1 | 요청 문서 §5-3 의 **"발급자 표의 auth-service 줄에서 OPERATOR 를 뺀다"를 하지 말아 주세요.** auth-service 운영자 토큰은 계속 게이트웨이·모든 서비스에서 운영자로 받아야 합니다. | 백오피스 LAN 배포(`http://192.168.0.40`)는 auth-service 로그인으로 계속 간다. 빼면 백오피스 전체가 401 |
| R2 | 백오피스가 쓰는 auth-service 운영자 API 를 계속 둬 주세요: `POST /auth/operator-logins`, `POST /auth/tokens`(갱신), `POST /auth/logouts`, `GET /auth/sessions/current`, `POST /auth/password-changes`, `GET·POST /operator-accounts`, `PUT /operator-accounts/{operatorId}`, `POST /operator-accounts/{operatorId}/password-resets` | 화면이 그대로 쓴다 |
| R3 | ADR-0054 결정 D("이전 동안 잠시 함께 둔다")·L 을 이 결정에 맞게 고칠지는 백엔드 판단. 고치면 회신에 알려 주세요 | 문서가 "이전 뒤 auth-service 운영자 로그인 제거"로 읽히지 않게 |

## 질문 (두 계정 저장소를 함께 쓰면서 생기는 것)

| # | 질문 |
|---|---|
| Q1 | 같은 직원이 auth-service 계정과 Keycloak 계정을 둘 다 가질 때, Keycloak 사용자 속성 `pmart_operator_id` 를 auth-service 계정의 `operatorId` 와 **같게** 넣어야 하나요? (`claude-dev` 는 같게 만들었다고 읽었다.) 다르게 넣으면 승인 요청자·"내 담당" 판정이 두 사람으로 갈리는지 |
| Q2 | 차단 목록(ADR-0054 결정 K·M): Keycloak 에서 계정을 비활성화하면 그 운영자 ID 로 낸 **auth-service 토큰도** 막히나요? 반대로 auth-service 에서 비활성화(`state=DISABLED`)하면 같은 운영자 ID 의 Keycloak 토큰도 막히나요? |
| Q3 | 역할을 두 곳에서 따로 관리하게 되는데(auth-service `roles`·Keycloak Realm 역할), 백엔드가 기준으로 삼는 쪽이 있나요? 지금 Keycloak Realm 에는 `OPERATOR_ADMIN` 만 있고 MD·PRODUCT_APPROVER·DISPLAY_APPROVER·PRICE_APPROVER 가 없다(Realm 가져오기 파일 기준) — 넣을 계획인지 |

## 클라이언트 지금 상태
- Keycloak 로그인(Authorization Code + PKCE S256, 요청 문서 §1~§4 대로)은 구현해 두었지만 **빌드 모드 `lan-keycloak` 에만** 있다. LAN 에 배포하는 `build:lan` 은 auth-service 로그인.
- 그래서 요청 문서 §5-3 의 "Keycloak 로그인으로 배포했다"는 **전환 확인 회신은 보내지 않는다.** 이 문서가 그 대신이다.
- Keycloak 로그인을 백오피스에 함께 붙이는(한 화면에 두 방식) 것은 사용자 결정이 아직 없다. 정해지면 따로 알린다.
