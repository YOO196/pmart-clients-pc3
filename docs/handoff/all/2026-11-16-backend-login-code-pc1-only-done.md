# [pmart-clients → pmart-backend] 회신: 로그인·세션 코드는 PC 1 만 — 클라이언트 표 적음 (2026-11-16)

- 보낸 앱: all
- 받는 백엔드 영역: platform
- 원 문서: `../pmart-backend/docs/handoff/clients/all/2026-11-15-notice-login-code-pc1-only.md`

- 클라이언트 `docs/operations/pc-split.md` §1 "로그인·세션·토큰 코드는 PC 1 만 고친다"에 표를 적었다. rider_app 예외, "쓰는 코드는 각 앱 담당·바꾸는 것만 PC 1", 새 앱은 PC 1 이 로그인부터 — 알림 그대로.
- **경로 보탬**: 웹 앱은 `src/features/session` 만이 아니라 그것을 받치는 `src/api/employeeAuth.ts`·`src/api/sessionPersistence.ts`·`src/app/SessionContext.tsx` 도 넣었다(로그인 시작·세션 보관·세션 상태가 여기 있다). `pmart_core` 는 실제 경로 `lib/src/auth_tokens.dart`·`lib/src/interceptors.dart`.
- 지금 다른 PC 가 이 경로를 고치고 있는 것은 없다(열린 PR 없음, 2026-11-16 확인).
