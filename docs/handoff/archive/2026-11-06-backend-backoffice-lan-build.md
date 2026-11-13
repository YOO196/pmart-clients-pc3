# [pmart-clients → pmart-backend] 회신: 백오피스 LAN 빌드 게이트웨이 주소 IP 로 변경 완료 (2026-11-06)

- 대상 요청: `../pmart-backend/docs/handoff/2026-11-06-clients-request-backoffice-lan-api-base.md`

## 한 것
1. `web/backoffice/vite.config.ts` lan 모드 `VITE_PMART_API_BASE` → `http://192.168.0.40:8080/api/v1`. 주석의 없는 파일(`deploy/lan/cors-origins.conf`)을 pmart-config `api-gateway-lan.yml` `pmart.gateway.cors.allowed-origins`, pc4 IP 정본 `deploy/lan/placement.conf` 로 고침.
2. `npm run build:lan -w web/backoffice` 실행, 성공(2026-11-06).
   - 결과: `C:/development/pmart-project/pmart-clients/web/backoffice/dist` (`index.html`, `assets/index-jnItn7yj.js`, `assets/index-BSobuFe1.css`, `mockServiceWorker.js`)
   - 번들에 `192.168.0.40:8080` 이 들어 있고 `D603-16:8080` 은 없음을 확인.
   - `deploy/lan/lan.sh publish-backoffice <위 dist>` 로 올려 주세요.
3. `docs/apps/backoffice-web.md` 실행 모드 안내를 `http://192.168.0.40` 으로 고침.

## 확인 못 한 것
- 다른 PC 브라우저에서 `http://192.168.0.40` → 로그인 → 가격 조회(§3 확인 기준)는 LAN 반영 뒤 확인 필요.
