// 라이더 화면 표기(rider 0.18.0 `GET /riders/display-names` — RS-MFC) — 목(MSW) 기준. 실서버 확인은 아니다.
import { screen, waitFor } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { describe, expect, it } from 'vitest';

import { API_BASE } from '../api/client';
import { renderAt } from '../test/render';
import { server } from '../test/server';

const nameCalls = (sent: readonly Request[]) =>
  sent.filter((r) => new URL(r.url).pathname.endsWith('/riders/display-names')).map((r) => new URL(r.url).searchParams.get('riderIds') ?? '');

describe('라이더 ID 대신 "가린 이름 · 라이더 번호"', () => {
  it('한 화면의 라이더를 모아 한 번에 묻는다(쉼표)', async () => {
    const view = renderAt('/c/MFC-BSN-01/return-handovers');
    await waitFor(() => expect(screen.getAllByTestId('rider-label').slice(0, 2).map((e) => e.textContent)).toEqual(['한*우 · 715520', '오*림 · 826631']));
    const calls = nameCalls(view.sent);
    expect(calls).toHaveLength(1);
    expect(calls[0]!.split(',').sort()).toEqual(['RD-31', 'RD-32']);
    expect(screen.queryByText(/RD-3/)).not.toBeInTheDocument();
  });

  it('조회 실패는 "라이더 조회 실패" — ID 를 대신 보이지 않는다', async () => {
    server.use(http.get(`${API_BASE}/riders/display-names`, () => new HttpResponse(null, { status: 503 })));
    renderAt('/c/MFC-BSN-01/return-handovers');
    await waitFor(() => expect(screen.getAllByTestId('rider-label')[0]).toHaveTextContent('라이더 조회 실패'));
    expect(screen.queryByText(/RD-3/)).not.toBeInTheDocument();
  });
});
