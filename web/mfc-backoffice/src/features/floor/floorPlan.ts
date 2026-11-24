// 센터별 도면 — 가상 현장(pmart-mfc-simulation) 평면을 센터마다 뽑은 JSON(layouts/<센터 ID>.json, tools/floors/run.mjs 로 만듦).
// 백엔드는 같은 시뮬레이터 평면의 칸 위치 파일로 센터 칸 좌표(mfc-location position)를 등록했다 — 좌표계가 같다(x 동쪽·z 남쪽 m, 원점 북서).
//   2026-11-24 대조: 다섯 센터 모두 서버 칸 9천~1만8천 칸이 이 도면 랙 1.6 m 안(어긋남 0).
// ⚠ 도면(구역·벽·랙 자리)은 서버 API 가 아니다 — 계약에 도면 API 가 없어 시뮬레이터 평면을 받아 쓴다(실측 도면 아님, 화면에 표시).
//   도면이 없는 센터는 "도면 없음"으로 보인다(다른 센터 도면으로 대신하지 않는다).
import { useQuery } from '@tanstack/react-query';

export type FloorZoneKind = 'FROZEN' | 'CHILLED' | 'AMBIENT' | 'INBOUND_STORE' | 'RECEIVING' | 'OFFICE' | 'PACKING' | 'QUARANTINE' | 'SHIPPING' | 'PARKING';
export type Temp = 'FROZEN' | 'CHILLED' | 'AMBIENT';
type R4 = readonly [number, number, number, number];
type P2 = readonly [number, number];

export interface Rect {
  readonly x0: number;
  readonly z0: number;
  readonly x1: number;
  readonly z1: number;
}
export interface Pt {
  readonly x: number;
  readonly z: number;
}

/** JSON 그대로의 모양(짧은 배열) */
interface RawPlan {
  readonly centerId: string;
  readonly name: string;
  readonly variant: string;
  readonly source: string;
  readonly width: number;
  readonly depth: number;
  readonly buildingDepth: number;
  readonly yardX: P2;
  readonly floorX0: number;
  readonly outsideYards: readonly R4[];
  readonly zones: ReadonlyArray<{ id: string; kind: FloorZoneKind; label: string; rect: R4; outline?: readonly P2[]; noTag?: boolean; noOutline?: boolean }>;
  readonly walls: ReadonlyArray<{ r: R4; glass?: boolean }>;
  readonly obstacles: ReadonlyArray<{ r: R4; kind: string }>;
  readonly racks: ReadonlyArray<{ code: string; temp: Temp; c: P2; along: 'x' | 'z'; face: 1 | -1; levels: number; slots: number; cells: number; stand: P2 | null; reserve?: boolean }>;
  readonly stations: ReadonlyArray<{ id: string; table: P2; stand: P2 }>;
  readonly reserves: ReadonlyArray<{ id: string; temp: Temp; role: string; r: R4; stand: P2; code: string | null }>;
  readonly dock: readonly P2[];
  readonly ship: readonly P2[];
  readonly points: { truckDoor: P2; inboundIdle: readonly P2[]; cartDepot: P2; idle: readonly P2[]; packQueue: P2; shipDrop: P2; riderPickup: P2 };
}

export interface FloorZone {
  readonly id: string;
  readonly kind: FloorZoneKind;
  readonly label: string;
  readonly rect: Rect;
  readonly outline: readonly Pt[] | null;
  readonly tag: boolean;
  readonly drawOutline: boolean;
}
export interface FloorRack {
  /** 칸 코드 앞부분 `{온도대}-{구역}-{랙 2자리}`(예 `C-B2-05`) — 시뮬레이터 대응표 그대로라 서버 칸 코드와 같다 */
  readonly code: string;
  readonly temp: Temp;
  readonly cx: number;
  readonly cz: number;
  readonly along: 'x' | 'z';
  readonly face: 1 | -1;
  readonly levels: number;
  readonly slots: number;
  /** 열린 칸 수(넓은 칸으로 합쳐 닫힌 칸 뺌) */
  readonly cells: number;
  /** 작업자가 서는 자리(칸들의 서는 지점 평균) */
  readonly stand: Pt | null;
  /** 보충재고 랙 */
  readonly reserve: boolean;
}
export interface FloorPlan {
  readonly centerId: string;
  readonly name: string;
  readonly source: string;
  readonly width: number;
  readonly depth: number;
  readonly buildingDepth: number;
  readonly yardX: readonly [number, number];
  readonly floorX0: number;
  readonly outsideYards: readonly Rect[];
  readonly zones: readonly FloorZone[];
  readonly walls: ReadonlyArray<Rect & { readonly glass: boolean }>;
  readonly obstacles: ReadonlyArray<Rect & { readonly kind: string }>;
  readonly racks: readonly FloorRack[];
  readonly stations: ReadonlyArray<{ readonly id: string; readonly table: Pt; readonly stand: Pt }>;
  readonly reserves: ReadonlyArray<{ readonly id: string; readonly temp: Temp; readonly role: string; readonly rect: Rect; readonly stand: Pt; readonly code: string | null }>;
  readonly dock: readonly Pt[];
  readonly points: { readonly truckDoor: Pt; readonly inboundIdle: readonly Pt[]; readonly idle: readonly Pt[]; readonly packQueue: Pt; readonly shipDrop: Pt };
  /** 그릴 범위(벽·구역·랙을 모두 담는 사각형) */
  readonly bounds: Rect;
  /** 건물 크기(m) — 글로 보인다 */
  readonly size: { readonly w: number; readonly d: number };
}

