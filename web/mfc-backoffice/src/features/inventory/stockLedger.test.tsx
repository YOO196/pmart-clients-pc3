// 재고 > 재고 이력 — mfc-inventory 0.48.0 stock-ledger 목.
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { describe, expect, it } from 'vitest';

import { API_BASE } from '../../api/client';
import { openFilter, renderAt } from '../../test/render';
import { server } from '../../test/server';
import { causeName } from './StockLedgerTab';

const rows = () => screen.getAllByTestId('ledger-row');
const causes = () => rows().map((r) => within(r).getAllByRole('cell')[1]!.textContent);

describe('재고 이력', () => {
  it('상품 코드 전에는 묻지 않고 한 줄 안내', async () => {
    const view = renderAt('/c/MFC-BJG-01/inventory?tab=ledger');
    expect(await screen.findByText('상품 코드를 넣고 조회해요.')).toBeInTheDocument();
    expect(view.gets('/stock-ledger')).toHaveLength(0);
  });

  it('상품 코드로 조회 — 최신순, 원인 이름, 지금 합계(서버 값), sku 를 보낸다', async () => {
    const view = renderAt('/c/MFC-BJG-01/inventory?tab=ledger');
    await userEvent.type(await screen.findByRole('searchbox', { name: '상품 코드(SKU)' }), 'sku-milk-1');
    await userEvent.click(screen.getByRole('button', { name: '조회' }));
    await waitFor(() => expect(causes()).toEqual(['정정', '품질 판정', '라이더 인계', '예약', '작업 실행', '입고 수령']));
    expect(new URL(view.gets('/stock-ledger')[0]!.url).searchParams.get('sku')).toBe('SKU-MILK-1');
    expect(screen.getByTestId('ledger-now-available-value')).toHaveTextContent(/^\d+$/);
    // 원인 칸에 코드도 남는다(올려 보면)
    expect(within(rows()[1]!).getAllByRole('cell')[1]).toHaveAttribute('title', 'QUALITY_QUARANTINE');
  });

  it('원인 거르기는 cause 로 서버에, 칩 ✕ 로 풀린다', async () => {
    const view = renderAt('/c/MFC-BJG-01/inventory?tab=ledger&sku=SKU-MILK-1');
    await waitFor(() => expect(rows()).toHaveLength(6));
    await openFilter();
    await userEvent.selectOptions(screen.getByRole('combobox', { name: '원인' }), 'HANDOVER');
    await waitFor(() => expect(causes()).toEqual(['라이더 인계']));
    expect(new URL(view.gets('/stock-ledger').at(-1)!.url).searchParams.getAll('cause')).toEqual(['HANDOVER']);
    await userEvent.click(screen.getByRole('button', { name: '원인 조건 풀기' }));
    await waitFor(() => expect(rows()).toHaveLength(6));
  });

  it('줄을 누르면 칸·LOT 줄과 그 뒤 합계가 펼쳐진다(이동이면 한 칸 −·다른 칸 +)', async () => {
    renderAt('/c/MFC-BJG-01/inventory?tab=ledger&sku=SKU-MILK-1');
    await waitFor(() => expect(rows()).toHaveLength(6));
    await userEvent.click(within(rows()[1]!).getAllByRole('cell')[2]!);
    const inline = await screen.findByTestId('ledger-inline');
    const entries = within(inline).getAllByTestId('ledger-entry').map((e) => within(e).getAllByRole('cell')[2]!.textContent);
    expect(entries).toEqual(expect.arrayContaining(['A-P1-01-1-01', 'QRT-A-01']));
    expect(within(inline).getByText('그 뒤 합계 · 보유')).toBeInTheDocument();
  });

  it('조회 실패(권한 밖 403)는 빈 목록이 아니라 오류', async () => {
    server.use(http.get(`${API_BASE}/mfcs/:mfcId/stock-ledger`, () => HttpResponse.json({ type: 'about:blank', title: 'FORBIDDEN', status: 403, code: 'FORBIDDEN' }, { status: 403, headers: { 'Content-Type': 'application/problem+json' } })));
    renderAt('/c/MFC-BJG-01/inventory?tab=ledger&sku=SKU-MILK-1');
    expect(await screen.findByRole('alert')).toBeInTheDocument();
    expect(screen.queryByText('조건에 맞는 이력이 없어요.')).not.toBeInTheDocument();
  });

  it('모르는 원인 코드는 그대로, QUALITY_·MOVE_ 는 묶음 이름', () => {
    expect(causeName('TIN')).toBe('입고 수령');
    expect(causeName('MOVE_PICK')).toBe('재고 이동');
    expect(causeName('NEW_THING')).toBe('NEW_THING');
  });
});
