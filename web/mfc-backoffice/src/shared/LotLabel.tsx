// LOT 화면 번호(ADR-0070, 백엔드 요청 clients/mfc-backoffice/2026-11-19-request-display-numbers) — mfc-inventory 0.30.0
// `GET /mfcs/{mfcId}/lot-numbers?lotIds=…`(1~200, 그 센터 운영자). 목록·표의 `LOT-…` 대신 LOT 번호(`L261107000497`).
// - 한 화면의 LOT 을 모아 한 번에 묻는다(같은 틱 요청을 센터마다 200개씩 묶음, LOT 마다 TanStack Query 캐시).
// - 모르는 LOT 은 응답에서 빠진다 → "LOT 번호 없음". 조회 실패 → "LOT 번호 확인 불가"(없는 것과 못 읽은 것을 섞지 않는다). 읽는 동안 "…".
// - 시스템 LOT ID 는 title(마우스 올림)과 상세의 시스템 번호 칸에만.
import { useQuery } from '@tanstack/react-query';
import { useParams } from 'react-router';

import { request } from '@pmart/web-core';
import type { Api } from '../api/client';
import type { operations } from '../api/generated/mfc-inventory';
import { useApi } from '../app/ApiContext';
import { messages } from './messages';

type LotNumber = operations['getLotNumbers']['responses'][200]['content']['application/json']['items'][number];

const MAX = 200;

interface Waiter {
  readonly resolve: (v: LotNumber | null) => void;
  readonly reject: (e: unknown) => void;
}

class LotBatcher {
  private queue = new Map<string, Map<string, Waiter[]>>();
  private scheduled = false;

  constructor(private readonly api: Api) {}

  load(mfcId: string, lotId: string): Promise<LotNumber | null> {
    return new Promise((resolve, reject) => {
      const center = this.queue.get(mfcId) ?? new Map<string, Waiter[]>();
      center.set(lotId, [...(center.get(lotId) ?? []), { resolve, reject }]);
      this.queue.set(mfcId, center);
      if (!this.scheduled) {
        this.scheduled = true;
        setTimeout(() => void this.flush(), 0);
      }
    });
  }

  private async flush() {
    const batch = this.queue;
    this.queue = new Map();
    this.scheduled = false;
    for (const [mfcId, center] of batch) {
      const ids = [...center.keys()];
      for (let i = 0; i < ids.length; i += MAX) {
        const chunk = ids.slice(i, i + MAX);
        try {
          const r = await request('GET', this.api.inventory.GET('/mfcs/{mfcId}/lot-numbers', { params: { path: { mfcId }, query: { lotIds: chunk } } }));
          const byId = new Map(r.items.map((l) => [l.lotId, l]));
          for (const id of chunk) for (const w of center.get(id) ?? []) w.resolve(byId.get(id) ?? null);
        } catch (e) {
          for (const id of chunk) for (const w of center.get(id) ?? []) w.reject(e);
        }
      }
    }
  }
}

const batchers = new WeakMap<Api, LotBatcher>();
const batcherOf = (api: Api) => {
  let b = batchers.get(api);
  if (!b) {
    b = new LotBatcher(api);
    batchers.set(api, b);
  }
  return b;
};

/** LOT 한 칸 — "L261107000497". 센터는 주소(`/c/:mfcId`)에서 */
export function LotLabel({ lotId, lotNo }: { readonly lotId: string | null | undefined; readonly lotNo?: string | null | undefined }) {
  const api = useApi();
  const { mfcId = '' } = useParams();
  const known = lotNo ?? null;
  const q = useQuery({
    queryKey: ['lot-number', mfcId, lotId],
    enabled: !!lotId && !!mfcId && !known,
    staleTime: 10 * 60_000,
    retry: false,
    queryFn: () => batcherOf(api).load(mfcId, lotId ?? ''),
  });
  if (!lotId) return <>{messages.none}</>;
  const no = known ?? q.data?.lotNo ?? null;
  if (no)
    return (
      <span className="font-mono" title={lotId} data-testid="lot-label">
        {no}
      </span>
    );
  const note = q.isError ? messages.lot.failed : q.isSuccess ? messages.lot.missing : '…';
  return (
    <span className={`text-xs ${q.isError ? 'text-warning' : 'text-base-content/50'}`} title={lotId} data-testid="lot-label" data-fallback={q.isError ? 'failed' : q.isSuccess ? 'missing' : 'loading'}>
      {note}
    </span>
  );
}
