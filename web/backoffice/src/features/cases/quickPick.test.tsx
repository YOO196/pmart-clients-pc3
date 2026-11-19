// 목록 줄 빠른 맡기(2026-11-19) — 다시 읽은 version 으로 맡고, 결과는 서버 응답대로
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';

import { as, renderAt } from '../../test/render';

describe('접수 건 목록 빠른 맡기', () => {
  it('아무도 안 맡은 건에 맡기 → 상세를 다시 읽고 version 과 Idempotency-Key 로 보낸다', async () => {
    const user = userEvent.setup();
    const view = renderAt('/cases?tab=unassigned', as.riderOps);
    const rows = await screen.findAllByTestId('case-row');
    const row = rows.find((r) => within(r).queryByTestId('quick-pick'));
    expect(row).toBeDefined();
    await user.click(within(row!).getByTestId('quick-pick'));
    // 맡은 뒤 목록을 다시 읽으면 그 줄은 "맡음"이 되어 빠른 단추·결과 글자가 사라질 수 있다 — 보낸 요청으로 본다
    const isPost = (r: Request) => r.method === 'POST' && new URL(r.url).pathname.endsWith('/assignments');
    await waitFor(() => expect(view.sent.some(isPost)).toBe(true));
    const post = view.sent.find(isPost);
    expect(post!.headers.get('Idempotency-Key')).toBeTruthy();
    expect(post!.headers.get('X-Expected-Version')).toMatch(/^\d+$/); // 다시 읽은 지금 version
    const caseId = decodeURIComponent(new URL(post!.url).pathname.split('/').at(-2) ?? '');
    // 맡기 전에 그 건을 다시 읽었다
    await waitFor(() => expect(view.sent.some((r) => r.method === 'GET' && new URL(r.url).pathname.endsWith(`/cases/${caseId}`))).toBe(true));
  });

  it('보기만 하는 상담원에게는 빠른 맡기가 없다(배송 접수 건)', async () => {
    renderAt('/cases?tab=unassigned', as.cs);
    await screen.findAllByTestId('case-row');
    const rows = screen.getAllByTestId('case-row').filter((r) => r.querySelector('[data-testid=quick-pick]'));
    // 상담원은 상담(CS) 종류만 맡을 수 있다 — 배송 종류 줄에는 없다
    for (const r of rows) expect(r.textContent).not.toMatch(/배송 실패|주소 불명/);
  });
});
