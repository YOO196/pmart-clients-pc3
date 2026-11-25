// 재고 > LOT 추적 — lot-resolutions(0.21.0)·stock·stock-ledger(0.48.0, lotId) 목.
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';

import { renderAt } from '../../test/render';
import { lotCode } from './LotTraceTab';

describe('LOT 추적', () => {
  it('LOT 번호 전에는 묻지 않고 한 줄 안내', async () => {
    const view = renderAt('/c/MFC-BJG-01/inventory?tab=lotTrace');
    expect(await screen.findByText('LOT 번호를 넣고 조회해요.')).toBeInTheDocument();
    expect(view.gets('/lot-resolutions')).toHaveLength(0);
  });

  it('LOT 번호 → (10) 괄호 꼴로 찾고, LOT 정보·지금 있는 칸·이 LOT 이 지나온 길(서버 값)', async () => {
    const view = renderAt('/c/MFC-BJG-01/inventory?tab=lotTrace');
    await userEvent.type(await screen.findByRole('searchbox', { name: 'LOT 번호·라벨 바코드' }), 'l261107000497');
    await userEvent.click(screen.getByRole('button', { name: '조회' }));
    const card = await screen.findByTestId('lot-card');
    expect(card).toHaveTextContent('L261107000497');
    expect(new URL(view.gets('/lot-resolutions')[0]!.url).searchParams.get('code')).toBe('(10)L261107000497');
    // 지금 있는 곳 — 이 LOT 칸만(다른 LOT 칸 RCV-C-01 은 없다)
    await waitFor(() => expect(screen.getAllByTestId('lot-where-row').map((r) => within(r).getAllByRole('cell')[0]!.textContent)).toEqual(['A-P1-01-1-01', 'QRT-A-01']));
    // 지나온 길 — lotId 로 거른 이력, 이동은 출발 −·도착 +
    await waitFor(() => expect(screen.getAllByTestId('lot-history-row').length).toBeGreaterThan(0));
    const ledger = view.gets('/stock-ledger').at(-1)!;
    expect(new URL(ledger.url).searchParams.get('lotId')).toBe('LOT-MILK-A');
    expect(screen.getByText('A-P1-01-1-01 −2 → QRT-A-01 +2')).toBeInTheDocument();
    // 주문·처리한 사람(inventory 0.49.0) — 주문은 화면 번호 8자리(work-orders → 출고), 운영자 ID 는 내지 않는다
    const handover = screen.getAllByTestId('lot-history-row').find((r) => r.textContent?.includes('라이더 인계'))!;
    await waitFor(() => expect(handover).toHaveTextContent('20000001'));
    expect(handover).not.toHaveTextContent('ORD-1');
    expect(handover).not.toHaveTextContent('OP-wkr-1');
  });

  it('없는 LOT 은 404 — 빈 화면이 아니라 오류', async () => {
    renderAt('/c/MFC-BJG-01/inventory?tab=lotTrace&lot=L000000000000');
    expect(await screen.findByRole('alert')).toBeInTheDocument();
    expect(screen.queryByTestId('lot-card')).not.toBeInTheDocument();
  });

  it('입력 꼴: 괄호 꼴·LOT:·스캐너 원문은 그대로, 맨 번호는 (10)', () => {
    expect(lotCode('L261107000497')).toBe('(10)L261107000497');
    expect(lotCode('(01)08801115114154(10)L261107000497')).toBe('(01)08801115114154(10)L261107000497');
    expect(lotCode('LOT:LOT-MILK-A')).toBe('LOT:LOT-MILK-A');
    expect(lotCode('0108801115114154')).toBe('0108801115114154');
  });
});
