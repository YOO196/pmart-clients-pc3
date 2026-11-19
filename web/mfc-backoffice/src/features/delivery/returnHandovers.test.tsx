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

    const claim = cards.find((c) => c.textContent?.includes('30000001-2'))!;
    expect(within(claim).getByTestId('return-code')).toHaveTextContent('4821');
    expect(within(claim).getByText('고객 반품 회수')).toBeInTheDocument();
    expect(within(claim).getByText('라이더가 2번 틀렸어요')).toBeInTheDocument();
    expect(within(claim).getByTestId('rider-label')).toHaveTextContent(/^라이더 정보 비공개$/);

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

    await userEvent.click(within(locked).getByRole('button', { name: '새 번호 내고 잠김 풀기' }));
    await userEvent.click(within(locked).getByRole('button', { name: '그만두기' }));
    expect(reissues(view.sent)).toHaveLength(0);

    await userEvent.click(within(locked).getByRole('button', { name: '새 번호 내고 잠김 풀기' }));
    expect(within(locked).getByRole('alertdialog')).toHaveTextContent('지금 번호는 더 이상 맞지 않아요');
    await userEvent.click(within(locked).getByRole('button', { name: '새 번호 내기' }));
    await waitFor(() => expect(reissues(view.sent)).toHaveLength(1));
    const req = reissues(view.sent)[0]!;
    expect(new URL(req.url).pathname).toMatch(/\/return-handovers\/DLV-RET-2\/code-reissues$/);
    expect(req.headers.get('Idempotency-Key')).toBeTruthy();
    expect(req.headers.get('X-Source-System')).toBeTruthy();

    // 다시 읽은 목록에서 잠김이 풀리고 번호가 바뀐다
    await waitFor(() => expect(screen.queryByText('1357')).not.toBeInTheDocument());
    const after = (await screen.findAllByTestId('return-handover')).find((c) => c.textContent?.includes('DLV-RET-2'))!;
    expect(within(after).queryByRole('alert')).not.toBeInTheDocument();
    expect(within(after).getByText(/^새 번호 \d{4} 를 냈어요/)).toBeInTheDocument();
  });

  it('이미 반납이 끝나 409 면 거절로 보이고, 조회 실패는 빈 목록이 아니다', async () => {
    server.use(http.post(`${API_BASE}/return-handovers/:deliveryId/code-reissues`, () => HttpResponse.json({ type: 'about:blank', title: 'Conflict', status: 409, code: 'INVALID_STATE' }, { status: 409, headers: { 'Content-Type': 'application/problem+json' } })));
    const first = renderAt('/c/MFC-BSN-01/return-handovers');
    const cards = await screen.findAllByTestId('return-handover');
    await userEvent.click(within(cards[0]!).getByRole('button', { name: /새 번호/ }));
    await userEvent.click(within(cards[0]!).getByRole('button', { name: '새 번호 내기' }));
    expect(await within(cards[0]!).findByRole('alert')).toBeInTheDocument();
    first.unmount();

    server.use(http.get(`${API_BASE}/return-handovers`, () => new HttpResponse(null, { status: 500 })));
    renderAt('/c/MFC-BSN-01/return-handovers');
    await waitFor(() => expect(screen.queryByText('반납을 기다리는 배송이 없어요')).not.toBeInTheDocument());
    expect(await screen.findByRole('button', { name: /다시/ })).toBeInTheDocument();
  });
});
