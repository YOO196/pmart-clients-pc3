// 추이 그래프 기간 — 기간 바(빠른 단추·날짜)·끌어서 확대·Ctrl+Z 이전 기간·정시 배송 31일씩 나눠 읽기. 목(MSW) 기준.
import { fireEvent, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';

import { renderAt } from '../../test/render';
import { addDays, buckets, presetFrom, chunks, daysIn, defaultUnit, hourShare, unitsFor, validRange } from './dashboardRules';

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
  it('기간 규칙 — 1년(366일) 넘음·끝일이 오늘 뒤·뒤집힌 날짜는 받지 않고, 정시 배송은 31일씩 나눈다', () => {
    const t = '2026-11-21';
    expect(validRange('2026-11-01', '2026-11-21', t)).toEqual({ from: '2026-11-01', to: '2026-11-21' });
    expect(validRange(addDays(t, -366), t, t)).toBeNull();
    expect(validRange(addDays(t, -365), t, t)).not.toBeNull();
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
    expect(screen.getByRole('heading', { name: /추이 · .* \(30일 · 일별\)/ })).toBeInTheDocument();
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
    drag(sized(screen.getByTestId('chart-picked-plot')), 50, 54);
    expect(within(screen.getByTestId('chart-picked')).getAllByTestId('chart-picked-col')).toHaveLength(14);
    expect(screen.getByTestId('range-back')).toBeDisabled();
  });

  it('칸 단위 — 1일은 시간(목만, 시간 합 = 그날 합), 1년은 월, 주는 월요일부터, 단위 바꾸기', async () => {
    const t = '2026-11-21'; // 토요일
    expect(unitsFor(1, true)).toEqual(['hour', 'day']);
    expect(unitsFor(1, false)).toEqual(['day']);
    expect(unitsFor(365, true)).toEqual(['day', 'week', 'month']);
    expect(defaultUnit(1, true)).toBe('hour');
    expect(defaultUnit(1, false)).toBe('day');
    expect(defaultUnit(365, true)).toBe('month');
    expect(buckets({ from: '2026-11-20', to: '2026-11-20' }, 'hour', t, 14)).toHaveLength(24);
    expect(buckets({ from: t, to: t }, 'hour', t, 14)).toHaveLength(15);
    const weeks = buckets({ from: '2026-11-05', to: t }, 'week', t, 14);
    expect(weeks.map((b) => [b.from, b.to])).toEqual([['2026-11-05', '2026-11-08'], ['2026-11-09', '2026-11-15'], ['2026-11-16', t]]);
    expect(buckets({ from: '2025-11-22', to: t }, 'month', t, 14).map((b) => b.label).slice(0, 2)).toEqual(['25년 11월', '25년 12월']);
    const total = Array.from({ length: 24 }, (_, h) => hourShare(137, h, 23)).reduce((a, b) => a + b, 0);
    expect(total).toBe(137);
    expect(Array.from({ length: 15 }, (_, h) => hourShare(40, h, 14)).reduce((a, b) => a + b, 0)).toBe(40);

    renderAt('/c/MFC-BSN-01/dashboard');
    await screen.findByTestId('chart-picked');
    const bar = screen.getByTestId('range-bar');
    await userEvent.click(within(bar).getByRole('button', { name: '1년' }));
    // 1년 = 11달 전 1일부터 → 월 12칸
    await waitFor(() => expect(within(screen.getByTestId('chart-picked')).getAllByTestId('chart-picked-col')).toHaveLength(12));
    expect(screen.getByLabelText('시작일')).toHaveValue(presetFrom(365, today()));
    expect(presetFrom(365, '2026-11-21')).toBe('2025-12-01');
    expect(presetFrom(365, '2026-12-05')).toBe('2026-01-01');
    expect(screen.getByRole('heading', { name: /월별/ })).toBeInTheDocument();
    await userEvent.click(within(bar).getByRole('button', { name: '주' }));
    await waitFor(() => expect(screen.getByRole('heading', { name: /주별/ })).toBeInTheDocument());
    expect(within(bar).getByRole('button', { name: '시간' })).toBeDisabled();
    await userEvent.click(within(bar).getByRole('button', { name: '1일' }));
    await waitFor(() => expect(screen.getByRole('heading', { name: /\(1일 · 시간별\)/ })).toBeInTheDocument());
    // Ctrl+Z 는 단위까지 되돌린다
    fireEvent.keyDown(window, { key: 'z', ctrlKey: true });
    await waitFor(() => expect(screen.getByRole('heading', { name: /주별/ })).toBeInTheDocument());
  });

  it('하루 칸 안을 끌면 그날 시간별', async () => {
    renderAt('/c/MFC-BSN-01/dashboard');
    await screen.findByTestId('chart-picked');
    // 14칸 중 마지막 칸(오늘) 안에서 10px 끌기
    drag(sized(screen.getByTestId('chart-picked-plot')), 580, 592);
    await waitFor(() => expect(screen.getByRole('heading', { name: /\(1일 · 시간별\)/ })).toBeInTheDocument());
    expect(screen.getByLabelText('시작일')).toHaveValue(today());
  });

  it('주소의 기간(?from=&to=)으로 열고, 맞지 않는 기간이면 기본 14일', async () => {
    renderAt(`/c/MFC-BSN-01/dashboard?from=${addDays(today(), -6)}&to=${today()}`);
    await waitFor(() => expect(within(screen.getByTestId('chart-picked')).getAllByTestId('chart-picked-col')).toHaveLength(7));
  });
});
