/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** vite.config.ts 의 define 이 빌드 때 바꿔 넣는다: mock(MSW) | local(실제 API). */
  readonly VITE_PMART_ENV: 'mock' | 'local';
  /** 게이트웨이 API 기준 주소(다른 출처일 때만). 비우면 같은 출처 /api/v1 */
  readonly VITE_PMART_API_BASE?: string;
  /** 직원 로그인 방식: auth-service(아이디·비밀번호, mock·local) | employee-auth(게이트웨이 로그인 시작 → 티켓 교환, lan). vite.config.ts 가 넣는다 */
  readonly VITE_PMART_LOGIN: 'auth-service' | 'employee-auth';
}
