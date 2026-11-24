// 배송 통계(배송 현황 › 배송 통계 탭) — execution 0.38.0 delivery-metrics · dispatch 0.16.0 metrics/dispatch. 목(MSW) 기준.
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { describe, expect, it } from 'vitest';

import { API_BASE } from '../../api/client';
import { renderAt } from '../../test/render';
import { server } from '../../test/server';
import { addDays } from '../dashboard/dashboardRules';
import { agg, dur, wavg } from './DeliveryStats';

const today = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul' }).format(new Date());
const unavailable = () => HttpResponse.json({ status: 503, code: 'DEPENDENCY_UNAVAILABLE', type: 'about:blank' }, { status: 503, headers: { 'content-type': 'application/problem+json' } });
const row = (date: string, riderId: string, x: Partial<Record<string, number | null>>) => ({
  date,
  mfcId: 'MFC-BSN-01',
  riderId,
  assigned: 0,
  completed: 0,
  failed: 0,
  cancelled: 0,
  late: 0,
  judged: 0,
  pickupWaitSeconds: null,
  pickupWaitCount: 0,
  deliverySeconds: null,
  deliveryCount: 0,
  ...x,
});

describe('배송 통계', () => {
  it('배송 현황의 "배송 통계" 탭 — 이 센터(mfcId)·최근 7일로 두 원천을 묻는다', async () => {
    const view = renderAt('/c/MFC-BSN-01/deliveries');
    await userEvent.click(await screen.findByRole('tab', { name: '배송 통계' }));
    await screen.findByTestId('tile-completion');
    for (const path of ['/delivery-metrics', '/metrics/dispatch']) {
      const q = new URL(view.gets(path).at(-1)!.url).searchParams;
      expect(q.get('mfcId')).toBe('MFC-BSN-01');
      expect(q.get('to')).toBe(today());
      expect(q.get('from')).toBe(addDays(today(), -6));
    }
    // 30일
    await userEvent.click(within(screen.getByTestId('stats-range')).getByRole('button', { name: '최근 30일' }));
    await waitFor(() => expect(new URL(view.gets('/delivery-metrics').at(-1)!.url).searchParams.get('from')).toBe(addDays(today(), -29)));
    // 라이더는 번호만(ADR-0085), 도움요청·실패 사유는 한국어
    await waitFor(() => expect(within(screen.getByTestId('stats-rider-table')).getAllByTestId('rider-label')[0]).toHaveTextContent(/^R\d{4,5}$/));
    expect(within(screen.getByTestId('stats-incident-table')).getByText('고객 연락 안 됨')).toBeInTheDocument();
    expect(within(screen.getByTestId('stats-failure-reasons')).getByText(/라이더 없음/)).toBeInTheDocument();
    // 지금 배송 탭으로 돌아가기
    await userEvent.click(screen.getByRole('tab', { name: '지금 배송' }));
    expect(screen.queryByTestId('delivery-stats')).not.toBeInTheDocument();
  });

  it('숫자 — 비율은 서버 수로, 평균은 건수로 가중, 분모 0 은 "—"', async () => {
    const d = today();
    server.use(
      http.get(`${API_BASE}/delivery-metrics`, () =>
        HttpResponse.json({
          from: d,
          to: d,
          rows: [
            row(d, 'RD-1', { assigned: 4, completed: 3, failed: 1, late: 1, judged: 2, pickupWaitSeconds: 300, pickupWaitCount: 3, deliverySeconds: 1200, deliveryCount: 3 }),
            row(d, 'RD-2', { assigned: 1, completed: 1, judged: 1, pickupWaitSeconds: 900, pickupWaitCount: 1, deliverySeconds: 600, deliveryCount: 1 }),
          ],
          incidents: [],
        }),
      ),
      http.get(`${API_BASE}/metrics/dispatch`, () => HttpResponse.json({ from: d, to: d, rows: [], failureReasons: [] })),
    );
    renderAt('/c/MFC-BSN-01/deliveries?view=stats');
    // 완료 4 / (완료 4 + 실패 1) = 80%, 지연 1 / 판정 3, 픽업 대기 (300×3 + 900×1) ÷ 4 = 450초 = 8분
    expect(await screen.findByTestId('tile-completion')).toHaveTextContent('80%');
    expect(screen.getByTestId('tile-late')).toHaveTextContent('33.3%');
    expect(screen.getByTestId('tile-pickup-wait')).toHaveTextContent('8분');
    expect(screen.getByTestId('tile-riders')).toHaveTextContent('2명');
    // 배차 줄이 없으면 배정 성공률 "—"(0% 아님)
    expect(await screen.findByTestId('tile-assign-rate')).toHaveTextContent('—');
    expect(screen.getByText('이 기간에 도움요청이 없어요.')).toBeInTheDocument();
  });

  it('배송 통계 조회 실패는 0 이 아니라 실패 안내, 배차 통계만 실패하면 그 칸만', async () => {
    server.use(http.get(`${API_BASE}/delivery-metrics`, unavailable));
    renderAt('/c/MFC-BSN-01/deliveries?view=stats');
    const stats = await screen.findByTestId('delivery-stats');
    await waitFor(() => expect(within(stats).getAllByRole('alert').length).toBeGreaterThan(0));
    expect(screen.queryByTestId('tile-completion')).not.toBeInTheDocument();
    expect(screen.queryByTestId('stats-empty')).not.toBeInTheDocument();
  });

  it('배차 통계만 실패 — 배송 품질은 보이고 배차 칸에 안내', async () => {
    server.use(http.get(`${API_BASE}/metrics/dispatch`, unavailable));
    renderAt('/c/MFC-BSN-01/deliveries?view=stats');
    expect(await screen.findByTestId('tile-completion')).toBeInTheDocument();
    await waitFor(() => expect(within(screen.getByTestId('stats-dispatch')).getByRole('alert')).toHaveTextContent('배차 통계를 불러오지 못했어요'));
    await waitFor(() => expect(screen.getByTestId('tile-assign')).toHaveTextContent('조회 실패'));
  });

  it('계산 — 초 표기·가중 평균·묶음 합', () => {
    expect(dur(null)).toBe('—');
    expect(dur(45)).toBe('45초');
    expect(dur(750)).toBe('13분');
    expect(dur(3900)).toBe('1시간 5분');
    expect(wavg([{ v: 100, k: 1 }, { v: null, k: 5 }, { v: 400, k: 3 }], (r) => r.v, (r) => r.k)).toBe(325);
    expect(wavg([{ v: 100, k: 0 }], (r) => r.v, (r) => r.k)).toBeNull();
    const a = agg([row('2026-11-23', 'RD-1', { assigned: 2, completed: 2 }), row('2026-11-23', 'RD-1', { assigned: 1, failed: 1 })]);
    expect([a.assigned, a.completed, a.failed, a.riders]).toEqual([3, 2, 1, 1]);
  });
});
