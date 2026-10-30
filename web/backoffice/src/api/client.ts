import createClient from 'openapi-fetch';

import { refreshOperatorTokens } from './auth';
import type { paths as ApprovalPaths } from './generated/approval';
import type { paths as AuthPaths } from './generated/auth';
import type { paths as BffPaths } from './generated/backoffice-bff';
import type { paths as CdcInventoryPaths } from './generated/cdc-inventory';
import type { paths as MfcInventoryPaths } from './generated/mfc-inventory';
import type { paths as PricingPaths } from './generated/pricing';
import type { paths as ProductPaths } from './generated/product';
import type { paths as ContentPaths } from './generated/product-content';
import { SOURCE_SYSTEM } from './command';
import { createPmartFetch, type PmartFetch } from './pmartFetch';
import { TokenStore } from './tokens';

export { SOURCE_SYSTEM };

/**
 * 게이트웨이 기준 경로. 기본은 같은 출처(개발 프록시·mock 의 MSW).
 * LAN 처럼 게이트웨이가 다른 출처면 VITE_PMART_API_BASE(예: http://D603-16:8080/api/v1) — 게이트웨이 CORS 허용 출처에 있어야 한다.
 */
export const API_BASE = import.meta.env.VITE_PMART_API_BASE || `${globalThis.location.origin}/api/v1`;

export const tokens = new TokenStore();

export function createApi(pmartFetch: PmartFetch, baseUrl = API_BASE) {
  const options = { baseUrl, fetch: pmartFetch };
  return {
    bff: createClient<BffPaths>(options),
    auth: createClient<AuthPaths>(options),
    approval: createClient<ApprovalPaths>(options),
    product: createClient<ProductPaths>(options),
    content: createClient<ContentPaths>(options),
    pricing: createClient<PricingPaths>(options),
    mfcInventory: createClient<MfcInventoryPaths>(options),
    cdcInventory: createClient<CdcInventoryPaths>(options),
  };
}

export type Api = ReturnType<typeof createApi>;

export const api: Api = createApi(
  createPmartFetch({
    sourceSystem: SOURCE_SYSTEM,
    tokens,
    // ADR-0018: 401 이면 refresh token 회전으로 한 번 갱신(single-flight). 세션이 끝나면 tokens 가 비워진다.
    refresh: () => refreshOperatorTokens(api, tokens),
  }),
);
