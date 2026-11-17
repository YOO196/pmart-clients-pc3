# 알림: mfc_app 기기 설정의 서버 주소 바꾸기(네트워크) 화면을 뺐다 — #48·#49 는 #52 로 합침 (2026-11-17, PC 1)

- 받는 곳: PC 3(mfc-app)
- 보낸 곳: PC 1 (로그인·세션·토큰 영역이라 PC 1 이 검토)

## 1. 무슨 일이 있었나
- PR #48·#49 검토에서 기기 설정의 **서버 주소 바꾸기**가 문제였다: 바꾼 주소로 직원 access·refresh token 이 가고, `http://` 를 받고, 주소를 바꿔도 세션이 남는다.
- 사용자 결정(2026-11-17): **"기기 설정에서 서버 주소와 모드를 고르는 화면 없애줘"** → **"main 에 바로 넣기"**.
- PC 3 포크(`YOO196/pmart-clients`)를 이 PC 계정에서 볼 수 없어(GitHub 404) #49 브랜치에 올리지 못했다. 그래서 PC 1 이 #49 + 화면 빼기를 **#52** 로 원본에 올려 합쳤다(main `ccaae1f`). **#48·#49 는 닫았다.**

## 2. 뺀 것 (#52 안의 `493107f`)
- `apps/mfc_app/lib/features/device/data/server_address.dart`(삭제)
- 기기 설정의 "네트워크" 칸, `NetworkSettingsScreen`, 라우트 `/setup/network`
- `main.dart` 의 저장 주소 읽기, `shared/providers.dart` `apiBaseUrlProvider` 의 저장 주소 우선 → **빌드 값(`PMART_API_BASE_URL`)만**(예전 main 과 같음)
- 문구 `network*`·`setupNetwork*`, 시험(네트워크 3·주소 정리 1), 캡처 `33-setup-network`, `docs/apps/mfc-app.md` 설명
- 남긴 것: 시작 메뉴·프린터·스캐너 확인·기기 정보·재고 확인·오늘 업무 내역 전부. 기기 정보의 "실행 모드"는 보기만이라 그대로(모드를 고르는 화면은 원래 없었다).

## 3. PC 3 이 할 일
1. **옛 브랜치(`mfc-app/device-setup-first`, `mfc-app/my-work-today`)는 더 쓰지 않는다.** 그 위에서 이어 작업하면 다음 PR 에 네트워크 화면이 다시 들어온다.
   ```bash
   git fetch origin
   git switch main && git reset --hard origin/main   # 로컬 main 을 원본에 맞춤(로컬에만 있는 커밋이 없는지 먼저 확인)
   git switch -c <새 브랜치> origin/main
   ```
   옛 브랜치에 아직 PR 로 안 보낸 작업이 있으면 그 커밋만 새 브랜치로 옮긴다(`git cherry-pick <커밋>`), 네트워크 화면 커밋은 빼고.
2. 서버 주소를 PDA 에서 바꾸는 기능을 다시 만들지 않는다(필요하면 사용자에게 먼저 묻는다). 주소는 빌드 값만.
3. PDA 에 이미 설치한 앱은 새 main 으로 다시 빌드해 설치하면 화면이 사라진다. 예전 앱에서 저장한 주소(보안 저장소 `mfc.server.v1`)는 남아 있어도 새 코드가 읽지 않는다.
4. 포크 접근: PC 1 이 PR 브랜치에 고친 커밋을 올릴 수 있게 포크 공개 여부·권한을 확인해 달라(지금은 404).

## 4. 같이 바뀐 것 — 로그인 토큰 처리 (PC 1, 손대지 않아도 됨)
- 최신 employee-auth 계약(`TokenPair.refreshToken` null 가능, ADR-0059)에 맞춰 `features/auth/data/auth_repository.dart` 를 고쳤다: refresh token 이 비어 오면 로그인은 "일시 오류"(토큰 보관 안 함), 갱신은 계약 위반으로 올린다(세션 끝남이 아님). `test/auth_test.dart` 토큰 픽스처에 `refreshTransport` 추가 + 시험 2개.
- `packages/pmart_api/gen/employee-auth` 는 **다시 생성**해야 한다: `dart tools/gen_api.dart --only=employee-auth` (contracts.lock dart = 백엔드 `0f2bd7ad`). 안 하면 analyze 에 "불필요한 null 비교" 경고가 날 수 있다.
- mfc_app `flutter analyze` 문제 없음, `flutter test` 182 통과(PC 1, main + 이 수정).
