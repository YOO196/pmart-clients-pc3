// 목 전용 — 센터 다섯 곳 도면을 한꺼번에(목 칸·작업자 위치 흉내가 쓴다). 화면은 features/floor/floorPlan 의 useFloorPlan 으로 센터마다 따로 읽는다.
import { toPlan, type FloorPlan } from '../features/floor/floorPlan';

const RAW = import.meta.glob<Parameters<typeof toPlan>[0]>('../features/floor/layouts/*.json', { import: 'default', eager: true });
let plans: readonly FloorPlan[] | null = null;

export function mockFloorPlans(): readonly FloorPlan[] {
  return (plans ??= Object.values(RAW).map(toPlan));
}

export function mockFloorPlan(mfcId: string): FloorPlan | null {
  return mockFloorPlans().find((p) => p.centerId === mfcId) ?? null;
}
