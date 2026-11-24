// 운영자 이름·사번(hr 0.8.0 employee-labels) — 목(MSW) 기준. 실서버 확인은 아니다.
import { screen, waitFor, within } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { describe, expect, it } from 'vitest';

import { API_BASE } from '../api/client';
import { renderAt } from '../test/render';
import { server } from '../test/server';

const labelCalls = (sent: readonly Request[]) => sent.filter((r) => new URL(r.url).pathname.endsWith('/hr/employee-labels')).map((r) => new URL(r.url).searchParams.getAll('operatorIds'));

describe('운영자 ID 대신 이름·사번', () => {
  it('배정 목록의 작업자 칸 — 한 화면의 ID 를 모아 한 번에 묻고, 같은 ID 는 한 번만', async () => {
    const view = renderAt('/c/MFC-SEED-01/assignments');
    const rows = await screen.findAllByTestId('assignment-row');
    await waitFor(() => expect(within(rows[0]!).getByTestId('operator-label')).toHaveTextContent(/·/));
    expect(screen.getAllByText('김현장').length).toBeGreaterThan(0);
    expect(screen.getByText('이알바')).toBeInTheDocument();
    expect(screen.queryByText('OP-wkr-2')).not.toBeInTheDocument();
    const calls = labelCalls(view.sent);
    expect(calls).toHaveLength(1);
    const ids = calls[0]!;
    expect(new Set(ids).size).toBe(ids.length);
    expect(ids).toEqual(expect.arrayContaining(['OP-wkr-1', 'OP-wkr-2']));
  });

  it('모르는 ID 는 "직원", 조회 실패는 "직원(이름 못 읽음)" — 운영자 ID 는 글자로 내지 않는다(ADR-0070 덧붙임)', async () => {
    server.use(http.get(`${API_BASE}/hr/employee-labels`, () => HttpResponse.json({ items: [] })));
    const first = renderAt('/c/MFC-SEED-01/assignments');
    await waitFor(() => expect(screen.getAllByTestId('operator-label')[0]).toHaveAttribute('data-fallback', 'unknown'));
    const label = screen.getAllByTestId('operator-label')[0]!;
    expect(label).toHaveTextContent(/^직원$/);
    expect(label).toHaveAttribute('title', expect.stringMatching(/^OP-/));
    expect(screen.queryByText('OP-wkr-1')).not.toBeInTheDocument();
    first.unmount();

    server.use(http.get(`${API_BASE}/hr/employee-labels`, () => new HttpResponse(null, { status: 500 })));
    renderAt('/c/MFC-SEED-01/assignments');
    await waitFor(() => expect(screen.getAllByTestId('operator-label')[0]).toHaveAttribute('data-fallback', 'failed'));
    expect(screen.getAllByText('직원(이름 못 읽음)').length).toBeGreaterThan(0);
  });
});
