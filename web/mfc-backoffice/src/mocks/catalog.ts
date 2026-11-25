// 본사 상품 목(product-service — 판매 상태 이름은 product 쪽: TEMPORARILY_SOLD_OUT·SALE_STOPPED(취급 쪽 사본은 TEMP_OUT·DISCONTINUED) `/products`·`/products/{id}`) — 상품 하나에 SKU 하나 이상. 취급 목(db.handlings)은 여기 SKU 를 모두 갖는다(SKU 투영 = 본사 상품 전체).
export interface MockProduct {
  readonly productId: string;
  readonly name: string;
  readonly categoryId: string;
  readonly saleState: 'ON_SALE' | 'TEMPORARILY_SOLD_OUT' | 'SALE_STOPPED';
  readonly skus: readonly string[];
}

export const MOCK_PRODUCTS: readonly MockProduct[] = [
  { productId: 'PRD-MILK', name: '서울우유 1L', categoryId: 'p13-c01', saleState: 'ON_SALE', skus: ['SKU-MILK-1'] },
  { productId: 'PRD-RAMEN', name: '신라면 5입', categoryId: 'p21-c02', saleState: 'ON_SALE', skus: ['SKU-RAMEN-5'] },
  { productId: 'PRD-TOFU', name: '국산콩 두부 300g', categoryId: 'p13-c04', saleState: 'ON_SALE', skus: ['SKU-TOFU'] },
  { productId: 'PRD-ICE', name: '바닐라 아이스크림', categoryId: 'p12-c04', saleState: 'ON_SALE', skus: ['SKU-ICE'] },
  { productId: 'PRD-CHICKEN', name: '냉동 닭가슴살', categoryId: 'p12-c02', saleState: 'ON_SALE', skus: ['SKU-CHICKEN'] },
  { productId: 'PRD-DUMPLING', name: '왕만두 1kg', categoryId: 'p12-c03', saleState: 'ON_SALE', skus: ['SKU-DUMPLING'] },
  { productId: 'PRD-PIZZA', name: '냉동 피자', categoryId: 'p12-c03', saleState: 'ON_SALE', skus: ['SKU-PIZZA'] },
  { productId: 'PRD-WATER', name: '생수 2L', categoryId: 'p21-c05', saleState: 'ON_SALE', skus: ['SKU-WATER-2L', 'SKU-WATER-6'] },
  { productId: 'PRD-COLA', name: '콜라 1.5L', categoryId: 'p21-c05', saleState: 'TEMPORARILY_SOLD_OUT', skus: ['SKU-COLA-1'] },
  { productId: 'PRD-NEW-1', name: '그릭요거트 플레인', categoryId: 'p13-c02', saleState: 'ON_SALE', skus: ['SKU-NEW-1'] },
  { productId: 'PRD-NEW-2', name: '콤부차 레몬', categoryId: 'p21-c05', saleState: 'ON_SALE', skus: ['SKU-NEW-2'] },
  { productId: 'PRD-DISC', name: '단종 과자', categoryId: 'p21-c01', saleState: 'SALE_STOPPED', skus: ['SKU-DISC-3'] },
  { productId: 'PRD-OLD', name: '옛 묶음 상품', categoryId: 'p21-c01', saleState: 'ON_SALE', skus: ['SKU-OLD-9'] },
];

export const productOfSku = (sku: string) => MOCK_PRODUCTS.find((p) => p.skus.includes(sku));
