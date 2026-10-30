// 콘텐츠 일괄 등록(seed-v1 zip) → 상품별 결과 → 제출 가능한 초안 제출 준비 → DISPLAY 승인.
import { useQuery } from '@tanstack/react-query';
import { Link, useNavigate, useParams } from 'react-router';

import { commandParams } from '../../api/command';
import { request } from '../../api/pmartFetch';
import { useApi } from '../../app/ApiContext';
import { CommandFeedback, reasonText } from '../../shared/Feedback';
import { messages as m } from '../../shared/messages';
import { QueryState } from '../../shared/QueryState';
import { toUiState } from '../../shared/toUiState';
import { useCommand } from '../../shared/useCommand';
import { RequestApproval } from '../approvals/RequestApproval';
import { multipart, ZipUpload } from '../products/ProductImportPage';

export function NewContentImportPage() {
  const api = useApi();
  const navigate = useNavigate();
  const upload = useCommand((file: File, key) =>
    request(
      'POST',
      api.content.POST('/content-import-batches', { ...commandParams(key), body: { file: '' }, ...multipart({ file }) }),
    ).then((b) => {
      void navigate(`/contents/import/${encodeURIComponent(b.batchId)}`);
      return b;
    }),
  );
  return (
    <section className="space-y-4">
      <h1 className="text-xl font-bold">{m.contents.importTitle}</h1>
      <ZipUpload
        busy={upload.busy}
        onUpload={(file) => void upload.run(file)}
      />
      <CommandFeedback command={upload} />
    </section>
  );
}

export function ContentImportPage() {
  const { batchId = '' } = useParams();
  const api = useApi();
  const query = useQuery({
    queryKey: ['content', 'import-batch', batchId],
    queryFn: () => request('GET', api.content.GET('/content-import-batches/{batchId}', { params: { path: { batchId } } })),
  });
  const submit = useCommand((_: null, key) =>
    request(
      'POST',
      api.content.POST('/content-import-batches/{batchId}/submissions', { ...commandParams(key, { path: { batchId } }) }),
    ),
  );

  return (
    <section className="space-y-4">
      <h1 className="text-xl font-bold">{m.products.batch(batchId)}</h1>
      <QueryState state={toUiState(query)} onRetry={() => void query.refetch()}>
        {(b) => (
          <>
            <p className="text-sm">{`${b.state} · ${b.productCount}`}</p>
            <table className="table table-sm bg-base-100">
              <tbody>
                {(b.items ?? []).map((it, i) => (
                  <tr key={it.draftId ?? i}>
                    <td>
                      {it.draftId ? (
                        <Link className="link" to={`/contents/drafts/${encodeURIComponent(it.draftId)}`}>
                          {it.draftId}
                        </Link>
                      ) : (
                        m.none
                      )}
                    </td>
                    <td>{it.sourceKey ?? m.none}</td>
                    <td>{it.outcome ? m.contents.outcome[it.outcome] : m.none}</td>
                    <td>{it.draft?.input?.name ?? m.none}</td>
                    <td>{it.draft?.submittable ? m.contents.submittable : (it.draft?.problems ?? []).map((p) => reasonText(p.code)).join(', ')}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            {b.state === 'UPLOADED' && (
              <button
                type="button"
                className="btn btn-sm"
                disabled={submit.busy || submit.phase.kind === 'done'}
                onClick={() => void submit.run(null)}
              >
                {m.products.submitBatch}
              </button>
            )}
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
    </section>
  );
}
