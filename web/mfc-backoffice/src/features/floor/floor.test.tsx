// 센터 도면(2026-11-21) — 랙 → 칸별 상품(stock-units locationPrefix), 작업자 → 정보·진행 중·예정 작업. 목(MSW) 기준.
import { fireEvent, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';

import { renderAt } from '../../test/render';

describe('센터 도면', () => {
  it('랙을 누르면 그 랙 칸의 지금 놓인 상품(재고 서버 값)·칸 상태 — locationPrefix 로 한 번에 읽는다', async () => {
    const view = renderAt('/c/MFC-BSN-01/floor');
    const rack = await waitFor(() => {
      const r = document.querySelector('[data-testid="floor-rack"][data-code="A-P1-01"]');
      if (!r) throw new Error('rack');
      return r;
    });
    fireEvent.click(rack);
    const panel = await screen.findByTestId('rack-panel');
    expect(panel).toHaveTextContent('랙 A-P1-01');
    await waitFor(() => expect(within(panel).getAllByTestId('rack-cell')).toHaveLength(1));
    expect(within(panel).getByText('A-P1-01-1-01')).toBeInTheDocument();
    expect(within(panel).getByText(/12개/)).toBeInTheDocument();
    const q = new URL(view.gets('/stock-units').at(-1)!.url).searchParams;
    expect(q.get('locationPrefix')).toBe('A-P1-01-');
  });

  it('등록된 칸이 없는 랙은 빈 랙으로 꾸미지 않고 그렇게 말한다', async () => {
    renderAt('/c/MFC-BSN-01/floor?rack=F-P3-09');
    expect(await screen.findByTestId('rack-empty')).toHaveTextContent('F-P3-09 로 시작하는 등록된 칸이 없어요');
  });

  it('작업자 점을 누르면 정보 · 진행 중 작업 · 예정 작업, 작업자 상세 링크', async () => {
    renderAt('/c/MFC-BSN-01/floor');
    await waitFor(() => expect(screen.getAllByTestId('floor-worker').length).toBe(3));
    const dot = screen.getAllByRole('button', { name: /김현장/ })[0]!;
    await userEvent.click(dot);
    const panel = await screen.findByTestId('worker-panel');
    expect(panel).toHaveTextContent('김현장');
    await waitFor(() => expect(within(screen.getByTestId('worker-running')).getAllByRole('link').length).toBeGreaterThan(0));
    expect(within(panel).getByRole('link', { name: '작업자 상세로' })).toHaveAttribute('href', '/c/MFC-BSN-01/workers/OP-wkr-1');
  });

  it('대시보드 도면을 누르면 센터 도면으로', async () => {
    renderAt('/c/MFC-BSN-01/dashboard');
    expect(await screen.findByTestId('floor-open')).toHaveAttribute('href', '/c/MFC-BSN-01/floor');
  });
});
