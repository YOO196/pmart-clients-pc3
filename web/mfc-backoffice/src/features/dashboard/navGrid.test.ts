// 작업자 점 길찾기 — 센터 다섯 곳 도면(시뮬레이터 평면)에서 벽·랙·탁자를 지나지 않고 문으로만.
import { describe, expect, it } from 'vitest';

import { mockFloorPlans } from '../../mocks/floorPlans';
import type { FloorPlan } from '../floor/floorPlan';
import { NavGrid, type P } from './navGrid';

/** 경로를 0.05m 간격으로 훑어 모두 걸을 수 있는 칸인지 */
function walkable(grid: NavGrid, from: P, path: readonly P[]) {
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

const plans: readonly FloorPlan[] = mockFloorPlans();

describe('작업자 길찾기 — 센터마다', () => {
  it('도면은 다섯 센터(실서버 ID)', () => {
    expect(plans.map((p) => p.centerId).sort()).toEqual(['MFC-BNG-01', 'MFC-CHC-01', 'MFC-MOKPO-01', 'MFC-SEED-01', 'MFC-SEJ-01']);
  });

  it.each(plans.map((p) => [p.centerId, p] as const))('%s: 냉동·냉장·상온 선반 앞 → 포장 대기·포장대·입고 팔레트, 모두 벽·랙을 지나지 않는 길', (_, plan) => {
    const grid = new NavGrid(plan);
    for (const temp of ['FROZEN', 'CHILLED', 'AMBIENT'] as const) {
      const rack = plan.racks.find((r) => r.temp === temp && !r.reserve && r.stand);
      if (!rack) continue;
      const from = grid.snapPoint(rack.stand!);
      for (const goal of [plan.points.packQueue, plan.stations[0]!.stand, plan.reserves[0]?.stand ?? plan.points.truckDoor]) {
        const path = grid.findPath(from, goal);
        expect(path, `${plan.centerId} ${temp} ${rack.code} → ${goal.x},${goal.z}`).not.toBeNull();
        expect(walkable(grid, from, path!)).toBe(true);
      }
    }
  });

  it('랙 위 점은 걸을 수 없다 — 가장 가까운 통로로 옮긴다', () => {
    const plan = plans[0]!;
    const grid = new NavGrid(plan);
    const rack = plan.racks.find((r) => !r.reserve)!;
    expect(grid.isFreeAt({ x: rack.cx, z: rack.cz })).toBe(false);
    expect(grid.isFreeAt(grid.snapPoint({ x: rack.cx, z: rack.cz }))).toBe(true);
  });
});
