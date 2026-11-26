// 밝은/어두운 테마(2026-11-18)
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it } from 'vitest';

import { as, renderAt } from '../test/render';
import { readTheme } from '../shared/theme';

beforeEach(() => {
  // 고른 테마는 다섯 앱이 같이 보는 쿠키(@pmart/web-core) — 시험마다 지운다.
  document.cookie = 'pmart_theme=; Path=/; Max-Age=0';
  document.documentElement.setAttribute('data-theme', 'pmart');
});

describe('밝은/어두운 테마', () => {
  it('머리줄 단추로 바꾸고, 다른 백오피스도 같이 보는 쿠키에 기억한다', async () => {
    const user = userEvent.setup();
    renderAt('/', as.cs);
    await user.click(await screen.findByRole('button', { name: '어두운 화면으로' }));
    expect(document.documentElement).toHaveAttribute('data-theme', 'pmart-dark');
    expect(readTheme()).toBe('pmart-dark');
    expect(document.cookie).toContain('pmart_theme=pmart-dark');

    await user.click(screen.getByRole('button', { name: '밝은 화면으로' }));
    expect(document.documentElement).toHaveAttribute('data-theme', 'pmart');
    expect(readTheme()).toBe('pmart');
  });

  it('고른 값이 없거나 이상하면 기기 설정(여기서는 밝은 화면)', () => {
    expect(readTheme()).toBe('pmart');
    document.cookie = 'pmart_theme=neon; Path=/';
    expect(readTheme()).toBe('pmart');
  });
});
