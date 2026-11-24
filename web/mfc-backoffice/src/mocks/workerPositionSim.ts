// 목 — 작업자 위치(mfc-capacity 0.34.0 `GET /mfcs/{mfcId}/worker-positions`) 흉내.
// 실서버 값의 뜻 그대로: 작업자마다 "마지막으로 스캔한 칸 한 건"(칸의 서는 지점 xM·zM, 스캔 시각 at). 걷는 중은 없다 — 화면이 두 스캔 사이를 통로로 이어 그린다.
// 시간으로 정해지는 순서(새로 고쳐도 같은 시각이면 같은 자리):
//   피킹 — 같은 온도대 랙을 피킹 순서대로 몇 개씩 건너며 집고(PICK), 한 바퀴 끝에 포장대(PACK, 포장도 맡으면)·포장 대기 칸
//   포장 — 자기 포장대(PACK)
//   재고 이동·보충 — 보충재고 랙(집기) ↔ 같은 온도대 선반(내려놓기) (REPLENISH·MOVE)
//   입고·적치 — 수령 칸(RECEIVE) → 입고 팔레트(PUTAWAY 집기) → 선반(PUTAWAY 놓기)
//   휴게 — 휴게 전 마지막 기록에서 멈춤(25분 넘게 전 — 화면은 오래된 기록으로 흐리게)
// 시뮬레이터(pmart-mfc-simulation)의 가상 작업자가 실서버에서 칸을 스캔하면 실서버도 같은 모양으로 온다.
import type { components } from '../api/generated/mfc-capacity';
import type { FloorPlan, FloorRack, Temp } from '../features/floor/floorPlan';
import type { MockWorker } from './db';
import { mockFloorPlan } from './floorPlans';

type Positions = components['schemas']['WorkerPositions'];
type Item = Positions['items'][number];

const hash = (s: string) => [...s].reduce((a, c) => (a * 31 + c.charCodeAt(0)) >>> 0, 7);
const mix = (a: number, b: number) => (Math.imul(a ^ (b * 0x9e3779b1), 1103515245) + 12345) >>> 0;
const pad2 = (n: number) => String(n).padStart(2, '0');

/** 스캔 간격(ms) — 역할마다 */
const PERIOD = { pick: 7000, pack: 20000, move: 11000, inbound: 12000 } as const;
type Kind = keyof typeof PERIOD;

function kindOf(w: MockWorker): Kind | null {
  const t = new Set(w.duties.at(0)?.taskTypes ?? []);
  if (t.has('PICK')) return 'pick';
  if (t.has('MOVE') || t.has('REPLENISH')) return 'move';
  if (t.has('PUTAWAY') || t.has('RECEIVE') || t.has('INSPECT')) return 'inbound';
  if (t.has('PACK')) return 'pack';
  return null;
}

function cellOf(r: FloorRack, n: number): { code: string; x: number; z: number } {
  const lv = 1 + (n % 3);
  const s = 1 + ((n >>> 3) % 2);
  const stand = r.stand ?? { x: r.cx, z: r.cz };
  const off = (s - 1.5) * 0.4;
  return { code: `${r.code}-${lv}-${pad2(s)}`, x: stand.x + (r.along === 'x' ? off : 0), z: stand.z + (r.along === 'z' ? off : 0) };
}

interface Shelves {
  readonly byTemp: Readonly<Record<Temp, readonly FloorRack[]>>;
  readonly reserveByTemp: Readonly<Record<Temp, readonly FloorRack[]>>;
  readonly temps: readonly Temp[];
}
const shelvesCache = new WeakMap<FloorPlan, Shelves>();
function shelves(plan: FloorPlan): Shelves {
  const hit = shelvesCache.get(plan);
  if (hit) return hit;
  const pick = (reserve: boolean, t: Temp) => plan.racks.filter((r) => r.reserve === reserve && r.temp === t && r.cells > 0);
  const temps: Temp[] = ['FROZEN', 'CHILLED', 'AMBIENT'];
  const out = {
    byTemp: { FROZEN: pick(false, 'FROZEN'), CHILLED: pick(false, 'CHILLED'), AMBIENT: pick(false, 'AMBIENT') },
    reserveByTemp: { FROZEN: pick(true, 'FROZEN'), CHILLED: pick(true, 'CHILLED'), AMBIENT: pick(true, 'AMBIENT') },
    temps: temps.filter((t) => pick(false, t).length > 0),
  };
  shelvesCache.set(plan, out);
  return out;
}

const station = (plan: FloorPlan, i: number) => {
  const s = plan.stations[i % Math.max(1, plan.stations.length)];
  return s ? { code: `PAK-A-${pad2((i % plan.stations.length) + 1)}`, x: s.stand.x, z: s.stand.z } : null;
};

