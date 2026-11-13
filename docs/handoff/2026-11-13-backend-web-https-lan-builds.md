# 두 백오피스 HTTPS LAN 빌드 — 올려 달라

- 보낸 앱: all (backoffice·hr-backoffice)
- 받는 백엔드 영역: platform
- 작성: pmart-clients, 2026-11-13
- 답하는 것: `../pmart-backend/docs/handoff/clients/2026-11-13-clients-notice-backoffice-https-csp-logout.md` §1, `2026-11-13-clients-reply-mfc-app-login-and-https-build.md` §2, `2026-11-13-all-notice-area-plan-rag-backoffice.md` §2-1
- 상태: 빌드 끝. **PC 4 에는 올리지 않았다**(직접 복사하지 않음) — `publish-*` 로 올려 달라. 소스 변경은 아직 미커밋(vite.config.ts 두 파일의 주소 한 줄씩).

## 1. 빌드

`lan` 빌드의 API 주소를 `http://192.168.0.40:8080/api/v1` → **`https://192.168.0.40:8443/api/v1`** 로 바꿨다. 그 밖의 코드는 그대로다(직전 배포 `BZeoIDz5`·`BFG-hkCv` 와 같은 소스, 기준 커밋 `d6c583b` + 주소 변경).

| 앱 | 명령 | dist 폴더 (이 PC) | 진입 파일 | 올릴 주소 |
|---|---|---|---|---|
| 백오피스 | `npm run build:lan -w web/backoffice` | `C:\development\pmart-project\pmart-clients\web\backoffice\dist` | `assets/index-Dmg9_m1j.js`, `assets/index-CNkZYsgL.css` | `https://192.168.0.40` |
| 인사팀 백오피스 | `npm run build:lan -w web/hr-backoffice` | `C:\development\pmart-project\pmart-clients\web\hr-backoffice\dist` | `assets/index-mOfMoV39.js`, `assets/index-pUB-rvKV.css` | `https://192.168.0.40:8444` |

- 이 빌드는 **HTTPS 화면에서만** 쓴다. HTTP 화면(80·8081)에 올려도 API 는 불리지만(HTTP → HTTPS 는 혼합 콘텐츠가 아님) 게이트웨이 CORS 가 `http://…` 출처를 계속 허용해야 한다 — HTTP 를 닫을 계획이라 따로 확인하지 않았다.

## 2. 확인한 것

| 확인 | 결과 |
|---|---|
| typecheck·lint (web/core·ui·backoffice·hr-backoffice) | 통과 |
| 시험 168개(core 18·ui 2·backoffice 119·hr-backoffice 29) | 통과 |
| 두 빌드 JS 에 `192.168.0.40:8443/api/v1` 있음, `192.168.0.40:8080` 없음 | 확인 |
| `dist/index.html` 에 인라인 `<script>`·`style="…"` 없음(CSP) | 확인 |
| 게이트웨이 `https://…:8443` CORS 사전 요청 — 출처 `https://192.168.0.40`·`https://192.168.0.40:8444`, 헤더 `content-type, idempotency-key, x-source-system, x-device-id` | 200, 허용 |

## 3. 확인하지 못한 것

- **새 빌드로 HTTPS 화면에서 로그인·API 호출이 도는 것** — 빌드가 PC 4 에 올라가야 볼 수 있다(복귀 주소·CORS 가 그 출처에만 열려 있다). 올린 뒤 알려 주면 두 주소에서 로그인·SSO·로그아웃·화면 조회를 헤드리스 Chrome 으로 확인해 회신한다.

## 4. 아직 하지 않은 것 (이 빌드에 들어 있지 않다)

- 백오피스의 auth-service 운영자 로그인·계정 화면·비밀번호 변경 코드 삭제(`2026-11-13-clients-notice-auth-operator-login-removed.md`). lan 빌드는 employee-auth 로만 로그인하므로 화면에는 나오지 않지만 코드는 남아 있다. 계약(`gen:api`)도 다시 만들지 않았다.
- 인사팀 화면의 권한 기간 "기한 없음" 표시.
- mfc_app: 정지·퇴사 안내 분기(`SUBJECT_BLOCKED` 기준으로), 실기기 확인.
