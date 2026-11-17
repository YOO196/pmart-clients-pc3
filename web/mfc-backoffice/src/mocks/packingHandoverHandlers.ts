// ⚠ 화면 개발·시험용 목 — 포장 인계 현황(bff 0.11.0 packing-handover). 실제 서버 동작이 아니다.
// 규칙(계약 그대로 흉내): 센터 관리자는 자기 센터만 — 다른 센터 mfcId 403, mfcId 비우면 센터 하나면 그 센터·여럿이면 400.
// state 를 비우면 끝나지 않은 출고(PREPARING·READY·PARTIALLY_HANDED_OVER). 단계(stage)는 행마다 정해 둔 값(서버 규칙의 예).
// 목 전용 스위치: 상태 CANCELLED 로 거르면 배송 원천 실패(delivery.state null, unavailableSources).
import { http, HttpResponse } from 'msw';

import { API_BASE } from '../api/client';
import { operator, problem, unauthorized } from './support';

const BFF = `${API_BASE}/backoffice`;
const OPEN_SHIPMENTS = ['PREPARING', 'READY', 'PARTIALLY_HANDED_OVER'];

interface Pkg {
  packageId: string;
  state: string;
  fenceState: string;
  handedOverAt: string | null;
  riderId: string | null;
}
interface ShipRow {
  shipmentId: string;
  orderId: string;
  orderNumber: string | null;
  mfcId: string;
  shipment: string;
  stage: string | null;
  pick: string | null;
  pack: string | null;
  kind?: string;
  packages: Pkg[];
  delivery: string | null;
  riderId: string | null;
}

const ships: ShipRow[] = [
  { shipmentId: 'SHP-1-S1', orderId: 'ORD-P-1', orderNumber: '10000001', mfcId: 'MFC-BSN-01', shipment: 'PREPARING', stage: 'REQUESTED', pick: 'READY', pack: 'WAITING', packages: [], delivery: 'UNASSIGNED', riderId: null },
  { shipmentId: 'SHP-2-S1', orderId: 'ORD-P-2', orderNumber: '10000002', mfcId: 'MFC-BSN-01', shipment: 'PREPARING', stage: 'PICKING', pick: 'IN_PROGRESS', pack: 'WAITING', packages: [], delivery: 'ASSIGNED', riderId: 'RD-1' },
  { shipmentId: 'SHP-3-S1', orderId: 'ORD-P-3', orderNumber: '10000003', mfcId: 'MFC-BSN-01', shipment: 'PREPARING', stage: null, pick: 'COMPLETED', pack: 'READY', packages: [], delivery: null, riderId: null },
  {
    shipmentId: 'SHP-4-S1',
    orderId: 'ORD-P-4',
    orderNumber: '10000004',
    mfcId: 'MFC-BSN-01',
    shipment: 'PARTIALLY_HANDED_OVER',
    stage: 'PARTIALLY_HANDED_OVER',
    pick: 'COMPLETED',
    pack: 'COMPLETED',
    kind: 'RESHIPMENT',
    packages: [
      { packageId: 'PKG-4-1', state: 'HANDED_OVER', fenceState: 'COMMITTED', handedOverAt: '2026-11-17T08:00:00.000Z', riderId: 'RD-2' },
      { packageId: 'PKG-4-2', state: 'SEALED', fenceState: 'NONE', handedOverAt: null, riderId: null },
    ],
    delivery: 'PICKED_UP',
    riderId: 'RD-2',
  },
  { shipmentId: 'SHP-5-S1', orderId: 'ORD-P-5', orderNumber: null, mfcId: 'MFC-BSN-01', shipment: 'CANCELLED', stage: null, pick: 'CANCELLED', pack: null, packages: [], delivery: 'CANCELLED', riderId: null },
  { shipmentId: 'SHP-9-S1', orderId: 'ORD-P-9', orderNumber: '10000009', mfcId: 'MFC-SEL-01', shipment: 'READY', stage: 'READY_FOR_HANDOVER', pick: 'COMPLETED', pack: 'COMPLETED', packages: [], delivery: 'ASSIGNED', riderId: 'RD-9' },
];

export const packingHandoverHandlers = [
  http.get(`${BFF}/views/packing-handover`, ({ request }) => {
    const who = operator(request);
    if (!who) return unauthorized();
    const q = new URL(request.url).searchParams;
    let mfcId = q.get('mfcId') ?? '';
    if (who.roles.includes('MFC_SUPERVISOR') && !who.roles.includes('OPERATOR_ADMIN')) {
      if (!mfcId) {
        if (who.centers.length !== 1) return problem(400, 'VALIDATION_FAILED', [{ field: 'mfcId', reason: 'REQUIRED' }]);
        mfcId = who.centers[0] ?? '';
      }
      if (!who.centers.includes(mfcId)) return problem(403, 'FORBIDDEN');
    } else if (!who.roles.includes('OPERATOR_ADMIN')) return problem(403, 'FORBIDDEN');
    const states = q.getAll('state');
    const down = states.includes('CANCELLED');
    const now = new Date().toISOString();
    const stamp = (system: string, ok = true) => ({ system, confidence: ok ? 'DIRECT' : 'UNKNOWN', asOf: { asOf: now, freshness: ok ? 'CURRENT' : 'UNAVAILABLE' } });
    const hit = ships.filter((r) => (!mfcId || r.mfcId === mfcId) && (states.length ? states.includes(r.shipment) : OPEN_SHIPMENTS.includes(r.shipment)));
    const items = hit.map((r) => {
      const handed = r.packages.filter((p) => p.state === 'HANDED_OVER').length;
      return {
        shipmentId: r.shipmentId,
        orderId: r.orderId,
        orderNumber: r.orderNumber,
        fulfillmentId: null,
        mfcId: r.mfcId,
        workOrderKind: r.kind ?? 'ORIGINAL',
        stage: r.stage,
        shipment: { state: r.shipment, version: 2, source: stamp('mfc-fulfillment-service') },
        createdAt: '2026-11-17T07:00:00.000Z',
        readyAt: r.packages.length ? '2026-11-17T07:40:00.000Z' : null,
        dispatchRequestedAt: r.pick === 'IN_PROGRESS' || r.packages.length ? '2026-11-17T07:10:00.000Z' : null,
        pick: r.pick ? { state: r.pick, blockReason: null, startedAt: null } : null,
        pack: r.pack ? { state: r.pack, blockReason: null, startedAt: null } : null,
        packageCount: r.packages.length,
        sealedPackages: r.packages.filter((p) => p.state === 'SEALED').length,
        handedOverQty: { qty: handed, source: stamp('mfc-fulfillment-service') },
        remainingPackages: r.packages.length - handed,
        packages: r.packages.map((p) => ({ ...p, handoverAuthorizedAt: null })),
        deliveryId: r.delivery ? `DLV-${r.orderId}` : null,
        delivery: r.delivery === null ? null : { state: down ? null : r.delivery, version: down ? null : 1, source: stamp('delivery-execution-service', !down) },
        riderId: down ? null : r.riderId,
      };
    });
    return HttpResponse.json({
      composedAt: now,
      sources: [stamp('mfc-fulfillment-service'), stamp('delivery-execution-service', !down)],
      unavailableSources: down ? ['delivery-execution-service'] : [],
      items,
      page: { size: 50, nextCursor: null },
    });
  }),
];
