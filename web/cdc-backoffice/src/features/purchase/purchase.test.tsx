// 상품 발주 — 발주 → 입고하면 발주 수량만큼 재고관리에 더해진다, 취소, 공급사 등록. 목(mocks/purchaseHandlers).
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';

import { renderAt } from '../../test/render';

const newOrder = async (supplier: string, qty: string) => {
  await userEvent.click(await screen.findByRole('button', { name: '발주 등록' }));
  const form = screen.getByTestId('po-form');
  await waitFor(() => expect(within(form).getByRole('option', { name: supplier })).toBeInTheDocument());
  await userEvent.selectOptions(within(form).getByTestId('po-supplier'), supplier);
  await userEvent.type(within(form).getByTestId('po-qty'), qty);
  await userEvent.click(within(form).getByTestId('po-submit'));
};

describe('상품 발주', () => {
  it('메뉴 자리 — 발주·공급사 관리 탭', async () => {
    renderAt('/c/CDC01/purchase');
    expect(await screen.findByRole('heading', { level: 1, name: '상품 발주' })).toBeInTheDocument();
    expect(screen.getByRole('tab', { name: '발주' })).toHaveAttribute('aria-selected', 'true');
    expect(screen.getByRole('tab', { name: '공급사 관리' })).toBeInTheDocument();
    expect(await screen.findAllByTestId('po-row')).toHaveLength(2);
  });

  it('발주하고 입고하면 재고관리 수량이 발주 수량만큼 늘어난다', async () => {
    const view = renderAt('/c/CDC01/purchase');
    await newOrder('한빛식품(시험)', '120');
    const detail = await screen.findByTestId('po-detail');
    expect(within(detail).getByTestId('po-state')).toHaveTextContent('입고 대기');
    const post = view.sent.find((r) => r.method === 'POST' && new URL(r.url).pathname.endsWith('/purchase-orders'))!;
    expect(post.headers.get('Idempotency-Key')).toBeTruthy();
    expect(post.headers.get('X-Source-System')).toBe('cdc-backoffice-web');
    expect(((await post.clone().json()) as { lines: unknown[] }).lines).toEqual([{ sku: 'SKU-1001', qty: 120 }]);

    await userEvent.click(screen.getByTestId('po-receive'));
    expect(await screen.findByText(/입고했어요/)).toBeInTheDocument();
    await waitFor(() => expect(within(screen.getByTestId('po-detail')).getByTestId('po-state')).toHaveTextContent('입고 완료'));
    const lot = within(screen.getByTestId('po-lines')).getByText(/^L\d+/).textContent;
    view.unmount();

    renderAt('/c/CDC01/inventory');
    const rows = await screen.findAllByTestId('stock-row');
    expect(rows[0]).toHaveTextContent('1,320');
    await userEvent.click(rows[0]!);
    expect(within(await screen.findByTestId('stock-places')).getByText(lot)).toBeInTheDocument();
  });

  it('입고 전에는 취소할 수 있고, 취소하면 입고 버튼이 없다', async () => {
    renderAt('/c/CDC01/purchase');
    await newOrder('대성농산(시험)', '50');
    await screen.findByTestId('po-detail');
    await userEvent.click(screen.getByTestId('po-cancel'));
    expect(await screen.findByText(/를 취소했어요/)).toBeInTheDocument();
    await waitFor(() => expect(within(screen.getByTestId('po-detail')).getByTestId('po-state')).toHaveTextContent('취소'));
    expect(screen.queryByTestId('po-receive')).not.toBeInTheDocument();
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
    await userEvent.click(screen.getByTestId('sup-submit'));
    await waitFor(() => expect(screen.getAllByTestId('supplier-row')).toHaveLength(4));
    const post = view.sent.find((r) => r.method === 'POST' && new URL(r.url).pathname.endsWith('/suppliers'))!;
    expect(await post.clone().json()).toMatchObject({ name: '새벽수산(시험)', skus: ['SKU-1002', 'SKU-2001'] });
    await userEvent.click(screen.getByRole('tab', { name: '발주' }));
    await userEvent.click(await screen.findByRole('button', { name: '발주 등록' }));
    expect(await within(screen.getByTestId('po-form')).findByRole('option', { name: '새벽수산(시험)' })).toBeInTheDocument();
  });
});
