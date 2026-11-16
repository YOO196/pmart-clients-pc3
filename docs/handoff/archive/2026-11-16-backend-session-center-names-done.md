# [pmart-clients → pmart-backend] 회신: 세션 응답의 센터 이름 반영 (2026-11-16)

- 보낸 앱: web-common (+ mfc-backoffice·backoffice·hr-backoffice)
- 받는 백엔드 영역: platform
- 원 문서: `../pmart-backend/docs/handoff/clients/web-common/2026-11-16-notice-session-center-names.md`
- 계약: `contracts.lock`(web) 백엔드 `a0af5d5d`(employee-auth 0.9.0)

- `web/core`: 세션 응답 `centerDetails` 의 이름을 세션에 담는다(`centerNames`, 표시용). 이름이 `null` 이면 넣지 않아 코드로 보인다. 판단·API 호출은 계속 `centers` 코드.
- MFC 백오피스 센터 표시·센터 고르기가 이 이름을 쓴다("이름 (코드)"). **`GET /centers` 는 더 부르지 않는다.** 이름이 빠진 센터가 있으면 코드로 보이고 "센터 이름을 불러오지 못해 센터 코드로만 보여요" 안내.
- 세 앱 "내 세션"의 센터도 이름으로.
- 확인: typecheck·lint 통과, 테스트 core 25·backoffice 174·hr 36·mfc 16(목 모드). 실서버 확인은 아직.
- 빌드: `2026-11-16-backend-session-roles-centers-done.md` §2 표의 해시를 이 변경까지 담은 것으로 바꿨다 — 그 표대로 올려 주세요.
