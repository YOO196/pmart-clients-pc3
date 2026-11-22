// 목(MSW) 전용 — 센터 주문량·매출 값 만들기. order-service 0.20.0(O-11) `GET /orders/metrics/series`·`/top-products` 목과
// product `GET /categories/tree`·mfc-inventory `/mfcs/{mfcId}/stocks` 목(상품 이름)이 쓴다. 화면은 이 파일을 모른다.
// 같은 날짜·시각이면 늘 같은 값(결정적).

export interface SimCategory {
  readonly id: string;
  readonly name: string;
}
export interface SimProduct {
  readonly sku: string;
  readonly name: string;
  readonly category: string;
  /** 1개 값(원) */
  readonly price: number;
  /** 주문 1건에 들어갈 기대 수량 */
  readonly perOrder: number;
}

export const SIM_CATEGORIES: readonly SimCategory[] = [
  { id: 'FRESH', name: '채소·과일' },
  { id: 'DAIRY', name: '우유·유제품' },
  { id: 'MEAT', name: '정육·달걀' },
  { id: 'FROZEN', name: '냉동' },
  { id: 'INSTANT', name: '간편식·라면' },
  { id: 'DRINK', name: '음료·생수' },
  { id: 'HOME', name: '생활용품' },
];

export const SIM_PRODUCTS: readonly SimProduct[] = [
  { sku: 'SKU-BANANA', name: '바나나 1송이', category: 'FRESH', price: 3980, perOrder: 0.22 },
  { sku: 'SKU-TOMATO', name: '토마토 1kg', category: 'FRESH', price: 6900, perOrder: 0.08 },
  { sku: 'SKU-ONION', name: '양파 1.5kg', category: 'FRESH', price: 4500, perOrder: 0.07 },
  { sku: 'SKU-MILK-1L', name: '서울우유 1L', category: 'DAIRY', price: 2980, perOrder: 0.3 },
  { sku: 'SKU-YOGURT', name: '플레인 요거트 4입', category: 'DAIRY', price: 3500, perOrder: 0.1 },
  { sku: 'SKU-TOFU', name: '국산콩 두부 300g', category: 'DAIRY', price: 2500, perOrder: 0.14 },
  { sku: 'SKU-EGG-30', name: '특란 30구', category: 'MEAT', price: 8900, perOrder: 0.12 },
  { sku: 'SKU-PORK', name: '삼겹살 500g', category: 'MEAT', price: 13900, perOrder: 0.07 },
  { sku: 'SKU-DUMPLING', name: '냉동 만두 1kg', category: 'FROZEN', price: 9900, perOrder: 0.08 },
  { sku: 'SKU-ICECREAM', name: '아이스크림 6입', category: 'FROZEN', price: 6000, perOrder: 0.09 },
  { sku: 'SKU-RAMEN-5', name: '라면 5입', category: 'INSTANT', price: 4580, perOrder: 0.16 },
  { sku: 'SKU-RICE-3', name: '즉석밥 3입', category: 'INSTANT', price: 3900, perOrder: 0.13 },
  { sku: 'SKU-WATER-2L', name: '생수 2L 6입', category: 'DRINK', price: 5900, perOrder: 0.18 },
  { sku: 'SKU-COLA', name: '콜라 1.5L', category: 'DRINK', price: 3200, perOrder: 0.1 },
  { sku: 'SKU-TISSUE', name: '물티슈 3입', category: 'HOME', price: 5500, perOrder: 0.06 },
  { sku: 'SKU-DETERGENT', name: '주방세제 1L', category: 'HOME', price: 4900, perOrder: 0.04 },
];

/** 시간대 곡선(점심·저녁 두 봉우리, 새벽 거의 없음) */
const HOUR = [1, 0, 0, 0, 0, 1, 2, 4, 6, 7, 8, 11, 13, 9, 7, 7, 9, 13, 17, 19, 16, 11, 6, 3];
/** 요일(월 0 … 일 6) — 금·토 저녁, 일요일 낮이 많다 */
const WEEKDAY = [0.92, 0.9, 0.95, 0.97, 1.12, 1.24, 1.1];
/** 카테고리별 시간 기울기 — 음료는 낮, 정육은 저녁, 간편식은 밤 */
const CAT_TILT: Readonly<Record<string, (h: number) => number>> = {
  DRINK: (h) => (h >= 12 && h <= 16 ? 1.5 : 0.9),
  MEAT: (h) => (h >= 16 && h <= 20 ? 1.5 : 0.8),
  INSTANT: (h) => (h >= 21 || h <= 1 ? 1.8 : 1),
};

const hash = (s: string) => {
  let x = 2166136261;
  for (let i = 0; i < s.length; i++) x = Math.imul(x ^ s.charCodeAt(i), 16777619);
  return ((x >>> 0) % 10_000) / 10_000;
};
const weekdayOf = (d: string) => (new Date(`${d}T00:00:00Z`).getUTCDay() + 6) % 7;
const dayNum = (d: string) => Date.parse(`${d}T00:00:00Z`) / 86_400_000;

/** 그 날짜·시각의 주문 수(센터 전체) */
export function simOrders(date: string, hour: number): number {
  const t = dayNum(date);
  // 몇 주에 걸친 물결 + 해마다 조금씩 늘어남 + 날짜·시각 잡음
  const season = 1 + 0.12 * Math.sin(t / 11) + 0.0006 * (t - 20_000);
  const noise = 0.8 + 0.4 * hash(`${date}T${hour}`);
  return Math.round(HOUR[hour]! * 1.6 * WEEKDAY[weekdayOf(date)]! * season * noise);
}

export interface SimFilter {
  readonly category?: string | null;
  readonly sku?: string | null;
}

/** 그 날짜·시각의 값 — 거르지 않으면 주문 수·매출, 카테고리면 그 카테고리가 든 주문 수·그 카테고리 매출, 상품이면 판매 수량·그 상품 매출 */
export function simAt(date: string, hour: number, f: SimFilter): { readonly orders: number; readonly amount: number; readonly qty: number } {
  const orders = simOrders(date, hour);
  const prods = SIM_PRODUCTS.filter((p) => (f.sku ? p.sku === f.sku : f.category ? p.category === f.category : true));
  let qty = 0;
  let amount = 0;
  let share = 0;
  for (const p of prods) {
    const tilt = CAT_TILT[p.category]?.(hour) ?? 1;
    const q = Math.round(orders * p.perOrder * tilt * (0.75 + 0.5 * hash(`${p.sku}${date}${hour}`)));
    qty += q;
    amount += q * p.price;
    share += p.perOrder * tilt;
  }
  if (f.sku) return { orders: qty, amount, qty };
  if (f.category) return { orders: Math.min(orders, Math.round(orders * Math.min(1, share))), amount, qty };
  // 전체 매출 = 상품 매출 + 목록에 없는 상품 몫(평균 장바구니 약 2.6만 원)
  return { orders, amount: Math.max(amount, orders * 26_000), qty: Math.max(qty, Math.round(orders * 2.6)) };
}
