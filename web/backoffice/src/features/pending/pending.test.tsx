// 처리 대기 — 이행 확인 필요(order 0.6.0). OPERATOR_ADMIN 은 모든 센터, 확인은 표시만, 나머지 조치는 준비 중.
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http } from 'msw';
import { describe, expect, it } from 'vitest';

import { API_BASE } from '../../api/client';
import { problem } from '../../mocks/support';
import { as, renderAt } from '../../test/render';
import { server } from '../../test/server';

describe('처리 대기 — 이행 확인 필요', () => {
  it('관리자: 센터를 비우면 모든 센터의 OPEN 을 새 것부터, 주문 번호는 주문 상세로', async () => {
    const view = renderAt('/pending/fulfillment-issues', as.admin);
    const rows = await screen.findAllByTestId('pending-issue');
    expect(rows.map((r) => within(r).getByRole('link').textContent)).toEqual(['ORD-MOCK-1003', 'ORD-MOCK-1001']);
    expect(rows[1]).toHaveTextContent('MFC-SEL-01');
    expect(rows[0]).toHaveTextContent('품질 격리');
    expect(within(rows[0]!).getByRole('link')).toHaveAttribute('href', '/orders/ORD-MOCK-1003');
    const url = new URL(view.sent.find((r) => r.url.includes('/fulfillment-issues'))!.url);
    expect(url.searchParams.get('state')).toBe('OPEN');
    expect(url.searchParams.has('mfcId')).toBe(false);
  });

  it('센터를 넣으면 그 센터만, 상태 탭은 URL 쿼리로', async () => {
    renderAt('/pending/fulfillment-issues', as.admin);
    await screen.findAllByTestId('pending-issue');
    await userEvent.type(screen.getByLabelText('센터(비우면 모든 센터)'), 'MFC-SEL-01');
    await userEvent.click(screen.getByRole('button', { name: '조회' }));
    await waitFor(() => expect(screen.getAllByTestId('pending-issue')).toHaveLength(1));
    await userEvent.click(screen.getByRole('tab', { name: '확인함' }));
    expect(await screen.findByText('해당 기록이 없어요.')).toBeInTheDocument(); // MFC-SEL-01 의 확인함 없음
  });

  it('확인 처리: 메모(개인정보 안내) → acknowledgements(키·출처) → 확인함 탭으로 옮겨 간다', async () => {
    const view = renderAt('/pending/fulfillment-issues', as.admin);
    const row = (await screen.findAllByTestId('pending-issue'))[0]!;
    await userEvent.click(within(row).getByRole('button', { name: '확인 처리' }));
    expect(within(row).getByText(/개인정보는 적지 마세요/)).toBeInTheDocument();
    await userEvent.type(within(row).getByLabelText('처리 메모'), 'MFC 에 재검수 요청');
    await userEvent.click(within(row).getByRole('button', { name: '확인으로 표시' }));
    await waitFor(() => expect(screen.getAllByTestId('pending-issue')).toHaveLength(1));
    const sent = view.mutations('/acknowledgements')[0]!;
    expect(sent.headers.get('Idempotency-Key')).toBeTruthy();
    expect(sent.headers.get('X-Source-System')).toBe('backoffice-web');
    expect(await sent.json()).toEqual({ note: 'MFC 에 재검수 요청' });
    await userEvent.click(screen.getByRole('tab', { name: '확인함' }));
    expect(await screen.findByText('MFC 에 재검수 요청')).toBeInTheDocument();
  });

  it('조회 실패는 빈 목록이 아니라 오류', async () => {
    server.use(http.get(`${API_BASE}/fulfillment-issues`, () => problem(500, 'INTERNAL_ERROR')));
    renderAt('/pending/fulfillment-issues', as.admin);
    expect(await screen.findByText('정보를 불러오지 못했어요')).toBeInTheDocument();
    expect(screen.queryByText('해당 기록이 없어요.')).not.toBeInTheDocument();
  });

  it('멈춘 주문 조치·인계 재시도·현장 중지 재시도는 준비 중 — 버튼 없음', async () => {
    renderAt('/pending/fulfillment-issues', as.admin);
    const box = await screen.findByTestId('pending-preparing');
    expect(box).toHaveTextContent('멈춘 주문 조치');
    expect(box).toHaveTextContent('인계 재시도');
    expect(within(box).queryByRole('button')).not.toBeInTheDocument();
  });
});