/** step 번째 스캔(0 부터)의 칸 */
function scanAt(plan: FloorPlan, w: MockWorker, kind: Kind, i: number, step: number): { code: string; x: number; z: number; activity: string } | null {
  const sh = shelves(plan);
  const h = hash(w.workerId);
  const tempOf = (k: number) => sh.temps[mix(h, k) % sh.temps.length]!;
  switch (kind) {
    case 'pick': {
      // 한 바퀴 = 선반 8번 + 포장(또는 포장 대기) 1번
      const tour = Math.floor(step / 9);
      const k = step % 9;
      const packs = (w.duties.at(0)?.taskTypes ?? []).includes('PACK');
      if (k === 8) {
        const st = packs ? station(plan, i + tour) : null;
        if (st) return { ...st, activity: 'PACK' };
        const q = plan.points.packQueue;
        return { code: 'PAK-A-01', x: q.x, z: q.z, activity: 'PICK' };
      }
      const racks = sh.byTemp[tempOf(tour)];
      if (racks.length === 0) return null;
      // 피킹 순서대로 몇 랙씩 건넌다(1~4)
      let idx = mix(h, tour) % racks.length;
      for (let j = 0; j < k; j++) idx = (idx + 1 + (mix(h + j, tour) % 4)) % racks.length;
      return { ...cellOf(racks[idx]!, mix(h, step)), activity: 'PICK' };
    }
    case 'pack': {
      const st = station(plan, i);
      return st ? { ...st, activity: 'PACK' } : null;
    }
    case 'move': {
      const round = Math.floor(step / 2);
      const t = tempOf(round);
      const from = sh.reserveByTemp[t];
      const to = sh.byTemp[t];
      const list = step % 2 === 0 && from.length > 0 ? from : to;
      if (list.length === 0) return null;
      return { ...cellOf(list[mix(h, step) % list.length]!, mix(h, step + 1)), activity: (w.duties.at(0)?.taskTypes ?? []).includes('MOVE') && round % 3 === 0 ? 'MOVE' : 'REPLENISH' };
    }
    case 'inbound': {
      const k = step % 3;
      if (k === 0) {
        const d = plan.dock[mix(h, step) % Math.max(1, plan.dock.length)] ?? plan.points.truckDoor;
        return { code: 'RCV-A-01', x: d.x, z: d.z, activity: 'RECEIVE' };
      }
      const t = tempOf(Math.floor(step / 3));
      if (k === 1) {
        const rs = plan.reserves.filter((r) => r.temp === t && r.code);
        const r = rs[mix(h, step) % Math.max(1, rs.length)];
        if (r) return { code: r.code!, x: r.stand.x, z: r.stand.z, activity: 'PUTAWAY' };
      }
      const racks = sh.byTemp[t];
      if (racks.length === 0) return null;
      return { ...cellOf(racks[mix(h, step) % racks.length]!, mix(h, step + 2)), activity: 'PUTAWAY' };
    }
  }
}

export function mockWorkerPositions(mfcId: string, workers: readonly MockWorker[], now: number, sinceMinutes: number): Positions {
  const since = now - sinceMinutes * 60_000;
  const plan = mockFloorPlan(mfcId);
  const items: Item[] = [];
  const unplaced: Positions['unplaced'] = [];
  workers
    .filter((w) => w.state === 'ACTIVE')
    .forEach((w, i) => {
      const kind = kindOf(w);
      if (!kind) return;
      const period = PERIOD[kind];
      const phase = hash(w.workerId) % period;
      // 휴게 중이면 멈춘 기록 — 30분 단위로 고정한 시각에서 25분 전(휴게 동안 점이 움직이지 않게)
      const t = w.onBreak ? Math.floor(now / 1_800_000) * 1_800_000 - 25 * 60_000 : now;
      const step = Math.floor((t + phase) / period);
      const at = step * period - phase;
      if (at < since) return;
      if (!plan) {
        unplaced.push({ workerId: w.workerId, locationCode: 'PAK-A-01', activityType: kind === 'pack' ? 'PACK' : 'PICK', at: new Date(at).toISOString(), reason: 'NO_POSITION' });
        return;
      }
      const scan = scanAt(plan, w, kind, i, step);
      if (!scan) return;
      items.push({ workerId: w.workerId, xM: Math.round(scan.x * 100) / 100, zM: Math.round(scan.z * 100) / 100, source: 'SCAN', locationCode: scan.code, activityType: scan.activity, at: new Date(at).toISOString() });
    });
  items.sort((a, b) => b.at.localeCompare(a.at));
  return { mfcId, asOf: new Date(now).toISOString(), since: new Date(since).toISOString(), items, unplaced, unavailableSources: [] };
}
