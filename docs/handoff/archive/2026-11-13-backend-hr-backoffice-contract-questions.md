# 인사팀 백오피스 요청 회신 — 계약 확인 결과와 질문 6건

- 작성: pmart-clients, 2026-11-13
- 답하는 것: `../pmart-backend/docs/handoff/clients/2026-11-13-clients-request-hr-backoffice.md` §5-1("계약만으로 만들기 어려운 것이 있으면 알려 달라")
- 본 것: `contracts/openapi/hr-service.yaml` 0.1.0, `approval-service.yaml`(종류 `GRANT`), `employee-auth-service.yaml`(로그인 `app`), `center-master-service.yaml`(`/centers`), 게이트웨이 `access/user-type-allowlist.txt`, `docs/business/flows/employee-account-provisioning.md` — 백엔드 `fc385b5` 기준
- **상태: 구현은 아직 시작하지 않았다**(사용자 시작 지시 대기). 이 문서는 계약을 읽고 확인한 것만 적는다.

## 1. 결론

요청서 §2 의 화면 8종은 모두 계약에 API 가 있어 **막히는 것은 없다.** 로그인은 `app=hr-backoffice` 만 바꿔 지금 백오피스 흐름을 그대로 쓴다(`app` 은 계약상 자유 문자열). 아래 6건은 답에 따라 화면이 달라지는 것들이다 — 답이 없으면 "답이 없을 때" 칸대로 만든다.

## 2. 질문

| # | 내용 | 답이 없을 때 이렇게 만든다 |
|---|---|---|
| Q1 | **본사 부서 코드 목록이 없다.** `Affiliation{type: HQ_DEPARTMENT, code}` 의 code 를 받아 올 API 가 없다. 정해진 부서 목록이 있는가, 자유 입력인가? | 자유 입력(계약 pattern `^[A-Za-z0-9_.-]{1,64}$` 만 검사). 목록 필터(`affiliationCode`)도 자유 입력 |
| Q2 | **`HR_ADMIN` 이 센터 목록을 조회할 수 있는가?** 센터 소속·요청 권한의 센터 고르기에 `GET /centers`(center-master)를 쓰려 한다. 계약에 역할 조건이 적혀 있지 않다. | `GET /centers` 로 고르기 목록을 만들고, 403·실패면 "센터 목록을 불러오지 못했어요" 안내 + 코드 직접 입력(빈 목록으로 보여 주지 않는다) |
| Q3 | **발급 다시 시도 조건이 문서마다 다르다.** 요청서 §2·흐름 문서는 "FAILED·COMPENSATED", 계약 `retryProvisioning` summary 는 "FAILED 일 때만". 어느 쪽이 맞는가? | 요청서대로 FAILED·COMPENSATED 에 버튼. 409 면 서버 안내를 그대로 보여 준다 |
| Q4 | **요청 권한의 근거가 조회에 없다.** 등록 `RequestedGrant.reason` 은 받는데 조회 `GrantRequestState` 에는 `reason` 이 없다. 상세 화면에 근거를 보여 주려면 필드가 필요하다. | 상세에는 역할·센터·기간·상태만 보여 준다(근거 칸 없음) |
| Q5 | **409 의 `code` 목록.** 계약에 `MAIL_ID_TAKEN` 만 적혀 있다. 버전 충돌(`X-Expected-Version`), 상태가 안 맞는 명령(퇴사자 정지, DONE 인데 재시도, 발급 전 메일 재발송·사서함 비밀번호 등)의 code 를 알려 달라. `departures` 는 `X-Expected-Version` 을 받는데 409 응답이 계약에 없다 — 버전이 달라도 처리되는가? | `MAIL_ID_TAKEN` 만 전용 문구, 나머지 409 는 Problem `detail` 을 그대로 보여 주고 "새로 고침 후 다시" 안내 |
| Q6 | **승인함에서 대상 직원의 이름을 알 수 없다.** `GRANT` 건의 `targetRef` 는 운영자 ID(`OP-…`)뿐이고 `GET /hr/employees/{id}` 는 `HR_ADMIN` 전용이라, 승인자(`OPERATOR_ADMIN`)는 누구의 권한인지 ID 로만 본다. 행 `attributes` 에 이름·사번·소속을 넣어 줄 수 있는가? | 승인 상세에 운영자 ID 만 보여 준다 |

## 3. 그 밖에 확인한 것(질문 아님)

- 역할 고르기 목록을 받아 올 API 는 없다 → 요청서 §3 의 12개를 화면에 고정으로 둔다. 역할이 늘면 알려 달라.
- `mailbox-password-resets` 는 같은 `Idempotency-Key` 재전송도 새로 발급한다 → 화면은 응답을 못 받은 경우 자동 재시도하지 않고, 사람이 다시 누르게 한다. `initialPassword` 는 화면 상태에만 두고(저장·로그·자동 복사 없음) 닫으면 지운다.
- `reinstatements` 의 `startDate`·`endDate` 는 요청서에 없지만 계약에 있어 복귀 화면에 선택 입력으로 넣는다.
- 지금 백오피스 승인 상세는 모르는 종류의 행 `attributes` 를 JSON 그대로 보여 준다 → `GRANT` 는 지금도 깨지지 않고 보이며, 역할·센터·기간·근거를 읽기 쉽게 보여 주는 표시를 추가할 예정.
- 실로그인 확인은 요청서대로 백엔드 LAN 배포(5-5) 알림 뒤에 한다. 그 전에는 목 서버로만 검증한다.
