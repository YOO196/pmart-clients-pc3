// 상품 관리 기본 목록 = 본사 상품 연동(2026-11-26) — product-service /products 목·mfc-inventory sku-handlings·sku-handling-batches 목.
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';

import { db } from '../../mocks/db';
import { renderAt } from '../../test/render';

const rows = () => screen.getAllByTestId('catalog-row');
const rowOf = (name: string) => rows().find((r) => within(r).queryByText(name, { selector: 'span.font-medium' }))!;
const switchOf = (name: string) => within(rowOf(name)).findByRole('switch', { name: `${name} 이 센터 판매` });
const batches = (sent: readonly Request[]) => sent.filter((r) => r.method === 'POST' && new URL(r.url).pathname.endsWith('/sku-handling-batches'));
const bulk = () => screen.getByTestId('catalog-bulk');
const open = () => renderAt('/c/MFC-BJG-01/products');
const loaded = () => waitFor(() => expect(rows().length).toBeGreaterThan(0));

describe('상품 관리 — 본사 상품 연동', () => {
  it('상품 관리는 재고 탭이 아니라 따로 메뉴 — 예전 주소(재고 ?tab=handlings)는 상품 관리로 넘긴다', async () => {
    renderAt('/c/MFC-BJG-01/inventory?tab=handlings&enabled=new');
    expect(await screen.findByRole('heading', { level: 1, name: '상품 관리' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: '상품 관리' })).toHaveAttribute('aria-current', 'page');
    expect(screen.queryByRole('tab', { name: '상품 취급' })).not.toBeInTheDocument();
  });

  it('기본으로 본사 판매 중 상품(불러오기 단추 없음) + 줄마다 이 센터 판매 스위치', async () => {
    open();
    await loaded();
    expect(screen.getByRole('radio', { name: '본사 상품' })).toHaveAttribute('aria-checked', 'true');
    expect(screen.queryByRole('button', { name: '본사 상품 불러오기' })).not.toBeInTheDocument();
    expect(await switchOf('서울우유 1L')).toBeChecked();
    expect(await switchOf('생수 2L')).not.toBeChecked();
    // 비활성 SKU 뿐인 상품은 켤 수 없다
    expect(await switchOf('옛 묶음 상품')).toBeDisabled();
    expect(within(rowOf('옛 묶음 상품')).getByText('켤 수 없음')).toBeInTheDocument();
    // 기본 거르기 = 판매 중 — 판매 중지 상품은 없다
    expect(rows().some((r) => r.textContent?.includes('단종 과자'))).toBe(false);
  });

  it('스위치는 상품의 SKU 전부를 일괄 API 로 켜고 끈다(같은 키·출처 헤더)', async () => {
    const view = open();
    await loaded();
    await userEvent.click(await switchOf('생수 2L'));
    await waitFor(() => expect(db.handlings.filter((h) => h.sku.startsWith('SKU-WATER')).every((h) => h.handlingEnabled)).toBe(true));
    await waitFor(async () => expect(await switchOf('생수 2L')).toBeChecked());
    const [post] = batches(view.sent);
    const body = (await post!.clone().json()) as { items: { sku: string; enabled: boolean }[] };
    expect(body.items.map((i) => i.sku).sort()).toEqual(['SKU-WATER-2L', 'SKU-WATER-6']);
    expect(post!.headers.get('Idempotency-Key')).toBeTruthy();
    expect(post!.headers.get('X-Source-System')).toBe('mfc-backoffice-web');
    await userEvent.click(await switchOf('생수 2L'));
    await waitFor(() => expect(db.handlings.filter((h) => h.sku.startsWith('SKU-WATER')).some((h) => h.handlingEnabled)).toBe(false));
    expect(batches(view.sent)).toHaveLength(2);
  });

  it('고른 상품 일괄 — 켤 수 없는 SKU 는 빼고, 이미 그 상태인 SKU 는 보내지 않는다', async () => {
    const view = open();
    await loaded();
    await switchOf('생수 2L');
    await userEvent.click(within(rowOf('생수 2L')).getByRole('checkbox', { name: '생수 2L 고르기' }));
    await userEvent.click(within(rowOf('옛 묶음 상품')).getByRole('checkbox', { name: '옛 묶음 상품 고르기' }));
    await userEvent.click(within(rowOf('서울우유 1L')).getByRole('checkbox', { name: '서울우유 1L 고르기' }));
    expect(within(bulk()).getByText('3개 고름')).toBeInTheDocument();
    await userEvent.click(within(bulk()).getByRole('button', { name: '이 센터에서 팔기' }));
    expect(await within(bulk()).findByText('상품 3개 — SKU 2개를 켰어요.')).toBeInTheDocument();
    const body = (await batches(view.sent)[0]!.clone().json()) as { items: { sku: string }[] };
    expect(body.items.map((i) => i.sku).sort()).toEqual(['SKU-WATER-2L', 'SKU-WATER-6']);
  });

  it('모두 고르기 = 지금 조건(판매 중)의 상품 전부, 조건을 바꾸면 풀린다', async () => {
    const view = open();
    await loaded();
    await switchOf('서울우유 1L');
    await userEvent.click(within(bulk()).getByRole('checkbox', { name: /조건에 맞는 상품 .*모두 고르기/ }));
    expect(await within(bulk()).findByText('11개 고름')).toBeInTheDocument();
    expect(within(bulk()).getByRole('checkbox', { name: '조건에 맞는 상품 11개 모두 고르기' })).toBeChecked();
    await userEvent.click(within(bulk()).getByRole('button', { name: '팔지 않기' }));
    expect(await within(bulk()).findByText('상품 11개 — SKU 6개를 껐어요.')).toBeInTheDocument();
    expect(db.handlings.filter((h) => h.handlingEnabled)).toHaveLength(0);
    expect(view.gets('/products').some((r) => new URL(r.url).searchParams.get('size') === '200')).toBe(true);
    // 조건을 바꾸면 고른 것은 풀린다
    await userEvent.type(screen.getByRole('searchbox', { name: '상품명·상품 코드·바코드' }), '우유');
    await userEvent.click(within(screen.getByTestId('catalog-products')).getByRole('button', { name: '조회' }));
    await waitFor(() => expect(rows()).toHaveLength(1));
    expect(within(bulk()).queryByText(/개 고름/)).not.toBeInTheDocument();
  });

  it('상품명 찾기는 product-service q 로', async () => {
    const view = open();
    await userEvent.type(await screen.findByRole('searchbox', { name: '상품명·상품 코드·바코드' }), '우유');
    await userEvent.click(within(screen.getByTestId('catalog-products')).getByRole('button', { name: '조회' }));
    await waitFor(() => expect(rows()).toHaveLength(1));
    expect(rows()[0]).toHaveTextContent('서울우유 1L');
    expect(view.gets('/products').some((r) => new URL(r.url).searchParams.get('q') === '우유')).toBe(true);
  });

  it('목록/카드 두 가지 보기 — 카드도 사진·고르기·스위치', async () => {
    const view = open();
    await loaded();
    await waitFor(() => expect(rowOf('서울우유 1L').querySelector('img')).not.toBeNull());
    expect(view.gets('/product-contents').length).toBeGreaterThan(0);
    await userEvent.click(within(bulk()).getByRole('button', { name: '카드' }));
    const cards = await screen.findAllByTestId('catalog-card');
    const water = cards.find((c) => c.textContent?.includes('생수 2L'))!;
    expect(water.querySelector('img')).not.toBeNull();
    await userEvent.click(await within(water).findByRole('switch', { name: '생수 2L 이 센터 판매' }));
    await waitFor(() => expect(db.handlings.find((h) => h.sku === 'SKU-WATER-6')!.handlingEnabled).toBe(true));
    // SKU별 취급 목록도 같은 보기(?view=card) — 카드형
    await userEvent.click(screen.getByRole('radio', { name: 'SKU별 취급' }));
    expect((await screen.findAllByTestId('handling-card')).length).toBeGreaterThan(0);
  });

  it('SKU별 취급 칩으로 예전 목록, 예전 주소(?enabled=)도 그쪽', async () => {
    renderAt('/c/MFC-BJG-01/products?enabled=true');
    expect(await screen.findByRole('radio', { name: 'SKU별 취급' })).toHaveAttribute('aria-checked', 'true');
    await waitFor(() => expect(screen.getAllByTestId('handling-row').length).toBeGreaterThan(0));
    await userEvent.click(screen.getByRole('radio', { name: '본사 상품' }));
    await loaded();
  });
});
