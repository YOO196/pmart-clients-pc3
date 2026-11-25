// 상품 발주 — 발주 → 가짜 공급사 회신·ASN → 입고 확정 → 재고관리 LOT, 취소, 공급사 등록. 제안 계약 목(mocks/purchaseHandlers).
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';

import { fakeSupplier } from '../../mocks/purchaseHandlers';
import { renderAt } from '../../test/render';

const newOrder = async (supplier: string, qty: string) => {
  await userEvent.click(await screen.findByRole('button', { name: '발주 등록' }));
  const form = screen.getByTestId('po-form');
  await waitFor(() => expect(within(form).getByRole('option', { name: supplier })).toBeInTheDocument());
  await userEvent.selectOptions(within(form).getByTestId('po-supplier'), supplier);
  expect(within(form).getByTestId('po-due')).not.toHaveValue('');
  await userEvent.type(within(form).getByTestId('po-qty'), qty);
  await userEvent.click(within(form).getByTestId('po-submit'));
};

describe('상품 발주', () => {
  it('메뉴 자리 — 입고·재고 묶음, 발주·공급사 관리 탭', async () => {
    renderAt('/c/CDC01/purchase');
    expect(await screen.findByRole('heading', { level: 1, name: '상품 발주' })).toBeInTheDocument();
    expect(screen.getByRole('tab', { name: '발주' })).toHaveAttribute('aria-selected', 'true');
    expect(screen.getByRole('tab', { name: '공급사 관리' })).toBeInTheDocument();
    expect(await screen.findAllByTestId('po-row')).toHaveLength(2);
  });

  it('발주하면 가짜 공급사가 회신(전량)하고 ASN 을 보낸다 → 입고 확정하면 재고관리에 그 LOT 가 생긴다', async () => {
    const view = renderAt('/c/CDC01/purchase');
    await newOrder('한빛식품(시험)', '120');
    const detail = await screen.findByTestId('po-detail');
    const post = view.sent.find((r) => r.method === 'POST' && new URL(r.url).pathname.endsWith('/purchase-orders'))!;
    expect(post.headers.get('Idempotency-Key')).toBeTruthy();
    expect(post.headers.get('X-Source-System')).toBe('cdc-backoffice-web');
    expect(((await post.clone().json()) as { lines: unknown[] }).lines).toEqual([{ sku: 'SKU-1001', qty: 120 }]);
    // 시험은 회신·ASN 이 바로 — 입고 예정
    await waitFor(() => expect(within(detail).getAllByTestId('po-state')[0]).toHaveTextContent('입고 예정'));
    expect(within(detail).getByText('전량 공급(가짜 회신)')).toBeInTheDocument();
    const row = screen.getByTestId('po-receive-row');
    const lot = within(row).getByText(/^L\d+/).textContent;
    await userEvent.clear(within(row).getByLabelText('SKU-1001 입고 수량'));
    await userEvent.type(within(row).getByLabelText('SKU-1001 입고 수량'), '118');
    await userEvent.clear(within(row).getByLabelText('SKU-1001 불량·반품'));
    await userEvent.type(within(row).getByLabelText('SKU-1001 불량·반품'), '2');
    await userEvent.click(screen.getByTestId('po-receive-go'));
    expect(await screen.findByText(/입고를 확정했어요/)).toBeInTheDocument();
    await waitFor(() => expect(within(screen.getByTestId('po-detail')).getAllByTestId('po-state')[0]).toHaveTextContent('입고 완료'));
    expect(within(screen.getByTestId('po-lines')).getByText('-2')).toBeInTheDocument();
    view.unmount();

    // 재고관리 — 그 SKU 의 LOT·입고장 칸
    renderAt('/c/CDC01/inventory');
    const rows = await screen.findAllByTestId('stock-row');
    expect(rows[0]).toHaveTextContent('1,318');
    await userEvent.click(rows[0]!);
    const places = await screen.findByTestId('stock-places');
    expect(within(places).getByText(lot)).toBeInTheDocument();
    expect(within(places).getByText('CDC01-C-5-91-01-0-1')).toBeInTheDocument();
  });

  it('일부 공급 공급사는 80% 만 회신, 회신을 기다리는 동안은 회신 대기 + 취소할 수 있다', async () => {
    fakeSupplier.asnMs = 60_000;
    renderAt('/c/CDC01/purchase');
    await newOrder('대성농산(시험)', '50');
    const detail = await screen.findByTestId('po-detail');
    await waitFor(() => expect(within(detail).getAllByTestId('po-state')[0]).toHaveTextContent('일부 확정'));
    expect(within(screen.getByTestId('po-lines')).getByText('40')).toBeInTheDocument();
    await userEvent.click(screen.getByTestId('po-cancel-open'));
    expect(screen.getByTestId('po-cancel-go')).toBeDisabled();
    await userEvent.type(screen.getByTestId('po-cancel-reason'), '수량 부족이라 다른 공급사로');
    await userEvent.click(screen.getByTestId('po-cancel-go'));
    expect(await screen.findByText(/를 취소했어요/)).toBeInTheDocument();
    await waitFor(() => expect(within(screen.getByTestId('po-detail')).getAllByTestId('po-state')[0]).toHaveTextContent('취소'));
  });

  it('거절 공급사 — 공급 거절, 입고 없음', async () => {
    renderAt('/c/CDC01/purchase');
    await newOrder('맑은샘음료(시험)', '10');
    const detail = await screen.findByTestId('po-detail');
    await waitFor(() => expect(within(detail).getAllByTestId('po-state')[0]).toHaveTextContent('공급 거절'));
    expect(screen.queryByTestId('po-receive')).not.toBeInTheDocument();
    expect(screen.queryByTestId('po-cancel-open')).not.toBeInTheDocument();
  });
});

describe('공급사 관리', () => {
  it('공급사를 등록하면 목록에 생기고 발주에서 고를 수 있다', async () => {
    const view = renderAt('/c/CDC01/purchase?tab=suppliers');
    expect(await screen.findAllByTestId('supplier-row')).toHaveLength(3);
    await userEvent.click(screen.getByRole('button', { name: '공급사 등록' }));
    expect(screen.getByTestId('sup-submit')).toBeDisabled();
    await userEvent.type(screen.getByTestId('sup-name'), '새벽수산(시험)');
    await userEvent.type(screen.getByTestId('sup-skus'), 'SKU-1002, SKU-2001');
    await userEvent.selectOptions(screen.getByTestId('sup-reply'), '일부 공급(80%)');
    await userEvent.click(screen.getByTestId('sup-submit'));
    await waitFor(() => expect(screen.getAllByTestId('supplier-row')).toHaveLength(4));
    const post = view.sent.find((r) => r.method === 'POST' && new URL(r.url).pathname.endsWith('/suppliers'))!;
    expect(await post.clone().json()).toMatchObject({
      name: '새벽수산(시험)',
      skus: ['SKU-1002', 'SKU-2001'],
      replyMode: 'PARTIAL',
      leadTimeDays: 2,
    });
    await userEvent.click(screen.getByRole('tab', { name: '발주' }));
    await userEvent.click(await screen.findByRole('button', { name: '발주 등록' }));
    expect(
      await within(screen.getByTestId('po-form')).findByRole('option', {
        name: '새벽수산(시험)',
      }),
    ).toBeInTheDocument();
  });
});
