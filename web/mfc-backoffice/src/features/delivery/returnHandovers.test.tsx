// 반납 인증번호(delivery-execution 0.28.0) — 목(MSW) 기준. 실서버 확인은 아니다.
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { describe, expect, it } from 'vitest';

import { API_BASE } from '../../api/client';
import { renderAt } from '../../test/render';
import { server } from '../../test/server';

const reissues = (sent: readonly Request[]) => sent.filter((r) => r.method === 'POST' && new URL(r.url).pathname.endsWith('/code-reissues'));

describe('반납 인증번호(우리 센터)', () => {
  it('주소의 센터로 부르고, 번호·종류·화면 번호·잠김을 보인다(다른 센터 것은 없다)', async () => {
    const view = renderAt('/c/MFC-BSN-01/return-handovers');
    const cards = await screen.findAllByTestId('return-handover');
    expect(cards).toHaveLength(2);
    expect(screen.queryByText('9999')).not.toBeInTheDocument();
    expect(new URL(view.gets('/return-handovers')[0]!.url).searchParams.get('mfcId')).toBe('MFC-BSN-01');

    const claim = cards.find((c) => c.textContent?.includes('D30000001-2'))!;
    expect(within(claim).getByTestId('return-code')).toHaveTextContent('4821');
    expect(within(claim).getByText('고객 반품 회수')).toBeInTheDocument();
    expect(within(claim).getByText('라이더가 2번 틀렸어요')).toBeInTheDocument();
    // 라이더 ID 대신 "가린 이름 · 라이더 번호"(rider 0.18.0 RS-MFC)
    await waitFor(() => expect(within(claim).getByTestId('rider-label')).toHaveTextContent(/^R7155$/));

    const locked = cards.find((c) => c.textContent?.includes('1357'))!;
    expect(within(locked).getByRole('alert')).toHaveTextContent('잠겼어요');
    expect(within(locked).getByText('전달 실패 반납')).toBeInTheDocument();
    // 화면 번호가 없으면 "번호 없음"만(ADR-0070 덧붙임)
    expect(within(locked).getAllByTestId('display-number')[0]).toHaveTextContent(/^번호 없음$/);
  });

  it('잠긴 번호 → 한 번 더 묻고 새 번호(멱등키·출처 헤더), 그만두면 보내지 않는다', async () => {
    const view = renderAt('/c/MFC-BSN-01/return-handovers');
    const cards = await screen.findAllByTestId('return-handover');
    const locked = cards.find((c) => c.textContent?.includes('1357'))!;

    await userEvent.click(within(locked).getByRole('button', { name: '재발급하고 잠금 해제' }));
    await userEvent.click(within(locked).getByRole('button', { name: '취소' }));
    expect(reissues(view.sent)).toHaveLength(0);

    await userEvent.click(within(locked).getByRole('button', { name: '재발급하고 잠금 해제' }));
    expect(within(locked).getByRole('alertdialog')).toHaveTextContent('지금 번호는 더 이상 쓸 수 없어요');
    await userEvent.click(within(locked).getByRole('button', { name: '재발급' }));
    await waitFor(() => expect(reissues(view.sent)).toHaveLength(1));
    const req = reissues(view.sent)[0]!;
    expect(new URL(req.url).pathname).toMatch(/\/return-handovers\/DLV-RET-2\/code-reissues$/);
    expect(req.headers.get('Idempotency-Key')).toBeTruthy();
    expect(req.headers.get('X-Source-System')).toBeTruthy();

    // 다시 읽은 목록에서 잠김이 풀리고 번호가 바뀐다
    await waitFor(() => expect(screen.queryByText('1357')).not.toBeInTheDocument());
    const after = (await screen.findAllByTestId('return-handover')).find((c) => c.textContent?.includes('DLV-RET-2'))!;
    expect(within(after).queryByRole('alert')).not.toBeInTheDocument();
    expect(within(after).getByText(/^번호 \d{4}을\(를\) 재발급했어요/)).toBeInTheDocument();
  });

  it('이미 반납이 끝나 409 면 거절로 보이고, 조회 실패는 빈 목록이 아니다', async () => {
    server.use(http.post(`${API_BASE}/return-handovers/:deliveryId/code-reissues`, () => HttpResponse.json({ type: 'about:blank', title: 'Conflict', status: 409, code: 'INVALID_STATE' }, { status: 409, headers: { 'Content-Type': 'application/problem+json' } })));
    const first = renderAt('/c/MFC-BSN-01/return-handovers');
    const cards = await screen.findAllByTestId('return-handover');
    await userEvent.click(within(cards[0]!).getByRole('button', { name: /번호 재발급|재발급하고/ }));
    await userEvent.click(within(cards[0]!).getByRole('button', { name: '재발급' }));
    expect(await within(cards[0]!).findByRole('alert')).toBeInTheDocument();
    first.unmount();

    server.use(http.get(`${API_BASE}/return-handovers`, () => new HttpResponse(null, { status: 500 })));
    renderAt('/c/MFC-BSN-01/return-handovers');
    await waitFor(() => expect(screen.queryByText('반납을 기다리는 배송이 없어요')).not.toBeInTheDocument());
    expect(await screen.findByRole('button', { name: /다시/ })).toBeInTheDocument();
  });

  it('도착한 회수품(반입 대기): 종류·도착 시각·상품 × 수량·라이더 표기 — 이 센터 것만, 시스템 ID 는 시스템 번호 칸에만', async () => {
    const view = renderAt('/c/MFC-BSN-01/return-handovers');
    const box = await screen.findByTestId('return-arrivals');
    const cards = await within(box).findAllByTestId('return-arrival');
    expect(cards).toHaveLength(2);
    expect(cards[0]).toHaveTextContent('고객 반품 회수');
    expect(cards[0]).toHaveTextContent('서울우유 1L × 2');
    await waitFor(() => expect(cards[0]).toHaveTextContent('R7155'));
    // 클레임 없는 반납(오배송 회수)은 환불로 이어지지 않는다는 표시
    expect(cards[1]).toHaveTextContent('클레임 없음');
    expect(cards[0]).not.toHaveTextContent('클레임 없음');
    expect(within(box).queryByText(/DLV-RET|RD-3/)).not.toBeInTheDocument();
    const q = new URL(view.gets('/return-arrivals')[0]!.url).searchParams;
    expect([q.get('mfcId'), q.get('state')]).toEqual(['MFC-BSN-01', 'WAITING']);
  });
});
