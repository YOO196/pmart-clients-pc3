// 라이더 찾기·계정 제한(라이더 운영).
// - 찾기·기본 정보: 계약 없음(BR-54, PC 5 BOD-3 예정) — 목 모드에서만 목(riderDirectoryMock), 실서버 모드는 안내만. 라이더 ID 를 알면 바로 연다.
// - 계정 제한 이력·걸기·바꾸기·풀기: rider-service 0.3.0 `GET/POST /riders/{riderId}/restrictions`(X-Expected-Version = 라이더 version).
//   바꾸면 픽업 전 배정은 풀리고 다시 배차, 픽업한 배송은 끝까지 전달(서버). 지금 서버 권한은 OPERATOR_ADMIN 만(RIDER_OPS 는 PC 5 반영 뒤).
// 전화번호·이름은 개인정보 — 목록은 가린 값, 상세는 기본 가림. 로그 금지. 제한 사유에는 개인정보를 적지 않는다(계약 설명).
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useState, type FormEvent } from 'react';
import { Link, useNavigate, useParams } from 'react-router';

import { request } from '@pmart/web-core';
import { QueryState, toUiState, useCommand } from '@pmart/web-ui';
import { commandParams } from '../../api/command';
import type { components } from '../../api/generated/rider';
import { useApi } from '../../app/ApiContext';
import { CommandFeedback } from '../../shared/Feedback';
import { messages as m } from '../../shared/messages';
import { Facts, label, Masked, NotInContract, text, when } from '../../shared/ops';
import { RiderComplaintTable } from '../riderComplaints/RiderComplaintPages';
import { ReviewTable } from './RestrictionReviewPage';
import { riderDirectoryMock, type DraftRiderFilter, type Restriction, type VehicleType } from './riderDirectoryMock';

type RestrictionRecord = components['schemas']['RiderRestrictionRecord'];
type RestrictionChange = components['schemas']['RiderRestrictionChange'];

const RESTRICTIONS = Object.keys(m.riders.restrictionName) as Restriction[];
const VEHICLES = Object.keys(m.riders.vehicleName) as VehicleType[];
const MAX_REASON = 500;

