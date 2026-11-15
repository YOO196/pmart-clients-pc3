# handoff — 백엔드로 보내는 요청·질문·회신

pmart-clients 와 pmart-backend 는 서로의 저장소에 쓰지 않는다. 각자 자기 `docs/handoff/` 에만 쓰고 상대 것은 읽기만 한다.
백엔드가 보낸 것은 `../pmart-backend/docs/handoff/clients/` 에서 읽는다.

## 폴더 — 앱 영역별 (2026-11-13 사용자 결정)

| 폴더 | 무엇 |
|---|---|
| `customer-app/` `mfc-app/` `rider-app/` `backoffice/` `hr-backoffice/` `web-common/` | 그 앱 영역이 보내는 문서 — **자기 영역 폴더에만 쓴다** |
| `all/` | 여러 앱 영역에 걸친 문서 |
| `archive/` | 처리가 끝난 문서(양쪽 할 일이 끝났거나 뒤 문서가 대체). 2026-11-13 폴더를 나눌 때 그때까지의 문서 35개를 옮겼다(이름 그대로) |

- 폴더는 첫 문서를 쓸 때 만든다(빈 폴더는 git 에 없다).
- 파일 이름: **`YYYY-MM-DD-backend-<주제>.md`**(폴더가 앱 영역을 말한다). `archive/` 의 옛 파일은 옛 이름 그대로다.
- 첫머리에 `보낸 앱: <앱 영역>`, `받는 백엔드 영역: platform|mfc|delivery`, 회신이면 원 문서 경로를 적는다.
- 끝난 문서는 `archive/` 로 옮긴다(`git mv`, 이름 그대로). 이 저장소 문서가 그 경로를 가리키면 같은 커밋에서 고친다. 옮기는 것은 그 영역 담당 — 다른 영역 폴더의 문서는 옮기지 않는다.
- 항목 번호(BR-xx)는 양쪽이 그대로 쓴다. 상태표는 `docs/backend-requests.md`.
- 규칙 정본: `docs/operations/pc-split.md` §5.

## 지금 열려 있는 문서 (2026-11-13)

| 문서 | 기다리는 것 |
|---|---|
| `all/2026-11-13-backend-client-todo-done.md` | 새 웹 빌드 두 개를 백엔드가 올리는 것 |
| `all/2026-11-13-backend-handoff-folders.md` | 백엔드 쪽 handoff 폴더를 같은 구조로 나눌지 |
| `mfc-app/2026-11-10-backend-pda-work-areas.md` | BR-52·BR-53 회신(R1·R3·R4, R8~R11 은 받음 — 나머지) |
| `backoffice/2026-11-15-backend-assistant-connected.md` | 새 백오피스 빌드 올리기, 업무 도우미·문의 답변의 HTTPS 게이트웨이 경로·CORS, 답변 POST 의 같은 키 재전송 |
| `backoffice/2026-11-15-backend-cs-rider-menus-done.md` | 고객센터·라이더 운영 메뉴 반영 회신 — BR-54~56, 역할·version 질문, PC 5 권한 반영 |
| `hr-backoffice/2026-11-15-backend-rider-ops-role-and-role-list.md` | `RIDER_OPS` 반영 회신, 역할 목록 API(BR-57)를 만들지 |
| `customer-app/2026-11-15-backend-support-chat-inquiry.md` | 고객앱 문의·AI 상담 반영 알림 — LAN 고객 토큰으로 실제 확인, 질문 3개 |
| `mfc-app/2026-11-14-backend-br52-next-priority.md` | BR-52 R2·R19-1 을 먼저 해 줄지, LAN 기존 상품의 상품명·바코드 재발행 상태 |
