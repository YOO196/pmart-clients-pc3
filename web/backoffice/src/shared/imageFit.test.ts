// 사진 권장 규격 경고(2026-11-24 — 화면에서 경고만, 올리기는 막지 않음)
import { describe, expect, it } from 'vitest';

import { BANNER_SPEC, CONTENT_SPEC, fitWarning } from './imageFit';

describe('fitWarning', () => {
  it('권장에 맞으면(비율 ±10%, 가로 1080 이상) 경고 없음', () => {
    expect(fitWarning(1080, 386, BANNER_SPEC['HOME_TOP'])).toBeNull();
    expect(fitWarning(1200, 450, BANNER_SPEC['HOME_TOP'])).toBeNull(); // 2.67:1 — 10% 안
    expect(fitWarning(1080, 1350, BANNER_SPEC['POPUP'])).toBeNull();
    expect(fitWarning(1080, 5000, CONTENT_SPEC['DESCRIPTION'])).toBeNull(); // 상세설명은 세로 자유
  });
  it('정사각형을 홈 배너에 — 위아래가 잘린다, 작으면 흐림까지', () => {
    expect(fitWarning(600, 600, BANNER_SPEC['HOME_TOP'])).toBe('600×600 — 2.8:1과 달라 위아래가 잘려요 · 1080px보다 작아 흐릴 수 있어요');
  });
  it('가로로 긴 그림을 상품 대표(1:1)에 — 양옆이 잘린다', () => {
    expect(fitWarning(2000, 1000, CONTENT_SPEC['MAIN'])).toBe('2000×1000 — 1:1과 달라 양옆이 잘려요');
  });
  it('로딩 화면(다 보이게)은 잘리지 않고 남는 곳을 채운다고 알림', () => {
    expect(fitWarning(1080, 1080, BANNER_SPEC['SPLASH'])).toContain('남는 곳은 색으로 채워요');
  });
});
