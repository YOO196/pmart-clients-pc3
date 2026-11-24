// 사진 권장 규격 경고 — 서버 값(storefront 0.15.0·product-content 0.8.0)으로, 막지 않음(2026-11-24)
import { describe, expect, it } from 'vitest';

import { fitWarning, formatText, specText, type ImageSpec } from './imageFit';

const HOME: ImageSpec = { ratio: 2.8, ratioLabel: '2.8:1', tolerance: 0.1, fit: 'cover', recommendedWidth: 1960, recommendedHeight: 700, minWidth: 1080, minHeight: 386 };
const SPLASH: ImageSpec = { ratio: 9 / 16, ratioLabel: '9:16', tolerance: 0.1, fit: 'contain', recommendedWidth: 1080, recommendedHeight: 1920, minWidth: 720, minHeight: 1280 };
const MAIN: ImageSpec = { ratio: 1, ratioLabel: '1:1', tolerance: 0.1, fit: 'cover', recommendedWidth: 1000, recommendedHeight: 1000, minWidth: 1000, minHeight: 1000 };
const DESC: ImageSpec = { tolerance: 0.1, fit: 'cover', recommendedWidth: 1000, recommendedHeight: null, minWidth: 1000, minHeight: null };

describe('fitWarning(서버 규격)', () => {
  it('권장 범위면 경고 없음 — 최소 이상·비율 ±10%', () => {
    expect(fitWarning(1960, 700, HOME)).toBeNull();
    expect(fitWarning(1080, 386, HOME)).toBeNull();
    expect(fitWarning(1000, 5000, DESC)).toBeNull(); // 세로 자유
  });
  it('지금 LAN 배너 1984×793(2.5:1) — 비율 밖이라 위아래가 잘린다(막지는 않음)', () => {
    expect(fitWarning(1984, 793, HOME)).toBe('1984×793 — 2.8:1과 달라 위아래가 잘려요');
  });
  it('정사각형 600 을 홈 배너에 — 비율·최소 둘 다', () => {
    expect(fitWarning(600, 600, HOME)).toBe('600×600 — 2.8:1과 달라 위아래가 잘려요 · 1080×386보다 작아 흐릴 수 있어요');
  });
  it('상품 대표가 가로로 길면 양옆, 상세가 좁으면 가로 경고, 로딩 화면은 남는 곳을 채운다', () => {
    expect(fitWarning(2000, 1000, MAIN)).toBe('2000×1000 — 1:1과 달라 양옆이 잘려요');
    expect(fitWarning(800, 3000, DESC)).toBe('800×3000 — 가로 1000px보다 작아 흐릴 수 있어요');
    expect(fitWarning(1080, 1080, SPLASH)).toContain('남는 곳은 색으로 채워요');
  });
  it('안내 줄: 권장·최소, 형식·용량', () => {
    expect(specText(HOME, true)).toBe('권장 1960×700(2.8:1) · 최소 1080×386');
    expect(specText(DESC, false)).toBe('권장 가로 1000');
    expect(formatText(['image/jpeg', 'image/png', 'image/webp'], 5 * 1024 * 1024)).toBe('JPEG·PNG·WEBP · 5MB 이하');
  });
});
