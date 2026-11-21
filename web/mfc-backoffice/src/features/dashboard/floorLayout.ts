// 위에서 본 센터 도면 — 가상 현장(../pmart-mfc-simulation/src/domain/layout.ts, 2026-11-21 읽어 옮김)의 평면 배치.
// ⚠ 실측 도면이 아니다(시뮬레이터도 "가정" — MFC-business-logic 1장 463평 면적·랙 규격만 문서 근거). 화면에 "가정 배치"로 표시한다.
// 좌표 m, x = 동쪽, z = 남쪽, 원점 = 건물 북서 모서리 — 위치(칸) 계약 FloorPosition 과 같은 좌표계라 서버 position 이 있으면 그대로 찍힌다.

export interface Rect {
  readonly x0: number;
  readonly z0: number;
  readonly x1: number;
  readonly z1: number;
}

export type FloorZoneKind = 'FROZEN' | 'CHILLED' | 'AMBIENT' | 'INBOUND_STORE' | 'RECEIVING' | 'OFFICE' | 'PACKING' | 'QUARANTINE' | 'SHIPPING' | 'PARKING';

export interface FloorZone {
  readonly id: string;
  readonly kind: FloorZoneKind;
  readonly label: string;
  readonly rect: Rect;
}

export interface FloorRack {
  readonly cx: number;
  readonly cz: number;
  readonly along: 'x' | 'z';
}

/** 작업자가 걷는 통로 — along 축으로 [from, to] 사이를 오간다. cross = 통로 중심 좌표 */
export interface Aisle {
  readonly zone: 'FROZEN' | 'CHILLED' | 'AMBIENT';
  readonly along: 'x' | 'z';
  readonly cross: number;
  readonly from: number;
  readonly to: number;
}

export interface Floor {
  readonly width: number;
  readonly depth: number;
  readonly buildingDepth: number;
  readonly zones: readonly FloorZone[];
  readonly walls: readonly Rect[];
  readonly racks: readonly FloorRack[];
  readonly aisles: readonly Aisle[];
  readonly stations: ReadonlyArray<{ readonly x: number; readonly z: number }>;
  readonly points: {
    readonly packQueue: { readonly x: number; readonly z: number };
    readonly dock: ReadonlyArray<{ readonly x: number; readonly z: number }>;
    readonly idle: ReadonlyArray<{ readonly x: number; readonly z: number }>;
    readonly lounge: ReadonlyArray<{ readonly x: number; readonly z: number }>;
  };
}

const RACK_LEN = 1.25;
const RACK_DEPTH = 0.45;
const AISLE = 0.7;
const W = 48;
const BD = 32;
const D = 40;

function fill(area: Rect, along: 'x' | 'z', zone: Aisle['zone'], crossAisleAt?: number) {
  const crossMin = along === 'z' ? area.x0 : area.z0;
  const crossMax = along === 'z' ? area.x1 : area.z1;
  const alongMin = along === 'z' ? area.z0 : area.x0;
  const alongMax = along === 'z' ? area.z1 : area.x1;
  const rows: number[] = [];
  const aisles: Aisle[] = [];
  let c = crossMin;
  while (c + 2 * RACK_DEPTH <= crossMax + 1e-6) {
    rows.push(c + RACK_DEPTH / 2, c + RACK_DEPTH * 1.5);
    aisles.push({ zone, along, cross: c + 2 * RACK_DEPTH + AISLE / 2, from: alongMin, to: alongMax });
    c += 2 * RACK_DEPTH + AISLE;
  }
  const segments: Array<[number, number]> = crossAisleAt !== undefined ? [[alongMin, crossAisleAt - 0.7], [crossAisleAt + 0.7, alongMax]] : [[alongMin, alongMax]];
  const racks: FloorRack[] = [];
  for (const r of rows)
    for (const [a0, a1] of segments) {
      const n = Math.floor((a1 - a0) / RACK_LEN);
      for (let i = 0; i < n; i++) {
        const a = a0 + RACK_LEN * (i + 0.5);
        racks.push(along === 'z' ? { cx: r, cz: a, along } : { cx: a, cz: r, along });
      }
    }
  return { racks, aisles: aisles.filter((a) => a.cross < crossMax + 0.4) };
}

