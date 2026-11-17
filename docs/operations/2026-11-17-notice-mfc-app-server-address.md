# 알림: mfc_app 기기 설정의 서버 주소 바꾸기 — 고친 뒤 #49 를 합친다 (2026-11-17, PC 1)

- 받는 곳: PC 3(mfc-app)
- 보낸 곳: PC 1 (PR #48·#49 검토. 로그인·세션·토큰 영역이라 PC 1 이 본다)
- 결정: 사용자 2026-11-17 "(가) 고친 뒤 합치기" — #49 는 아래를 고친 뒤 합친다. #48 은 그때 함께 닫는다(쌓은 PR 은 맨 위만, `stacked-pr-squash-conflicts.md` §5).

## 1. 무엇이 문제인가
`features/device/data/server_address.dart` + `shared/providers.dart` `apiBaseUrlProvider`: 기기 설정에서 저장한 주소가 빌드 주소(`PMART_API_BASE_URL`)보다 먼저 쓰인다.

1. **아무 주소나 넣을 수 있다** — PDA 를 만질 수 있는 사람이 주소를 바꾸면 직원 access·refresh token 이 그 서버로 간다.
2. **`http://` 를 받는다** — 스킴이 없으면 `http://` 를 붙인다. LAN 게이트웨이는 HTTPS(`https://192.168.0.40:8443`, ADR-0057)다. 암호화 없는 주소로 내려갈 수 있다.
3. **주소를 바꿔도 세션이 남는다** — 이전 서버에서 받은 토큰을 새 주소로 보낸다.

## 2. 부탁 (셋 다)
1. 서버 주소 바꾸기는 **release 가 아닌 빌드에서만** 보인다/쓴다(`kReleaseMode` 면 기기 설정에 칸이 없고 저장값도 무시). 고객앱 `trustPmartLanRootCa()` 와 같은 기준(ADR-0057 T6 "lan/debug 빌드만").
2. **`https://` 만** 받는다. 스킴이 없으면 `https://` 를 붙인다. `http://` 는 거절 문구.
3. 주소를 저장(또는 기본값으로 되돌림)하면 **로그아웃**(보관한 토큰 지움)하고 로그인 화면으로. 안내 문구에 "주소를 바꾸면 다시 로그인해야 해요".
- 시험: 위 세 가지(release 에서 무시, http 거절, 저장하면 토큰 지움).
- 고쳐서 #49 에 올리면 PC 1 이 다시 보고 #49 만 squash, #48 은 닫는다.

## 3. PR 에서 확인한 나머지(문제 없음)
- 로그인 화면 변경: 목 모드에서 시험용 로그인 화면을 여는 자리만 바뀜. 실서버 로그인 경로 그대로.
- 재고 확인 `GET /mfcs/{id}/stock` 은 계약상 직원(OPERATOR) 경로 — 작업자 토큰 가능 여부는 이미 보낸 백엔드 질문(`handoff/mfc-app/2026-11-17-backend-pda-stock-check.md`) 회신을 기다린다.
- main + #47·#49·#50 을 합쳐 시험: mfc_app analyze 문제 없음, test 181 통과 · 3 실패(아래 4, main 도 같음).

## 4. 참고 — PC 1 이 고칠 것(손대지 않아도 됨)
- 최신 백엔드 계약으로 employee-auth 를 다시 생성하면 `features/auth/data/auth_repository.dart` 119·223 줄이 컴파일되지 않는다(`TokenPair.refreshToken` 이 null 가능 — ADR-0059). `test/auth_test.dart` 토큰 픽스처 3개도 새 필수 항목이 없다. main 에서도 같다. 로그인·토큰 코드라 PC 1 이 따로 고친다.
