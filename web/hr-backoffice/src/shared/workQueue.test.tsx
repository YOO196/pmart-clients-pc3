// 목록 순서대로 직원 상세 넘기기·미리보기 Enter(2026-11-19)
import { fireEvent, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it } from 'vitest';

import { renderAt } from '../test/render';
import { safeFrom } from './workQueue';

beforeEach(() => sessionStorage.clear());

describe('직원 이전·다음', () => {
  it('직원 목록 줄 → 미리보기 → Enter 로 상세, ] 로 다음 직원', async () => {
    const user = userEvent.setup();
    renderAt('/employees');
    const rows = await screen.findAllByTestId('employee-row');
    expect(rows.length).toBeGreaterThan(1);
    await user.click(rows[0]!);
    fireEvent.keyDown(document.body, { key: 'Enter' });
    expect(await screen.findByTestId('queue-pos')).toHaveTextContent(`1 / ${rows.length}`);
    fireEvent.keyDown(window, { key: ']' });
    await waitFor(() => expect(screen.getByTestId('queue-pos')).toHaveTextContent(`2 / ${rows.length}`));
  });

  it('찾기 말(이름·메일)은 기억하는 목록 주소에서 뺀다', () => {
    expect(safeFrom('/employees?q=홍길동&status=ACTIVE')).toBe('/employees?status=ACTIVE');
  });
});
