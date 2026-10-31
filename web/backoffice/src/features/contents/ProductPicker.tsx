// 승인된 상품 고르기(콘텐츠 등록용). 목록은 GET /products 를 쪽 단위로 불러온다.
// 서버 검색어 파라미터가 없어(BR-31) 불러온 범위 안에서만 거른다. 다 불러오지 않았으면 "없음"으로 단정하지 않는다.
import { useInfiniteQuery } from '@tanstack/react-query';
import { useId, useMemo, useRef, useState } from 'react';

import { PmartFailure } from '../../api/failure';
import { request } from '../../api/pmartFetch';
import { useApi } from '../../app/ApiContext';
import { FailureAlert } from '../../shared/Feedback';
import { messages as m } from '../../shared/messages';

const PAGE_SIZE = 200;

export function ProductPicker({
  label,
  value,
  onChange,
}: {
  readonly label: string;
  readonly value: string;
  readonly onChange: (productId: string) => void;
}) {
  const api = useApi();
  const listId = useId();
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(0);
  const closeTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const query = useInfiniteQuery({
    queryKey: ['product', 'picker'],
    enabled: open,
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
  const term = value.trim().toLowerCase();
  const matches = useMemo(
    () =>
      term
        ? loaded.filter((p) =>
            [p.productId, p.internalName, p.baseProductId].some((x) => x?.toLowerCase().includes(term)),
          )
        : loaded,
    [loaded, term],
  );

  const pick = (productId: string) => {
    onChange(productId);
    setOpen(false);
  };
  const show = () => {
    if (closeTimer.current) clearTimeout(closeTimer.current);
    setOpen(true);
  };
  // 목록 항목을 누를 시간을 준 뒤 닫는다.
  const hideSoon = () => {
    closeTimer.current = setTimeout(() => setOpen(false), 150);
  };

  return (
    <div className="relative flex flex-col gap-1 text-sm" onMouseEnter={show} onMouseLeave={hideSoon}>
      <label htmlFor={`${listId}-input`}>{label}</label>
      <input
        id={`${listId}-input`}
        role="combobox"
        aria-expanded={open}
        aria-controls={listId}
        aria-autocomplete="list"
        autoComplete="off"
        placeholder={m.contents.pickerPlaceholder}
        className="input input-sm w-full"
        value={value}
        onFocus={show}
        onBlur={hideSoon}
        onChange={(e) => {
          onChange(e.target.value);
          setActive(0);
          setOpen(true);
        }}
        onKeyDown={(e) => {
          if (e.key === 'ArrowDown') {
            e.preventDefault();
            setOpen(true);
            setActive((i) => Math.min(i + 1, Math.max(matches.length - 1, 0)));
          } else if (e.key === 'ArrowUp') {
            e.preventDefault();
            setActive((i) => Math.max(i - 1, 0));
          } else if (e.key === 'Enter' && open && matches[active]?.productId) {
            e.preventDefault();
            pick(matches[active].productId);
          } else if (e.key === 'Escape') {
            setOpen(false);
          }
        }}
      />
      {open && (
        <div className="absolute top-full z-20 mt-1 w-full rounded-box bg-base-100 p-2 shadow-lg">
          {query.isPending && <p className="p-2 opacity-70">{m.loading}</p>}
          {query.error instanceof PmartFailure && <FailureAlert failure={query.error} />}
          {query.isSuccess && (
            <>
              <ul id={listId} role="listbox" aria-label={m.contents.pickerList} className="max-h-64 overflow-y-auto">
                {matches.map((p, i) => (
                  <li
                    key={p.productId}
                    role="option"
                    aria-selected={i === active}
                    className={`cursor-pointer rounded px-2 py-1 ${i === active ? 'bg-base-200' : ''}`}
                    onMouseDown={(e) => e.preventDefault()}
                    onMouseEnter={() => setActive(i)}
                    onClick={() => p.productId && pick(p.productId)}
                  >
                    <span className="font-medium">{p.internalName ?? m.none}</span>
                    <span className="ml-2 opacity-70">{p.productId}</span>
                    {p.saleState && <span className="ml-2 opacity-70">{m.products.saleStateName[p.saleState]}</span>}
                  </li>
                ))}
              </ul>
              {matches.length === 0 && (
                <p className="p-2 opacity-70">
                  {query.hasNextPage ? m.contents.pickerNoneYet(loaded.length) : m.contents.pickerNone}
                </p>
              )}
              {query.hasNextPage && (
                <button
                  type="button"
                  className="btn btn-ghost btn-xs mt-1"
                  disabled={query.isFetchingNextPage}
                  onMouseDown={(e) => e.preventDefault()}
                  onClick={() => void query.fetchNextPage()}
                >
                  {m.contents.pickerMore(loaded.length)}
                </button>
              )}
            </>
          )}
        </div>
      )}
    </div>
  );
}
