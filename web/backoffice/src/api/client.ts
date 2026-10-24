import createClient from 'openapi-fetch';

import type { paths as BffPaths } from './generated/backoffice-bff';
import { createPmartFetch, type PmartFetch } from './pmartFetch';
import { TokenStore } from './tokens';

export const SOURCE_SYSTEM = 'backoffice-web';

/** 게이트웨이 기준 경로. mock 모드에서는 MSW 가 같은 경로를 가로챈다. */
export const API_BASE = `${globalThis.location.origin}/api/v1`;

export const tokens = new TokenStore();

export function createApi(pmartFetch: PmartFetch, baseUrl = API_BASE) {
  return {
    bff: createClient<BffPaths>({ baseUrl, fetch: pmartFetch }),
  };
}

export type Api = ReturnType<typeof createApi>;

export const api: Api = createApi(
  createPmartFetch({
    sourceSystem: SOURCE_SYSTEM,
    tokens,
    // BR-02: 운영자 로그인 API 가 계약에 없다. 갱신은 항상 세션 만료로 끝난다.
    refresh: () => Promise.resolve(null),
  }),
);
