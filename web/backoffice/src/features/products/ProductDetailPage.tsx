// 상품 상세·SKU·판매 상태 변경. 일시품절·판매 재개는 바로, 판매중지는 PRODUCT 승인 뒤 approvalId 와 함께(2026-10-30 결정).
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { Link, useParams } from 'react-router';

import { commandParams } from '../../api/command';
import { SALE_STATES, type ChangeRequestBody, type ProductDetail, type SaleState } from '../../api/models';
import { request } from '../../api/pmartFetch';
import { settleCommand } from '../../api/settle';
import { useApi } from '../../app/ApiContext';
import { CommandFeedback } from '../../shared/Feedback';
import { formatSeoul } from '../../shared/format';
import { messages as m } from '../../shared/messages';
import { QueryState } from '../../shared/QueryState';
import { toUiState } from '../../shared/toUiState';
import { useCommand } from '../../shared/useCommand';
import { RequestApproval } from '../approvals/RequestApproval';

/** handoff 2026-10-30 §4.3 판매중지 변경 요청 본문 */
export function saleStopApprovalBody(productId: string, reason: string): ChangeRequestBody {
  return {
    type: 'PRODUCT',
    targetService: 'product-service',
    targetRef: `SALE-STATE:${productId}`,
    allowedActions: ['CHANGE_SALE_STATE'],
    summary: `판매중지: ${reason}`,
    lines: [{ lineKey: productId, attributes: { saleState: 'SALE_STOPPED' } }],
  };
}

