// 상품 초안 입력(계약 ProductDraftInput). 카테고리는 발효된 트리에서 고르고(대표 1·노출 여러 개), 대표 카테고리의 필터 옵션을
// 고르며, SKU 는 여러 개(물류 규격 포함). seed-v1 product.json 으로 채울 수 있다. 빈 칸은 보내지 않는다(0 으로 채우지 않음).
import { useQuery } from '@tanstack/react-query';
import { useMemo, useState } from 'react';

import { PmartFailure } from '../../api/failure';
import { STORAGE_TYPES, type CategoryNode, type ProductDraftInput, type SaleUnitType, type StorageType } from '../../api/models';
import { request } from '../../api/pmartFetch';
import { useApi } from '../../app/ApiContext';
import { FailureAlert } from '../../shared/Feedback';
import { messages as m } from '../../shared/messages';
import { parseProductJson, ProductJsonError, type SkuJson } from './productJson';

interface SkuRow {
  unitType: SaleUnitType;
  unitsPerSku: string;
  weightG: string;
  volumeMl: string;
  storageType: StorageType | '';
  alcohol: boolean;
  barcodes: string;
  unitsPerBox: string;
  ti: string;
  hi: string;
  boxesPerPallet: string;
}

interface FormValues {
  internalName: string;
  primaryCategoryId: string;
  categoryIds: string[];
  /** 트리에서 못 찾은 이름 경로(JSON). 서버가 이름으로 매핑한다(계약 categoryPaths). */
  categoryPaths: string[];
  /** filterGroupId → 고른 옵션 */
  filterOptions: Record<string, string[]>;
  skus: SkuRow[];
}

const list = (s: string) =>
  s
    .split(',')
    .map((x) => x.trim())
    .filter((x) => x.length > 0);
const int = (s: string): number | undefined => (/^\d+$/.test(s.trim()) ? Number(s.trim()) : undefined);
const numText = (n: number | undefined | null) => (n === undefined || n === null ? '' : String(n));

const emptySku = (): SkuRow => ({
  unitType: 'E',
  unitsPerSku: '1',
  weightG: '',
  volumeMl: '',
  storageType: '',
  alcohol: false,
  barcodes: '',
  unitsPerBox: '',
  ti: '',
  hi: '',
  boxesPerPallet: '',
});

const emptyValues = (): FormValues => ({
  internalName: '',
  primaryCategoryId: '',
  categoryIds: [],
  categoryPaths: [],
  filterOptions: {},
  skus: [emptySku()],
});

function skuRowOf(s: ProductDraftInput['skus'][number] | SkuJson): SkuRow {
  const l = 'logistics' in s ? s.logistics : undefined;
  const j = s as Partial<SkuJson>;
  return {
    unitType: s.unitType,
    unitsPerSku: String(s.unitsPerSku),
    weightG: numText(s.weightG),
    volumeMl: numText(s.volumeMl),
    storageType: s.storageType ?? l?.storageType ?? '',
    alcohol: s.alcohol ?? false,
    barcodes: (s.barcodes ?? []).join(', '),
    unitsPerBox: numText(l?.unitsPerBox ?? j.unitsPerBox),
    ti: numText(l?.ti ?? j.ti),
    hi: numText(l?.hi ?? j.hi),
    boxesPerPallet: numText(l?.boxesPerPallet ?? j.boxesPerPallet),
  };
}

function toValues(input: ProductDraftInput | undefined): FormValues {
  if (!input) return emptyValues();
  const filterOptions: Record<string, string[]> = {};
  for (const f of input.filterOptions ?? []) (filterOptions[f.filterGroupId] ??= []).push(f.option);
  return {
    internalName: input.product.internalName,
    primaryCategoryId: input.product.primaryCategoryId ?? '',
    categoryIds: input.product.categoryIds ?? [],
    categoryPaths: input.product.categoryPaths ?? [],
    filterOptions,
    skus: input.skus.length > 0 ? input.skus.map(skuRowOf) : [emptySku()],
  };
}

