# [pmart-clients → pmart-backend] 회신: MFC 백오피스 기반 만듦 + 배포·시험 계정 요청 (2026-11-15)

- 보낸 앱: mfc-backoffice
- 받는 백엔드 영역: platform (메뉴 API 질문은 mfc — PC 3)
- 원 문서: `../pmart-backend/docs/handoff/clients/mfc-backoffice/2026-11-15-request-mfc-backoffice.md`
- 클라이언트 화면 정리: `docs/apps/mfc-backoffice-web.md`

## 1. 한 것 — 기반만 (목 모드로 확인, 실서버 확인은 아직)
- 새 앱 `web/mfc-backoffice`(제안한 폴더 이름·개발 포트 그대로 — `http://localhost:5175`). 스택·로그인 코드는 다른 두 백오피스와 같다(`@pmart/web-core` 직원 로그인).
  - `app=mfc-backoffice`, 복귀 `<출처>/auth/callback`, 로그아웃 뒤 `/login`, `X-Source-System: mfc-backoffice-web`. LAN 빌드는 HTTPS 게이트웨이 `https://192.168.0.40:8443/api/v1` 를 부른다.
- 센터: 토큰 클레임 `centers` 로 고른다(§2-1 대로 `sessions/current` 는 쓰지 않는다). 주소에 센터를 넣는다(`/c/<mfcId>/<메뉴>`). 하나면 고르지 않고, 둘 이상이면 위에서 고른다. 이름은 `GET /centers?type=MFC` 에서 겹치는 것만 붙이고, 못 불러오면 코드로만 보인다.
  - 주소의 센터가 토큰에 없으면 "이 센터 권한이 없습니다", 403 문구도 같다.
- 역할: `MFC_WORKER` 만 있으면 "센터 관리자만 쓰는 화면입니다"(메뉴 없음). `MFC_SUPERVISOR` 가 없는 그 밖 역할은 막지 않고 안내만(판정은 서버). 맡은 센터가 없으면 안내만.
- 메뉴: §2 의 묶음 4개·메뉴 9개를 이름·순서 그대로 두었다(바꾸지 않음). **모든 메뉴가 아직 "화면 준비 중"** 이고, 들어가면 §2-1 의 "바로 쓸 수 있는 것"과 "자리만"을 나눠 보인다.
- 확인: typecheck·lint 통과, 테스트 14개 통과(목 모드). LAN 빌드 성공.

## 2. 요청
1. **빌드 올리기**: `web/mfc-backoffice/dist`(진입 `assets/index-DUFxsA45.js`, `assets/index-BtcOg322.css`)를 `lan.sh publish-mfc-backoffice` 로 올려 주세요. 기반만이라 로그인·센터 고르기·메뉴 자리 확인용이다.
2. **센터 관리자 시험 계정**(§3): `MFC_SUPERVISOR` + LAN MFC 하나. 비밀번호는 파일로(채팅·로그에 붙이지 않음). 센터 두 곳 계정도 있으면 센터 고르기를 확인할 수 있다.

## 3. §4 질문에 대한 답
- **이 앱을 어느 PC 가 만들지**: 기반은 PC 1(이 PC, 사용자 2026-11-15). 메뉴 화면을 누가 채울지는 아직 정하지 않았다 — 정해지면 `docs/operations/pc-split.md` 를 고치고 알린다. 앱 영역 `mfc-backoffice` 는 `pc-split.md` §3 에 넣었다.
- **폴더 이름·포트**: 제안대로 `web/mfc-backoffice`, `5175`.
- **기본 백오피스에 만든 MFC 화면**: 없다(회신 `backoffice/2026-11-15-backend-cs-rider-menus-done.md` §5 와 같음).
- **화면에 필요한데 API 에 없는 칸·조건**: 아직 메뉴 화면을 만들지 않아 목록이 없다. 화면을 만들면서 BR 로 올린다. 지금 보이는 "자리만" 목록은 §2-1 을 옮긴 것이다.
