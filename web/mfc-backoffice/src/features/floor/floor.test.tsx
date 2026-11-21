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
    const cell = within(panel).getByTestId('rack-cell');
    expect(cell).toHaveAttribute('data-code', 'A-P1-01-1-01');
    expect(cell).toHaveTextContent('01번 칸');
    expect(cell).toHaveTextContent(/12개/);
    // 요약: 칸 수 · 상품 있는 칸 · 재고 합
    expect(within(panel).getByTestId('rack-summary')).toHaveTextContent('1칸');
    expect(within(panel).getByTestId('rack-summary')).toHaveTextContent('1 / 1');
    // 고른 랙은 눌린 상태(보라) — 큰 흰 테두리가 아니라 aria-pressed 로 칠한다
    expect(rack).toHaveAttribute('aria-pressed', 'true');
    const q = new URL(view.gets('/stock-units').at(-1)!.url).searchParams;
    expect(q.get('locationPrefix')).toBe('A-P1-01-');
    // 칸 목록은 랙 온도대로 좁혀 읽는다(칸이 수천 개)
    const lq = view.gets('/locations').map((r) => new URL(r.url).searchParams);
    expect(lq.some((x) => x.get('temperatureZone') === 'AMBIENT')).toBe(true);
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
    const actions = screen.getByTestId('floor-actions');
    expect(within(actions).getByRole('link', { name: '작업자 상세로' })).toHaveAttribute('href', '/c/MFC-BSN-01/workers/OP-wkr-1');
    expect(within(actions).getByRole('link', { name: '이 작업자 배정 내역' })).toHaveAttribute('href', '/c/MFC-BSN-01/assignments?workerId=OP-wkr-1');
  });

  it('대시보드 도면을 누르면 센터 도면으로', async () => {
    renderAt('/c/MFC-BSN-01/dashboard');
    expect(await screen.findByTestId('floor-open')).toHaveAttribute('href', '/c/MFC-BSN-01/floor');
  });
});
