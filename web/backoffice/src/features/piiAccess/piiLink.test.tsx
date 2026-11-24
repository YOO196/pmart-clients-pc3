// 개인정보 열람 기록 — 이름으로도 상세(2026-11-24 사용자 "이름 또는 아이콘으로 바로 들어가지게")
import { screen, within } from '@testing-library/react';
import { describe, expect, it } from 'vitest';

import { as, renderAt } from '../../test/render';

describe('개인정보 열람 기록 줄', () => {
  it('직원 이름이 상세로 가는 링크(오른쪽 시각과 같은 곳)', async () => {
    renderAt('/pii-access-logs', as.admin);
    const row = (await screen.findAllByTestId('pii-log-row'))[0]!;
    const byName = within(row).getByTestId('pii-log-open');
    const byTime = within(row).getAllByRole('link')[0]!;
    expect(byName).toHaveAttribute('href', byTime.getAttribute('href'));
    expect(byName.getAttribute('href')).toMatch(/^\/pii-access-logs\/.+/);
  });
});
