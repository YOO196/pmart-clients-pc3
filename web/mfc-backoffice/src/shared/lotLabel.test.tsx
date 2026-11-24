// LOT 화면 번호(inventory 0.30.0 lot-numbers) — 목록에 LOT-… 대신 LOT 번호, 모르면 "LOT 번호 없음", 실패면 "확인 불가", 한 화면은 한 번에 묻는다.
import { screen, waitFor } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { describe, expect, it } from 'vitest';

import { API_BASE } from '../api/client';
import { renderAt } from '../test/render';
import { server } from '../test/server';

describe('LOT 번호', () => {
  it('이동 목록의 LOT 은 LOT 번호로, 시스템 LOT ID 는 글자로 내지 않는다 — 센터마다 한 번에 묻는다', async () => {
    const view = renderAt('/c/MFC-SEED-01/moves');
    await waitFor(() => expect(screen.getAllByTestId('lot-label')[0]).toHaveTextContent(/^L\d{12}$/));
    expect(screen.queryByText('LOT-MILK-A')).not.toBeInTheDocument();
    const calls = view.gets('/lot-numbers');
    expect(calls).toHaveLength(1);
    expect(new URL(calls[0]!.url).pathname).toContain('/mfcs/MFC-SEED-01/lot-numbers');
  });

  it('모르는 LOT 은 "LOT 번호 없음", 조회 실패는 "LOT 번호 확인 불가"', async () => {
    server.use(http.get(`${API_BASE}/mfcs/:mfcId/lot-numbers`, () => HttpResponse.json({ items: [] })));
    const first = renderAt('/c/MFC-SEED-01/moves');
    await waitFor(() => expect(screen.getAllByTestId('lot-label')[0]).toHaveTextContent('LOT 번호 없음'));
    first.unmount();
    server.use(http.get(`${API_BASE}/mfcs/:mfcId/lot-numbers`, () => new HttpResponse(null, { status: 500 })));
    renderAt('/c/MFC-SEED-01/moves');
    await waitFor(() => expect(screen.getAllByTestId('lot-label')[0]).toHaveTextContent('LOT 번호 확인 불가'));
  });

  it('작업 상세 제목은 주문번호 + 종류, 포장은 라벨 숫자(포장 시스템 ID 는 시스템 번호 칸)', async () => {
    renderAt('/c/MFC-SEED-01/tasks/TASK-PICK-1');
    expect(await screen.findByRole('heading', { level: 1, name: /^20000001 피킹/ })).toBeInTheDocument();
    const row = (await screen.findAllByTestId('package-row'))[0]!;
    expect(row).not.toHaveTextContent('PKG-');
  });
});
