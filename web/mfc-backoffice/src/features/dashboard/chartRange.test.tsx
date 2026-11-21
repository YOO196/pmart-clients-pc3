// 추이 그래프 기간 — 기간 바(빠른 단추·날짜)·끌어서 확대·Ctrl+Z 이전 기간·정시 배송 31일씩 나눠 읽기. 목(MSW) 기준.
import { fireEvent, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';

import { renderAt } from '../../test/render';
import { addDays, chunks, daysIn, validRange } from './dashboardRules';

const today = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul' }).format(new Date());

/** jsdom 은 크기가 0 — 그래프 판을 600px 로 보이게 */
function sized(el: HTMLElement) {
  el.getBoundingClientRect = () => ({ left: 0, top: 0, right: 600, bottom: 128, width: 600, height: 128, x: 0, y: 0, toJSON: () => ({}) });
  el.setPointerCapture = () => {};
  return el;
}
const drag = (plot: HTMLElement, x0: number, x1: number) => {
  fireEvent.pointerDown(plot, { button: 0, clientX: x0, pointerId: 1 });
  fireEvent.pointerMove(plot, { clientX: x1, pointerId: 1 });
  fireEvent.pointerUp(plot, { clientX: x1, pointerId: 1 });
};

describe('추이 그래프 기간', () => {
  it('기간 규칙 — 92일 넘음·끝일이 오늘 뒤·뒤집힌 날짜는 받지 않고, 정시 배송은 31일씩 나눈다', () => {
    const t = '2026-11-21';
    expect(validRange('2026-11-01', '2026-11-21', t)).toEqual({ from: '2026-11-01', to: '2026-11-21' });
    expect(validRange(addDays(t, -92), t, t)).toBeNull();
    expect(validRange(addDays(t, -91), t, t)).not.toBeNull();
    expect(validRange('2026-11-10', '2026-11-22', t)).toBeNull();
    expect(validRange('2026-11-10', '2026-11-01', t)).toBeNull();
    expect(validRange('x', t, t)).toBeNull();
    const parts = chunks({ from: addDays(t, -89), to: t }, 31);
    expect(parts.map((p) => daysIn(p).length)).toEqual([31, 31, 28]);
    expect(parts.at(-1)!.to).toBe(t);
  });

  it('빠른 단추 30일 → 30칸, 정시율은 31일 상한이라 나눠 읽는다(90일 = 3번)', async () => {
    const view = renderAt('/c/MFC-BSN-01/dashboard');
    await screen.findByTestId('chart-picked');
    const bar = screen.getByTestId('range-bar');
    await userEvent.click(within(bar).getByRole('button', { name: '30일' }));
    await waitFor(() => expect(within(screen.getByTestId('chart-picked')).getAllByTestId('chart-picked-col')).toHaveLength(30));
    expect(screen.getByRole('heading', { name: /추이 · .* \(30일\)/ })).toBeInTheDocument();
    await userEvent.click(within(bar).getByRole('button', { name: '90일' }));
    await userEvent.click(screen.getByRole('button', { name: '정시율' }));
    await waitFor(() => expect(within(screen.getByTestId('chart-on-time')).getAllByTestId('chart-on-time-col')).toHaveLength(90));
    const asked = view.gets('/metrics/on-time-deliveries').map((r) => new URL(r.url).searchParams);
    const wide = asked.filter((q) => q.get('to') === today() && (q.get('from') ?? '') > addDays(today(), -31));
    expect(wide.length).toBeGreaterThan(0);
    for (const q of asked) expect(daysIn({ from: q.get('from')!, to: q.get('to')! }).length).toBeLessThanOrEqual(31);
  });

  it('그래프를 끌면 그 구간(첫 칸~끝 칸)으로 확대, Ctrl+Z 면 바로 전 기간', async () => {
    renderAt('/c/MFC-BSN-01/dashboard');
    await screen.findByTestId('chart-picked');
    // 14칸, 칸 폭 600/14 ≈ 42.9px — 2번째 칸(50px)부터 6번째 칸(250px)까지 = 5일
    drag(sized(screen.getByTestId('chart-picked-plot')), 50, 250);
    await waitFor(() => expect(within(screen.getByTestId('chart-picked')).getAllByTestId('chart-picked-col')).toHaveLength(5));
    const from = addDays(today(), -12);
    expect(screen.getByLabelText('시작일')).toHaveValue(from);
    expect(screen.getByLabelText('끝일')).toHaveValue(addDays(from, 4));
    // 한 번 더 확대 → 되돌리기 두 번이면 처음 14일
    drag(sized(screen.getByTestId('chart-picked-plot')), 0, 300);
    await waitFor(() => expect(within(screen.getByTestId('chart-picked')).getAllByTestId('chart-picked-col')).toHaveLength(3));
    fireEvent.keyDown(window, { key: 'z', ctrlKey: true });
    await waitFor(() => expect(within(screen.getByTestId('chart-picked')).getAllByTestId('chart-picked-col')).toHaveLength(5));
    await userEvent.click(screen.getByTestId('range-back'));
    await waitFor(() => expect(within(screen.getByTestId('chart-picked')).getAllByTestId('chart-picked-col')).toHaveLength(14));
    expect(screen.getByTestId('range-back')).toBeDisabled();
  });

  it('한 칸만 누르면(끌지 않으면) 기간은 그대로', async () => {
    renderAt('/c/MFC-BSN-01/dashboard');
    await screen.findByTestId('chart-picked');
    drag(sized(screen.getByTestId('chart-picked-plot')), 50, 60);
    expect(within(screen.getByTestId('chart-picked')).getAllByTestId('chart-picked-col')).toHaveLength(14);
    expect(screen.getByTestId('range-back')).toBeDisabled();
  });

  it('주소의 기간(?from=&to=)으로 열고, 맞지 않는 기간이면 기본 14일', async () => {
    renderAt(`/c/MFC-BSN-01/dashboard?from=${addDays(today(), -6)}&to=${today()}`);
    await waitFor(() => expect(within(screen.getByTestId('chart-picked')).getAllByTestId('chart-picked-col')).toHaveLength(7));
  });
});
