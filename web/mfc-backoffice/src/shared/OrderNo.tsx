// 주문 ID → 화면 주문번호(8자리, ADR-0070 — 시스템 ID 는 화면에 내지 않는다).
// 재고 이력(inventory 0.49.0 orderId)에는 번호가 없다 — fulfillment 0.36.0 `GET /work-orders?orderId=` 의 orderNumber(백엔드 #473, 우리 부탁).
// 주문마다 한 번(같은 조회 키). 번호 전 주문·못 찾음은 "주문 번호 없음"(ID 를 대신 내지 않는다), 읽는 중 "…".
import { useQuery } from '@tanstack/react-query';

import { request } from '@pmart/web-core';
import { useApi } from '../app/ApiContext';
import { messages } from './messages';

export function useOrderNumber(orderId: string | null | undefined) {
  const api = useApi();
  return useQuery({
    queryKey: ['order-number', orderId],
    enabled: !!orderId,
    staleTime: 10 * 60_000,
    queryFn: async () => (await request('GET', api.fulfillment.GET('/work-orders', { params: { query: { orderId: orderId! } } }))).orderNumber ?? null,
  });
}

export function OrderNo({ orderId }: { readonly orderId: string | null | undefined }) {
  const q = useOrderNumber(orderId);
  if (!orderId) return <>{messages.none}</>;
  if (q.data) return <span className="font-mono">{q.data}</span>;
  return <span className="text-base-content/60">{q.isPending ? '…' : messages.orderNoUnknown}</span>;
}
