// 재고 실시간 반영(§4-16) — 스트림 이벤트를 받으면 화면 값을 직접 고치지 않고 그 상품·칸의 재고 조회만 다시 읽는다(서버 값만 보인다).
// 화면 표는 LOT·위치 단위인데 이벤트의 센터 값(H·Q·E·R·A)은 SKU 합이라 줄을 맞출 수 없다.
import { useQueryClient, type Query, type QueryClient } from '@tanstack/react-query';
import { useEffect, useRef, useState } from 'react';

import { API_BASE } from '../../api/client';
import { useApi } from '../../app/ApiContext';
import { messages } from '../../shared/messages';
import { openStockStream, type StockStreamEvent, type StockStreamStatus } from './stockStream';

/** 이벤트를 모아 한 번에 다시 읽는 간격 — 피킹이 몰려도 조회가 줄줄이 나가지 않게 */
export const STOCK_BATCH_MS = 300;
/** 스트림이 살아 있지 않을 때 재고 조회를 다시 읽는 간격(끊김 대비 — 표시 "60초 갱신") */
export const STOCK_FALLBACK_MS = 60_000;

interface Pending {
  all: boolean;
  skus: Set<string>;
  locations: Set<string>;
}

/** 이 센터 재고 조회인지(상품별 재고 · 센터 전체 재고 목록 · 도면 랙 칸별 재고 · 출하 부적격 LOT). pending 이 있으면 바뀐 것만. */
export function isStockQuery(mfcId: string, key: readonly unknown[], pending?: Pending): boolean {
  const [a, b, c, d] = key;
  const all = !pending || pending.all;
  if (a === 'stock' && b === mfcId) return all || pending.skus.has(String(c));
  if (a === 'list' && b === 'stock-units' && c === mfcId) return true;
  if (a === 'unshippable' && b === mfcId) return true;
  if (a === 'floor' && b === mfcId && c === 'stock-units') return all || [...pending.locations].some((l) => l.startsWith(String(d)));
  return false;
}

function invalidate(client: QueryClient, mfcId: string, pending?: Pending) {
  void client.invalidateQueries({
    predicate: (q: Query) => isStockQuery(mfcId, q.queryKey, pending),
  });
}

/** 이 센터 재고 스트림을 열고 상태를 돌려준다. 화면이 닫히면 끊는다. */
export function useStockStream(mfcId: string): StockStreamStatus {
  const api = useApi();
  const client = useQueryClient();
  const [status, setStatus] = useState<StockStreamStatus>('connecting');
  const versions = useRef(new Map<string, number>());

  useEffect(() => {
    versions.current = new Map();
    let pending: Pending | null = null;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const flush = () => {
      if (pending) invalidate(client, mfcId, pending);
      pending = null;
    };
    const queue = (add: (p: Pending) => void) => {
      pending ??= { all: false, skus: new Set(), locations: new Set() };
      add(pending);
      clearTimeout(timer);
      timer = setTimeout(flush, STOCK_BATCH_MS);
    };
    const onEvent = (e: StockStreamEvent) => {
      if ((e.type === 'ready' && !e.resumed) || e.type === 'resync') {
        queue((p) => (p.all = true));
        return;
      }
      if (e.type !== 'stock-changed' || (e.mfcId && e.mfcId !== mfcId)) return;
      // 이어 받기는 앞뒤 10초 여유로 같은 이벤트가 다시 온다 — SKU 마다 지금보다 큰 version 만
      const fresh = (e.items ?? []).filter((i) => i.version > (versions.current.get(i.sku) ?? -1));
      if (fresh.length === 0) return;
      for (const i of fresh) versions.current.set(i.sku, i.version);
      const skus = new Set(fresh.map((i) => i.sku));
      queue((p) => {
        for (const s of skus) p.skus.add(s);
        for (const u of e.units ?? []) if (skus.has(u.sku)) p.locations.add(u.locationCode);
        for (const h of e.holds ?? []) if (skus.has(h.sku)) p.locations.add(h.locationCode);
      });
    };
    const close = openStockStream({
      api,
      mfcId,
      onEvent,
      onStatus: setStatus,
      resume: new URL(API_BASE).origin === globalThis.location.origin,
    });
    return () => {
      close();
      clearTimeout(timer);
    };
  }, [api, client, mfcId]);

  // 살아 있지 않으면 60초마다 다시 읽는다(도면은 원래 60초 갱신이 있어 상품별 재고·목록만 — 같은 조회가 겹치지 않게)
  useEffect(() => {
    if (status === 'live') return;
    const id = setInterval(() => {
      void client.invalidateQueries({
        predicate: (q: Query) => isStockQuery(mfcId, q.queryKey) && q.queryKey[0] !== 'floor',
      });
    }, STOCK_FALLBACK_MS);
    return () => clearInterval(id);
  }, [client, mfcId, status]);

  return status;
}

/** 재고 화면 머리의 작은 글 — 실시간 · 다시 연결 중 · 실시간 끊김(60초 갱신). 사용자 2026-11-24 "응"(연결 상태 표시) */
export function StockLiveStatus({ mfcId }: { readonly mfcId: string }) {
  const status = useStockStream(mfcId);
  const s = messages.stockStream;
  const [text, tone] =
    status === 'live' ? [s.live, 'text-success'] : status === 'off' || status === 'down' ? [s.off, 'text-warning'] : [status === 'connecting' ? s.connecting : s.reconnecting, 'text-base-content/60'];
  return (
    <span role="status" data-testid="stock-live" data-status={status} className={`text-xs font-normal ${tone}`}>
      {text}
    </span>
  );
}