function SaleStateChange({ product }: { readonly product: ProductDetail }) {
  const api = useApi();
  const queryClient = useQueryClient();
  const productId = product.productId ?? '';
  const [saleState, setSaleState] = useState<SaleState>(product.saleState === 'ON_SALE' ? 'TEMPORARILY_SOLD_OUT' : 'ON_SALE');
  const [reason, setReason] = useState('');
  const [approvalId, setApprovalId] = useState('');
  const [approvalBody, setApprovalBody] = useState<ChangeRequestBody | null>(null);

  const change = useCommand(
    async (v: { saleState: SaleState; reason: string; approvalId: string; version: number | undefined }, key) => {
      const r = await settleCommand(
        key,
        () =>
          request(
            'POST',
            api.product.POST('/products/{productId}/sale-state-changes', {
              ...commandParams(key, { path: { productId }, version: v.version }),
              body: { saleState: v.saleState, reason: v.reason, ...(v.approvalId ? { approvalId: v.approvalId } : {}) },
            }),
          ),
        (requestId) =>
          request(
            'GET',
            api.product.GET('/products/{productId}/sale-state-changes/{requestId}', {
              params: { path: { productId, requestId } },
            }),
          ),
      );
      await queryClient.invalidateQueries({ queryKey: ['product'] });
      return r;
    },
  );

  const stop = saleState === 'SALE_STOPPED';
  return (
    <div className="space-y-3 rounded-box bg-base-100 p-4">
      <h2 className="font-bold">{m.products.changeSaleState}</h2>
      <div className="flex flex-wrap items-end gap-2">
        <label className="flex flex-col text-sm">
          {m.products.saleState}
          <select
            className="select select-sm"
            value={saleState}
            onChange={(e) => setSaleState(SALE_STATES.find((s) => s === e.target.value) ?? 'ON_SALE')}
          >
            {SALE_STATES.map((s) => (
              <option key={s} value={s}>
                {m.products.saleStateName[s]}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col text-sm">
          {m.reasonLabel}
          <input className="input input-sm" maxLength={200} value={reason} onChange={(e) => setReason(e.target.value)} />
        </label>
        {stop && (
          <label className="flex flex-col text-sm">
            {m.products.approvalIdLabel}
            <input className="input input-sm" value={approvalId} onChange={(e) => setApprovalId(e.target.value)} />
          </label>
        )}
        <button
          type="button"
          className="btn btn-primary btn-sm"
          disabled={change.busy || !reason.trim()}
          onClick={() =>
            void change.run({ saleState, reason: reason.trim(), approvalId: stop ? approvalId.trim() : '', version: product.version })
          }
        >
          {m.products.applyChange}
        </button>
      </div>
      {stop && (
        <div className="space-y-2">
          <p className="text-sm">{m.products.stopNeedsApproval}</p>
          {approvalBody ? (
            <RequestApproval body={approvalBody} onRequested={(r) => r.approvalId && setApprovalId(r.approvalId)} />
          ) : (
            <button
              type="button"
              className="btn btn-sm"
              disabled={!reason.trim()}
              onClick={() => setApprovalBody(saleStopApprovalBody(productId, reason.trim()))}
            >
              {m.approvals.requestApproval}
            </button>
          )}
        </div>
      )}
      <CommandFeedback command={change}>
        {() => (
          <div role="status" className="alert alert-success">
            {m.products.changeApplied}
          </div>
        )}
      </CommandFeedback>
    </div>
  );
}

export function ProductDetailPage() {
  const { productId = '' } = useParams();
  const api = useApi();
  const query = useQuery({
    queryKey: ['product', 'detail', productId],
    queryFn: () => request('GET', api.product.GET('/products/{productId}', { params: { path: { productId } } })),
  });

  return (
    <section className="space-y-4">
      <h1 className="text-xl font-bold">{m.products.detailTitle(productId)}</h1>
      <QueryState state={toUiState(query)} onRetry={() => void query.refetch()}>
        {(p) => (
          <>
            <dl className="grid grid-cols-[10rem_1fr] gap-1 rounded-box bg-base-100 p-4 text-sm">
              <dt>{m.products.internalName}</dt>
              <dd>{p.internalName ?? m.none}</dd>
              <dt>{m.products.saleState}</dt>
              <dd data-testid="sale-state">{p.saleState ? m.products.saleStateName[p.saleState] : m.none}</dd>
              <dt>{m.products.version}</dt>
              <dd>{p.version ?? m.none}</dd>
              <dt>{m.products.primaryCategoryId}</dt>
              <dd>{p.primaryCategoryId ?? m.none}</dd>
              <dt>{m.products.categoryIds}</dt>
              <dd>{(p.categoryIds ?? []).join(', ') || m.none}</dd>
              <dt>{m.approvals.dossier}</dt>
              <dd>
                {p.approvalId ? (
                  <Link className="link" to={`/approvals/${encodeURIComponent(p.approvalId)}`}>
                    {p.approvalId}
                  </Link>
                ) : (
                  m.none
                )}
              </dd>
              <dt>{m.products.publishedAt}</dt>
              <dd>{p.publishedAt ? formatSeoul(p.publishedAt) : m.none}</dd>
            </dl>
            {/* 고객용 상품명·설명·이미지는 콘텐츠(product-content-service, DISPLAY 승인)로 따로 등록한다. */}
            <Link className="btn btn-sm" to={`/contents/drafts/new?productId=${encodeURIComponent(productId)}`}>
              {m.products.addContent}
            </Link>
            <h2 className="font-bold">{m.products.skus}</h2>
            <table className="table table-sm bg-base-100">
              <thead>
                <tr>
                  <th>SKU</th>
                  <th>{m.products.unitType}</th>
                  <th>{m.products.unitsPerSku}</th>
                  <th>{m.products.weightG}</th>
                  <th>{m.products.storageType}</th>
                  <th>{m.products.barcodes}</th>
                  <th>{m.products.saleState}</th>
                </tr>
              </thead>
              <tbody>
                {(p.skus ?? []).map((s) => (
                  <tr key={s.sku}>
                    <td>
                      <Link className="link" to={`/prices?sku=${encodeURIComponent(s.sku)}`}>
                        {s.sku}
                      </Link>
                    </td>
                    <td>{m.products.unitName[s.unitType]}</td>
                    <td>{s.unitsPerSku}</td>
                    <td>{s.weightG ?? m.notSet}</td>
                    <td>{s.logistics?.storageType ? m.products.storageName[s.logistics.storageType] : m.none}</td>
                    <td>{(s.barcodes ?? []).join(', ') || m.none}</td>
                    <td>{m.products.saleStateName[s.saleState]}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            <SaleStateChange key={p.productId} product={p} />
          </>
        )}
      </QueryState>
    </section>
  );
}
