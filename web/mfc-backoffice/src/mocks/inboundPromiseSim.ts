// 입고 예정(TRF) 목 — mfc-inbound-service 0.16.0 `GET /inbound-promises`·`/inbound-promises/{trfId}`.
// 서버는 CDC 출발(TransferDeparted)·매니페스트 사건으로 예정을 만든다(LAN 은 출발한 TRF 부터 보인다 — 승인 사건은 내는 서비스가 아직 없다).
// 화면의 "실시간 흐름"을 보이려고 시각에서 만든다: 25분마다 한 대 출발 → 45분 뒤 도착(RECEIVING) → 20분 뒤 수령 반영(TIN_POSTED).
// 같은 출발 칸은 같은 trfId 라 다시 읽으면 단계만 바뀐다. 상태는 서버 값 그대로(EXPECTED·RECEIVING·TIN_POSTED).
import type { components } from '../api/generated/mfc-inbound';
import { MOCK_PRODUCTS } from './catalog';

type InboundPromise = components['schemas']['InboundPromise'];

const MIN = 60_000;
export const SIM_EVERY = 25 * MIN;
export const SIM_TRAVEL = 45 * MIN;
export const SIM_RECEIVE = 20 * MIN;
const SLOTS = 8;
const FROM_CDC = 'CDC-CG-01';

const hash = (s: string) => [...s].reduce((h, c) => (h * 31 + c.charCodeAt(0)) >>> 0, 7);

function promiseOf(mfcId: string, slot: number, now: number): InboundPromise {
  const departed = slot * SIM_EVERY;
  const arrived = departed + SIM_TRAVEL;
  const posted = arrived + SIM_RECEIVE;
  const state = now < arrived ? 'EXPECTED' : now < posted ? 'RECEIVING' : 'TIN_POSTED';
  const trfId = `TRF-SIM-${mfcId.slice(-2)}${String(slot % 100000).padStart(5, '0')}`;
  const h = hash(trfId);
  const n = 2 + (h % 2);
  const short = h % 5 === 0; // 다섯 대에 한 대는 덜 옴(수령 SHORT)
  const lines = Array.from({ length: n }, (_, i) => {
    const p = MOCK_PRODUCTS[(h + i * 3) % MOCK_PRODUCTS.length]!;
    const expectedQty = 6 + ((h >> (i * 3)) % 30);
    const receivedQty = state === 'TIN_POSTED' ? (short && i === 0 ? expectedQty - 2 : expectedQty) : 0;
    return {
      sku: p.skus[0]!,
      productName: p.name,
      barcodes: [],
      lotId: `CDC-L${(h + i) % 900}`,
      expiryDate: '2026-12-31',
      temperatureZone: null,
      expectedQty,
      receivedQty,
      quarantinedQty: 0,
      pendingQty: 0,
    };
  });
  return {
    trfId,
    departureId: `DEP-${trfId}`,
    mfcId,
    fromCdc: FROM_CDC,
    trfVersion: null,
    version: state === 'EXPECTED' ? 1 : state === 'RECEIVING' ? 2 : 3,
    state,
    plannedArrivalAt: new Date(arrived).toISOString(),
    deadlineMeaning: 'ARRIVAL',
    departedAt: new Date(departed).toISOString(),
    shipmentManifestId: `MAN-${trfId}`,
    cancelReason: null,
    eta: null,
    tripId: `TRIP-${slot % 1000}`,
    arrivedAt: state === 'EXPECTED' ? null : new Date(arrived).toISOString(),
    lines,
    packages: lines.map((l, i) => ({ lpn: `LPN-${trfId.slice(-5)}-${i + 1}`, sku: l.sku, lotId: l.lotId, qty: l.expectedQty, expiryDate: l.expiryDate })),
    receipts: [],
    sources: [{ system: 'cdc-inventory-service', asOf: { asOf: new Date(departed).toISOString() } }],
  };
}

/** 지금 시각의 그 센터 입고 예정 — 최근 출발 SLOTS 대(오래된 것부터, 서버 정렬 = 예정 도착 순) */
export function simPromises(mfcId: string, now = Date.now()): InboundPromise[] {
  const last = Math.floor(now / SIM_EVERY);
  return Array.from({ length: SLOTS }, (_, k) => promiseOf(mfcId, last - (SLOTS - 1 - k), now));
}