function toInput(v: FormValues, base: ProductDraftInput | undefined): ProductDraftInput {
  const categoryIds = v.categoryIds.filter((id) => id !== v.primaryCategoryId);
  const filterOptions = Object.entries(v.filterOptions).flatMap(([filterGroupId, options]) => options.map((option) => ({ filterGroupId, option })));
  // 원천 정보(baseProductKey·saleState 등)는 두고, 카테고리는 폼 값으로 다시 정한다.
  const baseProduct = { ...(base?.product ?? { internalName: '' }) };
  delete baseProduct.primaryCategoryId;
  delete baseProduct.categoryIds;
  delete baseProduct.categoryPaths;
  return {
    ...(base?.sourceSystem ? { sourceSystem: base.sourceSystem } : {}),
    ...(base?.sourceKey ? { sourceKey: base.sourceKey } : {}),
    ...(base?.derivedFields ? { derivedFields: base.derivedFields } : {}),
    product: {
      ...baseProduct,
      internalName: v.internalName.trim(),
      ...(v.primaryCategoryId ? { primaryCategoryId: v.primaryCategoryId } : {}),
      ...(categoryIds.length > 0 ? { categoryIds } : {}),
      // ID 를 하나도 못 정했을 때만 이름 경로를 보낸다(서버 매핑).
      ...(!v.primaryCategoryId && categoryIds.length === 0 && v.categoryPaths.length > 0 ? { categoryPaths: v.categoryPaths } : {}),
    },
    skus: v.skus.map((s) => {
      const weightG = int(s.weightG);
      const volumeMl = int(s.volumeMl);
      const barcodes = list(s.barcodes);
      const logistics: Record<'unitsPerBox' | 'ti' | 'hi' | 'boxesPerPallet', number> = {} as never;
      for (const k of ['unitsPerBox', 'ti', 'hi', 'boxesPerPallet'] as const) {
        const n = int(s[k]);
        if (n !== undefined) logistics[k] = n;
      }
      return {
        unitType: s.unitType,
        unitsPerSku: int(s.unitsPerSku) ?? 1,
        ...(weightG === undefined ? {} : { weightG }),
        ...(volumeMl === undefined ? {} : { volumeMl }),
        ...(s.storageType ? { storageType: s.storageType } : {}),
        alcohol: s.alcohol,
        ...(barcodes.length > 0 ? { barcodes } : {}),
        ...(Object.keys(logistics).length > 0 ? { logistics } : {}),
      };
    }),
    ...(filterOptions.length > 0 ? { filterOptions } : {}),
  };
}

const byPath = (a: CategoryNode, b: CategoryNode) => (a.path ?? a.name).localeCompare(b.path ?? b.name, 'ko');

