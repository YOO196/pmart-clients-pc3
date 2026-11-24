// 목 — 부산진구(MFC-SEED-01) 말고 다른 네 센터에도 시연 데이터(2026-11-24 사용자 "목 웹 다른 센터들에도 목 데이터 넣어줘").
// 브라우저 목(seedDemoFloor → enableDemoCenters)에서만 켠다 — 시험(vitest)은 부산진구 데이터만 보고, 다른 센터는 예전처럼 비어 있다.
// 목록 데이터는 부산진구 기록을 센터마다 옮겨 만든다(cloneForCenter): 센터 ID·기록 ID·화면 번호·작업자(그 센터 시연 작업자)·선반 칸 코드(그 센터 도면 랙)를 바꾼다.
// 숫자 지표(피킹·결품·정시·주문·배송 통계)는 같은 식에 센터 규모(scale)를 곱한다.
import { mockFloorPlan } from './floorPlans';

export const DEMO_HOME = 'MFC-SEED-01';

export interface DemoCenter {
  readonly id: string;
  /** 기록 ID·작업자 ID 뒤에 붙이는 센터 글자 */
  readonly key: string;
  /** 숫자 지표 규모(부산진구 = 1) */
  readonly scale: number;
  /** 화면 번호를 바꿀 때 더하는 수 */
  readonly no: number;
}

export const DEMO_OTHERS: readonly DemoCenter[] = [
  { id: 'MFC-MOKPO-01', key: 'mk', scale: 0.8, no: 1 },
  { id: 'MFC-SEJ-01', key: 'sj', scale: 1.25, no: 2 },
  { id: 'MFC-CHC-01', key: 'cc', scale: 0.6, no: 3 },
  { id: 'MFC-BNG-01', key: 'bn', scale: 0.95, no: 4 },
];

const enabled = new Set<string>([DEMO_HOME]);

/** 이 센터에 시연 데이터가 있나(부산진구는 늘, 다른 센터는 브라우저 목에서만) */
export const hasDemoData = (mfcId: string | null | undefined): boolean => !!mfcId && enabled.has(mfcId);
/** 숫자 지표 규모 — 부산진구·모르는 센터 1 */
export const demoScale = (mfcId: string | null | undefined): number => DEMO_OTHERS.find((c) => c.id === mfcId)?.scale ?? 1;
/** 규모를 곱한 정수(0 은 0) */
export const scaled = (n: number, mfcId: string | null | undefined): number => (n === 0 ? 0 : Math.max(0, Math.round(n * demoScale(mfcId))));

export function enableDemoCenters(): void {
  for (const c of DEMO_OTHERS) enabled.add(c.id);
}

const hash = (s: string) => [...s].reduce((a, ch) => (a * 31 + ch.charCodeAt(0)) >>> 0, 7);
const SHELF = /^([ACF])-[A-Z]\d-\d{2}-(\d)-(\d{2})$/;
/** 기록 ID 로 바꾸지 않는 *Id 칸(상품·LOT·라이더·분류는 센터마다 같은 것을 쓴다) */
const KEEP = new Set(['mfcId', 'centerId', 'sku', 'lotId', 'productId', 'categoryId', 'riderId', 'deviceId']);
/** 그 센터 시연 작업자 수(db.seedDemoFloor 의 kinds 와 같게) */
const WORKERS = 8;

/** 선반 칸 코드 → 그 센터 도면에서 같은 온도대 랙의 칸(코드마다 늘 같은 칸) */
function cellFor(code: string, c: DemoCenter): string {
  const m = SHELF.exec(code);
  const plan = mockFloorPlan(c.id);
  if (!m || !plan) return code;
  const temp = ({ A: 'AMBIENT', C: 'CHILLED', F: 'FROZEN' } as const)[m[1] as 'A'];
  const racks = plan.racks.filter((r) => r.temp === temp && !r.reserve);
  const rack = racks[hash(code) % Math.max(1, racks.length)];
  if (!rack) return code;
  const lv = Math.min(3, Number(m[2]));
  const s = Math.min(2, Number(m[3]));
  return `${rack.code}-${lv}-${String(s).padStart(2, '0')}`;
}

function person(id: string, c: DemoCenter): string {
  if (id.startsWith('OP-sup')) return `OP-sup-${c.key}`;
  if (id.startsWith('OP-admin')) return id;
  return `OP-demo-${c.key}-${(hash(id) % WORKERS) + 1}`;
}

function str(v: string, key: string, c: DemoCenter): string {
  if (v === DEMO_HOME) return c.id;
  if (v.startsWith('OP-')) return person(v, c);
  if (SHELF.test(v)) return cellFor(v, c);
  if (/Number$/.test(key) && /\d{2}$/.test(v)) return v.slice(0, -2) + String((Number(v.slice(-2)) + 17 * c.no) % 100).padStart(2, '0');
  if (/(Id|Ids|Ref)$/.test(key) && !KEEP.has(key) && v.length > 0) return `${v}-${c.key}`;
  return v.includes(DEMO_HOME) ? v.split(DEMO_HOME).join(c.id) : v;
}

/** 부산진구 기록 하나를 다른 센터 기록으로(깊은 사본) */
export function cloneForCenter<T>(value: T, c: DemoCenter, key = ''): T {
  if (typeof value === 'string') return str(value, key, c) as T;
  if (Array.isArray(value)) return (value as unknown[]).map((x): unknown => cloneForCenter(x, c, key)) as T;
  if (value instanceof Set) return new Set([...(value as Set<unknown>)].map((x): unknown => cloneForCenter(x, c, key))) as T;
  if (value instanceof Map) return new Map([...(value as Map<unknown, unknown>)].map(([k, x]) => [cloneForCenter(k, c, key), cloneForCenter(x, c, key)] as const)) as T;
  if (value && typeof value === 'object') {
    const out: Record<string, unknown> = {};
    for (const [k, x] of Object.entries(value)) out[k] = cloneForCenter(x, c, k);
    return out as T;
  }
  return value;
}

/** 부산진구 기록인가(mfcId·centerId 가 부산진구) */
export const isHome = (x: unknown): boolean => !!x && typeof x === 'object' && ((x as { mfcId?: unknown }).mfcId === DEMO_HOME || (x as { centerId?: unknown }).centerId === DEMO_HOME);

/** 배열에 다른 네 센터 사본을 덧붙인다(부산진구 기록만) */
export function addToArray<T>(list: T[]): void {
  const home = list.filter(isHome);
  for (const c of DEMO_OTHERS) for (const x of home) list.push(cloneForCenter(x, c));
}

/** Map 에 다른 네 센터 사본을 덧붙인다 — 키도 같은 규칙으로 바꾼다 */
export function addToMap<K extends string, V>(map: Map<K, V>): void {
  const home = [...map].filter(([, v]) => isHome(v));
  for (const c of DEMO_OTHERS)
    for (const [k, v] of home) {
      const nk = (k.includes(DEMO_HOME) ? k.split(DEMO_HOME).join(c.id) : `${k}-${c.key}`) as K;
      if (!map.has(nk)) map.set(nk, cloneForCenter(v, c));
    }
}
