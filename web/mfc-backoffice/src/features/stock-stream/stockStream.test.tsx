// 재고 실시간 반영(§4-16) — mfc-inventory 0.46.0 `/stock-stream` 목.
import { screen, waitFor } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { describe, expect, it } from 'vitest';

import { API_BASE } from '../../api/client';
import { db } from '../../mocks/db';
import { emitStockChange } from '../../mocks/stockStreamHandlers';
import { renderAt } from '../../test/render';
import { server } from '../../test/server';
import { createSseParser } from './sse';
import { isStockQuery } from './useStockStream';

const stockGets = (sent: Request[]) => sent.filter((r) => r.method === 'GET' && new URL(r.url).pathname.endsWith('/mfcs/MFC-BJG-01/stock'));
const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
const sse = (start: (push: (text: string) => void, close: () => void) => void) => {
  const enc = new TextEncoder();
  return new HttpResponse(
    new ReadableStream<Uint8Array>({
      start(c) {
        start(
          (t) => c.enqueue(enc.encode(t)),
          () => c.close(),
        );
      },
    }),
    { headers: { 'Content-Type': 'text/event-stream' } },
  );
};
const ready = (resumed: boolean) => `event: ready\ndata: {"type":"ready","resumed":${resumed}}\n\n`;

describe('SSE 줄 풀기', () => {
  it('조각이 나뉘어도·\\r\\n 이어도 이벤트 하나로, 주석(heartbeat)은 버린다', () => {
    const parse = createSseParser();
    expect(parse(': hb\n\nevent: sto')).toEqual([]);
    expect(parse('ck-changed\r\nid: SE-1\r\ndata: {"a":\r')).toEqual([]);
    expect(parse('\ndata: 1}\r\n\r\n')).toEqual([{ event: 'stock-changed', id: 'SE-1', data: '{"a":\n1}' }]);
  });
});

describe('재고 조회 고르기', () => {
  const pending = {
    all: false,
    skus: new Set(['SKU-MILK-1']),
    locations: new Set(['C-S1-03-2-04']),
  };
  it('바뀐 상품·그 칸이 든 랙만, 다른 센터는 아님', () => {
    expect(isStockQuery('MFC-BJG-01', ['stock', 'MFC-BJG-01', 'SKU-MILK-1'], pending)).toBe(true);
    expect(isStockQuery('MFC-BJG-01', ['stock', 'MFC-BJG-01', 'SKU-RAMEN-5'], pending)).toBe(false);
    expect(isStockQuery('MFC-BJG-01', ['floor', 'MFC-BJG-01', 'stock-units', 'C-S1-03-'], pending)).toBe(true);
    expect(isStockQuery('MFC-BJG-01', ['floor', 'MFC-BJG-01', 'stock-units', 'A-P1-01-'], pending)).toBe(false);
    expect(isStockQuery('MFC-BJG-01', ['list', 'stock-units', 'MFC-BJG-01', '', ''], pending)).toBe(true);
    expect(isStockQuery('MFC-BJG-01', ['stock', 'MFC-MOKPO-01', 'SKU-MILK-1'], pending)).toBe(false);
    expect(isStockQuery('MFC-BJG-01', ['policies', 'MFC-BJG-01'])).toBe(false);
  });
});