export function ProductDraftForm({
  initial,
  submitLabel,
  busy,
  onSubmit,
}: {
  readonly initial?: ProductDraftInput;
  readonly submitLabel: string;
  readonly busy: boolean;
  readonly onSubmit: (input: ProductDraftInput) => void;
}) {
  const api = useApi();
  const [v, setV] = useState<FormValues>(() => toValues(initial));
  const [note, setNote] = useState<{ ok: boolean; text: string } | null>(null);
  const set = <K extends keyof FormValues>(k: K, value: FormValues[K]) => setV((prev) => ({ ...prev, [k]: value }));
  const setSku = (i: number, patch: Partial<SkuRow>) =>
    setV((prev) => ({ ...prev, skus: prev.skus.map((s, j) => (j === i ? { ...s, ...patch } : s)) }));

  const tree = useQuery({
    queryKey: ['product', 'category-tree'],
    queryFn: () => request('GET', api.product.GET('/categories/tree', {})),
  });
  const nodes = useMemo(() => [...(tree.data?.nodes ?? [])].sort(byPath), [tree.data]);
  const nodeById = useMemo(() => new Map(nodes.map((n) => [n.categoryId, n])), [nodes]);
  const label = (id: string) => nodeById.get(id)?.path ?? nodeById.get(id)?.name ?? id;

  const filters = useQuery({
    queryKey: ['product', 'category-filters', v.primaryCategoryId],
    enabled: v.primaryCategoryId !== '',
    queryFn: () =>
      request('GET', api.product.GET('/categories/{categoryId}/filters', { params: { path: { categoryId: v.primaryCategoryId } } })),
  });
  const groups = filters.data?.groups ?? [];

  const toggleFilter = (groupId: string, option: string, on: boolean) =>
    setV((prev) => {
      const cur = prev.filterOptions[groupId] ?? [];
      const next = on ? [...new Set([...cur, option])] : cur.filter((o) => o !== option);
      return { ...prev, filterOptions: { ...prev.filterOptions, [groupId]: next } };
    });

  /** JSON 으로 채운다. 카테고리 이름 경로는 트리에서 같은 path 를 찾고, 없으면 categoryPaths 로 남긴다. */
  const fillFromJson = async (file: File | undefined) => {
    if (!file) return;
    try {
      const p = parseProductJson(await file.text());
      const pathToId = new Map(nodes.filter((n) => n.path).map((n) => [n.path!, n.categoryId]));
      const matched = p.categoryPaths.map((path) => pathToId.get(path)).filter((id): id is string => id !== undefined);
      const pending = p.categoryPaths.filter((path) => !pathToId.has(path));
      const primary = p.primaryCategoryId ?? matched[0] ?? '';
      const ids = [...new Set([...p.categoryIds, ...matched])].filter((id) => id !== primary);
      setV((prev) => ({
        ...prev,
        internalName: p.internalName ?? prev.internalName,
        primaryCategoryId: primary || prev.primaryCategoryId,
        categoryIds: ids.length > 0 ? ids : prev.categoryIds,
        categoryPaths: pending,
        skus: p.skus.length > 0 ? p.skus.map(skuRowOf) : prev.skus,
      }));
      setNote({ ok: true, text: m.products.jsonFilled(p.skus.length, matched.length + (p.primaryCategoryId ? 1 : 0) + p.categoryIds.length, pending.length) });
    } catch (e) {
      setNote({ ok: false, text: m.products.jsonInvalid(e instanceof ProductJsonError ? e.message : String(e)) });
    }
  };

  const clearAll = () => {
    setV(emptyValues());
    setNote(null);
  };

  const numField = (i: number, k: 'unitsPerSku' | 'weightG' | 'volumeMl' | 'unitsPerBox' | 'ti' | 'hi' | 'boxesPerPallet', text: string) => (
    <label className="flex flex-col gap-1 text-sm">
      {text}
      <input className="input input-sm w-full" inputMode="numeric" value={v.skus[i]![k]} onChange={(e) => setSku(i, { [k]: e.target.value })} />
    </label>
  );

  return (
    <form
      className="space-y-4 rounded-box bg-base-100 p-4"
      onSubmit={(e) => {
        e.preventDefault();
        if (v.internalName.trim()) onSubmit(toInput(v, initial));
      }}
    >
      <div className="flex flex-wrap items-end justify-between gap-2">
        <label className="flex flex-col gap-1 text-sm md:w-1/2">
          {m.products.internalName}
          <input className="input input-sm w-full" value={v.internalName} onChange={(e) => set('internalName', e.target.value)} />
        </label>
        <div className="flex items-center gap-2">
          <label className="flex items-center gap-2 text-sm">
            {m.products.jsonFill}
            <input
              type="file"
              accept="application/json,.json"
              aria-label={m.products.jsonFill}
              className="file-input file-input-sm"
              onChange={(e) => {
                void fillFromJson(e.target.files?.[0]);
                e.target.value = '';
              }}
            />
          </label>
          <button type="button" className="btn btn-ghost btn-sm" onClick={clearAll}>
            ✕ {m.products.clearAll}
          </button>
        </div>
      </div>
      <p className="text-xs opacity-70">{m.products.jsonHint}</p>
      {note && (
        <p role="status" className={`text-sm ${note.ok ? 'text-success' : 'text-error'}`}>
          {note.text}
        </p>
      )}

      {/* 카테고리 */}
      <div className="grid gap-3 md:grid-cols-2">
        <label className="flex flex-col gap-1 text-sm">
          {m.products.primaryCategory}
          <select
            className="select select-sm w-full"
            value={v.primaryCategoryId}
            disabled={tree.isPending}
            // 대표 카테고리는 노출 카테고리에 자동으로 들어간다(서버도 categoryIds 맨 앞에 대표를 둔다). 따로 고른 목록에서는 뺀다.
            onChange={(e) =>
              setV((prev) => ({ ...prev, primaryCategoryId: e.target.value, categoryIds: prev.categoryIds.filter((id) => id !== e.target.value) }))
            }
          >
            <option value="">{tree.isPending ? m.loading : m.products.categoryPick}</option>
            {v.primaryCategoryId && !nodeById.has(v.primaryCategoryId) && <option value={v.primaryCategoryId}>{v.primaryCategoryId}</option>}
            {nodes.map((n) => (
              <option key={n.categoryId} value={n.categoryId}>
                {n.path ?? n.name}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-sm">
          {m.products.categories}
          <select
            multiple
            size={5}
            className="select select-sm w-full"
            value={v.categoryIds}
            disabled={tree.isPending}
            onChange={(e) =>
              set(
                'categoryIds',
                [...e.target.selectedOptions].map((o) => o.value),
              )
            }
          >
            {nodes.map((n) => (
              <option key={n.categoryId} value={n.categoryId} disabled={n.categoryId === v.primaryCategoryId}>
                {n.categoryId === v.primaryCategoryId ? `${n.path ?? n.name} (${m.products.primaryTag})` : (n.path ?? n.name)}
              </option>
            ))}
          </select>
        </label>
        {tree.error instanceof PmartFailure && (
          <div className="md:col-span-2">
            <FailureAlert failure={tree.error} />
            <button type="button" className="btn btn-xs mt-1" onClick={() => void tree.refetch()}>
              {m.retry}
            </button>
          </div>
        )}
        {(v.primaryCategoryId !== '' || v.categoryIds.length > 0) && (
          <ul className="flex flex-wrap gap-1 md:col-span-2" aria-label={m.products.selectedCategories}>
            {v.primaryCategoryId !== '' && (
              <li className="badge badge-primary badge-outline gap-1">{`${label(v.primaryCategoryId)} · ${m.products.primaryTag}`}</li>
            )}
            {v.categoryIds.map((id) => (
              <li key={id} className="badge badge-outline gap-1">
                {label(id)}
                <button type="button" aria-label={m.products.removeCategory(label(id))} onClick={() => set('categoryIds', v.categoryIds.filter((x) => x !== id))}>
                  ✕
                </button>
              </li>
            ))}
          </ul>
        )}
        {v.categoryPaths.length > 0 && (
          <p className="text-warning text-xs md:col-span-2">{`${m.products.categoryPathsPending(v.categoryPaths.length)}: ${v.categoryPaths.join(' / ')}`}</p>
        )}
      </div>

      {/* 필터 옵션 */}
      {v.primaryCategoryId !== '' && (
        <fieldset className="space-y-2 rounded-box border border-base-300 p-3">
          <legend className="px-1 text-sm font-bold">{m.products.filters}</legend>
          {filters.isPending && <p className="text-sm opacity-70">{m.loading}</p>}
          {filters.error instanceof PmartFailure && <FailureAlert failure={filters.error} />}
          {filters.isSuccess && groups.length === 0 && <p className="text-sm opacity-70">{m.products.filtersNone}</p>}
          {groups.map((g) => (
            <div key={g.filterGroupId} className="flex flex-wrap items-center gap-3 text-sm">
              <span className="font-medium">{g.name}</span>
              {g.options.map((opt) => (
                <label key={opt} className="flex items-center gap-1">
                  <input
                    type="checkbox"
                    className="checkbox checkbox-xs"
                    aria-label={m.products.filterOption(g.name, opt)}
                    checked={(v.filterOptions[g.filterGroupId] ?? []).includes(opt)}
                    onChange={(e) => toggleFilter(g.filterGroupId, opt, e.target.checked)}
                  />
                  {opt}
                </label>
              ))}
            </div>
          ))}
        </fieldset>
      )}

      {/* SKU */}
      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-bold">{m.products.skus}</h2>
          <button type="button" className="btn btn-outline btn-xs" onClick={() => set('skus', [...v.skus, emptySku()])}>
            {m.products.addSku}
          </button>
        </div>
        {v.skus.map((s, i) => (
          <section key={i} className="space-y-2 rounded-box border border-base-300 p-3" aria-label={m.products.skuTitle(i + 1)}>
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-medium">{m.products.skuTitle(i + 1)}</h3>
              {v.skus.length > 1 && (
                <button
                  type="button"
                  className="btn btn-ghost btn-xs"
                  aria-label={m.products.removeSku(i + 1)}
                  onClick={() => set('skus', v.skus.filter((_, j) => j !== i))}
                >
                  ✕
                </button>
              )}
            </div>
            <div className="grid gap-3 md:grid-cols-3">
              <label className="flex flex-col gap-1 text-sm">
                {m.products.unitType}
                <select className="select select-sm" value={s.unitType} onChange={(e) => setSku(i, { unitType: e.target.value === 'B' ? 'B' : 'E' })}>
                  <option value="E">{m.products.unitName.E}</option>
                  <option value="B">{m.products.unitName.B}</option>
                </select>
              </label>
              {numField(i, 'unitsPerSku', m.products.unitsPerSku)}
              {numField(i, 'weightG', m.products.weightG)}
              {numField(i, 'volumeMl', m.products.volumeMl)}
              <label className="flex flex-col gap-1 text-sm">
                {m.products.storageType}
                <select
                  className="select select-sm"
                  value={s.storageType}
                  onChange={(e) => setSku(i, { storageType: STORAGE_TYPES.find((t) => t === e.target.value) ?? '' })}
                >
                  <option value="">{m.none}</option>
                  {STORAGE_TYPES.map((t) => (
                    <option key={t} value={t}>
                      {m.products.storageName[t]}
                    </option>
                  ))}
                </select>
              </label>
              <label className="flex flex-col gap-1 text-sm">
                {m.products.barcodes}
                <input className="input input-sm w-full" value={s.barcodes} onChange={(e) => setSku(i, { barcodes: e.target.value })} />
              </label>
              <label className="flex items-center gap-2 text-sm">
                <input type="checkbox" className="checkbox checkbox-sm" checked={s.alcohol} onChange={(e) => setSku(i, { alcohol: e.target.checked })} />
                {m.products.alcohol}
              </label>
            </div>
            <details className="text-sm">
              <summary className="cursor-pointer opacity-80">{m.products.logistics}</summary>
              <div className="mt-2 grid gap-3 md:grid-cols-4">
                {numField(i, 'unitsPerBox', m.products.unitsPerBox)}
                {numField(i, 'ti', m.products.ti)}
                {numField(i, 'hi', m.products.hi)}
                {numField(i, 'boxesPerPallet', m.products.boxesPerPallet)}
              </div>
            </details>
          </section>
        ))}
      </div>

      <button type="submit" className="btn btn-primary btn-sm" disabled={busy || !v.internalName.trim()}>
        {submitLabel}
      </button>
    </form>
  );
}
