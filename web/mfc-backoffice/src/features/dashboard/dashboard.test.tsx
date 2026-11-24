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
    expect(await screen.findByTestId('kpi-picked-value', {}, { timeout: 5000 })).toHaveTextContent('40줄');
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
    await screen.findByTestId('chart-orders');
    await userEvent.click(screen.getByRole('button', { name: '정시율' }));
    const chart = await screen.findByTestId('chart-on-time');
    expect(within(chart).getAllByTestId('chart-on-time-col')).toHaveLength(14);
    // 목은 일요일 줄이 없다(오늘은 늘 있음) → 14일 중 오늘이 아닌 일요일 수
    const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul' }).format(new Date());
    const sundays = lastDays(today, 14).filter((d) => d !== today && new Date(`${d}T00:00:00Z`).getUTCDay() === 0).length;
    expect(within(chart).getAllByText('—')).toHaveLength(sundays);
    await userEvent.click(screen.getByRole('button', { name: '피킹 줄' }));
    await userEvent.hover(within(await screen.findByTestId('chart-picked')).getAllByTestId('chart-picked-col').at(-1)!);
    expect(screen.getByTestId('chart-picked-tip')).toHaveTextContent('피킹 40줄 · 결품 4줄');
  });

  it('결품 많은 상품 상위 5 — sort=shortLines·limit=5', async () => {
    const view = renderAt('/c/MFC-BSN-01/dashboard');
    await userEvent.click(await screen.findByRole('button', { name: '결품' }));
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

  it('결품은 비율 선이 아니라 사유별 쌓은 막대(서버 shortLinesByReason) + 범례, 기간 결품률은 한 숫자', async () => {
    renderAt('/c/MFC-BSN-01/dashboard');
    await screen.findByTestId('chart-orders');
    await userEvent.click(screen.getByRole('button', { name: '결품' }));
    const chart = await screen.findByTestId('chart-short');
    expect(within(chart).getByTestId('chart-short-legend')).toHaveTextContent('재고 없음파손변질막힘');
    expect(screen.getByText(/기간 결품률 \d+\.\d%/)).toBeInTheDocument();
    // 오늘 칸 말풍선에 사유별 줄
    await userEvent.hover(within(chart).getAllByTestId('chart-short-col').at(-1)!);
    expect(screen.getByTestId('chart-short-tip')).toHaveTextContent(/결품 \d+줄 \(재고 없음 \d+/);
    expect(await screen.findByTestId('top-short')).toBeInTheDocument();
  });

  it('센터 도면(B안) — 목 모드면 재직 작업자마다 점(휴게는 휴게 역할), 실서버면 점 없이 "위치 API 없음"', async () => {
    renderAt('/c/MFC-BSN-01/dashboard');
    const map = await screen.findByTestId('floor-map');
    await waitFor(() => expect(within(map).getAllByTestId('floor-worker')).toHaveLength(3));
    expect(within(map).getAllByTestId('floor-worker').filter((d) => d.getAttribute('data-role') === 'break')).toHaveLength(1);
    expect(within(map).getByText('작업자 위치 시뮬레이션(목)')).toBeInTheDocument();
    expect(within(map).getByText('닫힘 2칸')).toBeInTheDocument();
  });

  it('주문·매출(order 0.20.0 O-11) — 센터·칸 단위로 묻고, 요일×시간 열지도, 카테고리·상품 거르기(URL), 많이 팔린 상품을 누르면 그 상품 추이', async () => {
    const view = renderAt('/c/MFC-BSN-01/dashboard');
    const chart = await screen.findByTestId('chart-orders');
    expect(within(chart).getAllByTestId('chart-orders-col')).toHaveLength(14);
    const series = () => view.gets('/orders/metrics/series').map((r) => new URL(r.url).searchParams);
    await waitFor(() => expect(series().some((q) => q.get('bucket') === 'WEEKDAY_HOUR')).toBe(true));
    const day = series().find((q) => q.get('bucket') === 'DAY')!;
    expect(day.get('mfcId')).toBe('MFC-BSN-01');
    expect(day.get('sku')).toBeNull();
    const heat = await screen.findByTestId('order-heat');
    expect(within(heat).getAllByTestId('order-heat-cell')).toHaveLength(7 * 24);
    expect(within(heat).getByTestId('order-heat-tip')).toHaveTextContent(/가장 많은 때 [월화수목금토일] \d+시/);
    // 많이 팔린 상품 이름은 센터 재고(stocks)에서
    await waitFor(() => expect(screen.getAllByTestId('top-sold-row')[0]).not.toHaveTextContent(/^SKU-/));
    // 카테고리 → 서버가 거른다(series·top-products 에 categoryId), 상품 목록도 그 카테고리만
    await userEvent.selectOptions(await screen.findByLabelText('카테고리'), 'DAIRY');
    await waitFor(() => expect(series().some((q) => q.get('categoryId') === 'DAIRY')).toBe(true));
    expect(view.gets('/orders/metrics/top-products').some((r) => new URL(r.url).searchParams.get('categoryId') === 'DAIRY')).toBe(true);
    await waitFor(() => expect(within(screen.getByLabelText('상품')).getAllByRole('option').map((o) => o.textContent).sort()).toEqual(['국산콩 두부 300g', '서울우유 1L', '전체 상품', '플레인 요거트 4입'].sort()));
    // 많이 팔린 상품 누르면 그 상품(sku)만 — 판매 수량 추이
    const rows = screen.getAllByTestId('top-sold-row');
    await userEvent.click(rows[0]!);
    await waitFor(() => expect(series().some((q) => q.get('sku') !== null && q.get('categoryId') === null)).toBe(true));
    await waitFor(() => expect(screen.getAllByTestId('top-sold-row')[0]).toHaveAttribute('aria-pressed', 'true'));
    await userEvent.hover(within(await screen.findByTestId('chart-orders')).getAllByTestId('chart-orders-col').at(-2)!);
    expect(screen.getByTestId('chart-orders-tip')).toHaveTextContent(/판매 [\d,]+개/);
    // 매출로 바꾸면 원 — 거른 동안은 그 상품 줄 금액(승인 금액은 서버가 null)
    await userEvent.click(screen.getByRole('button', { name: '매출' }));
    expect(screen.getByText('고른 상품 줄 금액만(할인 뺀 값)')).toBeInTheDocument();
    // 세로 눈금 — 이미 줄인 "50만원"을 다시 줄이지 않는다("50만만원" 아님)
    expect(within(await screen.findByTestId('chart-sales')).queryByText(/만만/)).not.toBeInTheDocument();
    await userEvent.hover(within(await screen.findByTestId('chart-sales')).getAllByTestId('chart-sales-col').at(-2)!);
    expect(screen.getByTestId('chart-sales-tip')).toHaveTextContent(/매출 [1-9][\d,]*원/);
  });

  it('주문 추이 — 0건 칸은 서버가 주지 않아 0 으로 채우고, 추이 조회 실패는 0 이 아니라 "조회 실패"', async () => {
    const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul' }).format(new Date());
    server.use(
      http.get(`${API_BASE}/orders/metrics/series`, ({ request }) => {
        const q = new URL(request.url).searchParams;
        if (q.get('bucket') !== 'DAY') return HttpResponse.json({ from: q.get('from'), to: q.get('to'), mfcId: q.get('mfcId'), bucket: q.get('bucket'), items: [] });
        return HttpResponse.json({
          from: q.get('from'),
          to: q.get('to'),
          mfcId: q.get('mfcId'),
          bucket: 'DAY',
          items: [{ start: `${today}T00:00:00+09:00`, orderCount: 7, approvedAmount: 182000, qty: 19, lineAmount: 182000 }],
        });
      }),
    );
    renderAt('/c/MFC-BSN-01/dashboard');
    const cols = within(await screen.findByTestId('chart-orders')).getAllByTestId('chart-orders-col');
    expect(cols).toHaveLength(14);
    await userEvent.hover(cols.at(-1)!);
    expect(screen.getByTestId('chart-orders-tip')).toHaveTextContent('주문 7건');
    await userEvent.hover(cols.at(-2)!);
    expect(screen.getByTestId('chart-orders-tip')).toHaveTextContent('주문 0건');

    // 기간을 바꿔 새로 읽을 때 실패
    server.use(http.get(`${API_BASE}/orders/metrics/series`, unavailable));
    await userEvent.click(within(screen.getByTestId('range-bar')).getByRole('button', { name: '30일' }));
    const panel = screen.getByRole('region', { name: /^추이/ });
    await waitFor(() => expect(within(panel).getByRole('alert')).toHaveTextContent('조회 실패'));
    expect(screen.queryByTestId('chart-orders')).not.toBeInTheDocument();
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
