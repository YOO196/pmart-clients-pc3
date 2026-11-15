# 쌓은 PR 을 squash 로 합칠 때 생기는 충돌 — 내역과 해결 (2026-11-16)

- 대상: 포크 → PR 로 보내는 PC(`pc-split.md` "다른 PC 가 원본에 넣는 방법")와 합치는 PC 1
- 사례: mfc_app PR #5~#10 (YOO196, 2026-11-15 올림, 2026-11-16 PC 1 이 합침)

## 1. 무슨 일이 있었나
- PR #5~#10 은 **앞 PR 브랜치 위에 다음 브랜치를 쌓았고, 여섯 개 모두 base 가 `main`** 이었다. 그래서 #10 에는 #5~#9 의 커밋이 다 들어 있다.
- 원본은 PR 을 **squash** 로 합친다(#1~#4 와 같음). squash 는 PR 의 커밋들을 **새 커밋 하나**로 만들어 main 에 넣는다. 원래 커밋(`c483f0c` 등)은 main 에 들어가지 않는다.
- 그 결과 #5 를 합친 뒤 #6 을 보면, #6 안의 #5 원래 커밋과 main 의 #5 squash 커밋이 git 에게는 **다른 커밋**이다. 두 쪽이 같은 파일을 새로 만들거나 고친 것으로 보여 충돌이 난다. 같은 일이 #6 → #7 → … 로 매번 되풀이된다.
- 시작할 때 GitHub 표시: #10 만 `MERGEABLE`, #5~#9 는 `UNKNOWN`(아직 계산 안 됨). #5 를 합친 직후 #6 은 `CONFLICTING`.

## 2. 충돌 파일 (PR 원래 상태 vs 앞 PR 을 squash 한 직후 main)

| PR | 그때 main | 충돌 파일 | 종류 |
|---|---|---|---|
| #6 피킹 위치 스캔 화면 | `578b140` (#5) | `docs/worklog/mfc-app/2026-11-16.md` | add/add |
| #7 위치 줄 선반 칸 색 블록 | `42c3903` (#6) | `apps/mfc_app/lib/shared/location_guide.dart`, `apps/mfc_app/tool/screenshots.dart`, 일지 | add/add |
| #8 역할별 홈·관리 메뉴 | `c591125` (#7) | `apps/mfc_app/lib/l10n/app_ko.arb`(내용), `tool/screenshots.dart`, 일지 | 내용·add/add |
| #9 이동 지시 만들기·취소 | `4097737` (#8) | `lib/features/work/presentation/work_screens.dart`, `lib/l10n/app_ko.arb`, `lib/router.dart`, `docs/apps/mfc-app.md`, 일지 | 내용·add/add |
| #10 실사 시작·차이 승인 | `fea8240` (#9) | #9 와 같은 다섯 파일 | 내용·add/add |

- #5 는 충돌 없이 합쳐졌다(`578b140`).
- 모든 충돌은 **앞 PR 이 이미 바꾼 줄**에서 났다. 뒤 PR 은 앞 PR 을 포함하므로 뒤 PR 쪽 파일이 "앞 PR + 이번 변경"으로 맞는 내용이다.
- 매일 하나인 일지 파일은 PR 마다 아래에 절을 더하므로 **모든 PR 에서** 충돌했다.

## 3. 어떻게 풀었나 (PC 1)
1. **먼저 한꺼번에 시험**: 지금 main(`f50025c`) 위에 #10 을 합친 로컬 브랜치를 만들었다. 충돌 없이 합쳐졌다. PR 이 쓰는 클라이언트 4개(product·mfc-capacity 0.14.0·mfc-inbound 0.9.0·mfc-inventory 0.16.0)를 백엔드 `082f3d1` 계약으로 다시 만들었다. 그 위에서 `flutter analyze` 문제 없음, `flutter test` 165개 통과(목 모드).
2. **#5 squash**.
3. **#6~#10 을 차례로 처리**(PR 이 "maintainer 수정 허용"이라 PC 1 이 PR 브랜치에 올릴 수 있었다):
   - PR 브랜치에 `origin/main` 을 합친다(merge 커밋).
   - 충돌 파일은 **PR 쪽 파일을 그대로 택한다**(`git checkout <PR 머리> -- <파일>`). 단 충돌 파일이 `apps/mfc_app/`·mfc-app 일지·`docs/apps/mfc-app.md` 밖이면 멈추게 했다(그런 경우는 없었다).
   - **확인**: 합친 결과의 `apps/`·`docs/apps/mfc-app.md`·mfc-app 일지가 PR 원래 머리와 한 글자도 다르지 않아야 올린다.
   - 포크의 PR 브랜치에 올린다 → GitHub 가 `MERGEABLE` 로 바뀐 것을 보고 squash.
   - PR 브랜치에 생긴 합치기 커밋: #6 `8306b9e`, #7 `d59eaee`, #8 `b488fdd`, #9 `ba9b93d`, #10 `4bc7852`.
4. **끝 확인**: 합친 원본 main(`7bb6c70`)과 1번 시험 브랜치의 내용이 같다(`git diff` 빈 결과). 1번 시험이 곧 최종 main 시험이다.
5. 다시 만든 클라이언트를 `contracts.lock`(dart)에 적고 일지와 같이 커밋했다(`098e349`).

## 4. 앞으로 — PR 을 보내는 PC
충돌을 안 만드는 순서대로 적었다.

1. **PR 은 한 번에 하나.** 앞 PR 이 합쳐진 뒤 `git fetch origin && git rebase origin/main` 하고 다음 PR 을 올린다.
2. 꼭 쌓아야 하면, 앞 PR 이 squash 된 뒤 다음 브랜치를 **앞 PR 커밋을 빼고** 옮긴 다음 강제 push 한다.
   ```bash
   git fetch origin
   # <앞 브랜치 머리> = 앞 PR 의 마지막 커밋(squash 전 원래 것)
   git rebase --onto origin/main <앞 브랜치 머리> <다음 브랜치>
   git push --force-with-lease fork <다음 브랜치>
   ```
   이렇게 하면 다음 PR 에는 자기 변경만 남는다. 충돌이 남으면 그 PR 의 진짜 충돌이다.
3. 쌓은 PR 설명 첫 줄에 "PR #N 위에 쌓음 — #N 다음에 합칠 것"을 적는다(이번처럼). PC 1 이 순서를 지킨다.
4. 일지: 같은 날 여러 PR 이 같은 일지 파일 끝에 절을 더하면 늘 충돌한다. 위 1·2 를 지키면 rebase 한 번에 풀린다. 충돌이 나면 **두 쪽 절을 모두 남긴다**.
5. PR 설명에 "계약 다시 생성: <서비스>, 백엔드 SHA"를 적는다. `contracts.lock` 은 PC 1 이 합치면서 고친다(`pc-split.md` §5).

## 5. 앞으로 — 합치는 PC 1
- 쌓은 PR 묶음이 오면 맨 위 PR 을 main 위에 먼저 합쳐 analyze·test 를 한 번 돌린다(§3-1).
- 그다음 아래 PR 부터 squash. 충돌하면 §3-3 처럼 "PR 쪽 파일 택하기 + PR 원래 머리와 같은지 확인"으로 푼다. 이 확인이 비지 않으면(PR 과 달라지면) 멈추고 PR 을 보낸 PC 에 rebase 를 부탁한다.
- maintainer 수정이 허용되지 않은 PR 은 PC 1 이 브랜치에 올릴 수 없다. 그때는 보낸 PC 에 §4-2 를 부탁한다.
- 다른 길: 맨 위 PR 하나만 **merge 커밋**으로 합치면 아래 PR 은 GitHub 가 "합쳐짐"으로 바꾼다. 다만 원본은 squash 로 합쳐 왔으므로, 이 방법을 쓸지는 사용자가 정한다.
