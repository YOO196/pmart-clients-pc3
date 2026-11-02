// 상품 JSON 읽기. 상품 등록 폼의 "상품 JSON 파일로 채우기"가 쓴다.
//
// 받는 모양:
//  1. seed-v1 product.json — { product: { internalName, primaryCategory: [이름...], categories: [[이름...]], saleState }, skus: [...] }
//     (카테고리는 B마트 이름 경로라 ID 가 없다 → 트리에서 이름 경로가 같은 노드를 찾고, 없으면 categoryPaths 로 보내 서버가 매핑한다)
//  2. 계약 ProductDraftInput 모양 — { product: { internalName, primaryCategoryId, categoryIds, categoryPaths }, skus: [...] }
import type { SaleUnitType, StorageType } from '../../api/models';

export interface SkuJson {
  readonly unitType: SaleUnitType;
  readonly unitsPerSku: number;
  readonly weightG?: number;
  readonly volumeMl?: number;
  readonly storageType?: StorageType;
  readonly alcohol?: boolean;
  readonly barcodes: readonly string[];
  readonly unitsPerBox?: number;
  readonly ti?: number;
  readonly hi?: number;
  readonly boxesPerPallet?: number;
}

export interface ProductJson {
  readonly internalName?: string;
  readonly primaryCategoryId?: string;
  readonly categoryIds: readonly string[];
  /** 이름 경로("상위 > 하위"). 첫 번째가 대표 후보다. */
  readonly categoryPaths: readonly string[];
  readonly skus: readonly SkuJson[];
}

export class ProductJsonError extends Error {}

const SEP = ' > ';

function isRecord(x: unknown): x is Record<string, unknown> {
  return typeof x === 'object' && x !== null && !Array.isArray(x);
}
const str = (x: unknown): string | undefined => (typeof x === 'string' && x.trim() ? x.trim() : undefined);
const num = (x: unknown): number | undefined => {
  if (typeof x === 'number' && Number.isFinite(x) && x >= 0) return x;
  if (typeof x === 'string' && /^\d+$/.test(x.trim())) return Number(x.trim());
  return undefined;
};
const strList = (x: unknown): string[] => (Array.isArray(x) ? x.map(str).filter((s): s is string => s !== undefined) : []);

/** 이름 경로: ["상위","하위"] 또는 "상위 > 하위" → "상위 > 하위" */
function pathOf(x: unknown): string | undefined {
  if (Array.isArray(x)) {
    const parts = strList(x);
    return parts.length > 0 ? parts.join(SEP) : undefined;
  }
  return str(x);
}

function skuOf(x: unknown, index: number): SkuJson {
  if (!isRecord(x)) throw new ProductJsonError(`skus[${index}] 가 객체가 아니에요`);
  const unitType = x['unitType'] === 'B' ? 'B' : 'E';
  const storage = str(x['storageType'] ?? (isRecord(x['logistics']) ? x['logistics']['storageType'] : undefined));
  const logistics = isRecord(x['logistics']) ? x['logistics'] : {};
  const opt = <T,>(v: T | undefined, key: string): Record<string, T> => (v === undefined ? {} : { [key]: v });
  return {
    unitType,
    unitsPerSku: num(x['unitsPerSku']) ?? 1,
    ...opt(num(x['weightG']), 'weightG'),
    ...opt(num(x['volumeMl']), 'volumeMl'),
    ...(storage === 'AMBIENT' || storage === 'CHILLED' || storage === 'FROZEN' ? { storageType: storage } : {}),
    ...(typeof x['alcohol'] === 'boolean' ? { alcohol: x['alcohol'] } : {}),
    barcodes: strList(x['barcodes']),
    ...opt(num(logistics['unitsPerBox']), 'unitsPerBox'),
    ...opt(num(logistics['ti']), 'ti'),
    ...opt(num(logistics['hi']), 'hi'),
    ...opt(num(logistics['boxesPerPallet']), 'boxesPerPallet'),
  };
}

export function parseProductJson(raw: string): ProductJson {
  let data: unknown;
  try {
    data = JSON.parse(raw) as unknown;
  } catch {
    throw new ProductJsonError('JSON 형식이 아니에요');
  }
  if (!isRecord(data)) throw new ProductJsonError('객체여야 해요');
  const product = isRecord(data['product']) ? data['product'] : data;
  const skusRaw = data['skus'];
  const skus = Array.isArray(skusRaw) ? skusRaw.map(skuOf) : [];

  const primaryPath = pathOf(product['primaryCategory']);
  const paths = [
    ...(primaryPath ? [primaryPath] : []),
    ...(Array.isArray(product['categories']) ? product['categories'].map(pathOf).filter((p): p is string => p !== undefined) : []),
    ...strList(product['categoryPaths']),
  ];
  const internalName = str(product['internalName']);
  const primaryCategoryId = str(product['primaryCategoryId']);
  const result: ProductJson = {
    ...(internalName === undefined ? {} : { internalName }),
    ...(primaryCategoryId === undefined ? {} : { primaryCategoryId }),
    categoryIds: strList(product['categoryIds']),
    categoryPaths: [...new Set(paths)],
    skus,
  };
  if (!result.internalName && skus.length === 0 && result.categoryPaths.length === 0 && result.categoryIds.length === 0) {
    throw new ProductJsonError('상품 정보(product·skus)가 없어요');
  }
  return result;
}
