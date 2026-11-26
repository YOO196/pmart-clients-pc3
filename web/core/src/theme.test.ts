// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest';

import { THEME_COOKIE, readChosenTheme, readSharedTheme, watchSharedTheme, writeSharedTheme } from './theme';

function clearCookie() {
  document.cookie = `${THEME_COOKIE}=; Path=/; Max-Age=0`;
}

function mockDevice(dark: boolean) {
  window.matchMedia = vi.fn().mockReturnValue({
    matches: dark,
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
  }) as typeof window.matchMedia;
}

describe('공통 테마(쿠키 — 다섯 백오피스가 같이 본다)', () => {
  afterEach(() => clearCookie());

  it('고른 적이 없으면 기기 설정을 따른다', () => {
    mockDevice(true);
    expect(readChosenTheme()).toBeNull();
    expect(readSharedTheme()).toBe('pmart-dark');
    mockDevice(false);
    expect(readSharedTheme()).toBe('pmart');
  });

  it('고르면 쿠키에 남고 기기 설정보다 앞선다', () => {
    mockDevice(true);
    writeSharedTheme('pmart');
    expect(document.cookie).toContain(`${THEME_COOKIE}=pmart`);
    expect(readSharedTheme()).toBe('pmart');
  });

  it('모르는 쿠키 값은 무시한다', () => {
    mockDevice(false);
    document.cookie = `${THEME_COOKIE}=purple; Path=/`;
    expect(readChosenTheme()).toBeNull();
    expect(readSharedTheme()).toBe('pmart');
  });

  it('다른 앱이 바꾼 뒤 이 탭으로 돌아오면(포커스) 새 테마를 알린다', () => {
    mockDevice(false);
    const seen: string[] = [];
    const stop = watchSharedTheme((t) => seen.push(t));
    writeSharedTheme('pmart-dark'); // 다른 앱(같은 호스트 다른 포트)이 쓴 것과 같다
    window.dispatchEvent(new Event('focus'));
    expect(seen).toEqual(['pmart-dark']);
    stop();
    writeSharedTheme('pmart');
    window.dispatchEvent(new Event('focus'));
    expect(seen).toEqual(['pmart-dark']);
  });
});
