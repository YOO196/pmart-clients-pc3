import createClient from 'openapi-fetch';

import { createPmartFetch, TokenStore, type EmployeeAuthPaths, type PmartFetch } from '@pmart/web-core';
import { SOURCE_SYSTEM } from './command';
import { refreshEmployeeTokens } from './employeeAuth';
import type { paths as ApprovalPaths } from './generated/approval';
import type { paths as BffPaths } from './generated/backoffice-bff';
import type { paths as CasePaths } from './generated/case';
import type { paths as CenterPaths } from './generated/center-master';
import type { paths as ClaimPaths } from './generated/claim';
import type { paths as DispatchPaths } from './generated/delivery-dispatch';
import type { paths as ExecutionPaths } from './generated/delivery-execution';
import type { paths as HrPaths } from './generated/hr';
import type { paths as CapacityPaths } from './generated/mfc-capacity';
import type { paths as FulfillmentPaths } from './generated/mfc-fulfillment';
import type { paths as InboundPaths } from './generated/mfc-inbound';
import type { paths as InventoryPaths } from './generated/mfc-inventory';
import type { paths as LocationPaths } from './generated/mfc-location';
import type { paths as QualityPaths } from './generated/mfc-quality';
import type { paths as OrderPaths } from './generated/order';
import type { paths as ProductPaths } from './generated/product';
import type { paths as ProductContentPaths } from './generated/product-content';
import type { paths as RiderPaths } from './generated/rider';

export { SOURCE_SYSTEM };

/** 게이트웨이 기준 경로. 기본은 같은 출처(개발 프록시·mock 의 MSW). lan 은 VITE_PMART_API_BASE(게이트웨이 CORS 허용 출처에 있어야 한다). */
export const API_BASE = import.meta.env.VITE_PMART_API_BASE || `${globalThis.location.origin}/api/v1`;

export const tokens = new TokenStore();

/** 메뉴별 계약(handoff §2): 인력·배정·운영 제한 = capacity, 작업 현황 = fulfillment, 이동·입고 = inbound, 재고 = inventory, 위치 = location, 품질 = quality */
export function createApi(pmartFetch: PmartFetch, baseUrl = API_BASE) {
  const options = { baseUrl, fetch: pmartFetch };
  return {
    employeeAuth: createClient<EmployeeAuthPaths>(options),
    center: createClient<CenterPaths>(options),
    capacity: createClient<CapacityPaths>(options),
    fulfillment: createClient<FulfillmentPaths>(options),
    inbound: createClient<InboundPaths>(options),
    inventory: createClient<InventoryPaths>(options),
    location: createClient<LocationPaths>(options),
    quality: createClient<QualityPaths>(options),
    // 우리 센터 배송 현황(bff 0.3.1 live-delivery — 계약 servers.url /api/v1/backoffice)·배차 실패 사건(case 0.5.2)
    bff: createClient<BffPaths>({ ...options, baseUrl: `${baseUrl}/backoffice` }),
    cases: createClient<CasePaths>(options),
    // 본사 승인 요청(AP-1) — 422 APPROVAL_REQUIRED 의 요청 본문으로 변경 요청 만들기·제출, 승인 상태 조회
    approval: createClient<ApprovalPaths>(options),
    // 내 정보 — hr-service 본인 조회
    hr: createClient<HrPaths>(options),
    // 반납 인증번호(delivery-execution 0.28.0) — 회수·반납 배송이 MFC 로 올 때 라이더에게 알려 줄 4자리
    execution: createClient<ExecutionPaths>(options),
    // 배차 지연 목록(delivery-dispatch 0.12.0)
    dispatch: createClient<DispatchPaths>(options),
    // 배차 불가로 취소(claim 0.11.0 DC-1 — 회사 사유 전체 취소는 lines 생략)
    claims: createClient<ClaimPaths>(options),
    // 라이더 화면 표기 묶음 조회(rider 0.18.0 RS-MFC — "R4785" — ADR-0085)
    rider: createClient<RiderPaths>(options),
    // 센터 대시보드 주문 수·매출(order 0.20.0 O-11 — MFC_SUPERVISOR 는 토큰 센터만)·카테고리 목록(product 공개 categories/tree)
    order: createClient<OrderPaths>(options),
    product: createClient<ProductPaths>(options),
    // 상품 사진·고객용 상품명 카드(product-content /product-contents — 상품 관리 카드형, 2026-11-25)
    content: createClient<ProductContentPaths>(options),
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

/** 콘텐츠 이미지 경로(계약: 상대 경로 `/api/v1/content-images/{id}`) → 화면에서 쓸 주소. LAN 은 화면(:8445)과 게이트웨이(:8443) 출처가 달라 게이트웨이 출처를 붙인다. w = 축소본 폭(240·480·720) */
export function contentImageUrl(url: string | null | undefined, w: 240 | 480 | 720): string | null {
  if (!url) return null;
  if (/^(data:|blob:)/.test(url)) return url;
  const abs = new URL(url, new URL(API_BASE).origin);
  abs.searchParams.set('w', String(w));
  return abs.toString();
}
