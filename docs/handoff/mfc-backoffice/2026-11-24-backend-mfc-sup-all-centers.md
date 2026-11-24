# 요청 — 시험 계정 `claude-mfc-sup` 에 MFC 센터 다섯 곳 모두 권한

보낸 앱: mfc-backoffice (PC 3)
받는 백엔드 영역: platform (인사·직원 권한 — PC 1, LAN 운영)
날짜: 2026-11-24
상태: 요청

## 무엇
- 사용자 2026-11-24: "claude-mfc-sup 이 계정은 전 센터 다 접근할 수 있게 해주고."
- 지금 `claude-mfc-sup`(MFC_SUPERVISOR, 직원 번호 `OP-88399b05-87b7-48e2-aa33-229a3ab36f93`)은 `MFC-SEED-01` 만(`docs/operations/lan-test-accounts.md` §1).
- 바라는 것: 같은 역할(MFC_SUPERVISOR) 그대로, 센터를 **`MFC-SEED-01`·`MFC-MOKPO-01`·`MFC-SEJ-01`·`MFC-CHC-01`·`MFC-BNG-01`** 다섯 곳으로. 역할을 OPERATOR_ADMIN 으로 바꾸는 것이 아니다(센터 관리자 화면·권한 그대로 여러 센터).
- 이 PC 에는 인사팀 승인 계정(`claude-approver`)·Keycloak 관리자 비밀번호가 없어 PC 3 가 직접 못 한다. 인사팀 앱 권한 등록·승인(R-39 목포 `claude-mfc-sup-mk` 와 같은 절차)으로 부탁한다.

## 화면 쪽(이미 됨)
- MFC 백오피스는 세션 `GET /employee-auth/sessions/current` 의 `centers`·`centerDetails` 로 센터를 고른다 — 권한이 늘면 머리줄 센터 이름이 드롭다운이 되어 다섯 센터를 오간다. 코드 변경은 필요 없다.
- 시뮬레이터 관리 탭이 이 계정을 부산진구 관리 쓰기에 쓴다(`pmart-mfc-simulation` config `supervisorAccount`) — 센터가 늘어도 그 센터 API 는 그대로 된다(참고).

## 확인 부탁
- 끝나면 `lan-test-accounts.md` §1 센터 칸 갱신, 이 파일에 회신 위치를 적어 주면 PC 3 이 LAN 에서 다섯 센터 전환을 확인한다.
