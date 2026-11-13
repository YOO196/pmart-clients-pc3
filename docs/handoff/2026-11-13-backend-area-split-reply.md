# 회신: 앱 영역 나누기 — 제안대로 받는다

- 보낸 앱: all
- 받는 백엔드 영역: platform
- 작성: pmart-clients, 2026-11-13
- 답하는 것: `../pmart-backend/docs/handoff/clients/2026-11-13-all-notice-area-split.md` §2
- 근거: 사용자 결정 2026-11-13 — "정한대로 해줘".
- 클라이언트 규칙 정본: pmart-clients `docs/operations/pc-split.md`(루트 `CLAUDE.md` 가 가리킨다).

## 1. 정한 규칙 (2026-11-14 부터)

| 항목 | 규칙 |
|---|---|
| 앱 영역 | 제안 그대로 — customer-app·mfc-app·rider-app·backoffice·hr-backoffice·web-common |
| 작업 일지 | `docs/worklog/<앱 영역>/YYYY-MM-DD.md` |
| 클라이언트 → 백엔드 handoff | `docs/handoff/YYYY-MM-DD-<앱 영역>-backend-<주제>.md`. 여러 앱이면 앱 영역 자리에 `all`. 첫머리에 `보낸 앱:`, `받는 백엔드 영역: platform\|mfc\|delivery` |
| 백엔드 → 클라이언트 handoff | 백엔드 새 이름 그대로 읽는다 — 각 앱 담당은 `*-<자기 앱 영역>-*` 와 `*-all-*` |
| 여럿이 고치는 문서 | `docs/backend-requests.md`·`contracts.lock`·`docs/roadmap.md`·루트 `CLAUDE.md` 는 main 에 합치는 쪽이 몰아서 고친다 |
| PC 간에 알아야 할 사실 | Claude 메모가 아니라 저장소 문서(`docs/operations/pc-split.md`, `CLAUDE.md`) |

- 2026-11-13 까지의 일지·handoff 는 이름·위치 그대로 둔다. 이 문서가 `보낸 앱`·`받는 백엔드 영역` 을 적은 첫 파일이다(파일 이름은 오늘 날짜라 옛 형식).
- 받는 백엔드 영역은 백엔드 `pc-split.md` §1 대로 고른다(인증·HR·승인·게이트웨이·배포·공통 계약과 그 밖 = platform, mfc-*-service = mfc, delivery-*·rider-* = delivery).

## 2. 아직 정하지 않은 것

- 어느 PC 가 어느 앱 영역을 맡는지 — 사용자가 정한다. 지금 정해진 것은 이 회신을 쓴 PC 가 **customer-app 위주**라는 것 하나다.
- 공통 문서를 합치는 PC, 영역 표에 없는 공통 폴더(`packages/pmart_*`·`tools/gen_api.dart` 등)의 담당.

## 3. 부탁

없다. 답이 필요한 것도 없다.
