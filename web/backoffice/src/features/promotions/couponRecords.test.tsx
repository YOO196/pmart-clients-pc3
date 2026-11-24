// 쿠폰 발급 기록(promotion 0.3.1 PRM-1, 2026-11-24) — 고객 상세 "쿠폰"·행사 상세 "발급 내역"
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';

import { as, renderAt } from '../../test/render';

describe('쿠폰 발급 기록', () => {
  it('고객 상세: 받은 쿠폰 — 행사·상태·경로(발급 직원·사유)·쓴 주문, 상태로 거르면 서버에 status', async () => {
    const user = userEvent.setup();
    const view = renderAt('/customers/CUS-1001', as.cs);
    const box = await screen.findByTestId('customer-coupons');
    const rows = await within(box).findAllByTestId('coupon-record');
    expect(rows).toHaveLength(2);
    expect(rows[0]).toHaveTextContent('첫 주문 3천원 쿠폰');
    expect(rows[0]).toHaveTextContent('사용');
    expect(rows[0]).toHaveTextContent('직원 지정 발급');
    expect(rows[0]).toHaveTextContent('배송 지연 보상');
    expect(await within(rows[0]!).findByText(/최상담/)).toBeInTheDocument(); // 발급 직원 이름(hr employee-labels)
    expect(within(rows[0]!).getByRole('link', { name: '주문 보기' })).toHaveAttribute('href', '/orders/ORD-MOCK-1001');
    expect(rows[1]).toHaveTextContent('보상');
    expect(rows[1]).toHaveTextContent('기한 지남');
    await user.selectOptions(within(box).getByLabelText('상태'), 'USED');
    await waitFor(() => expect(within(box).getAllByTestId('coupon-record')).toHaveLength(1));
    const q = new URL(view.sent.filter((r) => new URL(r.url).pathname.endsWith('/promotions/coupons')).at(-1)!.url).searchParams;
    expect(q.get('customerId')).toBe('CUS-1001');
    expect(q.get('status')).toBe('USED');
  });

  it('행사 상세: 발급 내역 — 고객은 가린 이름·번호(고객 일괄 조회), 고객 조회 권한이 없는 마케팅은 ID', async () => {
    renderAt('/promotions/PRM-seed-1', as.admin);
    const box = await screen.findByTestId('promotion-coupons');
    const rows = await within(box).findAllByTestId('coupon-record');
    expect(rows).toHaveLength(2);
    await waitFor(() => expect(rows.find((r) => r.textContent?.includes('482913'))).toBeDefined());
    expect(box).not.toHaveTextContent('김고객'); // 원문 이름 없음
  });

  it('행사 상세: 마케팅은 고객 이름을 못 붙여 ID 그대로(0 건으로 보이지 않게)', async () => {
    renderAt('/promotions/PRM-seed-1', as.marketing);
    const box = await screen.findByTestId('promotion-coupons');
    const rows = await within(box).findAllByTestId('coupon-record');
    expect(rows).toHaveLength(2);
    expect(box).toHaveTextContent('CUS-1001');
  });
});
