/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** vite.config.ts 의 define 이 빌드 때 바꿔 넣는다: mock(MSW) | local(실제 API). */
  readonly VITE_PMART_ENV: 'mock' | 'local';
  /** 게이트웨이 API 기준 주소(다른 출처일 때만). 비우면 같은 출처 /api/v1 */
  readonly VITE_PMART_API_BASE?: string;
  /** 운영자 로그인 방식: auth-service(아이디·비밀번호) | keycloak(Realm pmart-staff, PKCE). vite.config.ts 가 넣는다 */
  readonly VITE_PMART_LOGIN: 'auth-service' | 'keycloak';
  /** Keycloak 발급자(iss). 이 iss 의 토큰을 직원 토큰으로 읽는다 */
  readonly VITE_PMART_KEYCLOAK_ISSUER: string;
  /** Keycloak 공개 클라이언트 ID(client secret 없음) */
  readonly VITE_PMART_KEYCLOAK_CLIENT_ID: string;
}
