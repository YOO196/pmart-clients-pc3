// 상품 초안 입력(seed-v1 product.json 의 product·skus 블록, SKU 1개). 빈 칸은 보내지 않는다(0 으로 채우지 않음).
import { useState } from 'react';

import { STORAGE_TYPES, type ProductDraftInput, type SaleUnitType, type StorageType } from '../../api/models';
import { messages as m } from '../../shared/messages';

interface FormValues {
  internalName: string;
  primaryCategoryId: string;
  categoryIds: string;
  unitType: SaleUnitType;
  unitsPerSku: string;
  weightG: string;
  volumeMl: string;
  storageType: StorageType | '';
  alcohol: boolean;
  barcodes: string;
}

const list = (s: string) =>
  s
    .split(',')
    .map((x) => x.trim())
    .filter((x) => x.length > 0);

const int = (s: string): number | undefined => (/^\d+$/.test(s.trim()) ? Number(s.trim()) : undefined);

function toValues(input: ProductDraftInput | undefined): FormValues {
  const sku = input?.skus[0];
  return {
    internalName: input?.product.internalName ?? '',
    primaryCategoryId: input?.product.primaryCategoryId ?? '',
    categoryIds: (input?.product.categoryIds ?? []).join(', '),
    unitType: sku?.unitType ?? 'E',
    unitsPerSku: String(sku?.unitsPerSku ?? 1),
    weightG: sku?.weightG === undefined ? '' : String(sku.weightG),
    volumeMl: sku?.volumeMl === undefined ? '' : String(sku.volumeMl),
    storageType: sku?.storageType ?? '',
    alcohol: sku?.alcohol ?? false,
    barcodes: (sku?.barcodes ?? []).join(', '),
  };
}

function toInput(v: FormValues, base: ProductDraftInput | undefined): ProductDraftInput {
  const weightG = int(v.weightG);
  const volumeMl = int(v.volumeMl);
  const categoryIds = list(v.categoryIds);
  const barcodes = list(v.barcodes);
  return {
    ...(base?.sourceSystem ? { sourceSystem: base.sourceSystem } : {}),
    ...(base?.sourceKey ? { sourceKey: base.sourceKey } : {}),
    product: {
      ...(base?.product ?? {}),
      internalName: v.internalName.trim(),
      ...(v.primaryCategoryId.trim() ? { primaryCategoryId: v.primaryCategoryId.trim() } : {}),
      ...(categoryIds.length > 0 ? { categoryIds } : {}),
    },
    skus: [
      {
        unitType: v.unitType,
        unitsPerSku: int(v.unitsPerSku) ?? 1,
        ...(weightG === undefined ? {} : { weightG }),
        ...(volumeMl === undefined ? {} : { volumeMl }),
        ...(v.storageType ? { storageType: v.storageType } : {}),
        alcohol: v.alcohol,
        ...(barcodes.length > 0 ? { barcodes } : {}),
      },
    ],
  };
}

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
  const [v, setV] = useState<FormValues>(() => toValues(initial));
  const set = <K extends keyof FormValues>(k: K, value: FormValues[K]) => setV((prev) => ({ ...prev, [k]: value }));
  const text = (k: 'internalName' | 'primaryCategoryId' | 'categoryIds' | 'unitsPerSku' | 'weightG' | 'volumeMl' | 'barcodes', label: string, inputMode?: 'numeric') => (
    <label className="flex flex-col gap-1 text-sm">
      {label}
      <input
        className="input input-sm w-full"
        inputMode={inputMode}
        value={v[k]}
        onChange={(e) => set(k, e.target.value)}
      />
    </label>
  );

  return (
    <form
      className="grid gap-3 rounded-box bg-base-100 p-4 md:grid-cols-2"
      onSubmit={(e) => {
        e.preventDefault();
        if (v.internalName.trim()) onSubmit(toInput(v, initial));
      }}
    >
      {text('internalName', m.products.internalName)}
      {text('primaryCategoryId', m.products.primaryCategoryId)}
      {text('categoryIds', m.products.categoryIds)}
      <label className="flex flex-col gap-1 text-sm">
        {m.products.unitType}
        <select className="select select-sm" value={v.unitType} onChange={(e) => set('unitType', e.target.value === 'B' ? 'B' : 'E')}>
          <option value="E">{m.products.unitName.E}</option>
          <option value="B">{m.products.unitName.B}</option>
        </select>
      </label>
      {text('unitsPerSku', m.products.unitsPerSku, 'numeric')}
      {text('weightG', m.products.weightG, 'numeric')}
      {text('volumeMl', m.products.volumeMl, 'numeric')}
      <label className="flex flex-col gap-1 text-sm">
        {m.products.storageType}
        <select
          className="select select-sm"
          value={v.storageType}
          onChange={(e) => set('storageType', STORAGE_TYPES.find((s) => s === e.target.value) ?? '')}
        >
          <option value="">{m.none}</option>
          {STORAGE_TYPES.map((s) => (
            <option key={s} value={s}>
              {m.products.storageName[s]}
            </option>
          ))}
        </select>
      </label>
      {text('barcodes', m.products.barcodes)}
      <label className="flex items-center gap-2 text-sm">
        <input type="checkbox" className="checkbox checkbox-sm" checked={v.alcohol} onChange={(e) => set('alcohol', e.target.checked)} />
        {m.products.alcohol}
      </label>
      <div className="md:col-span-2">
        <button type="submit" className="btn btn-primary btn-sm" disabled={busy || !v.internalName.trim()}>
          {submitLabel}
        </button>
      </div>
    </form>
  );
}
