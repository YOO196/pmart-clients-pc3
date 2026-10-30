// 콘텐츠 초안 1건(고객용 상품명·설명·안내) + 이미지 → 제출 준비 → DISPLAY 승인 요청.
// 상품 승인으로 productId 가 생긴 뒤에만 제출할 수 있다(PRODUCT_NOT_LINKED).
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router';

import { commandParams } from '../../api/command';
import { IMAGE_ROLES, type ContentDraft, type ContentDraftInput, type ImageRole } from '../../api/models';
import { request } from '../../api/pmartFetch';
import { useApi } from '../../app/ApiContext';
import { CommandFeedback, reasonText } from '../../shared/Feedback';
import { messages as m } from '../../shared/messages';
import { QueryState } from '../../shared/QueryState';
import { toUiState } from '../../shared/toUiState';
import { useCommand } from '../../shared/useCommand';
import { RequestApproval } from '../approvals/RequestApproval';
import { multipart } from '../products/ProductImportPage';
import { AuthedImage } from './AuthedImage';

function ContentForm({
  initial,
  submitLabel,
  busy,
  onSubmit,
}: {
  readonly initial?: ContentDraftInput;
  readonly submitLabel: string;
  readonly busy: boolean;
  readonly onSubmit: (input: ContentDraftInput) => void;
}) {
  const [v, setV] = useState({
    productId: initial?.productId ?? '',
    name: initial?.name ?? '',
    description: initial?.description ?? '',
    storageGuide: initial?.storageGuide ?? '',
    returnGuide: initial?.returnGuide ?? '',
    notices: (initial?.notices ?? []).join('\n'),
  });
  type Key = keyof typeof v;
  const field = (k: Key, label: string, multiline = false) => (
    <label className="flex flex-col gap-1 text-sm">
      {label}
      {multiline ? (
        <textarea className="textarea textarea-sm w-full" rows={3} value={v[k]} onChange={(e) => setV({ ...v, [k]: e.target.value })} />
      ) : (
        <input className="input input-sm w-full" value={v[k]} onChange={(e) => setV({ ...v, [k]: e.target.value })} />
      )}
    </label>
  );
  const opt = (s: string) => (s.trim() ? s.trim() : null);

  return (
    <form
      className="grid gap-3 rounded-box bg-base-100 p-4 md:grid-cols-2"
      onSubmit={(e) => {
        e.preventDefault();
        const notices = v.notices
          .split('\n')
          .map((x) => x.trim())
          .filter(Boolean);
        onSubmit({
          ...(initial?.sourceSystem ? { sourceSystem: initial.sourceSystem } : {}),
          ...(initial?.sourceKey ? { sourceKey: initial.sourceKey } : {}),
          ...(initial?.options ? { options: initial.options } : {}),
          ...(v.productId.trim() ? { productId: v.productId.trim() } : {}),
          ...(v.name.trim() ? { name: v.name.trim() } : {}),
          description: opt(v.description),
          storageGuide: opt(v.storageGuide),
          returnGuide: opt(v.returnGuide),
          ...(notices.length > 0 ? { notices } : {}),
        });
      }}
    >
      {field('productId', m.contents.productId)}
      {field('name', m.contents.name)}
      {field('description', m.contents.description, true)}
      {field('notices', m.contents.notices, true)}
      {field('storageGuide', m.contents.storageGuide)}
      {field('returnGuide', m.contents.returnGuide)}
      <div className="md:col-span-2">
        <button type="submit" className="btn btn-primary btn-sm" disabled={busy}>
          {submitLabel}
        </button>
      </div>
    </form>
  );
}

export function NewContentDraftPage() {
  const api = useApi();
  const navigate = useNavigate();
  const [openId, setOpenId] = useState('');
  const create = useCommand((body: ContentDraftInput, key) =>
    request('POST', api.content.POST('/content-drafts', { ...commandParams(key), body })).then((d) => {
      void navigate(`/contents/drafts/${encodeURIComponent(d.draftId)}`);
      return d;
    }),
  );
  return (
    <section className="space-y-4">
      <h1 className="text-xl font-bold">{m.contents.draftTitle}</h1>
      <form
        className="flex gap-2"
        onSubmit={(e) => {
          e.preventDefault();
          if (openId.trim()) void navigate(`/contents/drafts/${encodeURIComponent(openId.trim())}`);
        }}
      >
        {/* BR-26: 초안 목록 API 가 없어 ID 로 연다 */}
        <input
          aria-label={m.products.openDraft}
          placeholder={m.products.openDraft}
          className="input input-sm"
          value={openId}
          onChange={(e) => setOpenId(e.target.value)}
        />
        <button type="submit" className="btn btn-sm">
          {m.search}
        </button>
      </form>
      <ContentForm
        submitLabel={m.products.create}
        busy={create.busy}
        onSubmit={(input) => void create.run(input)}
      />
      <CommandFeedback command={create} />
    </section>
  );
}