export function buildFloor(): Floor {
  const zones: FloorZone[] = [
    { id: 'A', kind: 'FROZEN', label: '냉동 A', rect: { x0: 0, z0: 0, x1: 12, z1: 30 } },
    { id: 'B', kind: 'CHILLED', label: '냉장 B', rect: { x0: 12.2, z0: 0, x1: 23, z1: 30 } },
    { id: 'C-H', kind: 'AMBIENT', label: '상온 C~H', rect: { x0: 23.2, z0: 0, x1: 37, z1: 15.4 } },
    { id: 'WH', kind: 'INBOUND_STORE', label: '입고창고', rect: { x0: 37.2, z0: 0, x1: 48, z1: 16.5 } },
    { id: 'RCV', kind: 'RECEIVING', label: '입고·검수', rect: { x0: 37.2, z0: 16.7, x1: 48, z1: 23 } },
    { id: 'OFF', kind: 'OFFICE', label: '휴게·사무', rect: { x0: 37.2, z0: 23.2, x1: 48, z1: 28.6 } },
    { id: 'PK', kind: 'PACKING', label: '패킹', rect: { x0: 25, z0: 20.5, x1: 35, z1: 28.5 } },
    { id: 'AQ', kind: 'QUARANTINE', label: '냉동 격리', rect: { x0: 0.2, z0: 26.6, x1: 3.8, z1: 29.8 } },
    { id: 'BQ', kind: 'QUARANTINE', label: '냉장 격리', rect: { x0: 12.4, z0: 26.6, x1: 16, z1: 29.8 } },
    { id: 'CQ', kind: 'QUARANTINE', label: '상온 격리', rect: { x0: 44.4, z0: 12.9, x1: 47.8, z1: 16.3 } },
    { id: 'SHIP', kind: 'SHIPPING', label: '출하대기', rect: { x0: 27, z0: 32.4, x1: 33, z1: 35 } },
    { id: 'PARK', kind: 'PARKING', label: '라이더 대기', rect: { x0: 24, z0: 36.5, x1: 36, z1: 39.6 } },
  ];
  const T = 0.2;
  const walls: Rect[] = [];
  const hWall = (z: number, x0: number, x1: number, doors: Array<[number, number]> = []) => {
    let cur = x0;
    for (const [d0, d1] of [...doors].sort((a, b) => a[0] - b[0])) {
      if (d0 > cur) walls.push({ x0: cur, z0: z - T / 2, x1: d0, z1: z + T / 2 });
      cur = d1;
    }
    if (cur < x1) walls.push({ x0: cur, z0: z - T / 2, x1, z1: z + T / 2 });
  };
  const vWall = (x: number, z0: number, z1: number, doors: Array<[number, number]> = []) => {
    let cur = z0;
    for (const [d0, d1] of [...doors].sort((a, b) => a[0] - b[0])) {
      if (d0 > cur) walls.push({ x0: x - T / 2, z0: cur, x1: x + T / 2, z1: d0 });
      cur = d1;
    }
    if (cur < z1) walls.push({ x0: x - T / 2, z0: cur, x1: x + T / 2, z1 });
  };
  hWall(0, 0, W);
  hWall(BD, 0, W, [[28.8, 31.2]]);
  vWall(0, 0, BD);
  vWall(W, 0, BD, [[18, 21.5]]);
  vWall(12.1, 0, 30);
  hWall(30.1, 0, 12.1, [[5, 7]]);
  hWall(30.1, 12.1, 23.1, [[16.8, 18.8]]);
  vWall(23.1, 0, 30.1, [[17, 19]]);
  vWall(37.1, 0, 16.6, [[11.8, 14.2]]);
  hWall(16.6, 37.1, W, [[40, 42]]);
  vWall(37.1, 16.6, 28.7, [[18.4, 20.6]]);
  hWall(23.1, 37.1, W, [[44, 45.5]]);
  hWall(28.7, 37.1, W, [[40, 41.6]]);
  hWall(20.5, 25, 35, [[33.0, 34.8]]);
  hWall(28.5, 25, 35, [[33.0, 34.8]]);
  vWall(25, 20.5, 28.5);
  vWall(35, 20.5, 28.5);

  const frozen = fill({ x0: 1.0, z0: 1.0, x1: 11.2, z1: 25.6 }, 'z', 'FROZEN', 13);
  const chilled = fill({ x0: 13.2, z0: 1.0, x1: 22.2, z1: 25.6 }, 'z', 'CHILLED', 13);
  const ambient = fill({ x0: 24.0, z0: 0.8, x1: 36.4, z1: 14.6 }, 'x', 'AMBIENT');

  const stations = Array.from({ length: 8 }, (_, i) => ({ x: 25.9 + (i % 4) * 2.0, z: i < 4 ? 22.35 : 26.65 }));
  return {
    width: W,
    depth: D,
    buildingDepth: BD,
    zones,
    walls,
    racks: [...frozen.racks, ...chilled.racks, ...ambient.racks],
    aisles: [...frozen.aisles, ...chilled.aisles, ...ambient.aisles],
    stations,
    points: {
      packQueue: { x: 33.9, z: 19.4 },
      dock: Array.from({ length: 6 }, (_, i) => ({ x: 39.5 + (i % 3) * 2.6, z: 18.4 + Math.floor(i / 3) * 3.0 })),
      idle: Array.from({ length: 12 }, (_, i) => ({ x: 24.6 + (i % 6) * 1.6, z: 16.6 + Math.floor(i / 6) * 1.2 })),
      lounge: Array.from({ length: 6 }, (_, i) => ({ x: 39 + (i % 3) * 2.8, z: 24.8 + Math.floor(i / 3) * 2.2 })),
    },
  };
}
