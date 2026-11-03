// 승인된 상품 고르기(콘텐츠 등록용). 검색·필터 없는 드롭다운(사용자 결정 2026-11-02).
// 목록은 GET /products 를 쪽 단위로 불러온다. 다 불러오지 않았으면 "더 불러오기"를 보인다.
import { useInfiniteQuery } from '@tanstack/react-query';
import { useId, useMemo } from 'react';

import { PmartFailure } from '../../api/failure';
import type { ProductSummary } from '../../api/models';
import { request } from '../../api/pmartFetch';
import { useApi } from '../../app/ApiContext';
import { FailureAlert } from '../../shared/Feedback';
import { messages as m } from '../../shared/messages';

const PAGE_SIZE = 200;

export function ProductPicker({
  label,
  value,
  onChange,
  onClear,
}: {
  readonly label: string;
  readonly value: string;
  /** 고른 상품. 목록에 없는 ID(상품 상세에서 넘어온 값 등)면 product 는 없다. */
  readonly onChange: (productId: string, product?: ProductSummary) => void;
  /** 상품이 골라져 있을 때 오른쪽 X — 폼 전체를 비운다. */
  readonly onClear?: () => void;
}) {
  const api = useApi();
  const selectId = useId();

  const query = useInfiniteQuery({
    queryKey: ['product', 'picker'],
    initialPageParam: '',
    queryFn: ({ pageParam }) =>
      request(
        'GET',
        api.product.GET('/products', {
          params: { query: { size: PAGE_SIZE, ...(pageParam ? { cursor: pageParam } : {}) } },
        }),
      ),
    getNextPageParam: (last) => last.page?.nextCursor ?? undefined,
  });

  const loaded = useMemo(() => query.data?.pages.flatMap((p) => p.items ?? []) ?? [], [query.data]);
  const known = loaded.some((p) => p.productId === value);

  return (
    <div className="flex flex-col gap-1 text-sm">
      <label htmlFor={selectId}>{label}</label>
      {/* X 는 드롭다운 상자 안(오른쪽 화살표 왼쪽)에 겹쳐 둔다. */}
      <div className="relative">
        <select
          id={selectId}
          className={`select select-sm w-full${value && onClear ? ' pr-14' : ''}`}
          value={value}
          disabled={query.isPending}
          onChange={(e) => {
            const id = e.target.value;
            onChange(
              id,
              loaded.find((p) => p.productId === id),
            );
          }}
        >
          <option value="">{query.isPending ? m.loading : m.contents.pickerSelect}</option>
          {/* 목록에 없는 값(상품 상세에서 넘어온 ID 등)도 선택된 채로 보인다 */}
          {value && !known && <option value={value}>{value}</option>}
          {loaded.map((p) => (
            <option key={p.productId} value={p.productId ?? ''}>
              {`${p.internalName ?? m.none} · ${p.productId ?? ''}${p.saleState ? ` · ${m.products.saleStateName[p.saleState]}` : ''}`}
            </option>
          ))}
        </select>
        {value && onClear && (
          <button
            type="button"
            className="btn btn-ghost btn-xs btn-circle absolute top-1/2 right-8 -translate-y-1/2"
            aria-label={m.contents.clearAll}
            title={m.contents.clearAll}
            onClick={onClear}
          >
            ✕
          </button>
        )}
      </div>
      {query.error instanceof PmartFailure && <FailureAlert failure={query.error} />}
      {query.hasNextPage && (
        <button type="button" className="btn btn-ghost btn-xs self-start" disabled={query.isFetchingNextPage} onClick={() => void query.fetchNextPage()}>
          {m.contents.pickerMore(loaded.length)}
        </button>
      )}
    </div>
  );
}
