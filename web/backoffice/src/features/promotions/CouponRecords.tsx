// 쿠폰 발급 기록(promotion 0.3.1 PRM-1, 2026-11-24 사용자 "만들어") — 고객 상세 "쿠폰"과 행사 상세 "발급 내역"이 같이 쓴다.
// `GET /promotions/coupons?customerId|promotionId&status&source&size&cursor` — 받은 시각 최근 순. 상태·경로는 서버 값 그대로(HELD 를 USED 로 접지 않는다).
// 고객 이름은 응답에 없다 — 행사 기준 목록은 customer `GET /customers?customerIds=`(쉼표 50개까지, 가린 값)로 붙인다. 고객 조회 권한이 없는 역할(마케팅)은 ID 그대로.
// 발급한 직원은 hr employee-labels(StaffName). 조회 실패는 빈 목록으로 보이지 않는다(QueryState).
import { useInfiniteQuery, useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { Link } from 'react-router';

import { request } from '@pmart/web-core';
import { formatSeoul, QueryState, toUiState } from '@pmart/web-ui';
import type { components } from '../../api/generated/promotion';
import { useApi } from '../../app/ApiContext';
import { DataTable, StatusBadge, type Tone } from '../../shared/admin';
import { messages } from '../../shared/messages';
import { StaffName } from '../lookup/parts';

type CouponRecord = components['schemas']['CouponRecord'];
const m = messages.promotions.records;
const STATUSES = ['AVAILABLE', 'HELD', 'USED', 'EXPIRED'] as const;
const SOURCES = ['DOWNLOAD', 'STAFF', 'SIGNUP', 'COMPENSATION'] as const;
const statusTone = (s: CouponRecord['status']): Tone => (s === 'AVAILABLE' ? 'info' : s === 'HELD' ? 'warning' : s === 'USED' ? 'success' : 'ghost');
const discountText = (d: CouponRecord['discount']) => (d.type === 'RATE' ? `${d.value}%${d.maxAmount ? ` (최대 ${d.maxAmount.toLocaleString('ko-KR')}원)` : ''}` : `${d.value.toLocaleString('ko-KR')}원`);

export function CouponRecords({ by, testId }: { readonly by: { readonly customerId: string } | { readonly promotionId: string }; readonly testId?: string }) {
  const api = useApi();
  const forCustomer = 'customerId' in by;
  const [status, setStatus] = useState<(typeof STATUSES)[number] | ''>('');
  const [source, setSource] = useState<(typeof SOURCES)[number] | ''>('');
  const query = useInfiniteQuery({
    queryKey: ['promotions', 'coupon-records', by, status, source],
    queryFn: ({ pageParam }) =>
      request(
        'GET',
        api.promotion.GET('/promotions/coupons', {
          params: { query: { ...by, ...(status ? { status } : {}), ...(source ? { source } : {}), size: 20, ...(pageParam ? { cursor: pageParam } : {}) } },
        }),
      ),
    initialPageParam: undefined as string | undefined,
    getNextPageParam: (last) => last.page.nextCursor ?? undefined,
  });
  const items = query.data?.pages.flatMap((p) => p.items) ?? [];
  // 행사 기준이면 고객 가린 이름(50개씩 — 이 목록 안의 고객만)
  const ids = forCustomer ? [] : [...new Set(items.map((x) => x.customerId))].slice(0, 50);
  const names = useQuery({
    queryKey: ['customers', 'by-ids', ids],
    enabled: ids.length > 0,
    retry: false,
    queryFn: () => request('GET', api.customer.GET('/customers', { params: { query: { customerIds: ids.join(',') } } })),
  });
  const nameOf = (id: string) => {
    const c = names.data?.items?.find((x) => x.customerId === id);
    return c ? [c.nameMasked, c.customerNumber].filter(Boolean).join(' · ') || id : id;
  };
  return (
    <section className="overflow-hidden rounded-box border border-base-300 bg-base-100 shadow-sm" aria-label={forCustomer ? m.titleCustomer : m.titlePromotion} data-testid={testId ?? 'coupon-records'}>
      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-base-300 px-4 py-3">
        <h2 className="text-sm font-semibold">{forCustomer ? m.titleCustomer : m.titlePromotion}</h2>
        <div className="flex flex-wrap items-center gap-2 text-xs">
          <label className="flex items-center gap-1 text-base-content/60">
            {m.status}
            <select className="select select-xs w-28" value={status} onChange={(e) => setStatus(STATUSES.find((x) => x === e.target.value) ?? '')}>
              <option value="">{m.all}</option>
              {STATUSES.map((x) => (
                <option key={x} value={x}>
                  {m.statusName[x]}
                </option>
              ))}
            </select>
          </label>
          <label className="flex items-center gap-1 text-base-content/60">
            {m.source}
            <select className="select select-xs w-32" value={source} onChange={(e) => setSource(SOURCES.find((x) => x === e.target.value) ?? '')}>
              <option value="">{m.all}</option>
              {SOURCES.map((x) => (
                <option key={x} value={x}>
                  {m.sourceName[x]}
                </option>
              ))}
            </select>
          </label>
        </div>
      </div>
      <QueryState state={toUiState(query)} onRetry={() => void query.refetch()}>
        {() =>
          items.length === 0 ? (
            <p className="px-4 py-6 text-center text-sm text-base-content/60">{status || source ? m.emptyFiltered : forCustomer ? m.emptyCustomer : m.emptyPromotion}</p>
          ) : (
            <div className="space-y-2 pb-3">
              <DataTable>
                <thead>
                  <tr>
                    <th>{forCustomer ? m.col.promotion : m.col.customer}</th>
                    <th>{m.col.status}</th>
                    <th>{m.col.source}</th>
                    <th>{m.col.issuedAt}</th>
                    <th>{m.col.validUntil}</th>
                    <th>{m.col.used}</th>
                  </tr>
                </thead>
                <tbody>
                  {items.map((x) => (
                    <tr key={x.couponId} data-testid="coupon-record">
                      <td>
                        {forCustomer ? (
                          <>
                            <Link className="link link-hover font-medium" to={`/promotions/${encodeURIComponent(x.promotionId)}`}>
                              {x.promotionName}
                            </Link>
                            <span className="ml-1.5 text-xs text-base-content/55">{discountText(x.discount)}</span>
                          </>
                        ) : (
                          <Link className="link link-hover" to={`/customers/${encodeURIComponent(x.customerId)}`} title={x.customerId}>
                            {nameOf(x.customerId)}
                          </Link>
                        )}
                      </td>
                      <td>
                        <StatusBadge tone={statusTone(x.status)}>{m.statusName[x.status]}</StatusBadge>
                      </td>
                      <td className="text-sm">
                        <span>{m.sourceName[x.source]}</span>
                        {x.issuedBy && (
                          <span className="ml-1 text-xs text-base-content/55">
                            · <StaffName id={x.issuedBy} />
                          </span>
                        )}
                        {x.issueReason && <p className="max-w-56 truncate text-xs text-base-content/55" title={x.issueReason}>{x.issueReason}</p>}
                      </td>
                      <td className="whitespace-nowrap text-xs">{formatSeoul(x.issuedAt)}</td>
                      <td className="whitespace-nowrap text-xs">{formatSeoul(x.validUntil)}</td>
                      <td className="whitespace-nowrap text-xs">
                        {x.orderId ? (
                          <Link className="link link-hover" to={`/orders/${encodeURIComponent(x.orderId)}`}>
                            {x.status === 'HELD' ? m.heldOrder : m.usedOrder}
                          </Link>
                        ) : (
                          messages.none
                        )}
                        {x.usedAt && <p className="text-base-content/55">{formatSeoul(x.usedAt)}</p>}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </DataTable>
              {query.hasNextPage && (
                <div className="px-4">
                  <button type="button" className="btn btn-xs" disabled={query.isFetchingNextPage} onClick={() => void query.fetchNextPage()}>
                    {m.more}
                  </button>
                </div>
              )}
            </div>
          )
        }
      </QueryState>
    </section>
  );
}
