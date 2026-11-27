// 상품 관리 기본 목록 = 본사 상품 연동(2026-11-26) — product-service /products 목·mfc-inventory sku-handling-batches 목.
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';

import { db } from '../../mocks/db';
import { renderAt } from '../../test/render';

const rows = () => screen.getAllByTestId('catalog-row');
// 상품 칸 = 사진(없으면 첫 글자) + 이름 — 이름으로 끝나는 칸
const rowOf = (name: string) => rows().find((r) => within(r).getAllByRole('cell')[1]!.textContent?.endsWith(name))!;
const open = async () => {
  renderAt('/c/MFC-BJG-01/products');
  await waitFor(() => expect(rows().length).toBeGreaterThan(0));
};

describe('상품 관리 — 본사 상품 연동', () => {
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
    await waitFor(() => expect(rows().length).toBeGreaterThan(0));
    await userEvent.click(within(rowOf('생수 2L')).getByRole('checkbox'));
    await userEvent.click(within(rowOf('그릭요거트 플레인')).getByRole('checkbox'));
    await userEvent.click(screen.getByRole('button', { name: '선택한 2개 켜기' }));
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

  it('머리 칸 체크로 보이는 상품 모두 고르기 → 한꺼번에 끈다(enabled false), 다시 누르면 모두 풀기', async () => {
    const view = renderAt('/c/MFC-BJG-01/products');
    await waitFor(() => expect(within(rowOf('서울우유 1L')).getByText('취급 중')).toBeInTheDocument());
    expect(screen.queryByRole('columnheader', { name: '고르기' })).toBeNull();
    const all = screen.getByRole('checkbox', { name: '보이는 상품 모두 고르기' });
    await userEvent.click(all);
    expect(rows().every((r) => within(r).getByRole<HTMLInputElement>('checkbox').checked)).toBe(true);
    await userEvent.click(all);
    expect(rows().some((r) => within(r).getByRole<HTMLInputElement>('checkbox').checked)).toBe(false);
    await userEvent.click(within(rowOf('서울우유 1L')).getByRole('checkbox'));
    await userEvent.click(screen.getByRole('button', { name: '선택한 1개 끄기' }));
    expect(await screen.findByText(/개를 껐어요/)).toBeInTheDocument();
    const post = view.sent.find((r) => r.method === 'POST' && new URL(r.url).pathname.endsWith('/sku-handling-batches'))!;
    const body = (await post.clone().json()) as { items: { sku: string; enabled: boolean }[] };
    expect(body.items.every((i) => !i.enabled)).toBe(true);
    await waitFor(() => expect(within(rowOf('서울우유 1L')).getByText('안 함')).toBeInTheDocument());
  });

  it('켤 수 없는 SKU 가 섞이면 서버가 전부 거절 — 아무것도 바뀌지 않음을 알린다', async () => {
    await open();
    await userEvent.click(within(rowOf('옛 묶음 상품')).getByRole('checkbox'));
    await userEvent.click(within(rowOf('생수 2L')).getByRole('checkbox'));
    await userEvent.click(screen.getByRole('button', { name: '선택한 2개 켜기' }));
    expect(await screen.findByText(/아무것도 바꾸지 않았어요/)).toBeInTheDocument();
    expect(db.handlings.find((h) => h.sku === 'SKU-WATER-2L')!.handlingEnabled).toBe(false);
  });

  it('상품명 찾기는 product-service q 로', async () => {
    const view = renderAt('/c/MFC-BJG-01/products');
    await userEvent.type(await screen.findByRole('searchbox', { name: '상품명·상품 코드·바코드' }), '우유');
    await userEvent.click(within(screen.getByTestId('catalog-products')).getByRole('button', { name: '조회' }));
    await waitFor(() => expect(rows()).toHaveLength(1));
    expect(rows()[0]).toHaveTextContent('서울우유 1L');
    expect(view.gets('/products').some((r) => new URL(r.url).searchParams.get('q') === '우유')).toBe(true);
  });

  it('목록/카드 두 가지 보기 — 카드는 대표 사진(product-content)과 이름, 고르기·켜기는 같다', async () => {
    const view = renderAt('/c/MFC-BJG-01/products');
    await waitFor(() => expect(rows().length).toBeGreaterThan(0));
    // 목록에도 사진(게시된 상품)
    await waitFor(() => expect(rowOf('서울우유 1L').querySelector('img')).not.toBeNull());
    expect(view.gets('/product-contents').length).toBeGreaterThan(0);
    await userEvent.click(within(screen.getByTestId('catalog-products')).getByRole('button', { name: '카드' }));
    const cards = await screen.findAllByTestId('catalog-card');
    const water = cards.find((c) => c.textContent?.includes('생수 2L'))!;
    expect(water.querySelector('img')).not.toBeNull();
    await userEvent.click(within(water).getByRole('checkbox'));
    await userEvent.click(screen.getByRole('button', { name: '선택한 1개 켜기' }));
    expect(await screen.findByText('2개 SKU 중 2개를 켰어요(이미 켜진 것은 그대로).')).toBeInTheDocument();
    // SKU별 취급 목록도 같은 보기(?view=card) — 카드형
    await userEvent.click(screen.getByRole('radio', { name: 'SKU별 취급' }));
    expect(screen.getAllByTestId('handling-card').length).toBeGreaterThan(0);
  });

  it('기본으로 본사 상품이 뜨고(불러오기 버튼 없음), 줄마다 이 센터 취급을 켜고 끈다 — 상품의 SKU 전부', async () => {
    const view = renderAt('/c/MFC-BJG-01/products');
    await waitFor(() => expect(rows().length).toBeGreaterThan(0));
    expect(screen.getByRole('radio', { name: '본사 상품' })).toHaveAttribute('aria-checked', 'true');
    expect(screen.queryByRole('button', { name: '본사 상품 불러오기' })).not.toBeInTheDocument();
    await userEvent.click(await within(rowOf('생수 2L')).findByRole('button', { name: '생수 2L 이 센터 취급 켜기' }));
    expect(await within(rowOf('생수 2L')).findByText('이 센터에서 팔아요.')).toBeInTheDocument();
    expect(db.handlings.filter((h) => h.sku.startsWith('SKU-WATER')).every((h) => h.handlingEnabled)).toBe(true);
    await waitFor(() => expect(within(rowOf('생수 2L')).getByText('취급 중')).toBeInTheDocument());
    await userEvent.click(within(rowOf('생수 2L')).getByRole('button', { name: '생수 2L 이 센터 취급 끄기' }));
    expect(await within(rowOf('생수 2L')).findByText('이 센터에서 팔지 않아요.')).toBeInTheDocument();
    expect(db.handlings.filter((h) => h.sku.startsWith('SKU-WATER')).some((h) => h.handlingEnabled)).toBe(false);
    const posts = view.sent.filter((r) => r.method === 'POST' && new URL(r.url).pathname.endsWith('/sku-handling-batches'));
    expect(posts).toHaveLength(2);
    expect(posts[0]!.headers.get('Idempotency-Key')).not.toBe(posts[1]!.headers.get('Idempotency-Key'));
  });

  it('SKU별 취급 칩으로 예전 목록, 예전 주소(?enabled=)도 그쪽', async () => {
    renderAt('/c/MFC-BJG-01/products?enabled=true');
    expect(await screen.findByRole('radio', { name: 'SKU별 취급' })).toHaveAttribute('aria-checked', 'true');
    await waitFor(() => expect(screen.getAllByTestId('handling-row').length).toBeGreaterThan(0));
    await userEvent.click(screen.getByRole('radio', { name: '본사 상품' }));
    await waitFor(() => expect(rows().length).toBeGreaterThan(0));
  });
});