describe('재고 화면 실시간 반영', () => {
  it('연결되면 "실시간", 재고가 바뀌면 그 상품 재고를 다시 읽는다', async () => {
    const view = renderAt('/c/MFC-BJG-01/inventory?sku=SKU-MILK-1');
    await waitFor(() => expect(screen.getByTestId('stock-live')).toHaveAttribute('data-status', 'live'));
    expect(screen.getByTestId('stock-live')).toHaveTextContent('실시간');
    await screen.findAllByTestId('unit-row');
    await wait(400);
    const before = stockGets(view.sent).length;
    const unit = db.stockUnits.find((u) => u.mfcId === 'MFC-BJG-01' && u.sku === 'SKU-MILK-1' && u.qualityState === 'NORMAL')!;
    db.stockUnits = db.stockUnits.map((u) => (u === unit ? { ...u, qty: u.qty - 1 } : u));
    emitStockChange('MFC-BJG-01', 'TASK_EXECUTION', [
      {
        sku: unit.sku,
        lotId: unit.lotId,
        locationCode: unit.locationCode,
        qualityState: unit.qualityState,
        workState: unit.workState,
        delta: -1,
      },
    ]);
    await waitFor(() => expect(stockGets(view.sent).length).toBe(before + 1));
  });

  it('다른 상품이 바뀌면 이 상품 재고는 다시 읽지 않는다', async () => {
    const view = renderAt('/c/MFC-BJG-01/inventory?sku=SKU-MILK-1');
    await waitFor(() => expect(screen.getByTestId('stock-live')).toHaveAttribute('data-status', 'live'));
    await screen.findAllByTestId('unit-row');
    await wait(400);
    const before = stockGets(view.sent).length;
    emitStockChange('MFC-BJG-01', 'TASK_EXECUTION', [
      {
        sku: 'SKU-RAMEN-5',
        lotId: 'LOT-X',
        locationCode: 'A-P1-01-1-01',
        qualityState: 'NORMAL',
        workState: 'STORED',
        delta: -1,
      },
    ]);
    await wait(500);
    expect(stockGets(view.sent).length).toBe(before);
  });

  it('같은 version 이 다시 오면(이어 받기 겹침) 버린다', async () => {
    const changed = (version: number) =>
      `event: stock-changed\nid: SE-${version}\ndata: ${JSON.stringify({
        type: 'stock-changed',
        eventId: `SE-${version}`,
        mfcId: 'MFC-BJG-01',
        cause: 'TASK_EXECUTION',
        items: [
          {
            sku: 'SKU-MILK-1',
            onHandQty: 1,
            quarantinedQty: 0,
            sellableQty: 1,
            reservedQty: 0,
            availableQty: 1,
            availableDelta: -1,
            version,
          },
        ],
        units: [],
        holds: [],
      })}\n\n`;
    server.use(
      http.get(`${API_BASE}/stock-stream`, () =>
        sse((push) => {
          push(ready(true));
          setTimeout(() => push(changed(5)), 600);
          setTimeout(() => push(changed(5) + changed(4)), 1_200);
        }),
      ),
    );
    const view = renderAt('/c/MFC-BJG-01/inventory?sku=SKU-MILK-1');
    await screen.findAllByTestId('unit-row');
    await waitFor(() => expect(screen.getByTestId('stock-live')).toHaveAttribute('data-status', 'live'));
    const before = stockGets(view.sent).length;
    await waitFor(() => expect(stockGets(view.sent).length).toBe(before + 1), {
      timeout: 2_000,
    });
    await wait(1_000);
    expect(stockGets(view.sent).length).toBe(before + 1);
  });

  it('권한 밖(403)이면 멈추고 "실시간 끊김 — 60초 갱신"', async () => {
    server.use(
      http.get(`${API_BASE}/stock-stream`, () =>
        HttpResponse.json(
          {
            type: 'about:blank',
            title: 'FORBIDDEN',
            status: 403,
            code: 'FORBIDDEN',
          },
          {
            status: 403,
            headers: { 'Content-Type': 'application/problem+json' },
          },
        ),
      ),
    );
    renderAt('/c/MFC-BJG-01/inventory');
    await waitFor(() => expect(screen.getByTestId('stock-live')).toHaveAttribute('data-status', 'off'));
    expect(screen.getByTestId('stock-live')).toHaveTextContent('실시간 끊김 — 60초 갱신');
  });

  it('서버가 닫으면 다시 연결하고, 다시 붙으면 재고를 한 번 다시 읽는다', async () => {
    let opened = 0;
    server.use(
      http.get(`${API_BASE}/stock-stream`, () => {
        opened += 1;
        const first = opened === 1;
        return sse((push, close) => {
          push(ready(false));
          if (first) setTimeout(close, 300);
        });
      }),
    );
    const view = renderAt('/c/MFC-BJG-01/inventory?sku=SKU-MILK-1');
    await screen.findAllByTestId('unit-row');
    await waitFor(() => expect(screen.getByTestId('stock-live')).toHaveAttribute('data-status', 'reconnecting'));
    const before = stockGets(view.sent).length;
    await waitFor(() => expect(opened).toBe(2), { timeout: 3_000 });
    await waitFor(() => expect(screen.getByTestId('stock-live')).toHaveAttribute('data-status', 'live'));
    await waitFor(() => expect(stockGets(view.sent).length).toBe(before + 1));
  });

  it('재고 수량이 없는 탭(보충 기준)에서는 스트림을 열지 않는다', async () => {
    const view = renderAt('/c/MFC-BJG-01/inventory?tab=policies');
    await wait(500);
    expect(view.gets('/stock-stream')).toHaveLength(0);
    expect(screen.queryByTestId('stock-live')).not.toBeInTheDocument();
  });
});
