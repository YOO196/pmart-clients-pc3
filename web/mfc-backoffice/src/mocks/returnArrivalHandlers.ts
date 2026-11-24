// 반납 도착 대기 목(mfc-inbound 0.13.0 `GET /return-arrivals?mfcId=&state=WAITING` — 그 센터 운영자, 오래된 순).
// 백오피스는 보기만(반입은 PDA). 서울 센터 건은 부산 센터 목록에 나오지 않는다.
import { http, HttpResponse } from 'msw';

import { API_BASE } from '../api/client';
import type { components } from '../api/generated/mfc-inbound';
import { operator, problem, unauthorized } from './support';
import { addToArray } from './demoCenters';

type ReturnArrival = components['schemas']['ReturnArrival'];

const arrivals: ReturnArrival[] = [
  {
    arrivalId: 'DLV-RET-0',
    mfcId: 'MFC-BJG-01',
    purpose: 'CLAIM_RETURN',
    claimId: 'CLM-1',
    caseId: null,
    originDeliveryId: 'DLV-ORD-1',
    orderId: 'ORD-1',
    riderId: 'RD-31',
    state: 'WAITING',
    returnReceiptId: null,
    arrivedAt: '2026-11-20T02:40:00.000Z',
    lines: [
      { orderLineId: 'OL-1', sku: 'SKU-MILK-1', productName: '서울우유 1L', qty: 2 },
      { orderLineId: 'OL-2', sku: 'SKU-RAMEN-5', productName: '신라면 5입', qty: 1 },
    ],
  },
  {
    arrivalId: 'DLV-RET-3',
    mfcId: 'MFC-BJG-01',
    purpose: 'MISDELIVERY_RECOVERY',
    claimId: null,
    caseId: 'CASE-MD-1',
    originDeliveryId: 'DLV-ORD-9',
    orderId: 'ORD-9',
    riderId: 'RD-32',
    state: 'WAITING',
    returnReceiptId: null,
    arrivedAt: '2026-11-20T02:55:00.000Z',
    lines: [{ orderLineId: 'OL-9', sku: 'SKU-YOG-1', productName: '그릭요거트 400g', qty: 1 }],
  },
  {
    arrivalId: 'DLV-RET-S',
    mfcId: 'MFC-MOKPO-01',
    purpose: 'FAILED_DELIVERY_RETURN',
    claimId: null,
    caseId: null,
    originDeliveryId: 'DLV-S-9',
    orderId: 'ORD-S-9',
    riderId: 'RD-39',
    state: 'WAITING',
    returnReceiptId: null,
    arrivedAt: '2026-11-20T01:00:00.000Z',
    lines: [{ orderLineId: 'OL-S', sku: 'SKU-CHIP-1', productName: '감자칩 110g', qty: 3 }],
  },
];

export const returnArrivalHandlers = [
  http.get(`${API_BASE}/return-arrivals`, ({ request }) => {
    if (!operator(request)) return unauthorized();
    const q = new URL(request.url).searchParams;
    const mfcId = q.get('mfcId');
    if (!mfcId) return problem(400, 'VALIDATION_FAILED', [{ field: 'mfcId', reason: 'REQUIRED' }]);
    const state = q.get('state') ?? 'WAITING';
    return HttpResponse.json({ items: arrivals.filter((a) => a.mfcId === mfcId && a.state === state) });
  }),
];

/** 브라우저 목 — 다른 네 센터에도 반품 도착(부산진구 것을 옮김, demoCenters) */
export function addDemoCenterArrivals(): void {
  addToArray(arrivals);
}
