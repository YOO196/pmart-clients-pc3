// 배차 취소(dispatch 0.3.2 — 사유 OPERATOR 는 approvalRef 필수, BOD-1). 2026-11-27 사용자 캡처: 기본 "운영 판단"으로 눌려 늘 APPROVAL_REQUIRED.
import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { describe, expect, it } from 'vitest';

import { API_BASE } from '../../api/client';
import { dispatchOf, mockDeliveries } from '../../mocks/deliveryHandlers';
import { as, renderAt } from '../../test/render';
import { server } from '../../test/server';

const posts = (sent: readonly Request[]) => sent.filter((r) => r.method === 'POST' && new URL(r.url).pathname.endsWith('/assignment-cancellations'));

describe('배차 취소', () => {
  it('사유를 고르기 전에는 못 누르고, 고른 사유로 보낸다', async () => {
    const view = renderAt('/deliveries/DLV-1', as.riderOps);
    const form = await screen.findByRole('form', { name: '배차 취소' });
    const send = within(form).getByRole('button', { name: '배차 취소' });
    expect(send).toBeDisabled();
    await userEvent.selectOptions(within(form).getByRole('combobox'), 'RIDER_UNABLE');
    expect(within(form).queryByLabelText('승인 번호')).toBeNull();
    await userEvent.click(send);
    expect(await within(form).findByText('반영했어요.')).toBeInTheDocument();
    expect((await posts(view.sent)[0]!.clone().json()) as unknown).toEqual({ requestedBy: 'OPERATOR', reason: 'RIDER_UNABLE', reassign: true });
  });

  it('운영 판단은 승인 번호를 넣어야 보낼 수 있고, approvalRef 로 같이 보낸다', async () => {
    const view = renderAt('/deliveries/DLV-1', as.riderOps);
    const form = await screen.findByRole('form', { name: '배차 취소' });
    const send = within(form).getByRole('button', { name: '배차 취소' });
    await userEvent.selectOptions(within(form).getByRole('combobox'), 'OPERATOR');
    expect(within(form).getByText('운영 판단은 승인 번호가 필요해요.')).toBeInTheDocument();
    expect(send).toBeDisabled();
    await userEvent.type(within(form).getByLabelText('승인 번호'), 'APR-77');
    await userEvent.click(send);
    expect(await within(form).findByText('반영했어요.')).toBeInTheDocument();
    expect((await posts(view.sent)[0]!.clone().json()) as unknown).toEqual({ requestedBy: 'OPERATOR', reason: 'OPERATOR', reassign: true, approvalRef: 'APR-77' });
  });

  it('배차 중(라이더 없음)이면 다시 배차하기를 끄고 잠그고, reassign=false 로 보낸다(서버는 배차 중 재배차 취소를 INVALID_STATE 로 거절)', async () => {
    server.use(http.get(`${API_BASE}/deliveries/DLV-1/dispatch`, () => HttpResponse.json({ ...dispatchOf(mockDeliveries[0]!), state: 'DISPATCHING' })));
    const view = renderAt('/deliveries/DLV-1', as.riderOps);
    const form = await screen.findByRole('form', { name: '배차 취소' });
    const again = within(form).getByRole('checkbox', { name: '다시 배차하기' });
    expect(again).not.toBeChecked();
    expect(again).toBeDisabled();
    expect(within(form).getByText('아직 배차 중이라 다시 배차 없이 취소만 돼요.')).toBeInTheDocument();
    await userEvent.selectOptions(within(form).getByRole('combobox'), 'STORE_REQUEST');
    await userEvent.click(within(form).getByRole('button', { name: '배차 취소' }));
    expect(await within(form).findByText('반영했어요.')).toBeInTheDocument();
    expect((await posts(view.sent)[0]!.clone().json()) as unknown).toEqual({ requestedBy: 'OPERATOR', reason: 'STORE_REQUEST', reassign: false });
  });
});
