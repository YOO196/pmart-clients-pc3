// 목 — 다른 센터 시연 기록 옮기기 규칙(브라우저 목 전용, demoCenters).
import { describe, expect, it } from 'vitest';

import { DEMO_OTHERS, cloneForCenter, hasDemoData, scaled } from './demoCenters';
import { mockFloorPlan } from './floorPlans';

const sejong = DEMO_OTHERS.find((c) => c.id === 'MFC-SEJ-01')!;

describe('다른 센터 시연 기록', () => {
  it('시험에서는 부산진구만 데이터가 있다(브라우저 목에서만 켬)', () => {
    expect(hasDemoData('MFC-BJG-01')).toBe(true);
    expect(hasDemoData('MFC-SEJ-01')).toBe(false);
    expect(scaled(10, 'MFC-BJG-01')).toBe(10);
    expect(scaled(10, 'MFC-SEJ-01')).toBe(13);
  });

  it('센터·기록 ID·작업자·선반 칸을 그 센터 것으로 바꾸고, 상품·LOT·라이더는 그대로', () => {
    const task = {
      taskId: 'TASK-1',
      mfcId: 'MFC-BJG-01',
      sku: 'SKU-MILK-1',
      lotId: 'LOT-MILK-A',
      riderId: 'RD-7',
      assignment: { workerId: 'OP-wkr-1', assignedBy: 'OP-sup-1' },
      lines: [{ locationCode: 'C-S1-03-2-04', qty: 2 }],
      packingLocation: 'PAK-A-01',
      deliveryNumber: 'D35726513',
      taskIds: ['TASK-2'],
    };
    const out = cloneForCenter(task, sejong);
    expect(out.mfcId).toBe('MFC-SEJ-01');
    expect(out.taskId).toBe('TASK-1-sj');
    expect(out.taskIds).toEqual(['TASK-2-sj']);
    expect([out.sku, out.lotId, out.riderId]).toEqual(['SKU-MILK-1', 'LOT-MILK-A', 'RD-7']);
    expect(out.assignment.workerId).toMatch(/^OP-demo-sj-[1-8]$/);
    expect(out.assignment.assignedBy).toBe('OP-sup-sj');
    expect(out.packingLocation).toBe('PAK-A-01');
    expect(out.deliveryNumber).not.toBe('D35726513');
    // 선반 칸 → 세종 도면의 냉장 랙 칸
    const rack = out.lines[0]!.locationCode.split('-').slice(0, 3).join('-');
    expect(mockFloorPlan('MFC-SEJ-01')!.racks.some((r) => r.code === rack && r.temp === 'CHILLED')).toBe(true);
    // 같은 사람·칸은 늘 같은 것으로
    expect(cloneForCenter(task, sejong)).toEqual(out);
    // 원본은 그대로
    expect(task.mfcId).toBe('MFC-BJG-01');
  });
});
