// 상품 사진·고객용 상품명(product-content `GET /product-contents?productIds=` — 최대 100개씩, 게시된 상품만) + 목록/카드 보기 전환.
// 상품 관리(2026-11-25 사용자 "상품 사진이 함께 올라가는 카드형과 리스트형 두가지 방식으로 볼 수 있게"). 미게시 상품은 사진 없이 이름 첫 글자 칸.
import { useQuery } from '@tanstack/react-query';
import { useSearchParams } from 'react-router';

import { request } from '@pmart/web-core';
import { contentImageUrl } from '../api/client';
import { useApi } from '../app/ApiContext';
import { messages } from './messages';

const m = messages.productCards;
const CHUNK = 100;

export interface ProductCardInfo {
  readonly name: string | null;
  readonly imageUrl: string | null;
}

/** productId → 이름·대표 사진. 같은 상품 묶음은 한 번만 읽는다(10분). 실패해도 화면은 사진 없이 돈다 */
export function useProductCards(productIds: readonly (string | null | undefined)[]) {
  const api = useApi();
  const ids = [...new Set(productIds.filter((x): x is string => !!x))].sort();
  return useQuery({
    queryKey: ['product-cards', ids],
    enabled: ids.length > 0,
    staleTime: 10 * 60_000,
    queryFn: async () => {
      const out = new Map<string, ProductCardInfo>();
      for (let i = 0; i < ids.length; i += CHUNK) {
        // 계약 productIds 는 style form·explode false(쉼표 하나로) — openapi-fetch 기본(같은 이름 반복)이 아니게
        const r = await request('GET', api.content.GET('/product-contents', { params: { query: { productIds: ids.slice(i, i + CHUNK) } }, querySerializer: { array: { style: 'form', explode: false } } }));
        for (const c of r.items ?? []) if (c.productId) out.set(c.productId, { name: c.name ?? null, imageUrl: c.mainImage?.url ?? null });
      }
      return out;
    },
  });
}

/** 대표 사진(정사각) — 없으면 이름 첫 글자. size = 화면 px(카드 160·목록 40) */
export function ProductThumb({ info, fallback, size }: { readonly info: ProductCardInfo | undefined; readonly fallback: string; readonly size: 'card' | 'row' }) {
  const src = contentImageUrl(info?.imageUrl, size === 'card' ? 480 : 240);
  const box = size === 'card' ? 'aspect-square w-full' : 'h-10 w-10';
  return src ? (
    <img src={src} alt="" loading="lazy" className={`${box} shrink-0 rounded-field border border-base-300 bg-base-200 object-cover`} />
  ) : (
    <span aria-hidden="true" className={`${box} flex shrink-0 items-center justify-center rounded-field border border-base-300 bg-base-200 font-bold text-base-content/40 ${size === 'card' ? 'text-3xl' : 'text-sm'}`}>
      {(info?.name ?? fallback).slice(0, 1)}
    </span>
  );
}

export type ProductView = 'list' | 'card';

/** 보기 — URL `?view=card`(기본 목록) */
export function useProductView(): [ProductView, (v: ProductView) => void] {
  const [params, setParams] = useSearchParams();
  const view: ProductView = params.get('view') === 'card' ? 'card' : 'list';
  return [
    view,
    (v) => {
      const next = new URLSearchParams(params);
      if (v === 'card') next.set('view', 'card');
      else next.delete('view');
      setParams(next, { replace: true });
    },
  ];
}

export function ViewToggle({ view, onChange }: { readonly view: ProductView; readonly onChange: (v: ProductView) => void }) {
  return (
    <div className="pm-seg" role="group" aria-label={m.viewLabel}>
      {(['list', 'card'] as const).map((v) => (
        <button key={v} type="button" aria-pressed={view === v} onClick={() => onChange(v)}>
          {m.view[v]}
        </button>
      ))}
    </div>
  );
}
