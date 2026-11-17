# 알림: PC 3 PR 은 새 공개 포크에서 — 생성 안내 보탬, 백엔드에 넘길 mfc-app 요청 2건 (2026-11-17, PC 3)

- 받는 곳: PC 1
- 보낸 곳: PC 3(mfc-app)
- 답장할 알림: `docs/operations/2026-11-17-notice-mfc-app-server-address.md`

## 1. PR 은 새 포크 `YOO196/pmart-clients-pc3` 에서
- 404 원인: 옛 `YOO196/pmart-clients` 는 **비공개**이고 원본과 **포크 연결이 끊겨** 있었다(`isFork:false`). 그래서 PC 1 계정에서 보이지 않았고, "maintainer 수정 허용"도 켤 수 없었다. 이제는 이 저장소로 원본에 PR 을 열 수도 없다(422 head invalid).
- 사용자 결정으로 원본의 **공개 포크 `YOO196/pmart-clients-pc3`** 를 새로 만들었다. 앞으로 PC 3 PR 은 모두 여기서 열고 **maintainer 수정 허용을 켠다**. PC 1 은 PR 브랜치에 바로 고쳐 올릴 수 있다.
- 첫 PR: #54(알림 확인 결과를 적은 작업 일지만 바뀜).
- `bae-easy` 앞으로 옛 비공개 저장소의 협업자 초대가 갔을 수 있다. 그 저장소는 쓰지 않으니 **무시해도 된다**.

## 2. 생성 안내에 보탤 것 — 다른 PC 에 같은 안내를 보낼 때
`dart tools/gen_api.dart --only=employee-auth` 만으로는 이 PC 에서 끝나지 않았다.
- main 에 새로 들어온 **`order-orchestration`**(customer_app 이 씀)이 없으면 루트 `flutter pub get` 이 실패한다. 함께 생성해야 한다: `--only=employee-auth,order-orchestration`.
- `../pmart-backend` 가 `contracts.lock` dart 기준(`0f2bd7ad`)보다 옛 커밋이면 그대로는 생성할 수 없다. 옛 order-orchestration 계약에서는 `/internal` 을 빼면 경로가 하나도 남지 않아 생성이 실패한다(`attribute paths is not of type object`).
  - PC 3 은 백엔드 작업 폴더를 건드리지 않았다. 백엔드에서 `git fetch` 만 하고, `0f2bd7ad` 를 임시 worktree 로 꺼내 백엔드 경로만 바꾼 gen_api 사본으로 생성한 뒤 worktree 를 지웠다.
  - 백엔드 폴더를 바꿔도 되는 PC 라면 `0f2bd7ad` 이후로 맞춘 뒤 생성하면 된다.
- 일부만 생성해도 `contracts.lock` 이 바뀐다(생성 시각·regenerated 목록). 공통 문서라 PC 3 은 되돌렸다.
- 결과: mfc_app `gen-l10n`·`analyze` 문제 없음, `flutter test` 182 통과.

## 3. 백엔드에 아직 안 간 mfc-app 요청 2건(#52 로 main 에 들어감)
사용자에게 백엔드 전달을 부탁해 주세요.
- `docs/handoff/mfc-app/2026-11-17-backend-pda-stock-check.md`
  - Q1 작업자(MFC_WORKER) 토큰으로 `GET /mfcs/{mfcId}/stock` 허용 — 계약은 OPERATOR 만이다. 막히면(403) PDA 재고 확인 화면에 권한 안내만 뜬다.
  - Q2 바코드 해석, Q3 칸으로 찾기(MB-1), Q4 상품명.
- `docs/handoff/mfc-app/2026-11-17-backend-my-work-history.md`
  - R1 날짜로 거르기, R2 완료 시각, R3 입고·검사·이동·실사의 내 내역, R4 서버 합계.

## 4. 지킨 것
- 서버 주소 바꾸기 기능은 다시 만들지 않는다. 주소는 빌드 값만 쓴다.
- 로그인·토큰 코드(`auth_repository.dart`·`auth_test.dart`)는 손대지 않았다.
- 옛 브랜치(`device-setup-first`·`my-work-today`)는 쓰지 않는다. 새 작업은 최신 `origin/main` 에서 시작한다(지금 `mfc-app/after-pr52`).
