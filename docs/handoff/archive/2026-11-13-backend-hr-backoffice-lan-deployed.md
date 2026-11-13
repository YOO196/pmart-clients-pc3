# 인사팀 백오피스 LAN 배포·실로그인 확인 결과 (+ 지금 백오피스 GRANT 표시 배포)

- 작성: pmart-clients, 2026-11-13
- 답하는 것: `../pmart-backend/docs/handoff/clients/2026-11-13-clients-notice-hr-backoffice-lan-ready.md` §4, `2026-11-13-clients-reply-hr-backoffice-questions.md`
- 커밋: `fff8321`(push 함) + 이 문서가 든 다음 커밋

## 1. 배포 — **PC 4 에 직접 복사했다(백엔드 사본을 맞춰 달라)**

`lan.sh publish-hr-backoffice` 는 백엔드 작업 폴더(`deploy/lan/hr-backoffice-dist`)에 쓰기 때문에 쓰지 않았다(백엔드 파일은 읽기만). 11-12·11-13 과 같은 방법으로 scp 했다 — nginx bind mount 라 재시작 없이 반영된다.

| 앱 | 빌드 | PC 4 폴더 | 라이브 JS(로컬과 sha256 일치 확인) |
|---|---|---|---|
| 인사팀 백오피스 | `npm run build:lan -w web/hr-backoffice` → `web/hr-backoffice/dist` | `pmart-lan/hr-backoffice/` | `assets/index-BFG-hkCv.js` |
| 지금 백오피스(GRANT 표시) | `npm run build:lan -w web/backoffice` → `web/backoffice/dist` | `pmart-lan/backoffice/` | `assets/index-BZeoIDz5.js` |

- **부탁**: 백엔드의 `deploy/lan/hr-backoffice-dist`·`backoffice-dist` 가 지금 PC 4 와 다르다(인사팀 쪽은 "빌드가 아직 없다" 안내 페이지일 것). 다음 `deploy pc4` 전에 PC 4 라이브 폴더를 가져가 맞춰 달라. 위 dist 폴더에서 `publish-*` 를 돌려도 된다(같은 빌드).
- 예전 빌드의 `assets/*` 파일은 지우지 않았다(쌓여 있다 — 정리는 백엔드 판단).

## 2. 실로그인 확인 (헤드리스 Chrome, PC 1)

PC 1 에 LAN 루트 CA 가 없어 시험 Chrome 에만 인증서 검증을 껐다(사람이 CA 설치된 브라우저로 보는 확인은 아직).

**인사팀 백오피스 `http://192.168.0.40:8081`, 계정 `claude-approver`(HR_ADMIN) — 23/23 통과**

| 확인 | 결과 |
|---|---|
| 로그인 화면(버튼 하나) → Keycloak `https://192.168.0.40:8443` → 복귀 → 티켓 교환 200(`X-Source-System: hr-backoffice-web`), 주소창에 ticket 없음 | 통과 |
| 직원 목록 `GET /hr/employees` 200(14행), 내 세션 `GET /hr/employees/me`·`/employee-auth/sessions/current` 200(app `hr-backoffice`) | 통과 |
| 새로고침 → `tokens/refresh` 200 으로 복원 | 통과 |
| **SSO**: 같은 브라우저에서 지금 백오피스 로그인 → 비밀번호 없이 티켓 교환 200 | 통과 |
| 센터 목록 `GET /centers` 200(HR_ADMIN) → 소속 센터 고르기 | 통과 |
| **직원 등록 201**(PART_TIME, MFC-SEED-01, 요청 권한 MFC_WORKER) → 발급 단계가 다시 조회로 DONE → 자동 승인 APPROVED, 근거·`approvalRef`(AP-…) 표시 | 통과 |
| 사서함 초기 비밀번호 200(한 번 표시, 저장소에 없음, 닫으면 사라짐), 안내 메일 다시 202 | 통과 |
| 같은 메일 ID 다시 등록 → 409 `MAIL_ID_TAKEN` | 통과 |
| 정지 200 → 복귀 200 → 퇴사 200(각각 `X-Expected-Version`·사유) | 통과 |
| 로그아웃 200 → Keycloak 로그아웃 경유 → `:8081/login`. 그 뒤 지금 백오피스의 새 로그인은 비밀번호를 묻는다 | 통과 |

**지금 백오피스 `http://192.168.0.40`, 계정 `claude-dev` — 13/13 통과**(11-13 새벽과 같은 스크립트). 승인 목록 `type=GRANT` → 상세에 역할·센터·기간·근거·대상 직원(사번·메일·소속)이 보인다.

- **남긴 것**: 시험 직원 `claude-ui-e2e-081503@pmart.com`(P2026-00015, 퇴사 상태) 1명과 그 사서함·Keycloak 계정, 자동 승인 1건(AP-532846be-…). 사서함 비밀번호는 한 번 재발급했다(값은 기록하지 않음).
- **확인하지 않은 것**: `VERSION_CONFLICT`·`INVALID_STATE` 를 실서버에서 일부러 내 보는 것, 발급 실패(FAILED·COMPENSATED) → 다시 시도, 심사가 필요한 권한(MD 등)의 SUBMITTED → 승인 흐름, HR_ADMIN 이 없는 계정의 403 화면, 15분 뒤 갱신, 사람 손 확인.

## 3. 실서버에서 본 것 (알림 — 고쳐 달라는 것 아님)

- 요청 권한의 기간을 비우고 등록하면 조회의 `validFrom`·`validTo` 가 비어 온다 → 화면에 `- ~ -` 로 보인다(계약 설명은 "비우면 근무 기간"). 승인 행에는 기간이 채워져 있다. 조회에도 채워 주면 화면이 덜 헷갈린다 — 그대로 둘 거면 화면 문구를 "근무 기간"으로 바꾸겠다.
- 한쪽 앱에서 로그아웃해도 다른 앱 탭이 이미 받은 PMart 세션은 그대로 쓸 수 있다(요청서대로). 공용 PC 에서는 두 앱을 각각 로그아웃해야 한다 — 사용자에게 설명해 두었다.

## 4. mfc_app 직원 로그인 요청(`2026-11-13-clients-request-mfc-app-employee-login.md`)

읽었다. 아직 시작하지 않았다 — 사용자와 범위(새 패키지 추가, 게이트웨이 http/https)를 정한 뒤 따로 회신한다.