function DirectorySearch() {
  const [draft, setDraft] = useState({ phone: '', restriction: '', vehicleType: '' });
  const [filter, setFilter] = useState<DraftRiderFilter | null>(null);
  const query = useQuery({
    queryKey: ['riders', 'directory-mock', filter],
    queryFn: () => riderDirectoryMock.search(filter ?? {}),
    enabled: filter !== null,
  });
  const submit = (e: FormEvent) => {
    e.preventDefault();
    setFilter({
      ...(draft.phone.trim() ? { phone: draft.phone.trim() } : {}),
      ...(draft.restriction ? { restriction: draft.restriction as Restriction } : {}),
      ...(draft.vehicleType ? { vehicleType: draft.vehicleType as VehicleType } : {}),
    });
  };
  return (
    <>
      <form className="flex flex-wrap items-end gap-2 rounded-box bg-base-100 p-4" onSubmit={submit} aria-label={m.riders.search}>
        <label className="text-sm">
          {m.riders.phone}
          <input className="input input-sm mt-1 block" inputMode="numeric" autoComplete="off" value={draft.phone} onChange={(e) => setDraft((d) => ({ ...d, phone: e.target.value }))} />
        </label>
        <label className="text-sm">
          {m.riders.restriction}
          <select className="select select-sm mt-1 block" value={draft.restriction} onChange={(e) => setDraft((d) => ({ ...d, restriction: e.target.value }))}>
            <option value="">{m.riders.any}</option>
            {RESTRICTIONS.map((r) => (
              <option key={r} value={r}>
                {m.riders.restrictionName[r]}
              </option>
            ))}
          </select>
        </label>
        <label className="text-sm">
          {m.riders.vehicle}
          <select className="select select-sm mt-1 block" value={draft.vehicleType} onChange={(e) => setDraft((d) => ({ ...d, vehicleType: e.target.value }))}>
            <option value="">{m.riders.any}</option>
            {VEHICLES.map((v) => (
              <option key={v} value={v}>
                {m.riders.vehicleName[v]}
              </option>
            ))}
          </select>
        </label>
        <button type="submit" className="btn btn-sm">
          {m.riders.search}
        </button>
      </form>
      {filter !== null && (
        <QueryState state={toUiState(query)} onRetry={() => void query.refetch()}>
          {(rows) =>
            rows.length === 0 ? (
              <p className="text-sm opacity-70">{m.riders.empty}</p>
            ) : (
              <table className="table table-sm rounded-box bg-base-100">
                <thead>
                  <tr>
                    <th>{m.riders.riderId}</th>
                    <th>{m.riders.name}</th>
                    <th>{m.riders.phone}</th>
                    <th>{m.riders.vehicle}</th>
                    <th>{m.riders.operating}</th>
                    <th>{m.riders.mfc}</th>
                    <th>{m.riders.restriction}</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((r) => (
                    <tr key={r.riderId} data-testid="rider-row">
                      <td>
                        <Link className="link" to={`/riders/${encodeURIComponent(r.riderId)}`}>
                          {r.riderId}
                        </Link>
                      </td>
                      <td>{r.name}</td>
                      <td>{r.phoneMasked}</td>
                      <td>{label(m.riders.vehicleName, r.vehicleType)}</td>
                      <td>{label(m.riders.operatingName, r.operating)}</td>
                      <td>{text(r.operatingMfcId)}</td>
                      <td>{label(m.riders.restrictionName, r.restriction)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )
          }
        </QueryState>
      )}
    </>
  );
}

export function RiderSearchPage() {
  const navigate = useNavigate();
  const [riderId, setRiderId] = useState('');
  const open = (e: FormEvent) => {
    e.preventDefault();
    if (riderId.trim()) void navigate(`/riders/${encodeURIComponent(riderId.trim())}`);
  };
  return (
    <section className="space-y-4">
      <h1 className="text-xl font-bold">{m.riders.title}</h1>
      <p className="text-sm opacity-70">{m.riders.intro}</p>
      <form className="flex max-w-xl items-end gap-2 rounded-box bg-base-100 p-4" onSubmit={open} aria-label={m.riders.open}>
        <label className="flex-1 text-sm">
          {m.riders.riderId}
          <input className="input input-sm mt-1 w-full" value={riderId} onChange={(e) => setRiderId(e.target.value)} />
        </label>
        <button type="submit" className="btn btn-primary btn-sm" disabled={!riderId.trim()}>
          {m.riders.open}
        </button>
      </form>
      {/* BR-54: 계약 전 — 목 모드에서만 목 검색 */}
      <NotInContract br="BR-54">{() => <DirectorySearch />}</NotInContract>
    </section>
  );
}

function DirectoryBasic({ riderId }: { readonly riderId: string }) {
  const query = useQuery({ queryKey: ['riders', 'directory-mock', 'detail', riderId], queryFn: () => riderDirectoryMock.get(riderId) });
  return (
    <QueryState state={toUiState(query)} onRetry={() => void query.refetch()}>
      {(r) =>
        r === null ? (
          <p className="text-sm opacity-70">{m.problem['NOT_FOUND']}</p>
        ) : (
          <Facts
            testId="rider-basic"
            rows={[
              [m.riders.name, <Masked key="n" value={r.name} />],
              [m.orders.phone, <Masked key="p" value={r.phone} />],
              [m.riders.vehicle, label(m.riders.vehicleName, r.vehicleType)],
              [m.riders.operating, label(m.riders.operatingName, r.operating)],
              [m.riders.mfc, text(r.operatingMfcId)],
              [m.riders.restriction, label(m.riders.restrictionName, r.restriction)],
            ]}
          />
        )
      }
    </QueryState>
  );
}

/** "YYYY-MM-DDTHH:mm"(서울 벽시계) → ISO. */
const seoulLocalToIso = (v: string) => new Date(`${v}:00+09:00`).toISOString();

function RestrictionForm({ riderId, current, version }: { readonly riderId: string; readonly current: Restriction | undefined; readonly version: number | undefined }) {
  const api = useApi();
  const queryClient = useQueryClient();
  const [restriction, setRestriction] = useState<Restriction | ''>('');
  const [until, setUntil] = useState('');
  const [reason, setReason] = useState('');
  const [evidence, setEvidence] = useState('');
  const [approvalRef, setApprovalRef] = useState('');

  const change = useCommand(async (body: RestrictionChange, key) => {
    try {
      return await request(
        'POST',
        api.riders.POST('/riders/{riderId}/restrictions', { ...commandParams(key, { path: { riderId }, version }), body }),
      );
    } finally {
      void queryClient.invalidateQueries({ queryKey: ['riders', 'restrictions', riderId] });
    }
  });
  const locked = change.busy;
  const ready = restriction !== '' && restriction !== current && reason.trim() !== '';

  return (
    <form
      className="space-y-2 rounded-box bg-base-100 p-4"
      aria-label={m.riders.changeTitle}
      onSubmit={(e) => {
        e.preventDefault();
        if (!ready || locked) return;
        const refs = evidence
          .split(',')
          .map((s) => s.trim())
          .filter(Boolean);
        void change.run({
          restriction,
          reason: reason.trim(),
          ...(restriction !== 'NORMAL' && until ? { until: seoulLocalToIso(until) } : {}),
          ...(refs.length > 0 ? { evidenceRefs: refs } : {}),
          ...(approvalRef.trim() ? { approvalRef: approvalRef.trim() } : {}),
        });
      }}
    >
      <h2 className="font-bold">{m.riders.changeTitle}</h2>
      <p className="text-xs opacity-60">{m.riders.changeIntro}</p>
      <label className="block text-sm">
        {m.riders.newRestriction}
        <select className="select select-sm mt-1 block" value={restriction} disabled={locked} onChange={(e) => setRestriction(e.target.value as Restriction | '')}>
          <option value="">-</option>
          {RESTRICTIONS.map((r) => (
            <option key={r} value={r} disabled={r === current}>
              {m.riders.restrictionName[r]}
            </option>
          ))}
        </select>
      </label>
      {restriction !== '' && restriction !== 'NORMAL' && (
        <label className="block text-sm">
          {m.riders.untilLabel}
          <input type="datetime-local" className="input input-sm mt-1 block" value={until} disabled={locked} onChange={(e) => setUntil(e.target.value)} />
        </label>
      )}
      <label className="block text-sm">
        {m.riders.reason}
        <textarea className="textarea mt-1 w-full" rows={2} maxLength={MAX_REASON} required value={reason} disabled={locked} onChange={(e) => setReason(e.target.value)} />
      </label>
      <p className="text-xs opacity-60">{m.riders.reasonHint}</p>
      <label className="block text-sm">
        {m.riders.evidence}
        <input className="input input-sm mt-1 w-full" placeholder={m.riders.evidenceHint} value={evidence} disabled={locked} onChange={(e) => setEvidence(e.target.value)} />
      </label>
      <label className="block text-sm">
        {m.riders.approvalRef}
        <input className="input input-sm mt-1 block" value={approvalRef} disabled={locked} onChange={(e) => setApprovalRef(e.target.value)} />
      </label>
      <button type="submit" className="btn btn-warning btn-sm" disabled={!ready || locked}>
        {m.riders.apply}
      </button>
      <CommandFeedback command={change} unknown={{ body: m.riders.unknown }}>
        {(r) => (
          <p role="status" className="text-sm text-success" data-testid="restriction-result">
            {`${m.riders.applied} ${label(m.riders.restrictionName, r.restriction)}`}
          </p>
        )}
      </CommandFeedback>
    </form>
  );
}

function Restrictions({ riderId }: { readonly riderId: string }) {
  const api = useApi();
  const query = useQuery({
    queryKey: ['riders', 'restrictions', riderId],
    queryFn: () => request('GET', api.riders.GET('/riders/{riderId}/restrictions', { params: { path: { riderId } } })),
  });
  return (
    <QueryState state={toUiState(query)} onRetry={() => void query.refetch()}>
      {(r) => {
        const items: RestrictionRecord[] = r.items ?? [];
        const latest = items[0];
        return (
          <>
            <Facts
              testId="rider-restriction"
              rows={[
                [m.riders.current, <span key="c" data-testid="rider-current-restriction">{label(m.riders.restrictionName, r.current)}</span>],
                [m.riders.until, latest && latest.restriction === r.current && r.current !== 'NORMAL' ? (latest.until ? when(latest.until) : m.riders.untilNone) : m.none],
              ]}
            />
            <RestrictionForm riderId={riderId} current={r.current} version={latest?.version} />
            <h2 className="font-bold">{m.riders.history}</h2>
            {items.length === 0 ? (
              <p className="text-sm opacity-70">{m.riders.noHistory}</p>
            ) : (
              <table className="table table-sm rounded-box bg-base-100">
                <thead>
                  <tr>
                    <th>{m.riders.changedAt}</th>
                    <th>{m.riders.previous}</th>
                    <th>{m.riders.restriction}</th>
                    <th>{m.riders.until}</th>
                    <th>{m.riders.reason}</th>
                    <th>{m.riders.evidence}</th>
                    <th>{m.riders.changedBy}</th>
                  </tr>
                </thead>
                <tbody>
                  {items.map((h, i) => (
                    <tr key={`${h.changedAt ?? ''}-${i}`} data-testid="restriction-row">
                      <td>{when(h.changedAt)}</td>
                      <td>{label(m.riders.restrictionName, h.previous)}</td>
                      <td>{label(m.riders.restrictionName, h.restriction)}</td>
                      <td>{h.until ? when(h.until) : m.none}</td>
                      <td className="max-w-xs whitespace-pre-wrap">{text(h.reason)}</td>
                      <td>{(h.evidenceRefs ?? []).join(', ') || m.none}</td>
                      <td>{text(h.changedBy)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </>
        );
      }}
    </QueryState>
  );
}

export function RiderDetailPage() {
  const { riderId = '' } = useParams();
  return (
    <section className="max-w-5xl space-y-4">
      <h1 className="text-xl font-bold">{`${m.riders.detailTitle} ${riderId}`}</h1>
      <h2 className="font-bold">{m.riders.basic}</h2>
      {/* BR-54: 기본 정보는 계약 전 — 목 모드에서만 */}
      <NotInContract br="BR-54">{() => <DirectoryBasic riderId={riderId} />}</NotInContract>
      <Restrictions riderId={riderId} />
      <h2 className="font-bold">{m.riders.reviews}</h2>
      <ReviewTable state="OPEN" riderId={riderId} />
      <h2 className="font-bold">{m.riders.complaints}</h2>
      <RiderComplaintTable riderId={riderId} />
      <Link className="link text-sm" to="/riders">
        {m.riders.back}
      </Link>
    </section>
  );
}
