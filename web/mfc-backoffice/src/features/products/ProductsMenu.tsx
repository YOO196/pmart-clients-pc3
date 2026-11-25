// 상품 관리(2026-11-25 사용자 "재고탭에서 빼서 상품관리 탭으로 밖에 두자. 센터 취급물품에 대한 거") — `/c/:mfcId/products`.
// 이 센터가 파는 상품(취급 ON/OFF·새 상품)과 본사 상품 불러오기. 화면 본문은 재고 메뉴에 있던 것을 그대로 쓴다(features/inventory HandlingsTab·CatalogImport).
import { HandlingsTab } from '../inventory/InventoryPages';
import { messages } from '../../shared/messages';

export function ProductsMenu({ mfcId }: { readonly mfcId: string }) {
  return (
    <section className="space-y-4">
      <h1>{messages.menus.products}</h1>
      <HandlingsTab mfcId={mfcId} />
    </section>
  );
}
