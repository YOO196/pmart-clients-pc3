// 작업자 점 길찾기 — 벽·랙·포장대를 지나지 않고 문으로만(가상 현장 navgrid 를 옮김).
import { describe, expect, it } from 'vitest';

import { buildFloor } from './floorLayout';
import { NavGrid, type P } from './navGrid';

const floor = buildFloor();
const grid = new NavGrid(floor);

/** 경로를 0.05m 간격으로 훑어 모두 걸을 수 있는 칸인지 */
function walkable(from: P, path: readonly P[]) {
  let prev = from;
  for (const p of path) {
    const n = Math.ceil(Math.hypot(p.x - prev.x, p.z - prev.z) / 0.05);
    for (let i = 0; i <= n; i++) {
      const t = n === 0 ? 1 : i / n;
      if (!grid.isFreeAt({ x: prev.x + (p.x - prev.x) * t, z: prev.z + (p.z - prev.z) * t })) return false;
    }
    prev = p;
  }
  return true;
}

describe('작업자 길찾기', () => {
  it('냉동 통로 → 포장 대기: 길이 있고, 벽·랙을 지나지 않는다(냉동실 문으로 나온다)', () => {
    const aisle = floor.aisles.find((a) => a.zone === 'FROZEN')!;
    const from = grid.snapPoint({ x: aisle.cross, z: 5 });
    const path = grid.findPath(from, floor.points.packQueue);
    expect(path).not.toBeNull();
    expect(walkable(from, path!)).toBe(true);
    // 냉동실 남쪽 벽(z=30.1)의 문(x 5~7)을 지난다 — 벽을 뚫고 동쪽으로 가지 않는다
    const out = path!.find((p) => p.z > 30.1);
    expect(out === undefined || (out.x > 4.5 && out.x < 7.5) || path!.some((p) => p.z > 29 && p.x > 4.5 && p.x < 7.5)).toBe(true);
  });

  it('상온 통로 ↔ 하차 칸 · 휴게실 · 포장대: 모두 걸을 수 있는 길', () => {
    const aisle = floor.aisles.find((a) => a.zone === 'AMBIENT')!;
    const from = grid.snapPoint({ x: 30, z: aisle.cross });
    for (const goal of [floor.points.dock[0]!, floor.points.lounge[0]!, floor.stations[5]!]) {
      const path = grid.findPath(from, goal);
      expect(path).not.toBeNull();
      expect(walkable(from, path!)).toBe(true);
    }
  });

  it('랙 위 점은 걸을 수 없다 — 가장 가까운 통로로 옮긴다', () => {
    const rack = floor.racks[0]!;
    expect(grid.isFreeAt({ x: rack.cx, z: rack.cz })).toBe(false);
    expect(grid.isFreeAt(grid.snapPoint({ x: rack.cx, z: rack.cz }))).toBe(true);
  });
});
