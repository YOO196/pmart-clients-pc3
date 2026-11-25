// 추이 그래프 기간 — 기간 바(빠른 단추·날짜)·끌어서 확대·Ctrl+Z 한 단계 넓게·정시 배송 31일씩 나눠 읽기. 목(MSW) 기준.
import { fireEvent, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it } from 'vitest';

import { env } from '../../env';
import { renderAt } from '../../test/render';
import { addDays, buckets, partialOf, pickingKey, presetFrom, zoomOut, chunks, daysIn, defaultUnit, hourShare, unitsFor, validRange } from './dashboardRules';

const today = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul' }).format(new Date());

/** jsdom 은 크기가 0 — 그래프 판을 600px 로 보이게 */
function sized(el: HTMLElement) {
  el.getBoundingClientRect = () => ({ left: 0, top: 0, right: 600, bottom: 128, width: 600, height: 128, x: 0, y: 0, toJSON: () => ({}) });
  el.setPointerCapture = () => {};
  return el;
}
/** 목 모드 기본은 주문 그래프 — 피킹 줄로 바꾼다 */
async function openPicked() {
  await userEvent.click(await screen.findByRole('button', { name: '피킹 줄' }));
  await screen.findByTestId('chart-picked');
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

  it('빠른 단추 30일 → 30칸·지난 30일 비교선, 90일 출하 준수(목 시뮬레이션) 90칸', async () => {
    const view = renderAt('/c/MFC-BJG-01/dashboard');
    await openPicked();
    const bar = screen.getByTestId('range-bar');
    await userEvent.click(within(bar).getByRole('button', { name: '30일' }));
    await waitFor(() => expect(within(screen.getByTestId('chart-picked')).getAllByTestId('chart-picked-col')).toHaveLength(30));
    expect(screen.getByRole('heading', { name: /추이 · .* \(30일 · 일별\)/ })).toBeInTheDocument();
    // 30칸이라 막대, 지난 30일(바로 앞 같은 길이)을 같이 읽어 옅은 점선
    expect(within(screen.getByTestId('chart-picked')).getAllByTestId('chart-picked-bar').length).toBeGreaterThan(0);
    const picks = view.gets('/metrics/picking-lines').map((r) => new URL(r.url).searchParams);
    await waitFor(() => expect(view.gets('/metrics/picking-lines').some((r) => new URL(r.url).searchParams.get('to') === addDays(today(), -30))).toBe(true));
    expect(picks.length).toBeGreaterThan(0);
    await waitFor(() => expect(within(screen.getByTestId('chart-picked')).getByTestId('chart-picked-prev')).toBeInTheDocument());
    await userEvent.click(within(bar).getByRole('button', { name: '90일' }));
    // 90일은 기본이 주 단위(일별은 요일 톱니) — 주 칸 막대
    const weeks = buckets({ from: presetFrom(90, today()), to: today() }, 'week', today(), 0).length;
    await waitFor(() => expect(within(screen.getByTestId('chart-picked')).getAllByTestId('chart-picked-col')).toHaveLength(weeks));
    expect(screen.getByRole('heading', { name: /\(90일 · 주별\)/ })).toBeInTheDocument();
    // 기간 끝에 잘린 주(첫 주·이번 주)는 옅은 막대, 말풍선에 "n일 중 m일만"
    const partials = buckets({ from: presetFrom(90, today()), to: today() }, 'week', today(), 0).filter((b) => daysIn(b).length < 7);
    expect(within(screen.getByTestId('chart-picked')).getAllByTestId('chart-picked-bar').filter((r) => r.hasAttribute('data-partial')).length).toBeLessThanOrEqual(partials.length);
    if (partials.length > 0) {
      const lastCol = within(screen.getByTestId('chart-picked')).getAllByTestId('chart-picked-col').at(-1)!;
      if (daysIn(partials.at(-1)!).length < 7 && partials.at(-1)!.to === today()) expect(lastCol).toHaveAccessibleName(/7일 중 \d일만/);
    }
    // 일 단위로 바꾸면 90칸 — 막대가 아니라 면 없는 선
    await userEvent.click(within(bar).getByRole('button', { name: '일' }));
    await waitFor(() => expect(within(screen.getByTestId('chart-picked')).getAllByTestId('chart-picked-col')).toHaveLength(90));
    expect(within(screen.getByTestId('chart-picked')).queryAllByTestId('chart-picked-bar')).toHaveLength(0);
    await userEvent.click(screen.getByRole('button', { name: '출하 준수' }));
    await waitFor(() => expect(within(screen.getByTestId('chart-ship')).getAllByTestId('chart-ship-col')).toHaveLength(90));
    expect(screen.getByText('출하 약속 준수율 — 목 시뮬레이션(API 요청함)')).toBeInTheDocument();
  });

  it('기간 끝에 잘린 주·월 칸 — 며칠만 들었나(일·시간 칸은 해당 없음)', () => {
    expect(partialOf({ from: '2026-11-23', to: '2026-11-24' }, 'week')).toEqual({ days: 2, full: 7 });
    expect(partialOf({ from: '2026-11-16', to: '2026-11-22' }, 'week')).toBeNull();
    expect(partialOf({ from: '2026-02-10', to: '2026-02-28' }, 'month')).toEqual({ days: 19, full: 28 });
    expect(partialOf({ from: '2026-11-01', to: '2026-11-30' }, 'month')).toBeNull();
    expect(partialOf({ from: '2026-11-24', to: '2026-11-24' }, 'day')).toBeNull();
  });

  it('한 단계 넓게 규칙 — 1일 → 7일 → 30일 → 90일 → 1년, 가운데 중심, 오늘을 넘지 않음', () => {
    const t = '2026-11-21';
    expect(zoomOut({ from: '2026-11-10', to: '2026-11-10' }, t)).toEqual({ from: '2026-11-07', to: '2026-11-13' });
    // 30일 창이 오늘을 넘으면 오늘에 붙인다
    expect(zoomOut({ from: '2026-11-07', to: '2026-11-13' }, t)).toEqual({ from: '2026-10-23', to: t });
    expect(zoomOut({ from: '2026-10-01', to: '2026-10-07' }, t)).toEqual({ from: '2026-09-20', to: '2026-10-19' });
    expect(zoomOut({ from: t, to: t }, t)).toEqual({ from: addDays(t, -6), to: t });
    expect(zoomOut({ from: '2026-08-24', to: t }, t)).toEqual({ from: '2025-12-01', to: t });
    expect(zoomOut({ from: '2025-12-01', to: t }, t)).toBeNull();
  });

  it('그래프를 끌면 그 구간(첫 칸~끝 칸)으로 확대, Ctrl+Z 면 앞 상태가 아니라 한 단계 넓게', async () => {
    renderAt('/c/MFC-BJG-01/dashboard');
    await openPicked();
    // 14칸, 칸 폭 600/14 ≈ 42.9px — 2번째 칸(50px)부터 6번째 칸(250px)까지 = 5일
    drag(sized(screen.getByTestId('chart-picked-plot')), 50, 250);
    await waitFor(() => expect(within(screen.getByTestId('chart-picked')).getAllByTestId('chart-picked-col')).toHaveLength(5));
    const from = addDays(today(), -12);
    expect(screen.getByLabelText('시작일')).toHaveValue(from);
    expect(screen.getByLabelText('끝일')).toHaveValue(addDays(from, 4));
    // 5일 → Ctrl+Z → 7일(가운데 중심 — 앞 상태 14일이 아님)
    fireEvent.keyDown(window, { key: 'z', ctrlKey: true });
    await waitFor(() => expect(within(screen.getByTestId('chart-picked')).getAllByTestId('chart-picked-col')).toHaveLength(7));
    expect(screen.getByLabelText('시작일')).toHaveValue(addDays(from, 2 - 3));
    // 단추도 같다 → 30일
    await userEvent.click(screen.getByTestId('range-back'));
    await waitFor(() => expect(within(screen.getByTestId('chart-picked')).getAllByTestId('chart-picked-col')).toHaveLength(30));
  });

  it('한 칸만 누르면(끌지 않으면) 기간은 그대로', async () => {
    renderAt('/c/MFC-BJG-01/dashboard');
    await openPicked();
    drag(sized(screen.getByTestId('chart-picked-plot')), 50, 54);
    expect(within(screen.getByTestId('chart-picked')).getAllByTestId('chart-picked-col')).toHaveLength(14);
  });

  it('칸 단위 — 1일은 시간(목만, 시간 합 = 그날 합), 1년은 월, 주는 월요일부터, 단위 바꾸기', async () => {
    const t = '2026-11-21'; // 토요일
    expect(unitsFor(1, true)).toEqual(['hour', 'day']);
    expect(unitsFor(1, false)).toEqual(['day']);
    expect(unitsFor(365, true)).toEqual(['day', 'week', 'month']);
    expect(defaultUnit(1, true)).toBe('hour');
    expect(defaultUnit(1, false)).toBe('day');
    expect(defaultUnit(365, true)).toBe('month');
    expect(defaultUnit(31, true)).toBe('day');
    expect(defaultUnit(90, true)).toBe('week');
    expect(buckets({ from: '2026-11-20', to: '2026-11-20' }, 'hour', t, 14)).toHaveLength(24);
    expect(buckets({ from: t, to: t }, 'hour', t, 14)).toHaveLength(15);
    const weeks = buckets({ from: '2026-11-05', to: t }, 'week', t, 14);
    expect(weeks.map((b) => [b.from, b.to])).toEqual([['2026-11-05', '2026-11-08'], ['2026-11-09', '2026-11-15'], ['2026-11-16', t]]);
    expect(buckets({ from: '2025-11-22', to: t }, 'month', t, 14).map((b) => b.label).slice(0, 2)).toEqual(['25년 11월', '25년 12월']);
    const total = Array.from({ length: 24 }, (_, h) => hourShare(137, h, 23)).reduce((a, b) => a + b, 0);
    expect(total).toBe(137);
    expect(Array.from({ length: 15 }, (_, h) => hourShare(40, h, 14)).reduce((a, b) => a + b, 0)).toBe(40);
    // 새벽(곡선 0)에도 합계를 버리지 않는다
    expect(Array.from({ length: 3 }, (_, h) => hourShare(40, h, 2))).toEqual([0, 0, 40]);

    renderAt('/c/MFC-BJG-01/dashboard');
    await openPicked();
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
    expect(within(bar).queryByRole('button', { name: '시간' })).not.toBeInTheDocument();
    await userEvent.click(within(bar).getByRole('button', { name: '1일' }));
    await waitFor(() => expect(screen.getByRole('heading', { name: /\(1일 · 시간별\)/ })).toBeInTheDocument());
    // 1일 → Ctrl+Z → 7일(일별), 1년이면 단추가 꺼진다
    fireEvent.keyDown(window, { key: 'z', ctrlKey: true });
    await waitFor(() => expect(screen.getByRole('heading', { name: /\(7일 · 일별\)/ })).toBeInTheDocument());
    await userEvent.click(within(bar).getByRole('button', { name: '1년' }));
    await waitFor(() => expect(screen.queryByTestId('range-back')).not.toBeInTheDocument());
  });

  it('하루 칸 안을 끌면 그날 시간별', async () => {
    renderAt('/c/MFC-BJG-01/dashboard');
    await openPicked();
    // 14칸 중 마지막 칸(오늘) 안에서 10px 끌기
    drag(sized(screen.getByTestId('chart-picked-plot')), 580, 592);
    await waitFor(() => expect(screen.getByRole('heading', { name: /\(1일 · 시간별\)/ })).toBeInTheDocument());
    expect(screen.getByLabelText('시작일')).toHaveValue(today());
  });

  it('주소의 기간(?from=&to=)으로 열고, 맞지 않는 기간이면 기본 14일', async () => {
    renderAt(`/c/MFC-BJG-01/dashboard?from=${addDays(today(), -6)}&to=${today()}`);
    await openPicked();
    await waitFor(() => expect(within(screen.getByTestId('chart-picked')).getAllByTestId('chart-picked-col')).toHaveLength(7));
  });

  describe('피킹 지표 칸 단위(fulfillment 0.34.0 bucket)', () => {
    afterEach(() => {
      env.isMock = true;
    });
    const asked = (view: ReturnType<typeof renderAt>) => view.gets('/metrics/picking-lines').map((r) => new URL(r.url).searchParams);

    it('줄 → 칸 key — 시간은 hour(+09:00)의 시, 주는 월요일, 달은 YYYY-MM', () => {
      expect(pickingKey({ date: '2026-11-21', hour: '2026-11-21T14:00:00+09:00' }, 'hour')).toBe('2026-11-21T14');
      expect(pickingKey({ date: '2026-11-16', hour: null }, 'week')).toBe('2026-11-16');
      expect(pickingKey({ date: '2026-11-01', hour: null }, 'month')).toBe('2026-11');
      expect(buckets({ from: '2026-11-21', to: '2026-11-21' }, 'hour', '2026-11-21', 14)[14]!.key).toBe('2026-11-21T14');
    });

    it('단위마다 서버가 센다 — 1년 월별은 한 번(MONTH), 주별 WEEK, 1일 시간별은 HOUR, 시간 칸 합 = 그날 합', async () => {
      const view = renderAt('/c/MFC-BJG-01/dashboard');
      await openPicked();
      const bar = screen.getByTestId('range-bar');
      await userEvent.click(within(bar).getByRole('button', { name: '1년' }));
      await waitFor(() => expect(within(screen.getByTestId('chart-picked')).getAllByTestId('chart-picked-col')).toHaveLength(12));
      // 이번 기간만(지난 기간 비교선 요청은 빼고 센다)
      const month = asked(view).filter((q) => q.get('bucket') === 'MONTH' && q.get('to') === today());
      expect(month).toHaveLength(1);
      expect(month[0]!.get('from')).toBe(presetFrom(365, today()));
      await userEvent.click(within(bar).getByRole('button', { name: '주' }));
      await waitFor(() => expect(asked(view).some((q) => q.get('bucket') === 'WEEK')).toBe(true));
      await userEvent.click(within(bar).getByRole('button', { name: '1일' }));
      await waitFor(() => expect(screen.getByRole('heading', { name: /\(1일 · 시간별\)/ })).toBeInTheDocument());
      const hour = asked(view).filter((q) => q.get('bucket') === 'HOUR' && q.get('to') === today());
      expect(hour.at(-1)!.get('from')).toBe(today());
      // 목의 오늘 합계 40줄 — 시간 칸 말풍선을 더하면 같다(서버 칸 값 그대로 그림)
      const cols = within(screen.getByTestId('chart-picked')).getAllByTestId('chart-picked-col');
      let sum = 0;
      for (const c of cols) {
        await userEvent.hover(c);
        sum += Number(/피킹 ([\d,]+)줄/.exec(screen.getByTestId('chart-picked-tip').textContent ?? '')?.[1]?.replace(/,/g, '') ?? 0);
      }
      expect(sum).toBe(40);
    });

    it('92일 넘는 일별은 92일씩 나눠 읽는다(DAY)', async () => {
      const view = renderAt(`/c/MFC-BJG-01/dashboard?from=${addDays(today(), -119)}&to=${today()}&unit=day`);
      await openPicked();
      await waitFor(() => expect(within(screen.getByTestId('chart-picked')).getAllByTestId('chart-picked-col')).toHaveLength(120));
      const day = asked(view).filter((q) => q.get('bucket') === 'DAY' && q.get('to') !== null && q.get('from')! >= addDays(today(), -119));
      const long = day.filter((q) => q.get('from')! < addDays(today(), -13));
      expect(long.map((q) => daysIn({ from: q.get('from')!, to: q.get('to')! }).length).sort((a, b) => a - b)).toEqual([28, 92]);
    });

    it('실서버 — 주문·피킹 줄·결품은 시간 칸이 켜지고, 출하 준수는 API 없음(목만)', async () => {
      env.isMock = false;
      renderAt('/c/MFC-BJG-01/dashboard');
      // 실서버도 주문(order 0.20.0)이 기본 — 1일이면 시간별
      await screen.findByTestId('chart-orders');
      await userEvent.click(within(screen.getByTestId('range-bar')).getByRole('button', { name: '1일' }));
      await waitFor(() => expect(screen.getByRole('heading', { name: /\(1일 · 시간별\)/ })).toBeInTheDocument());
      await openPicked();
      const bar = screen.getByTestId('range-bar');
      await userEvent.click(within(bar).getByRole('button', { name: '1일' }));
      await waitFor(() => expect(screen.getByRole('heading', { name: /\(1일 · 시간별\)/ })).toBeInTheDocument());
      await userEvent.click(screen.getByRole('button', { name: '결품' }));
      expect(within(bar).getByRole('button', { name: '시간' })).toBeInTheDocument();
      await userEvent.click(screen.getByRole('button', { name: '출하 준수' }));
      await waitFor(() => expect(within(bar).queryByRole('button', { name: '시간' })).not.toBeInTheDocument());
      expect(screen.getByTestId('ship-no-api')).toHaveTextContent('출하 약속 준수율은 아직 없어요.');
      expect(screen.queryByTestId('chart-ship')).not.toBeInTheDocument();
    });
  });
});
