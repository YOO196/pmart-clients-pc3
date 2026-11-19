// 목록 순서대로 상세 넘기기(2026-11-19)
import { fireEvent, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it } from 'vitest';

import { as, renderAt } from '../test/render';

beforeEach(() => sessionStorage.clear());

describe('목록 순서대로 이전·다음', () => {
  it('접수 건 목록에서 상세로 가면 "1 / N", ] 로 다음 건, [ 로 앞 건', async () => {
    const user = userEvent.setup();
    renderAt('/cases?tab=unassigned', as.riderOps);
    const rows = await screen.findAllByTestId('case-row');
    expect(rows.length).toBeGreaterThan(1);
    await user.click(within(rows[0]!).getAllByRole('link')[0]!);
    expect(await screen.findByTestId('queue-pos')).toHaveTextContent(`1 / ${rows.length}`);
    expect(screen.queryByTestId('queue-prev')).not.toBeInTheDocument();
    fireEvent.keyDown(window, { key: ']' });
    await waitFor(() => expect(screen.getByTestId('queue-pos')).toHaveTextContent(`2 / ${rows.length}`));
    fireEvent.keyDown(window, { key: '[' });
    await waitFor(() => expect(screen.getByTestId('queue-pos')).toHaveTextContent(`1 / ${rows.length}`));
  });

  it('목록을 거치지 않고 바로 연 상세에는 띠가 없다', async () => {
    renderAt('/cases/CASE-MOCK-1', as.riderOps);
    await screen.findByTestId('case-number');
    expect(screen.queryByTestId('queue-nav')).not.toBeInTheDocument();
  });

  it('승인함 목록 → 상세에서도', async () => {
    const user = userEvent.setup();
    renderAt('/approvals', as.admin);
    const rows = await screen.findAllByTestId('approval-row');
    expect(rows.length).toBeGreaterThan(1);
    // 승인함 줄을 누르면 미리보기 — 거기서 '상세 열기'
    await user.click(rows[1]!);
    await user.click(await screen.findByRole('link', { name: '상세 열기' }));
    expect(await screen.findByTestId('queue-pos')).toHaveTextContent(`2 / ${rows.length}`);
  });
});
