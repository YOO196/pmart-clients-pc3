import createClient from 'openapi-fetch';

import { createPmartFetch, TokenStore, type EmployeeAuthPaths, type PmartFetch } from '@pmart/web-core';
import { SOURCE_SYSTEM } from './command';
import { refreshEmployeeTokens } from './employeeAuth';
import type { paths as CenterPaths } from './generated/center-master';
import type { paths as HrPaths } from './generated/hr';

export { SOURCE_SYSTEM };

/** 게이트웨이 기준 경로. 기본은 같은 출처(개발 프록시·mock 의 MSW). lan 은 VITE_PMART_API_BASE(게이트웨이 CORS 허용 출처에 있어야 한다). */
export const API_BASE = import.meta.env.VITE_PMART_API_BASE || `${globalThis.location.origin}/api/v1`;

export const tokens = new TokenStore();

export function createApi(pmartFetch: PmartFetch, baseUrl = API_BASE) {
  const options = { baseUrl, fetch: pmartFetch };
  return {
    employeeAuth: createClient<EmployeeAuthPaths>(options),
    hr: createClient<HrPaths>(options),
    center: createClient<CenterPaths>(options),
  };
}

export type Api = ReturnType<typeof createApi>;

export const api: Api = createApi(
  createPmartFetch({
    sourceSystem: SOURCE_SYSTEM,
    tokens,
    // 401 이면 refresh token 회전으로 한 번 갱신(single-flight). 세션이 끝나면 tokens 가 비워진다.
    refresh: () => refreshEmployeeTokens(api, tokens),
  }),
);
