// 센터 목록(MB-1) — 기본 거르기(일이 남은 상태), 열기 = 그 화면의 상세, 다른 센터 403, 조회 실패는 빈 목록이 아님, 더 보기(커서).
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { describe, expect, it } from 'vitest';

import { API_BASE } from '../../api/client';
import { db } from '../../mocks/db';
import { renderAt } from '../../test/render';
import { server } from '../../test/server';

const getsTo = (sent: Request[], path: string) => sent.filter((r) => r.method === 'GET' && new URL(r.url).pathname.endsWith(path));

describe('센터 목록(MB-1)', () => {
  it('품질 해제 승인 대기 목록 — 기본은 대기만, 열기는 판정 상세', async () => {
    const view = renderAt('/c/MFC-BSN-01/quality');
    const list = await screen.findByTestId('list-decisions');
    const rows = await within(list).findAllByTestId('list-decisions-row');
    expect(rows).toHaveLength(1);
    expect(rows[0]).not.toHaveTextContent('QD-1'); // 목록에는 시스템 ID 를 내지 않는다(ADR-0070 덧붙임)
    expect(rows[0]).toHaveTextContent('해제 승인 대기');
    const req = getsTo(view.sent, '/quality-decisions')[0]!;
    expect(new URL(req.url).searchParams.getAll('state')).toEqual(['REQUESTED']);
    expect(new URL(req.url).searchParams.get('mfcId')).toBe('MFC-BSN-01');

    await userEvent.click(within(rows[0]!).getByRole('button', { name: '열기' }));
    expect(await screen.findByRole('button', { name: '해제 승인' })).toBeInTheDocument();
  });

  it('전체로 바꾸면 상태를 보내지 않는다', async () => {
    const view = renderAt('/c/MFC-BSN-01/quality');
    await screen.findAllByTestId('list-decisions-row');
    await userEvent.selectOptions(screen.getByRole('combobox', { name: '격리·해제 판정 상태' }), '');
    await waitFor(() => expect(getsTo(view.sent, '/quality-decisions').length).toBeGreaterThan(1));
    const last = getsTo(view.sent, '/quality-decisions').at(-1)!;
    expect(new URL(last.url).searchParams.getAll('state')).toEqual([]);
  });

  it('검수 탭: 검수할 회수품 반입 목록에서 열면 검수 화면이 반입을 불러온다', async () => {
    renderAt('/c/MFC-BSN-01/quality?tab=inspections');
    const list = await screen.findByTestId('list-return-receipts');
    const row = (await within(list).findAllByTestId('list-return-receipts-row'))[0]!;
    expect(row).not.toHaveTextContent('RR-1');
    expect(row).toHaveTextContent('검수 대기');
    await userEvent.click(within(row).getByRole('button', { name: '열기' }));
    const form = await screen.findByRole('form', { name: '검수 결과 보내기' });
    expect(within(form).getByRole('group', { name: 'SKU-RAMEN-5 × 2' })).toBeInTheDocument();
  });

  it('실사 목록 — 기본은 승인 대기', async () => {
    renderAt('/c/MFC-BSN-01/inventory?tab=counts');
    const rows = await within(await screen.findByTestId('list-count-sessions')).findAllByTestId('list-count-sessions-row');
    expect(rows).toHaveLength(1);
    expect(rows[0]).not.toHaveTextContent('CNT-1');
    expect(rows[0]).toHaveTextContent('승인 대기');
  });

  it('센터 전체 재고 — 상품 코드 없이, 열기는 그 상품 재고', async () => {
    renderAt('/c/MFC-BSN-01/inventory');
    const list = await screen.findByTestId('list-stock-units');
    const rows = await within(list).findAllByTestId('list-stock-units-row');
    expect(rows.length).toBe(db.stockUnits.filter((u) => u.mfcId === 'MFC-BSN-01').length);
    const milk = rows.find((r) => r.textContent?.includes('SKU-MILK-1'))!;
    await userEvent.click(within(milk).getByRole('button', { name: '열기' }));
    await waitFor(() => expect(screen.getAllByTestId('unit-row').length).toBeGreaterThan(0));
  });

  it('다음 쪽이 있으면 더 보기로 이어 읽는다(같은 거르기, 커서)', async () => {
    let calls = 0;
    server.use(
      http.get(`${API_BASE}/supply-requests`, ({ request }) => {
        calls++;
        const cursor = new URL(request.url).searchParams.get('cursor');
        const item = (id: string, at: string) => ({ supplyRequestId: id, mfcId: 'MFC-BSN-01', state: 'SUBMITTED', lines: [{ sku: 'SKU-MILK-1', qty: 1 }], version: 1, submittedAt: at });
        return HttpResponse.json(cursor === 'c2' ? { items: [item('SR-2', '2026-11-19T02:00:00.000Z')], nextCursor: null } : { items: [item('SR-1', '2026-11-19T01:00:00.000Z')], nextCursor: 'c2' });
      }),
    );
    renderAt('/c/MFC-BSN-01/inbound?tab=supply');
    const list = await screen.findByTestId('list-supply-requests');
    // 줄은 시각으로 알아본다(시스템 ID 는 목록에 없다)
    await waitFor(() => expect(within(list).getAllByTestId('list-supply-requests-row')).toHaveLength(1));
    await userEvent.click(within(list).getByRole('button', { name: '더 보기' }));
    await waitFor(() => expect(within(list).getAllByTestId('list-supply-requests-row')).toHaveLength(2));
    expect(calls).toBe(2);
    expect(within(list).queryByRole('button', { name: '더 보기' })).not.toBeInTheDocument();
  });

  it('조회 실패는 "항목 없음"이 아니라 오류', async () => {
    server.use(http.get(`${API_BASE}/assignment-plans`, () => HttpResponse.json({ status: 503, code: 'DEPENDENCY_UNAVAILABLE', title: 'x', type: 'about:blank' }, { status: 503, headers: { 'content-type': 'application/problem+json' } })));
    renderAt('/c/MFC-BSN-01/assignments?tab=plan');
    const list = await screen.findByTestId('list-plans');
    await waitFor(() => expect(within(list).getByRole('button', { name: /다시/ })).toBeInTheDocument());
    expect(within(list).queryByText('조건에 맞는 항목이 없어요')).not.toBeInTheDocument();
  });
});
