// 배너 그림 규격 — 서버 값으로 안내, 서버 경고는 막지 않고 보여 줌(storefront 0.15.0, 2026-11-24 사용자 "서버에서 막지 않고 경고만"·"규격 값은 백엔드 값으로")
import { screen, within } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';

import { bannerDims } from '../../mocks/storefrontHandlers';
import { as, renderAt } from '../../test/render';

afterEach(() => bannerDims.clear());

describe('배너 그림 규격', () => {
  it('자리 옆에 서버 규격(권장·최소), 저장된 그림이 비율 밖이면 서버 경고 그대로', async () => {
    bannerDims.set('bimg-seed-winter', { w: 1984, h: 793 });
    renderAt('/display/home/LD-seed-1', as.admin);
    const card = (await screen.findAllByTestId('layout-banner'))[0]!;
    expect(await within(card).findByTestId('banner-image-size')).toHaveTextContent('권장 1960×700(2.8:1) · 최소 1080×386');
    expect(await within(card).findByTestId('banner-image-fit')).toHaveTextContent('지금 1984×793 — HOME_TOP 권장 2.8:1');
    expect(within(card).getByText(/JPEG·PNG·WEBP · 5MB 이하/)).toBeInTheDocument();
  });
});
