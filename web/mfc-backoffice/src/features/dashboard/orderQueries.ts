// 센터 대시보드 주문 수·매출 — order-service 0.20.0(O-11, 사용자 2026-11-23 "센터 관리자에게 연다"):
// - 추이 `GET /orders/metrics/series` — bucket HOUR(시간 칸)·DAY(일·주·월 칸은 일 값을 더함), 93일씩 나눠 읽음. 0건 칸은 오지 않는다 → 0.
// - 요일 × 시간대 `bucket=WEEKDAY_HOUR`(366일까지 한 번) — 서버 평균(avg…)을 그대로.
// - 많이 팔린 상품 `GET /orders/metrics/top-products`(93일 상한 — 넘으면 끝날까지 최근 93일, 카테고리 거르기는 서버).
// - 카테고리 목록 product `GET /categories/tree`(TOP 만), 상품 이름 mfc-inventory `GET /mfcs/{mfcId}/stocks?sku=`(productName — 없으면 SKU).
// 매출 = 승인 금액(환불 빼지 않음). sku·categoryId 로 거르면 서버가 approvedAmount 를 null 로 주고 그 상품 줄 금액(lineAmount)·수량(qty)만 — 섞지 않는다.
import { useQuery } from '@tanstack/react-query';

import { request } from '@pmart/web-core';
import { useApi } from '../../app/ApiContext';
import { OPS_REFRESH_MS } from '../ops/opsQueries';
import { addDays, chunks, spanDays, type Range, type Unit } from './dashboardRules';

/** 주문 지표 기간 상한 — HOUR·DAY·top-products 93일, WEEKDAY_HOUR 366일 */
export const ORDER_CHUNK = 93;

export interface OrderFilter {
  readonly sku: string | null;
  readonly categoryId: string | null;
}

/** 많이 팔린 상품은 나눠 합칠 수 없다(상위가 조각마다 다름) — 93일을 넘으면 끝날까지 최근 93일 */
export const topRangeOf = (r: Range): Range => (spanDays(r) > ORDER_CHUNK ? { from: addDays(r.to, -(ORDER_CHUNK - 1)), to: r.to } : r);

/** 추이 칸 key — HOUR 는 "YYYY-MM-DDTHH"(칸 key 와 같음), DAY 는 날짜 */
export const seriesKey = (start: string, unit: Unit) => (unit === 'hour' ? start.slice(0, 13) : start.slice(0, 10));

const filterQuery = (f: OrderFilter) => ({ ...(f.sku ? { sku: f.sku } : f.categoryId ? { categoryId: f.categoryId } : {}) });

export function useOrderTrend(mfcId: string, r: Range, unit: Unit, f: OrderFilter, enabled: boolean) {
  const api = useApi();
  const common = { refetchInterval: OPS_REFRESH_MS, enabled } as const;
  const bucket = unit === 'hour' ? ('HOUR' as const) : ('DAY' as const);
  const series = useQuery({
    ...common,
    queryKey: ['dashboard', mfcId, 'order-series', r.from, r.to, bucket, f.sku, f.categoryId],
    queryFn: async () => {
      const parts = await Promise.all(
        chunks(r, ORDER_CHUNK).map((c) => request('GET', api.order.GET('/orders/metrics/series', { params: { query: { from: c.from, to: c.to, mfcId, bucket, ...filterQuery(f) } } }))),
      );
      return parts.flatMap((p) => p.items);
    },
  });
  const heat = useQuery({
    ...common,
    queryKey: ['dashboard', mfcId, 'order-heat', r.from, r.to, f.sku, f.categoryId],
    queryFn: async () => (await request('GET', api.order.GET('/orders/metrics/series', { params: { query: { from: r.from, to: r.to, mfcId, bucket: 'WEEKDAY_HOUR', ...filterQuery(f) } } }))).items,
  });
  const tr = topRangeOf(r);
  // 상품 고르기 칸도 이 목록(상위 50)으로 — 카테고리만 서버에서 거른다(상품을 고르면 그 상품이 든 카테고리 목록 그대로)
  const top = useQuery({
    ...common,
    queryKey: ['dashboard', mfcId, 'order-top', tr.from, tr.to, f.categoryId],
    queryFn: async () =>
      (await request('GET', api.order.GET('/orders/metrics/top-products', { params: { query: { from: tr.from, to: tr.to, mfcId, limit: 50, ...(f.categoryId ? { categoryId: f.categoryId } : {}) } } }))).items,
  });
  const categories = useQuery({
    enabled,
    staleTime: 10 * 60_000,
    queryKey: ['category-tree'],
    queryFn: async () =>
      ((await request('GET', api.product.GET('/categories/tree', {}))).nodes ?? []).filter((n) => n.level === 'TOP').sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0)),
  });
  const skus = [...new Set([...(top.data ?? []).map((x) => x.sku), ...(f.sku ? [f.sku] : [])])].sort();
  const names = useQuery({
    enabled: enabled && skus.length > 0,
    staleTime: 10 * 60_000,
    queryKey: ['dashboard', mfcId, 'sku-names', skus.join(',')],
    queryFn: async () => {
      const r2 = await request('GET', api.inventory.GET('/mfcs/{mfcId}/stocks', { params: { path: { mfcId }, query: { sku: skus } } }));
      return new Map(r2.items.flatMap((x) => (x.productName ? [[x.sku, x.productName] as const] : [])));
    },
  });
  return { series, heat, top, tr, categories, names };
}
