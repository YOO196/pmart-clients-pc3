# PC 나눠 작업하기 — 앱 영역·기록 규칙 (2026-11-13)

여러 PC 가 이 저장소를 동시에 고친다(사용자 결정 2026-11-13 — "클라이언트 영역은 앱 단위로"). 같은 파일을 여러 PC 가 고치면 합칠 때 충돌하므로 **작업 일지·handoff·소유를 앱 영역 단위로 나눈다.** 백엔드의 같은 규칙은 `../pmart-backend/docs/operations/pc-split.md`, 제안서는 `../pmart-backend/docs/handoff/clients/2026-11-13-all-notice-area-split.md`.

적용: **2026-11-14 부터.** 2026-11-13 까지의 일지·handoff 파일은 이름·위치를 그대로 둔다.

## 1. 앱 영역

| 영역 | 폴더 |
|---|---|
| **customer-app** | `apps/customer_app` |
| **mfc-app** | `apps/mfc_app` |
| **rider-app** | `apps/rider_app` |
| **backoffice** | `web/backoffice` |
| **hr-backoffice** | `web/hr-backoffice` |
| **web-common** | `web/core`·`web/ui`·`tools/web-tools` (두 웹앱 공통 — 한 주인) |

- 영역 이름은 백엔드 제안과 같다(백엔드가 handoff 파일 이름에 그대로 쓴다).
- 위 표에 없는 공통 폴더(`packages/pmart_*`, `tools/gen_api.dart`, 루트 `CLAUDE.md`·`.claude/rules/`, `docs/architecture/` 등)는 따로 영역을 두지 않았다. 고칠 때는 고친 앱 영역의 일지에 적고 `영향: <다른 앱 영역>` 을 단다. 담당을 정해야 하면 사용자가 정한다(미정).
- 어느 PC 가 어느 영역을 맡는지는 사용자가 정한다. 2026-11-13: 이 규칙을 쓴 PC 는 **customer-app 위주**.
- 남의 영역 폴더를 고쳐야 하면 그 영역 담당과 겹치지 않게 사용자에게 먼저 알린다.

## 2. 작업 일지 — 앱 영역별 폴더

- **`docs/worklog/<앱 영역>/YYYY-MM-DD.md`**. 자기 영역 파일에만 쓴다.
- 다른 영역에 영향을 준 일은 자기 일지에 `영향: backoffice` 처럼 적는다(남의 일지에 쓰지 않는다).
- 형식과 나머지 규칙은 `docs/worklog/README.md` 그대로.

## 3. handoff — 파일 이름에 앱 영역

- 클라이언트 → 백엔드: **`docs/handoff/YYYY-MM-DD-<앱 영역>-backend-<주제>.md`**. 여러 앱에 걸치면 앱 영역 자리에 `all`.
  - 첫머리에 **`보낸 앱: <앱 영역>`** 과 **`받는 백엔드 영역: platform|mfc|delivery`** 를 적는다. 회신이면 원 문서 경로도 적는다.
  - 받는 영역 고르기: 인증·로그인·HR·승인·게이트웨이·배포·공통 계약과 아래 둘 밖의 모든 서비스는 platform, MFC 업무 API(mfc-*-service)는 mfc, 배송·라이더(delivery-*·rider-service·rider-auth-service)는 delivery.
  - 예: `2026-11-14-mfc-app-backend-picking-scan.md`(받는 백엔드 영역 mfc).
- 백엔드 → 클라이언트: `../pmart-backend/docs/handoff/clients/YYYY-MM-DD-<받는 앱 영역>-<종류>-<주제>.md`. 각 앱 담당은 **`*-<자기 앱 영역>-*` 와 `*-all-*`** 만 읽으면 된다. 2026-11-13 까지의 파일은 `…-clients-…`.
- 한 주제는 한 앱 영역이 보낸다(같은 주제를 두 PC 가 따로 보내지 않는다).

## 4. 여럿이 고치는 문서 — 한 곳이 몰아서

`docs/backend-requests.md`, `contracts.lock`, `docs/roadmap.md`, 루트 `CLAUDE.md` 처럼 여러 앱 영역이 고치는 파일은 각 PC 가 따로 고치지 않는다. 각 PC 는 자기 일지·handoff 파일에만 적고(예: "BR-xx 등록 필요", "계약 다시 생성: employee-auth, 백엔드 SHA"), main 에 합치는 쪽이 한 번에 반영한다. 자기 앱 줄 하나만 고치는 것은 괜찮다.

- 어느 PC 가 합치는지는 사용자가 정한다(미정).
- 브랜치 이름은 `<앱 영역>/<주제>`(예 `mfc-app/login-notice`)를 권한다.

## 5. 다른 PC 도 알아야 할 사실은 저장소 문서에

Claude 메모는 PC 마다 따로라 서로 모른다. 다른 PC 도 알아야 할 사실(바뀐 규칙·계정 받는 법·배포 방법)은 메모가 아니라 저장소 문서에 둔다 — 이 문서, 루트 `CLAUDE.md`, 백엔드의 `docs/operations/dev-on-other-pcs.md`(다른 PC 에서 개발하는 법).
