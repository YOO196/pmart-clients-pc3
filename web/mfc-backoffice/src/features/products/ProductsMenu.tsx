// 상품 관리(2026-11-25 사용자 "재고탭에서 빼서 상품관리 탭으로 밖에 두자. 센터 취급물품에 대한 거") — `/c/:mfcId/products`.
// 기본 목록은 본사 상품 연동(2026-11-26 사용자 "본사상품 불러오기 말고 기본적으로 뜨는 상품들이 본사 취급품 연동이면 좋겠어") —
// 본사 상품(product-service)마다 이 센터 취급 여부·켜기/끄기. SKU 하나씩 보던 취급 목록은 칩 `?list=sku`(예전 `?enabled=` 주소도 그쪽).
import { useSearchParams } from 'react-router';

import { CatalogProducts } from '../inventory/CatalogImport';
import { HandlingsTab, NewProductsBanner } from '../inventory/InventoryPages';
import { messages } from '../../shared/messages';

const m = messages.inventory.catalog;

export function ProductsMenu({ mfcId }: { readonly mfcId: string }) {
  const [params, setParams] = useSearchParams();
  const list = params.get('list') === 'sku' || params.has('enabled') ? 'sku' : 'hq';
  const go = (v: 'hq' | 'sku', enabled?: string) => {
    const next = new URLSearchParams(params);
    next.delete('enabled');
    if (v === 'sku') next.set('list', 'sku');
    else next.delete('list');
    if (enabled) next.set('enabled', enabled);
    setParams(next, { replace: true });
  };
  return (
    <section className="space-y-4">
      <h1>{messages.menus.products}</h1>
      <NewProductsBanner mfcId={mfcId} onShow={() => go('sku', 'new')} />
      <div role="radiogroup" aria-label={m.listLabel} className="flex gap-2" data-testid="product-lists">
        {(
          [
            ['hq', m.listHq],
            ['sku', m.listSku],
          ] as const
        ).map(([v, label]) => (
          <button key={v} type="button" role="radio" aria-checked={list === v} className={`btn btn-sm rounded-full ${list === v ? '' : 'btn-ghost border border-base-300'}`} onClick={() => go(v)}>
            {label}
          </button>
        ))}
      </div>
      {list === 'hq' ? <CatalogProducts mfcId={mfcId} /> : <HandlingsTab mfcId={mfcId} />}
    </section>
  );
}