const rect = ([x0, z0, x1, z1]: R4): Rect => ({ x0, z0, x1, z1 });
const pt = ([x, z]: P2): Pt => ({ x, z });

export function toPlan(raw: RawPlan): FloorPlan {
  const zones = raw.zones.map<FloorZone>((z) => ({
    id: z.id,
    kind: z.kind,
    label: z.label,
    rect: rect(z.rect),
    outline: z.outline ? z.outline.map(pt) : null,
    tag: !z.noTag,
    drawOutline: !z.noOutline,
  }));
  const walls = raw.walls.map((w) => ({ ...rect(w.r), glass: !!w.glass }));
  const racks = raw.racks.map<FloorRack>((r) => ({
    code: r.code,
    temp: r.temp,
    cx: r.c[0],
    cz: r.c[1],
    along: r.along,
    face: r.face,
    levels: r.levels,
    slots: r.slots,
    cells: r.cells,
    stand: r.stand ? pt(r.stand) : null,
    reserve: !!r.reserve,
  }));
  const boxes: Rect[] = [...zones.filter((z) => z.kind !== 'PARKING').map((z) => z.rect), ...walls];
  const bounds = {
    x0: Math.min(...boxes.map((b) => b.x0)),
    z0: Math.min(...boxes.map((b) => b.z0)),
    x1: Math.max(...boxes.map((b) => b.x1)),
    z1: Math.max(...boxes.map((b) => b.z1)),
  };
  const inside = walls.length ? { x0: Math.min(...walls.map((w) => w.x0)), x1: Math.max(...walls.map((w) => w.x1)), z0: Math.min(...walls.map((w) => w.z0)), z1: Math.max(...walls.map((w) => w.z1)) } : bounds;
  return {
    centerId: raw.centerId,
    name: raw.name,
    source: raw.source,
    width: raw.width,
    depth: raw.depth,
    buildingDepth: raw.buildingDepth,
    yardX: [raw.yardX[0], raw.yardX[1]],
    floorX0: raw.floorX0,
    outsideYards: raw.outsideYards.map(rect),
    zones,
    walls,
    obstacles: raw.obstacles.map((o) => ({ ...rect(o.r), kind: o.kind })),
    racks,
    stations: raw.stations.map((s) => ({ id: s.id, table: pt(s.table), stand: pt(s.stand) })),
    reserves: raw.reserves.map((s) => ({ id: s.id, temp: s.temp, role: s.role, rect: rect(s.r), stand: pt(s.stand), code: s.code })),
    dock: raw.dock.map(pt),
    points: {
      truckDoor: pt(raw.points.truckDoor),
      inboundIdle: raw.points.inboundIdle.map(pt),
      idle: raw.points.idle.map(pt),
      packQueue: pt(raw.points.packQueue),
      shipDrop: pt(raw.points.shipDrop),
    },
    bounds,
    size: { w: Math.round(inside.x1 - inside.x0), d: Math.round(inside.z1 - inside.z0) },
  };
}

/** 센터 ID → 도면 JSON(센터를 열 때만 불러온다) */
const FILES = import.meta.glob<RawPlan>('./layouts/*.json', { import: 'default' });
const fileOf = (mfcId: string) => `./layouts/${mfcId}.json`;

export function hasFloorPlan(mfcId: string): boolean {
  return fileOf(mfcId) in FILES;
}

const cache = new Map<string, FloorPlan>();
export async function loadFloorPlan(mfcId: string): Promise<FloorPlan | null> {
  const hit = cache.get(mfcId);
  if (hit) return hit;
  const load = FILES[fileOf(mfcId)];
  if (!load) return null;
  const plan = toPlan(await load());
  cache.set(mfcId, plan);
  return plan;
}

/** 도면(바뀌지 않는다 — 한 번 읽으면 끝). data === null 이면 이 센터 도면이 없다 */
export function useFloorPlan(mfcId: string) {
  return useQuery({ queryKey: ['floor-plan', mfcId], queryFn: () => loadFloorPlan(mfcId), staleTime: Infinity, gcTime: Infinity });
}

/** 칸 코드 → 그 칸의 랙(앞 세 마디) */
export const rackCodeOf = (locationCode: string) => locationCode.split('-').slice(0, 3).join('-');
export const tempOfCode = (code: string): Temp | null => ({ A: 'AMBIENT', C: 'CHILLED', F: 'FROZEN' } as const)[code.charAt(0) as 'A'] ?? null;
