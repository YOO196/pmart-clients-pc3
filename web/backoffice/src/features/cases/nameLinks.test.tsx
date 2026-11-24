// 목록 이름은 바로 상세(2026-11-24 사용자 "이름 또는 아이콘으로 바로 들어가지게" — 줄 나머지는 미리보기 그대로)
import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';

import { as, renderAt } from '../../test/render';

describe('목록 이름 = 상세 링크', () => {
  it('접수 건: 요약은 상세 링크, 우선순위 칸을 누르면 미리보기', async () => {
    const user = userEvent.setup();
    renderAt('/cases', as.admin);
    const row = (await screen.findAllByTestId('case-row'))[0]!;
    const name = within(row).getByTestId('case-summary');
    expect(name.tagName).toBe('A');
    expect(name.getAttribute('href')).toMatch(/^\/cases\/.+/);
    await user.click(row.querySelector('td')!);
    expect(await screen.findByRole('complementary')).toBeInTheDocument();
  });

  it('클레임: 표기(이름)는 상세 링크', async () => {
    renderAt('/claims', as.cs);
    const row = (await screen.findAllByTestId('claim-row'))[0]!;
    const name = within(row).getByTestId('claim-label');
    expect(name.tagName).toBe('A');
    expect(name.getAttribute('href')).toMatch(/^\/claims\/.+/);
  });
});
