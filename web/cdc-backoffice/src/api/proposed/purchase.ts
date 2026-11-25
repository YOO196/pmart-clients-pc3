// 상품 발주·공급사 — **제안 계약(목 전용)**. 사용자 2026-11-26 "비즈니스 로직대로 발주관련 만들되, 실제 공급사가 있는 게 아니라
// 주문에 대한 회신 가짜데이터로 받고 입고 시키라고".
// 정본 계약 procurement-service·supplier-service·cdc-inbound(ASN)는 아직 3단계 자리표시자(응답 Placeholder, 발주 목록 없음)라
// 경로 이름은 그 계약을 따르고 필드는 여기서 제안한다 — docs/handoff/cdc-backoffice/2026-11-26-backend-purchase-orders.md.
// 백엔드가 계약을 정하면 이 파일을 지우고 generated 타입으로 바꾼다. 실서버(local·lan)에서는 화면이 호출하지 않는다(PurchaseMenu).
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
/** 경로 변수 없는 명령(POST /suppliers·/purchase-orders) */
type PostRoot<B, R> = {
  parameters: {
    query?: never;
    header: CommandHeader;
    path?: never;
    cookie?: never;
  };
  requestBody: Json<B>;
  responses: { 200: Json<R>; 201: Json<R>; 409: Problem; 422: Problem };
};

/** 가짜 공급사의 회신 규칙(시험용) — 진짜 공급사가 없어 발주를 받으면 이 규칙대로 회신·ASN 을 만든다 */
export type ReplyMode = 'FULL' | 'PARTIAL' | 'REJECT';
export type SupplierState = 'ACTIVE' | 'SUSPENDED';

export interface Supplier {
  supplierId: string;
  name: string;
  businessNo: string | null;
  contactName: string | null;
  phone: string | null;
  /** 발주 → 도착까지 일 수(납기 기본값) */
  leadTimeDays: number;
  skus: string[];
  replyMode: ReplyMode;
  state: SupplierState;
  createdAt: string;
}

export interface SupplierBody {
  name: string;
  businessNo?: string;
  contactName?: string;
  phone?: string;
  leadTimeDays: number;
  skus: string[];
  replyMode: ReplyMode;
}

/**
 * 발주 상태 — 사업 흐름: 발주(ISSUED) → 공급사 회신(CONFIRMED·PARTIALLY_CONFIRMED·REJECTED) → ASN(ASN_RECEIVED) → 입고(RECEIVED).
 * 취소(CANCELLED)는 ASN 전에만.
 */
export type PoState = 'ISSUED' | 'CONFIRMED' | 'PARTIALLY_CONFIRMED' | 'REJECTED' | 'ASN_RECEIVED' | 'RECEIVED' | 'CANCELLED';

export interface PoLine {
  sku: string;
  orderedQty: number;
  /** 공급사가 회신한 수량(회신 전 null) */
  confirmedQty: number | null;
  /** ASN 수량(ASN 전 null) */
  shippedQty: number | null;
  lot: string | null;
  expiresAt: string | null;
  /** 입고 확정 수량(입고 전 null) */
  receivedQty: number | null;
  rejectedQty: number | null;
}

export interface Asn {
  asnId: string;
  shippedAt: string;
  expectedArrivalAt: string;
  vehicleNo: string | null;
}

export interface PurchaseOrder {
  purchaseOrderId: string;
  cdcId: string;
  supplierId: string;
  supplierName: string;
  state: PoState;
  dueDate: string;
  note: string | null;
  lines: PoLine[];
  issuedBy: string;
  issuedAt: string;
  repliedAt: string | null;
  replyNote: string | null;
  asn: Asn | null;
  receivedAt: string | null;
  receivedBy: string | null;
  cancelledAt: string | null;
  cancelReason: string | null;
  version: number;
}

export interface PoBody {
  cdcId: string;
  supplierId: string;
  dueDate: string;
  note?: string;
  lines: { sku: string; qty: number }[];
}

export interface ReceiptBody {
  lines: { sku: string; receivedQty: number; rejectedQty: number }[];
}

export interface paths {
  '/suppliers': {
    get: Get<{ state?: SupplierState }, NoPath, { items: Supplier[] }>;
    post: PostRoot<SupplierBody, Supplier>;
  };
  '/suppliers/{supplierId}': {
    get: Get<never, { supplierId: string }, Supplier>;
  };
  '/purchase-orders': {
    get: Get<{ cdcId: string; state?: PoState }, NoPath, { items: PurchaseOrder[] }>;
    post: PostRoot<PoBody, PurchaseOrder>;
  };
  '/purchase-orders/{purchaseOrderId}': {
    get: Get<never, { purchaseOrderId: string }, PurchaseOrder>;
  };
  '/purchase-orders/{purchaseOrderId}/cancellations': {
    post: Post<{ purchaseOrderId: string }, { reason: string }, PurchaseOrder>;
  };
  /** cdc-inbound — ASN 실수령·검수 확정 → 재고 증가 */
  '/asn/{asnId}/receipts': {
    post: Post<{ asnId: string }, ReceiptBody, PurchaseOrder>;
  };
}
