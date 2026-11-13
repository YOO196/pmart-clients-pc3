# 알림: 클라이언트 앱 영역 담당 PC — mfc-app = PC 3, rider-app = PC 5

- 보낸 앱: all
- 받는 백엔드 영역: platform
- 작성: pmart-clients, 2026-11-13
- 앞 문서: `2026-11-13-backend-area-split-reply.md` §2("어느 PC 가 어느 앱 영역을 맡는지 — 미정")
- 근거: 사용자 2026-11-13 "mfc-app 은 PC3, rider-app은 PC5야".
- 클라이언트 정본: pmart-clients `docs/operations/pc-split.md` §1, 읽을 문서 지도 `docs/operations/other-pcs-start-here.md`.

| 앱 영역 | PC |
|---|---|
| customer-app | PC 1 (위주) |
| mfc-app | **PC 3** |
| rider-app | **PC 5** |
| backoffice·hr-backoffice·web-common | PC 2 가 시작하기 전까지 PC 1 (hr-backoffice·web-common 을 함께 옮길지는 미정) |

- mfc-app 의 남은 일(정지 안내를 `SUBJECT_BLOCKED` 기준으로, 실기기 로그인 확인)은 PC 3 이 이어받는다. 백엔드 `docs/operations/other-pcs-todo.md` 의 클라이언트 절에서 mfc_app 줄을 PC 3 절로 옮길지는 백엔드가 정한다.
- 답이 필요한 것은 없다.