function ImageUpload({ draft }: { readonly draft: ContentDraft }) {
  const api = useApi();
  const queryClient = useQueryClient();
  const [file, setFile] = useState<File | null>(null);
  const [role, setRole] = useState<ImageRole>('MAIN');
  const [sortOrder, setSortOrder] = useState('0');
  const upload = useCommand(async (v: { file: File; role: ImageRole; sortOrder: number }, key) => {
    const img = await request(
      'POST',
      api.content.POST('/content-drafts/{draftId}/images', {
        ...commandParams(key, { path: { draftId: draft.draftId } }),
        body: { file: '', role: v.role, sortOrder: v.sortOrder },
        ...multipart({ file: v.file, role: v.role, sortOrder: String(v.sortOrder) }),
      }),
    );
    await queryClient.invalidateQueries({ queryKey: ['content', 'draft', draft.draftId] });
    return img;
  });

  return (
    <div className="space-y-2">
      <div className="flex flex-wrap items-end gap-2">
        <input
          type="file"
          accept="image/jpeg,image/png,image/webp"
          aria-label={m.contents.uploadImage}
          className="file-input file-input-sm"
          onChange={(e) => setFile(e.target.files?.[0] ?? null)}
        />
        <select
          aria-label={m.contents.images}
          className="select select-sm w-36"
          value={role}
          onChange={(e) => setRole(IMAGE_ROLES.find((r) => r === e.target.value) ?? 'MAIN')}
        >
          {IMAGE_ROLES.map((r) => (
            <option key={r} value={r}>
              {m.contents.imageRole[r]}
            </option>
          ))}
        </select>
        <input
          aria-label={m.contents.sortOrder}
          className="input input-sm w-20"
          inputMode="numeric"
          value={sortOrder}
          onChange={(e) => setSortOrder(e.target.value)}
        />
        <button
          type="button"
          className="btn btn-sm"
          disabled={!file || upload.busy}
          onClick={() => file && void upload.run({ file, role, sortOrder: /^\d+$/.test(sortOrder) ? Number(sortOrder) : 0 })}
        >
          {m.contents.uploadImage}
        </button>
      </div>
      <CommandFeedback command={upload} />
    </div>
  );
}

export function ContentDraftPage() {
  const { draftId = '' } = useParams();
  const api = useApi();
  const queryClient = useQueryClient();
  const key = ['content', 'draft', draftId];
  const query = useQuery({
    queryKey: key,
    queryFn: () => request('GET', api.content.GET('/content-drafts/{draftId}', { params: { path: { draftId } } })),
  });
  const update = useCommand(async ({ body, version }: { body: ContentDraftInput; version: number }, k) => {
    const d = await request(
      'PUT',
      api.content.PUT('/content-drafts/{draftId}', { ...commandParams(k, { path: { draftId }, version: version }), body }),
    );
    queryClient.setQueryData(key, d);
    return d;
  });
  const submit = useCommand(async (_: null, k) => {
    const r = await request(
      'POST',
      api.content.POST('/content-drafts/{draftId}/submissions', { ...commandParams(k, { path: { draftId } }) }),
    );
    await queryClient.invalidateQueries({ queryKey: key });
    return r;
  });

  return (
    <section className="space-y-4">
      <h1 className="text-xl font-bold">{m.contents.draftDetail(draftId)}</h1>
      <QueryState state={toUiState(query)} onRetry={() => void query.refetch()}>
        {(d) => (
          <>
            <p className="text-sm">
              {`${m.products.state}: ${d.state} · ${d.productId ? `${m.products.productId} ${d.productId}` : m.reason.PRODUCT_NOT_LINKED} · `}
              <span className={d.submittable ? 'text-success' : 'text-warning'}>
                {d.submittable ? m.contents.submittable : m.contents.notSubmittable}
              </span>
            </p>
            {(d.problems?.length ?? 0) > 0 && (
              <ul className="list-disc pl-5 text-sm" aria-label={m.products.problems}>
                {(d.problems ?? []).map((p, i) => (
                  <li key={`${p.code}-${i}`}>{reasonText(p.code)}</li>
                ))}
              </ul>
            )}
            {d.state === 'DRAFT' && (
              <ContentForm
                key={d.version}
                {...(d.input ? { initial: d.input } : {})}
                submitLabel={m.products.update}
                busy={update.busy}
                onSubmit={(body) => void update.run({ body, version: d.version })}
              />
            )}
            <CommandFeedback command={update} />

            <div className="space-y-2 rounded-box bg-base-100 p-4">
              <h2 className="font-bold">{m.contents.images}</h2>
              <div className="flex flex-wrap gap-3">
                {(d.images ?? []).map((img) => (
                  <figure key={img.imageId} className="w-32 text-xs">
                    <AuthedImage imageId={img.imageId} alt={`${m.contents.imageRole[img.role]} ${img.sortOrder}`} className="h-32 w-32 object-contain" />
                    <figcaption>{`${m.contents.imageRole[img.role]} · ${img.sortOrder}`}</figcaption>
                  </figure>
                ))}
              </div>
              {d.state === 'DRAFT' && <ImageUpload draft={d} />}
            </div>

            {d.state === 'DRAFT' && (
              <button type="button" className="btn btn-sm" disabled={submit.busy || !d.submittable} onClick={() => void submit.run(null)}>
                {m.products.submit}
              </button>
            )}
            <CommandFeedback command={submit}>
              {(r) => <RequestApproval body={r.approvalRequest} />}
            </CommandFeedback>
            {d.approvalId && (
              <Link className="link text-sm" to={`/approvals/${encodeURIComponent(d.approvalId)}`}>
                {`${m.approvals.open} (${d.approvalId})`}
              </Link>
            )}
            {d.state === 'PUBLISHED' && (
              <p className="text-success text-sm">{`${m.contents.published} v${d.contentVersion ?? m.none}`}</p>
            )}
          </>
        )}
      </QueryState>
    </section>
  );
}
