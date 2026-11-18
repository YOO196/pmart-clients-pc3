# [pmart-clients → pmart-backend] 요청: 직원 "내 정보" — 내 비밀번호 바꾸기, 내 연락처 등록·변경 (2026-11-18)

- 보낸 앱: mfc-backoffice (PC 3). 다른 직원 앱(backoffice·hr-backoffice·rider-backoffice)도 같은 API를 쓸 수 있게 해 주세요.
- 받는 백엔드 영역: platform (employee-auth-service, hr-service)
- 사용자 결정(2026-11-18):
  - MFC 백오피스에 "내 정보" 화면을 둔다. 로그인한 직원(센터 관리자)이 **자기 비밀번호를 직접 바꾼다**. 지금 비밀번호와 새 비밀번호를 넣는 방식이다.
  - 회사 메일은 로그인 ID이자 사서함이다. 이것은 **인사팀만 바꾼다**. 본인은 **연락처(휴대폰·개인 메일)만** 등록하고 바꾼다.

## 지금
- 본인 조회 `GET /hr/employees/me`(`EmployeeSelf` — 이름·사번·회사 메일·고용 형태·소속·상태)만 있다. 바꾸는 API는 없다.
- 비밀번호(Keycloak)는 처음에 메일 링크로 정하는 것뿐이다. Keycloak 본인 계정 화면(`/realms/pmart-staff/account`)은 게이트웨이를 통과하지 않아 열리지 않는다(`keycloak-structure.md`). 비밀번호 찾기도 꺼져 있다(결정 L).
- 그래서 지금 직원은 비밀번호를 바꾸려면 인사팀에 설정 메일을 다시 보내 달라고 해야 한다(`invite-resends`, HR_ADMIN).

## 요청

### R1. 내 비밀번호 바꾸기(본인만)
- 예시(이름은 백엔드가 정한다): `POST /employee-auth/me/password-changes` `{currentPassword, newPassword}`. 직원 토큰 본인만 부른다. Idempotency-Key·X-Source-System을 붙인다.
- 서버가 **지금 비밀번호를 확인한 뒤** Keycloak 비밀번호를 바꾼다. 확인 없이 바꾸면 자리를 비운 화면에서 남이 바꿀 수 있다.
- 거절 코드 예시:
  - `CURRENT_PASSWORD_INVALID`: 지금 비밀번호가 틀림.
  - `PASSWORD_POLICY_VIOLATION`: Realm 비밀번호 규칙 위반. 무슨 규칙인지 `details`로 알려 주세요. 화면은 규칙을 계산하지 않고 서버가 준 사유만 보여 준다.
  - `PASSWORD_SAME_AS_CURRENT`: 지금과 같음(필요하면).
- 연속으로 틀리면 잠가 주세요(횟수·시간은 백엔드가 정해서 회신). 잠기면 그 코드와 풀리는 시각을 주세요.
- **비밀번호는 로그·사건·멱등 기록·감사 기록 어디에도 남기지 않는다.** 멱등 기록에는 결과만 남긴다.
- 바꾼 뒤 세션을 어떻게 하는지 정해서 회신에 적어 주세요. 제안: 지금 세션은 유지하고, 다른 기기·브라우저 세션은 끝낸다(ADR-0061 흐름).
- 화면에 "언제 바꿨는지"를 보이고 싶다. `GET /hr/employees/me`나 세션 조회에 `passwordChangedAt`을 넣을 수 있으면 넣어 주세요(선택).

### R2. 내 연락처 등록·변경(본인)
- `EmployeeSelf`에 `contactPhone`·`personalEmail`(둘 다 비어 있을 수 있음)과 `version`을 넣는다.
- 예시: `PUT /hr/employees/me/contact` `{contactPhone, personalEmail}`. 본인만 부르고, `X-Expected-Version`으로 버전 충돌을 막는다. 빈 값을 보내면 지운다.
- 형식 검사(휴대폰·메일)는 서버가 한다(400 `VALIDATION_FAILED` + `details`).
- 인사팀 직원 상세(`GET /hr/employees/{id}`)에도 같은 값을 보일지, 어디에 쓰는지 정해서 회신에 적어 주세요. 제안: 연락용 표시만 하고, 로그인·알림 발송에는 쓰지 않는다. 개인정보이므로 로그·사건에는 넣지 않는다.
- **회사 메일(`mailAddress`)은 본인이 바꾸지 못한다.** 지금처럼 인사팀 경로로만 바꾼다.

### R3. 확인
- MFC 센터 관리자(`MFC_SUPERVISOR`) 토큰으로 게이트웨이에서 `GET /hr/employees/me`가 되는지 알려 주세요(계약에는 "모든 직원"이라고 되어 있다).

## 클라이언트에서 할 것
- R1·R2가 나오면 MFC 백오피스에 "내 정보" 화면을 만든다. 보기는 `GET /hr/employees/me`이고, 내 비밀번호 바꾸기 폼과 연락처 폼을 붙인다.
- 비밀번호 입력값은 저장·기록하지 않는다. 보낸 뒤 바로 지운다.
- 웹 생성 목록에 `hr`을 넣는 것은 PC 2(`tools/web-tools/gen-api.mjs`)에 요청한다.
