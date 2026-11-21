// 센터 대시보드 — 기존 지표 API 만(fulfillment picking-lines·by-sku, dispatch on-time, tasks, workers, bff live-delivery). 목(MSW) 기준.
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { describe, expect, it } from 'vitest';

import { API_BASE } from '../../api/client';
import { renderAt } from '../../test/render';
import { server } from '../../test/server';
import { lastDays, rate, rateText, shortDate } from './dashboardRules';

const unavailable = () => HttpResponse.json({ status: 503, code: 'DEPENDENCY_UNAVAILABLE', type: 'about:blank' }, { status: 503, headers: { 'content-type': 'application/problem+json' } });

describe('센터 대시보드', () => {
  it('오늘 숫자 넷 — 피킹 줄·결품률(서버 분자/분모)·정시 배송률·끝나지 않은 작업', async () => {
    const view = renderAt('/c/MFC-BSN-01/dashboard');
    expect(await screen.findByTestId('kpi-picked-value')).toHaveTextContent('40줄');
    expect(screen.getByTestId('kpi-short-rate-value')).toHaveTextContent('10.0%');
    expect(await screen.findByTestId('kpi-on-time-value')).toHaveTextContent('88.9%');
    expect(await screen.findByTestId('kpi-open-tasks-value')).toHaveTextContent(/^\d+건$/);
    const q = new URL(view.gets('/metrics/picking-lines')[0]!.url).searchParams;
    expect(q.get('mfcId')).toBe('MFC-BSN-01');
    expect(q.get('to')).toBe(new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul' }).format(new Date()));
    expect(lastDays(q.get('to')!, 14)[0]).toBe(q.get('from'));
  });

  it('14일 막대 — 날짜마다 한 칸, 줄 없는 날은 정시율 "—"(0% 아님), 마우스를 올리면 말풍선', async () => {
    renderAt('/c/MFC-BSN-01/dashboard');
    // B안: 추이 패널에서 정시율을 골라 본다
    await screen.findByTestId('chart-picked');
    await userEvent.click(screen.getByRole('button', { name: '정시율' }));
    const chart = await screen.findByTestId('chart-on-time');
    expect(within(chart).getAllByTestId('chart-on-time-col')).toHaveLength(14);
    // 목은 일요일 줄이 없다 → 14일 중 일요일 2번
    expect(within(chart).getAllByText('—')).toHaveLength(2);
    await userEvent.click(screen.getByRole('button', { name: '피킹 줄' }));
    await userEvent.hover(within(await screen.findByTestId('chart-picked')).getAllByTestId('chart-picked-col').at(-1)!);
    expect(screen.getByTestId('chart-picked-tip')).toHaveTextContent('피킹 40줄 · 결품 4줄');
  });

  it('결품 많은 상품 상위 5 — sort=shortLines·limit=5', async () => {
    const view = renderAt('/c/MFC-BSN-01/dashboard');
    const rows = await screen.findAllByTestId('top-short-row');
    expect(rows).toHaveLength(5);
    expect(rows[0]).toHaveTextContent('서울우유 1L');
    const q = new URL(view.gets('/by-sku')[0]!.url).searchParams;
    expect([q.get('sort'), q.get('limit')]).toEqual(['shortLines', '5']);
  });

  it('원천 하나가 실패해도 나머지는 보이고, 실패한 칸은 0 이 아니라 "조회 실패"', async () => {
    server.use(http.get(`${API_BASE}/metrics/on-time-deliveries`, unavailable));
    renderAt('/c/MFC-BSN-01/dashboard');
    expect(await screen.findByTestId('kpi-picked-value')).toHaveTextContent('40줄');
    await waitFor(() => expect(screen.getByTestId('kpi-on-time')).toHaveTextContent('조회 실패'));
    expect(screen.queryByTestId('kpi-on-time-value')).not.toBeInTheDocument();
  });

  it('우선 확인 칩 — 서버 값으로 센 급한 일, 누르면 그 화면으로', async () => {
    renderAt('/c/MFC-BSN-01/dashboard');
    const bar = await screen.findByTestId('priority-bar');
    await waitFor(() => expect(within(bar).getByRole('link', { name: /출하 약속 초과/ })).toHaveTextContent('3건'));
    await waitFor(() => expect(within(bar).getByRole('link', { name: /배차 지연/ })).toHaveTextContent('2건'));
    expect(within(bar).getByRole('link', { name: /배차 지연/ })).toHaveAttribute('href', '/c/MFC-BSN-01/dispatch-delays');
    expect(within(bar).getByRole('link', { name: /막힌 작업/ })).toHaveAttribute('href', '/c/MFC-BSN-01/tasks?state=BLOCKED');
  });

  it('알림 피드 — 긴급(약속 초과·지난 배차 지연)이 먼저, 5줄까지 + 나머지 건수', async () => {
    renderAt('/c/MFC-BSN-01/dashboard');
    await waitFor(() => expect(screen.getAllByTestId('alert-feed-row').length).toBe(5));
    const rows = screen.getAllByTestId('alert-feed-row');
    expect(rows[0]).toHaveTextContent('긴급');
    expect(rows.at(-1)).toHaveTextContent('주의');
    expect(within(rows[0]!).getByRole('link', { name: '조치 보기' })).toBeInTheDocument();
    expect(screen.getByText(/건 더 — 홈 예외 처리함/)).toBeInTheDocument();
  });

  it('피킹 그림은 피킹 줄·결품률을 골라 본다(축 하나)', async () => {
    renderAt('/c/MFC-BSN-01/dashboard');
    await screen.findByTestId('chart-picked');
    await userEvent.click(screen.getByRole('button', { name: '결품률' }));
    expect(await screen.findByTestId('chart-short-rate')).toBeInTheDocument();
    expect(screen.queryByTestId('chart-picked')).not.toBeInTheDocument();
  });

  it('구역 칸 지도(B안) — 위치 서버 상태로 칸을 칠하고, 칸은 그 칸 상세로', async () => {
    renderAt('/c/MFC-BSN-01/dashboard');
    const map = await screen.findByTestId('zone-map');
    expect(within(map).getAllByTestId('zone-block').length).toBeGreaterThan(1);
    expect(within(map).getByText('닫힘 2칸')).toBeInTheDocument();
    const closed = map.querySelector('[data-state="CLOSED"]')!;
    expect(closed.getAttribute('href')).toMatch(/^\/c\/MFC-BSN-01\/locations\//);
  });

  it('메뉴에 있고 누르면 대시보드', async () => {
    renderAt('/c/MFC-BSN-01/ops');
    await userEvent.click(await screen.findByRole('link', { name: '센터 대시보드' }));
    expect(await screen.findByRole('heading', { level: 1, name: '센터 대시보드' })).toBeInTheDocument();
  });
});

describe('대시보드 계산', () => {
  it('분모 0 은 null("—"), 날짜·비율 글자', () => {
    expect(rate(3, 0)).toBeNull();
    expect(rateText(null)).toBe('—');
    expect(rateText(rate(1, 3))).toBe('33.3%');
    expect(shortDate('2026-11-01')).toBe('11/1');
    expect(lastDays('2026-03-01', 3)).toEqual(['2026-02-27', '2026-02-28', '2026-03-01']);
  });
});
