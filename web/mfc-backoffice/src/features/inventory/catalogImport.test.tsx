// 재고 > 상품 취급 > 본사 상품 불러오기 — product-service /products 목·mfc-inventory sku-handling-batches 목.
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';

import { db } from '../../mocks/db';
import { renderAt } from '../../test/render';

const rows = () => screen.getAllByTestId('catalog-row');
const rowOf = (name: string) => rows().find((r) => within(r).getAllByRole('cell')[1]!.textContent === name)!;
const open = async () => {
  renderAt('/c/MFC-BJG-01/products');
  await userEvent.click(await screen.findByRole('button', { name: '본사 상품 불러오기' }));
  await waitFor(() => expect(rows().length).toBeGreaterThan(0));
};

describe('본사 상품 불러오기', () => {
  it('상품 관리는 재고 탭이 아니라 따로 메뉴 — 예전 주소(재고 ?tab=handlings)는 상품 관리로 넘긴다', async () => {
    renderAt('/c/MFC-BJG-01/inventory?tab=handlings&enabled=new');
    expect(await screen.findByRole('heading', { level: 1, name: '상품 관리' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: '상품 관리' })).toHaveAttribute('aria-current', 'page');
    expect(screen.queryByRole('tab', { name: '상품 취급' })).not.toBeInTheDocument();
  });

  it('본사 판매 중 상품 목록 + 이 센터 취급 여부(켜진 SKU 의 상품)', async () => {
    await open();
    expect(within(rowOf('서울우유 1L')).getByText('취급 중')).toBeInTheDocument();
    await waitFor(() => expect(within(rowOf('생수 2L')).getByText('안 함')).toBeInTheDocument());
    // 기본 거르기 = 판매 중 — 판매 중지 상품은 없다
    expect(rows().some((r) => r.textContent?.includes('단종 과자'))).toBe(false);
  });

  it('고른 상품의 SKU 를 한꺼번에 켠다(일괄, 같은 키·출처 헤더) — 여러 SKU 상품은 모두', async () => {
    const view = renderAt('/c/MFC-BJG-01/products');
    await userEvent.click(await screen.findByRole('button', { name: '본사 상품 불러오기' }));
    await waitFor(() => expect(rows().length).toBeGreaterThan(0));
    await userEvent.click(within(rowOf('생수 2L')).getByRole('checkbox'));
    await userEvent.click(within(rowOf('그릭요거트 플레인')).getByRole('checkbox'));
    await userEvent.click(screen.getByRole('button', { name: '선택한 2개 이 센터에서 판매' }));
    expect(await screen.findByText('3개 SKU 중 3개를 켰어요(이미 켜진 것은 그대로).')).toBeInTheDocument();
    const post = view.sent.find((r) => r.method === 'POST' && new URL(r.url).pathname.endsWith('/sku-handling-batches'))!;
    const body = (await post.clone().json()) as { items: { sku: string; enabled: boolean }[] };
    expect(body.items.map((i) => i.sku).sort()).toEqual(['SKU-NEW-1', 'SKU-WATER-2L', 'SKU-WATER-6']);
    expect(body.items.every((i) => i.enabled)).toBe(true);
    expect(post.headers.get('Idempotency-Key')).toBeTruthy();
    expect(post.headers.get('X-Source-System')).toBe('mfc-backoffice-web');
    expect(db.handlings.find((h) => h.sku === 'SKU-WATER-6')!.handlingEnabled).toBe(true);
    await waitFor(() => expect(within(rowOf('생수 2L')).getByText('취급 중')).toBeInTheDocument());
  });

  it('켤 수 없는 SKU 가 섞이면 서버가 전부 거절 — 아무것도 바뀌지 않음을 알린다', async () => {
    await open();
    await userEvent.click(within(rowOf('옛 묶음 상품')).getByRole('checkbox'));
    await userEvent.click(within(rowOf('생수 2L')).getByRole('checkbox'));
    await userEvent.click(screen.getByRole('button', { name: '선택한 2개 이 센터에서 판매' }));
    expect(await screen.findByText(/아무것도 바꾸지 않았어요/)).toBeInTheDocument();
    expect(db.handlings.find((h) => h.sku === 'SKU-WATER-2L')!.handlingEnabled).toBe(false);
  });

  it('상품명 찾기는 product-service q 로', async () => {
    const view = renderAt('/c/MFC-BJG-01/products');
    await userEvent.click(await screen.findByRole('button', { name: '본사 상품 불러오기' }));
    await userEvent.type(await screen.findByRole('searchbox', { name: '상품명·상품 코드·바코드' }), '우유');
    await userEvent.click(within(screen.getByTestId('catalog-import')).getByRole('button', { name: '조회' }));
    await waitFor(() => expect(rows().map((r) => within(r).getAllByRole('cell')[1]!.textContent)).toEqual(['서울우유 1L']));
    expect(view.gets('/products').some((r) => new URL(r.url).searchParams.get('q') === '우유')).toBe(true);
  });
});
