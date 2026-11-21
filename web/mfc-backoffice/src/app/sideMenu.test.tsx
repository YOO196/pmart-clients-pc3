// 왼쪽 메뉴 접기(2026-11-21) — 좁은 화면이면 접어서 시작, 단추로 고르면 이 브라우저에 기억.
import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { renderAt } from '../test/render';

const narrowScreen = (matches: boolean) =>
  vi.stubGlobal('matchMedia', (q: string) => ({ matches, media: q, addEventListener: () => {}, removeEventListener: () => {} }) as unknown as MediaQueryList);

describe('왼쪽 메뉴 접기', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('넓은 화면은 펴서 시작 → "메뉴 접기"로 접으면 묶음 아이콘만, 다시 열어도 접힌 채(기억)', async () => {
    narrowScreen(false);
    const first = renderAt('/c/MFC-BSN-01/ops');
    const side = await screen.findByTestId('side-menu');
    expect(side).toHaveAttribute('data-collapsed', 'false');
    await userEvent.click(within(side).getByRole('button', { name: '메뉴 접기' }));
    expect(side).toHaveAttribute('data-collapsed', 'true');
    expect(within(side).getByRole('link', { name: '출고 운영' })).toHaveAttribute('href', '/c/MFC-BSN-01/tasks');
    first.unmount();
    renderAt('/c/MFC-BSN-01/ops');
    expect(await screen.findByTestId('side-menu')).toHaveAttribute('data-collapsed', 'true');
  });

  it('좁은 화면(1023px 이하)은 접어서 시작 — "메뉴 펴기"로 편다', async () => {
    narrowScreen(true);
    renderAt('/c/MFC-BSN-01/ops');
    const side = await screen.findByTestId('side-menu');
    expect(side).toHaveAttribute('data-collapsed', 'true');
    await userEvent.click(within(side).getByRole('button', { name: '메뉴 펴기' }));
    expect(side).toHaveAttribute('data-collapsed', 'false');
  });
});
