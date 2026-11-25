// 상품 발주·공급사 — 화면용 단순 모양(목 전용). 사용자 2026-11-26 "서비스를 새로 만들 게 아니라 페이지만 그렇게 만들고
// 구현 자체는 발주 내용에 따라 cdc 재고 적재량 달라지도록 단순하게".
// 백엔드 서비스·계약을 새로 요청하지 않는다. 실서버(local·lan)에서는 화면이 호출하지 않는다(PurchaseMenu).
/** commandParams 가 넣는 헤더(web-core CommandHeader 와 같은 모양) */
type CommandHeader = {
  'Idempotency-Key': string;
  'X-Source-System': string;
  'X-Expected-Version'?: number;
};

type Json<T> = { content: { 'application/json': T } };
type Problem = Json<{ code?: string; title?: string; status?: number }>;
type Get<Q, P, R> = {
  parameters: { query?: Q; header?: never; path: P; cookie?: never };
  requestBody?: never;
  responses: { 200: Json<R>; 404: Problem };
};
type Post<P, B, R> = {
  parameters: { query?: never; header: CommandHeader; path: P; cookie?: never };
  requestBody: Json<B>;
  responses: { 200: Json<R>; 201: Json<R>; 409: Problem; 422: Problem };
};
type NoPath = Record<string, never>;
/** 경로 변수 없는 명령 */
type PostRoot<B, R> = {
  parameters: { query?: never; header: CommandHeader; path?: never; cookie?: never };
  requestBody: Json<B>;
  responses: { 200: Json<R>; 201: Json<R>; 409: Problem; 422: Problem };
};

export interface Supplier {
  supplierId: string;
  name: string;
  contactName: string | null;
  phone: string | null;
  /** 공급 상품 */
  skus: string[];
  createdAt: string;
}

export interface SupplierBody {
  name: string;
  contactName?: string;
  phone?: string;
  skus: string[];
}

/** 발주(공급사는 가짜라 발주하면 바로 공급 확정) → 입고(재고에 더함). 입고 전엔 취소할 수 있다 */
export type PoState = 'ORDERED' | 'RECEIVED' | 'CANCELLED';

export interface PoLine {
  sku: string;
  qty: number;
  /** 입고 때 붙는 LOT(입고 전 null) */
  lot: string | null;
}

export interface PurchaseOrder {
  purchaseOrderId: string;
  cdcId: string;
  supplierId: string;
  supplierName: string;
  state: PoState;
  note: string | null;
  lines: PoLine[];
  orderedBy: string;
  orderedAt: string;
  receivedAt: string | null;
  cancelledAt: string | null;
}

export interface PoBody {
  cdcId: string;
  supplierId: string;
  note?: string;
  lines: { sku: string; qty: number }[];
}

export interface paths {
  '/suppliers': {
    get: Get<never, NoPath, { items: Supplier[] }>;
    post: PostRoot<SupplierBody, Supplier>;
  };
  '/purchase-orders': {
    get: Get<{ cdcId: string; state?: PoState }, NoPath, { items: PurchaseOrder[] }>;
    post: PostRoot<PoBody, PurchaseOrder>;
  };
  '/purchase-orders/{purchaseOrderId}': {
    get: Get<never, { purchaseOrderId: string }, PurchaseOrder>;
  };
  /** 입고 — 발주 수량만큼 CDC 재고에 더한다 */
  '/purchase-orders/{purchaseOrderId}/receipts': {
    post: Post<{ purchaseOrderId: string }, Record<string, never>, PurchaseOrder>;
  };
  '/purchase-orders/{purchaseOrderId}/cancellations': {
    post: Post<{ purchaseOrderId: string }, Record<string, never>, PurchaseOrder>;
  };
}
