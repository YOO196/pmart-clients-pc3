// 재고 > LOT 추적 — lot-resolutions(0.21.0)·stock·stock-ledger(0.48.0, lotId) 목.
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';

import { pageList } from '../../shared/Pager';
import { openFilter, renderAt } from '../../test/render';
import { looksLikeLotCode, lotCode } from './LotTraceTab';

describe('LOT 추적', () => {
  it('LOT 번호를 몰라도 센터 LOT 목록(소비기한 이른 순) — 상품명·코드로 찾기, 품질 필터는 서버로, LOT 을 누르면 추적', async () => {
    const view = renderAt('/c/MFC-BJG-01/inventory?tab=lotTrace');
    await waitFor(() => expect(screen.getAllByTestId('lot-row').length).toBeGreaterThan(1));
    expect(view.gets('/lot-resolutions')).toHaveLength(0);
    // 글자 찾기 — 받은 목록 안에서(상품명·상품 코드·LOT 번호)
    await userEvent.type(screen.getByRole('searchbox', { name: '상품명·상품 코드·LOT 번호' }), 'milk');
    await userEvent.click(screen.getByRole('button', { name: '조회' }));
    await waitFor(() => expect(screen.getAllByTestId('lot-row').every((r) => r.textContent?.includes('SKU-MILK-1'))).toBe(true));
    // 품질 필터 — stock-units qualityState 로 서버에
    await openFilter();
    await userEvent.selectOptions(screen.getByRole('combobox', { name: '품질' }), 'QUARANTINED');
    await waitFor(() => expect(view.gets('/stock-units').some((r) => new URL(r.url).searchParams.get('qualityState') === 'QUARANTINED')).toBe(true));
    await waitFor(() => expect(screen.getAllByTestId('lot-row')).toHaveLength(1));
    // LOT 을 누르면 그 LOT 추적, ‹ 로 목록
    await userEvent.click(within(screen.getAllByTestId('lot-row')[0]!).getAllByRole('button')[0]!);
    expect(await screen.findByTestId('lot-card')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'LOT 목록' }));
    expect(await screen.findByTestId('lot-list')).toBeInTheDocument();
  });

  it('LOT 번호 → (10) 괄호 꼴로 찾고, LOT 정보·지금 있는 칸·이 LOT 이 지나온 길(서버 값)', async () => {
    const view = renderAt('/c/MFC-BJG-01/inventory?tab=lotTrace');
    await userEvent.type(await screen.findByRole('searchbox', { name: '상품명·상품 코드·LOT 번호' }), 'l261107000497');
    await userEvent.click(screen.getByRole('button', { name: '조회' }));
    const card = await screen.findByTestId('lot-card');
    expect(card).toHaveTextContent('L261107000497');
    expect(new URL(view.gets('/lot-resolutions')[0]!.url).searchParams.get('code')).toBe('(10)L261107000497');
    // 지금 있는 곳 — 이 LOT 칸만(다른 LOT 칸 RCV-C-01 은 없다)
    await waitFor(() => expect(screen.getAllByTestId('lot-where-row').map((r) => within(r).getAllByRole('cell')[0]!.textContent)).toEqual(['A-P1-01-1-01', 'QRT-A-01']));
    // 지나온 길 — lotId 로 거른 이력, 이동은 출발 −·도착 +
    await waitFor(() => expect(screen.getAllByTestId('lot-history-row').length).toBeGreaterThan(0));
    const ledger = view.gets('/stock-ledger').at(-1)!;
    expect(new URL(ledger.url).searchParams.get('lotId')).toBe('LOT-MILK-A');
    expect(screen.getByText('A-P1-01-1-01 −2 → QRT-A-01 +2')).toBeInTheDocument();
    // 주문·처리한 사람(inventory 0.49.0) — 주문은 화면 번호 8자리(work-orders → 출고), 운영자 ID 는 내지 않는다
    const handover = screen.getAllByTestId('lot-history-row').find((r) => r.textContent?.includes('라이더 인계'))!;
    await waitFor(() => expect(handover).toHaveTextContent('20000001'));
    expect(handover).not.toHaveTextContent('ORD-1');
    expect(handover).not.toHaveTextContent('OP-wkr-1');
    // 출처는 서비스 이름만(포장 번호 PKG-… 같은 시스템 번호는 줄에 내지 않는다)
    expect(handover).toHaveTextContent('출고 작업');
    expect(handover).not.toHaveTextContent('PKG-20000001');
  });

  it('없는 LOT 은 404 — 빈 화면이 아니라 오류', async () => {
    renderAt('/c/MFC-BJG-01/inventory?tab=lotTrace&lot=L000000000000');
    expect(await screen.findByRole('alert')).toBeInTheDocument();
    expect(screen.queryByTestId('lot-card')).not.toBeInTheDocument();
  });

  it('입력 꼴: 괄호 꼴·LOT:·스캐너 원문은 그대로, 맨 번호는 (10)', () => {
    expect(lotCode('L261107000497')).toBe('(10)L261107000497');
    expect(lotCode('(01)08801115114154(10)L261107000497')).toBe('(01)08801115114154(10)L261107000497');
    expect(lotCode('LOT:LOT-MILK-A')).toBe('LOT:LOT-MILK-A');
    expect(lotCode('0108801115114154')).toBe('0108801115114154');
    // 찾기 칸: LOT 번호·바코드면 바로 추적, 상품명 글자는 목록 거르기
    expect(looksLikeLotCode('L261107000497')).toBe(true);
    expect(looksLikeLotCode('(10)L261107000497')).toBe(true);
    expect(looksLikeLotCode('서울우유')).toBe(false);
    expect(looksLikeLotCode('SKU-MILK-1')).toBe(false);
    // 쪽이 많으면 첫·끝·지금 앞뒤만(사이 …) — 75쪽 목록이 화면을 넘치지 않게
    expect(pageList(1, 5)).toEqual([1, 2, 3, 4, 5]);
    expect(pageList(10, 75)).toEqual([1, null, 9, 10, 11, null, 75]);
    expect(pageList(1, 75)).toEqual([1, 2, null, 75]);
  });
});
