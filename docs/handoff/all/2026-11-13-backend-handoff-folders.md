# 알림·제안: 클라이언트 handoff 를 앱 영역 폴더로 나눴다 — 백엔드 쪽도 같은 구조로

- 보낸 앱: all
- 받는 백엔드 영역: platform
- 작성: pmart-clients, 2026-11-13
- 근거: 사용자 2026-11-13 "handoff 공간 나누는 게 맞는 것 같아" → "그 구조로 진행하자"(백엔드에는 사용자가 직접 말한다).
- 앞 문서: `archive/2026-11-13-backend-area-split-reply.md`(파일 이름에 앱 영역 — 이 문서가 그 규칙을 **폴더로** 바꾼다)
- 클라이언트 정본: pmart-clients `docs/handoff/README.md`, `docs/operations/pc-split.md` §5.

## 1. 클라이언트가 바꾼 것 (오늘부터)

```
pmart-clients/docs/handoff/
  customer-app/  mfc-app/  rider-app/  backoffice/  hr-backoffice/  web-common/   # 그 앱 영역이 보내는 문서
  all/           # 여러 앱에 걸친 문서
  archive/       # 처리가 끝난 문서(이름 그대로)
  README.md      # 규칙·지금 열려 있는 문서 목록
```

- 파일 이름: `YYYY-MM-DD-backend-<주제>.md`(폴더가 앱 영역). 첫머리 `보낸 앱`·`받는 백엔드 영역` 은 그대로.
- 왜: 한 폴더에 모든 앱의 문서가 쌓여(37개) 자기 것을 이름 패턴으로 골라야 했고, 끝난 것과 남은 것이 섞여 있었다. 작업 일지(`docs/worklog/<앱 영역>/`)와 같은 모양이 된다.

## 2. 옮긴 파일 — 백엔드 문서의 링크가 바뀐다

`pmart-clients/docs/handoff/<파일>` 로 적힌 링크는 아래처럼 바뀐다(파일 이름·내용은 그대로). 고칠지는 백엔드가 정한다.

| 옮긴 곳 | 파일 |
|---|---|
| `all/` | `2026-11-13-backend-client-todo-done.md`(**아직 열림 — 새 웹 빌드를 올려 달라**) |
| `mfc-app/` | `2026-11-10-backend-pda-work-areas.md`(**아직 열림 — BR-52·BR-53 회신 대기**) |
| `archive/` | 그 밖의 35개 전부(2026-10-24 ~ 2026-11-13) |

- `archive/` 로 옮긴 것 중 오늘 것: `…-area-split-reply`, `…-client-area-pcs-decided`(반영 확인함), `…-web-https-lan-builds`(올림 확인함), `…-hr-backoffice-contract-questions`·`…-hr-backoffice-lan-deployed`·`…-backoffice-sso-logout-deployed`·`…-mfc-app-employee-login-reply`(회신 받음), `2026-11-10-backend-dispatch-manual-only`(BR-51 회신 받음).
- 열린 것으로 잘못 옮긴 문서가 있으면 알려 달라 — 되돌린다.

## 3. 제안 — 백엔드 → 클라이언트 쪽도 같은 구조로

```
pmart-backend/docs/handoff/clients/
  customer-app/  mfc-app/  rider-app/  backoffice/  hr-backoffice/  web-common/  all/
  archive/       # 지금 그대로
```

- 파일 이름은 `YYYY-MM-DD-<종류>-<주제>.md`(종류 request·reply·notice), 첫머리 `보낸 영역:` 그대로.
- 그러면 각 앱 담당 PC 는 **자기 폴더와 `all/` 만** 보면 된다(지금은 `*-<앱 영역>-*`·`*-all-*` 이름 패턴으로 고른다).
- 지금 `clients/` 바로 아래에 남아 있는 문서(옛 이름 `…-clients-…` 포함)를 어느 폴더로 옮길지는 백엔드가 정한다. 옮기면 알려 달라 — 클라이언트 문서(`docs/operations/other-pcs-start-here.md` §2-2 등)의 경로를 고친다.

## 4. 답을 기다리는 것

- §3 을 받을지, 받으면 언제부터인지(폴더 이름·파일 이름 규칙).
