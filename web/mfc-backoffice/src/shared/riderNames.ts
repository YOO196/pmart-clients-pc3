// 라이더 화면 표기 묶음 조회(rider 0.18.0 `GET /riders/display-names?riderIds=a,b` — 쉼표, 50개까지).
// 같은 틱에 부른 라이더 ID 를 모아 한 번에 묻는다(LotLabel·OperatorLabel 과 같은 방식). 없는 ID 는 응답에서 빠진다 → null.
import { request } from '@pmart/web-core';
import type { Api } from '../api/client';

export interface RiderName {
  readonly riderNumber: string | null;
  readonly nameMasked: string | null;
}

const MAX = 50;

interface Waiter {
  readonly resolve: (v: RiderName | null) => void;
  readonly reject: (e: unknown) => void;
}

class RiderBatcher {
  private queue = new Map<string, Waiter[]>();
  private scheduled = false;

  constructor(private readonly api: Api) {}

  load(riderId: string): Promise<RiderName | null> {
    return new Promise((resolve, reject) => {
      this.queue.set(riderId, [...(this.queue.get(riderId) ?? []), { resolve, reject }]);
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
    const ids = [...batch.keys()];
    for (let i = 0; i < ids.length; i += MAX) {
      const chunk = ids.slice(i, i + MAX);
      try {
        const r = await request('GET', this.api.rider.GET('/riders/display-names', { params: { query: { riderIds: chunk.join(',') } } }));
        const byId = new Map(r.items.map((x) => [x.riderId, { riderNumber: x.riderNumber ?? null, nameMasked: x.nameMasked ?? null }]));
        for (const id of chunk) for (const w of batch.get(id) ?? []) w.resolve(byId.get(id) ?? null);
      } catch (e) {
        for (const id of chunk) for (const w of batch.get(id) ?? []) w.reject(e);
      }
    }
  }
}

const batchers = new WeakMap<Api, RiderBatcher>();

export function loadRiderName(api: Api, riderId: string): Promise<RiderName | null> {
  let b = batchers.get(api);
  if (!b) {
    b = new RiderBatcher(api);
    batchers.set(api, b);
  }
  return b.load(riderId);
}
