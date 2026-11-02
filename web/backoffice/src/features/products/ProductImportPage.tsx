// 상품 일괄 등록(seed-v1 zip) → 상품별 검증 → 유효 행 제출 준비 → PRODUCT 승인(1건 + 행 N개) → id-map.
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router';

import { commandParams } from '../../api/command';
import { STORAGE_TYPES, type ProductDraft, type ProductDraftInput, type StorageType } from '../../api/models';
import { request } from '../../api/pmartFetch';
import { useApi } from '../../app/ApiContext';
import { CommandFeedback } from '../../shared/Feedback';
import { messages as m } from '../../shared/messages';
import { QueryState } from '../../shared/QueryState';
import { toUiState } from '../../shared/toUiState';
import { useCommand } from '../../shared/useCommand';
import { RequestApproval } from '../approvals/RequestApproval';
import { DraftProblems } from './ProductDraftPage';

/** multipart 본문. openapi-fetch 는 FormData 를 그대로 보내고 Content-Type 경계를 브라우저에 맡긴다. */
export const multipart = (fields: Record<string, Blob | string>) => {
  const form = new FormData();
  for (const [k, v] of Object.entries(fields)) form.append(k, v);
  return { bodySerializer: () => form };
};

export function ZipUpload({
  busy,
  onUpload,
}: {
  readonly busy: boolean;
  readonly onUpload: (file: File) => void;
}) {
  const [file, setFile] = useState<File | null>(null);
  return (
    <div className="flex flex-wrap items-end gap-2 rounded-box bg-base-100 p-4">
      <label className="flex flex-col text-sm">
        {m.products.zipFile}
        <input
          type="file"
          accept=".zip,application/zip"
          className="file-input file-input-sm"
          onChange={(e) => setFile(e.target.files?.[0] ?? null)}
        />
      </label>
      <button type="button" className="btn btn-primary btn-sm" disabled={!file || busy} onClick={() => file && onUpload(file)}>
        {m.products.upload}
      </button>
    </div>
  );
}

/** seed-v1.zip 을 올려 배치를 만들고(검증까지 서버가 한다) 그 배치 화면으로 간다. */
function useImportUpload() {
  const api = useApi();
  const navigate = useNavigate();
  return useCommand((file: File, key) =>
    request(
      'POST',
      api.product.POST('/product-import-batches', { ...commandParams(key), body: { file: '' }, ...multipart({ file }) }),
    ).then((b) => {
      void navigate(`/products/import/${encodeURIComponent(b.batchId)}`);
      return b;
    }),
  );
}

export function NewProductImportPage() {
  const upload = useImportUpload();
  return (
    <section className="space-y-4">
      <h1 className="text-xl font-bold">{m.products.importTitle}</h1>
      <ZipUpload busy={upload.busy} onUpload={(file) => void upload.run(file)} />
      <CommandFeedback command={upload} />
    </section>
  );
}

/**
 * INVALID 초안의 빠진 값(중량·보관 방식)을 배치 화면에서 바로 채운다(백엔드 요청 2026-11-02 §3-2).
 * 값을 미리 채우지 않는다 — 운영자가 상품명·용량을 보고 넣는다. 저장은 `PUT /product-drafts/{id}`(입력 전체, 버전 확인) → 서버 재검증.
 */
function FillMissing({ draft, batchId }: { readonly draft: ProductDraft; readonly batchId: string }) {
  const api = useApi();
  const queryClient = useQueryClient();
  const sku = draft.input?.skus[0];
  const [weightG, setWeightG] = useState(sku?.weightG === undefined ? '' : String(sku.weightG));
  const [storageType, setStorageType] = useState<StorageType | ''>(sku?.storageType ?? '');
  const save = useCommand(async (_: null, key) => {
    const input = draft.input;
    if (!input || !sku) throw new Error('input');
    const w = /^\d+$/.test(weightG.trim()) ? Number(weightG.trim()) : undefined;
    const first = {
      ...sku,
      ...(w === undefined ? {} : { weightG: w }),
      ...(storageType ? { storageType } : {}),
    };
    const body: ProductDraftInput = { ...input, skus: [first, ...input.skus.slice(1)] };
    const d = await request(
      'PUT',
      api.product.PUT('/product-drafts/{draftId}', { ...commandParams(key, { path: { draftId: draft.draftId }, version: draft.version }), body }),
    );
    await queryClient.invalidateQueries({ queryKey: ['product', 'import-batch', batchId] });
    return d;
  });
  const name = draft.input?.product.internalName ?? draft.draftId;
  return (
    <div className="flex flex-wrap items-end gap-2 text-sm" aria-label={`${m.products.fillInvalid} ${name}`}>
      <span className="opacity-70">{m.products.volumeHint(sku?.volumeMl)}</span>
      <label className="flex flex-col">
        {m.products.weightG}
        <input className="input input-xs w-24" inputMode="numeric" value={weightG} onChange={(e) => setWeightG(e.target.value)} />
      </label>
      <label className="flex flex-col">
        {m.products.storageType}
        <select className="select select-xs" value={storageType} onChange={(e) => setStorageType(STORAGE_TYPES.find((s) => s === e.target.value) ?? '')}>
          <option value="">{m.none}</option>
          {STORAGE_TYPES.map((s) => (
            <option key={s} value={s}>
              {m.products.storageName[s]}
            </option>
          ))}
        </select>
      </label>
      <button type="button" className="btn btn-xs" disabled={save.busy || (!weightG.trim() && !storageType)} onClick={() => void save.run(null)}>
        {m.products.fillSave}
      </button>
      <CommandFeedback command={save}>{() => <span className="text-success">{m.products.fillSaved(name)}</span>}</CommandFeedback>
    </div>
  );
}

/** 배치 화면에서 바로 다른 파일을 올린다(다른 메뉴로 갔다 올 필요 없음). 배치가 바뀌면 새로 시작한다(key). */
function AnotherUpload() {
  const upload = useImportUpload();
  return (
    <div className="space-y-2">
      <h2 className="font-bold">{m.products.uploadAnother}</h2>
      <ZipUpload busy={upload.busy} onUpload={(file) => void upload.run(file)} />
      <CommandFeedback command={upload} />
    </div>
  );
}

function downloadJson(name: string, value: unknown) {
  const url = URL.createObjectURL(new Blob([JSON.stringify(value, null, 2)], { type: 'application/json' }));
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  a.click();
  URL.revokeObjectURL(url);
}

export function ProductImportPage() {
  const { batchId = '' } = useParams();
  const api = useApi();
  const query = useQuery({
    queryKey: ['product', 'import-batch', batchId],
    queryFn: () => request('GET', api.product.GET('/product-import-batches/{batchId}', { params: { path: { batchId } } })),
  });
  const submit = useCommand((_: null, key) =>
    request(
      'POST',
      api.product.POST('/product-import-batches/{batchId}/submissions', { ...commandParams(key, { path: { batchId } }) }),
    ),
  );
  const idMap = useCommand(async () => {
    const map = await request(
      'GET',
      api.product.GET('/product-import-batches/{batchId}/id-map', { params: { path: { batchId } } }),
    );
    downloadJson('id-map.json', map);
    return map;
  });

  return (
    <section className="space-y-4">
      <h1 className="text-xl font-bold">{m.products.batch(batchId)}</h1>
      <QueryState state={toUiState(query)} onRetry={() => void query.refetch()}>
        {(b) => (
          <>
            <p className="text-sm">{`${b.state} · ${m.products.counts(b.productCount, b.validCount, b.invalidCount)}`}</p>
            {(b.drafts ?? []).some((d) => d.state === 'DRAFT' && d.validationState !== 'VALID') && (
              <p className="text-sm opacity-80">{m.products.fillInvalidHint}</p>
            )}
            <table className="table table-sm bg-base-100">
              <tbody>
                {(b.drafts ?? []).map((d) => (
                  <tr key={d.draftId}>
                    <td>
                      <Link className="link" to={`/products/drafts/${encodeURIComponent(d.draftId)}`}>
                        {d.draftId}
                      </Link>
                    </td>
                    <td>{d.sourceKey ?? m.none}</td>
                    <td>{d.input?.product.internalName ?? m.none}</td>
                    <td>
                      <DraftProblems draft={d} />
                      {d.state === 'DRAFT' && d.validationState !== 'VALID' && d.input && (
                        <FillMissing key={`${d.draftId}-${d.version}`} draft={d} batchId={batchId} />
                      )}
                    </td>
                    <td>{d.resultSkus?.join(', ') ?? ''}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            <div className="flex gap-2">
              {b.state === 'VALIDATED' && (
                <button
                  type="button"
                  className="btn btn-sm"
                  disabled={submit.busy || submit.phase.kind === 'done' || b.validCount === 0}
                  onClick={() => void submit.run(null)}
                >
                  {m.products.submitBatch}
                </button>
              )}
              <button type="button" className="btn btn-sm" disabled={idMap.busy} onClick={() => void idMap.run(undefined)}>
                {m.products.idMap}
              </button>
              <button type="button" className="btn btn-ghost btn-sm" onClick={() => void query.refetch()}>
                {m.checkAgain}
              </button>
            </div>
            <CommandFeedback command={idMap} />
            <CommandFeedback command={submit}>
              {(r) => (
                <div className="space-y-2">
                  {(r.excludedDraftIds?.length ?? 0) > 0 && (
                    <p className="text-sm">{`${m.products.excluded}: ${(r.excludedDraftIds ?? []).join(', ')}`}</p>
                  )}
                  <RequestApproval body={r.approvalRequest} />
                </div>
              )}
            </CommandFeedback>
          </>
        )}
      </QueryState>
      <AnotherUpload key={batchId} />
    </section>
  );
}
