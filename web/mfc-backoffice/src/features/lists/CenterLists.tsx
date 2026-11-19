// 센터 목록(MB-1 — 백엔드 회신 2026-11-18 `clients/mfc-backoffice/2026-11-18-reply-lists-and-roles.md`).
// 지금까지 번호로만 열던 화면 위에 그 센터 목록을 둔다. "열기"는 그 화면의 번호 쿼리를 채운다(아래 상세·처리 흐름은 그대로).
// 기본 거르기는 일이 남은 상태(해제 승인 대기·폐기 승인 대기·실사 승인 대기 등) — 전체로 바꿀 수 있다.
import { request } from '@pmart/web-core';
import { formatSeoul } from '@pmart/web-ui';
import { useNavigate } from 'react-router';

import { useApi } from '../../app/ApiContext';
import { centerPath } from '../../app/nav';
import { CursorList, useQueryParam } from '../../shared/CursorList';
import { messages } from '../../shared/messages';
import { Who } from '../../shared/OperatorLabel';

const l = messages.lists;
const when = (t: string | null | undefined) => (t ? formatSeoul(t) : messages.none);
const assignmentsPath = (mfcId: string, rest: string) => centerPath(mfcId, `assignments/${rest}`);
/** 상태 하나로 거르기 — 비었으면 보내지 않는다(전체). */
const arr = <T extends string>(s: string): { state?: T[] } => (s ? { state: [s as T] } : {});

// ---------------------------------------------------------------- 품질

const DECISION_STATES = ['REQUESTED', 'SUBMITTED', 'APPLIED', 'UNKNOWN_RESULT', 'REJECTED', 'DECLINED'] as const;
type DecisionState = (typeof DECISION_STATES)[number];

export function DecisionList({ mfcId }: { readonly mfcId: string }) {
  const api = useApi();
  const [state, setState] = useQueryParam('decisionState', 'REQUESTED');
  const [, open] = useQueryParam('decisionId');
  const q = messages.quality;
  return (
    <CursorList
      title={l.decisions}
      testId="list-decisions"
      queryKey={['list', 'quality-decisions', mfcId, state]}
      fetchPage={(cursor) =>
        request('GET', api.quality.GET('/quality-decisions', { params: { query: { mfcId, ...arr<DecisionState>(state), ...(cursor ? { cursor } : {}) } } }))
      }
      head={[l.id, l.kind, l.reason, l.stateCol, l.at]}
      cells={(d) => [
        <span className="font-mono">{d.qualityDecisionId}</span>,
        q.type[d.decisionType] ?? d.decisionType,
        q.reason[d.reason] ?? d.reason,
        q.decisionState[d.state ?? ''] ?? d.state,
        when(d.decidedAt),
      ]}
      rowKey={(d) => d.qualityDecisionId ?? ''}
      onOpen={(d) => d.qualityDecisionId && open(d.qualityDecisionId)}
      emptyText={l.empty}
      states={DECISION_STATES}
      stateLabels={q.decisionState}
      state={state}
      onState={setState}
    />
  );
}

const DISPOSAL_STATES = ['REQUESTED', 'APPROVED', 'PARTIALLY_EXECUTED', 'COMPLETED', 'REJECTED'] as const;
type DisposalState = (typeof DISPOSAL_STATES)[number];

export function DisposalList({ mfcId }: { readonly mfcId: string }) {
  const api = useApi();
  const [state, setState] = useQueryParam('disposalState', 'REQUESTED');
  const [, open] = useQueryParam('disposalId');
  const q = messages.quality;
  return (
    <CursorList
      title={l.disposals}
      testId="list-disposals"
      queryKey={['list', 'disposal-approvals', mfcId, state]}
      fetchPage={(cursor) =>
        request('GET', api.quality.GET('/disposal-approvals', { params: { query: { mfcId, ...arr<DisposalState>(state), ...(cursor ? { cursor } : {}) } } }))
      }
      head={[l.id, l.stateCol, l.requester, l.at, l.reason]}
      cells={(d) => [<span className="font-mono">{d.disposalApprovalId}</span>, q.disposalState[d.state ?? ''] ?? d.state, <Who id={d.requesterId} />, when(d.requestedAt), d.reason ?? messages.none]}
      rowKey={(d) => d.disposalApprovalId ?? ''}
      onOpen={(d) => d.disposalApprovalId && open(d.disposalApprovalId)}
      emptyText={l.empty}
      states={DISPOSAL_STATES}
      stateLabels={q.disposalState}
      state={state}
      onState={setState}
    />
  );
}

const APPLY_STATES = ['SUBMITTED', 'APPLIED', 'REJECTED', 'UNKNOWN_RESULT'] as const;
type ApplyState = (typeof APPLY_STATES)[number];

export function InspectionList({ mfcId }: { readonly mfcId: string }) {
  const api = useApi();
  const [state, setState] = useQueryParam('inspectionState', '');
  const [, open] = useQueryParam('inspectionId');
  const apply = messages.inbound.applyStatus;
  return (
    <CursorList
      title={l.inspections}
      testId="list-inspections"
      queryKey={['list', 'return-inspections', mfcId, state]}
      fetchPage={(cursor) =>
        request('GET', api.quality.GET('/return-inspections', { params: { query: { mfcId, ...arr<ApplyState>(state), ...(cursor ? { cursor } : {}) } } }))
      }
      head={[l.id, l.claim, l.resale, l.dispose, l.stateCol, l.at]}
      cells={(r) => [
        <span className="font-mono">{r.returnInspectionId}</span>,
        <span className="font-mono">{r.claimId}</span>,
        r.resaleQty ?? messages.none,
        r.disposeQty ?? messages.none,
        apply[r.inventoryApplyStatus ?? ''] ?? r.inventoryApplyStatus,
        when(r.inspectedAt),
      ]}
      rowKey={(r) => r.returnInspectionId ?? ''}
      onOpen={(r) => r.returnInspectionId && open(r.returnInspectionId)}
      emptyText={l.empty}
      states={APPLY_STATES}
      stateLabels={apply}
      state={state}
      onState={setState}
    />
  );
}

// ---------------------------------------------------------------- 입고

/** 회수품 반입 — 입고 탭(열기 = 반입 보기)과 품질 검수 탭(열기 = 검수할 반입 불러오기)에서 같이 쓴다. */
export function ReturnReceiptList({ mfcId, title }: { readonly mfcId: string; readonly title?: string }) {
  const api = useApi();
  const [state, setState] = useQueryParam('receiptState', '');
  const [, open] = useQueryParam('returnReceiptId');
  const i = messages.inbound;
  return (
    <CursorList
      title={title ?? l.returnReceipts}
      testId="list-return-receipts"
      queryKey={['list', 'return-receipts', mfcId, state]}
      fetchPage={(cursor) =>
        request('GET', api.inbound.GET('/return-receipts', { params: { query: { mfcId, ...arr<ApplyState>(state), ...(cursor ? { cursor } : {}) } } }))
      }
      head={[l.id, l.claim, l.stateCol, l.inspection, l.at]}
      cells={(r) => [
        <span className="font-mono">{r.returnReceiptId}</span>,
        <span className="font-mono">{r.claimId}</span>,
        i.applyStatus[r.inventoryApplyStatus ?? ''] ?? r.inventoryApplyStatus,
        i.inspectionState[r.inspectionState ?? ''] ?? r.inspectionState ?? messages.none,
        when(r.receivedAt),
      ]}
      rowKey={(r) => r.returnReceiptId ?? ''}
      onOpen={(r) => r.returnReceiptId && open(r.returnReceiptId)}
      emptyText={l.empty}
      states={APPLY_STATES}
      stateLabels={i.applyStatus}
      state={state}
      onState={setState}
    />
  );
}

const SUPPLY_STATES = ['DRAFT', 'SUBMITTED', 'ACKNOWLEDGED', 'WITHDRAWN'] as const;
type SupplyState = (typeof SUPPLY_STATES)[number];

export function SupplyRequestList({ mfcId }: { readonly mfcId: string }) {
  const api = useApi();
  const [state, setState] = useQueryParam('supplyState', '');
  const [, open] = useQueryParam('supplyRequestId');
  const i = messages.inbound;
  return (
    <CursorList
      title={l.supplyRequests}
      testId="list-supply-requests"
      queryKey={['list', 'supply-requests', mfcId, state]}
      fetchPage={(cursor) =>
        request('GET', api.inbound.GET('/supply-requests', { params: { query: { mfcId, ...arr<SupplyState>(state), ...(cursor ? { cursor } : {}) } } }))
      }
      head={[l.id, l.stateCol, l.lineCount, l.at]}
      cells={(r) => [<span className="font-mono">{r.supplyRequestId}</span>, i.supplyState[r.state ?? ''] ?? r.state, l.lines(r.lines.length), when(r.submittedAt)]}
      rowKey={(r) => r.supplyRequestId ?? ''}
      onOpen={(r) => r.supplyRequestId && open(r.supplyRequestId)}
      emptyText={l.empty}
      states={SUPPLY_STATES}
      stateLabels={i.supplyState}
      state={state}
      onState={setState}
    />
  );
}

const LOAD_STATES = ['EXPECTED', 'PENDING', 'APPLIED', 'REJECTED'] as const;
type LoadState = (typeof LOAD_STATES)[number];

export function InitialLoadList({ mfcId }: { readonly mfcId: string }) {
  const api = useApi();
  const [state, setState] = useQueryParam('loadState', 'EXPECTED');
  const [, open] = useQueryParam('approvalId');
  const i = messages.inbound;
  return (
    <CursorList
      title={l.initialLoads}
      testId="list-initial-loads"
      queryKey={['list', 'initial-stock-loads', mfcId, state]}
      fetchPage={(cursor) =>
        request('GET', api.inbound.GET('/initial-stock-loads', { params: { query: { mfcId, ...arr<LoadState>(state), ...(cursor ? { cursor } : {}) } } }))
      }
      head={[l.receipt, l.approval, l.stateCol, l.lineCount, l.at]}
      cells={(r) => [
        <span className="font-mono">{r.receiptId}</span>,
        <span className="font-mono">{r.approvalId}</span>,
        i.loadState[r.state] ?? r.state,
        l.lines(r.lines.length),
        when(r.createdAt),
      ]}
      rowKey={(r) => r.receiptId}
      onOpen={(r) => open(r.approvalId)}
      emptyText={l.empty}
      states={LOAD_STATES}
      stateLabels={i.loadState}
      state={state}
      onState={setState}
    />
  );
}

// ---------------------------------------------------------------- 재고

const COUNT_STATES = ['COUNTING', 'RECOUNT_REQUIRED', 'PENDING_APPROVAL', 'MATCHED', 'ADJUSTED', 'REJECTED'] as const;
type CountState = (typeof COUNT_STATES)[number];

export function CountSessionList({ mfcId }: { readonly mfcId: string }) {
  const api = useApi();
  const [state, setState] = useQueryParam('countState', 'PENDING_APPROVAL');
  const [, open] = useQueryParam('sessionId');
  const inv = messages.inventory;
  return (
    <CursorList
      title={l.countSessions}
      testId="list-count-sessions"
      queryKey={['list', 'count-sessions', mfcId, state]}
      fetchPage={(cursor) =>
        request(
          'GET',
          api.inventory.GET('/mfcs/{mfcId}/count-sessions', { params: { path: { mfcId }, query: { ...arr<CountState>(state), ...(cursor ? { cursor } : {}) } } }),
        )
      }
      head={[l.id, l.stateCol, l.locations, l.createdBy, l.updatedAt]}
      cells={(s) => [
        <span className="font-mono">{s.sessionId}</span>,
        inv.countState[s.state ?? ''] ?? s.state,
        (s.locationCodes ?? []).join(', ') || messages.none,
        <Who id={s.createdBy} />,
        when(s.updatedAt),
      ]}
      rowKey={(s) => s.sessionId ?? ''}
      onOpen={(s) => s.sessionId && open(s.sessionId)}
      emptyText={l.empty}
      states={COUNT_STATES}
      stateLabels={inv.countState}
      state={state}
      onState={setState}
    />
  );
}

const QUALITY_STATES = ['PENDING_INSPECTION', 'NORMAL', 'QUARANTINED', 'DISPOSAL_PENDING'] as const;
type QualityState = (typeof QUALITY_STATES)[number];

/** 센터 전체 재고(상품 코드 없이) — `GET /mfcs/{id}/stock-units`. 열기 = 그 상품의 재고 보기(정정은 거기서). */
export function StockUnitList({ mfcId }: { readonly mfcId: string }) {
  const api = useApi();
  const [quality, setQuality] = useQueryParam('unitQuality', '');
  const [location, setLocation] = useQueryParam('unitLocation', '');
  const [, open] = useQueryParam('sku');
  const mv = messages.moves;
  return (
    <CursorList
      title={l.stockUnits}
      testId="list-stock-units"
      queryKey={['list', 'stock-units', mfcId, quality, location]}
      fetchPage={(cursor) =>
        request(
          'GET',
          api.inventory.GET('/mfcs/{mfcId}/stock-units', {
            params: {
              path: { mfcId },
              query: { ...(quality ? { qualityState: quality as QualityState } : {}), ...(location ? { locationCode: location } : {}), ...(cursor ? { cursor } : {}) },
            },
          }),
        )
      }
      head={[l.sku, l.lot, l.location, l.qty, mv.qualityState, mv.workState, l.expiry]}
      cells={(u) => [
        <span>
          <span className="font-mono">{u.sku}</span> {u.productName ?? ''}
        </span>,
        <span className="font-mono">{u.lotNo ?? u.lotId}</span>,
        <span className="font-mono">{u.locationCode}</span>,
        u.qty,
        mv.quality[u.qualityState] ?? u.qualityState,
        mv.work[u.workState] ?? u.workState,
        u.expiryDate ?? messages.none,
      ]}
      rowKey={(u) => `${u.sku}-${u.lotId}-${u.locationCode}-${u.qualityState}-${u.workState}`}
      onOpen={(u) => open(u.sku)}
      emptyText={l.empty}
      states={QUALITY_STATES}
      stateLabels={mv.quality}
      state={quality}
      onState={setQuality}
      filters={
        <label className="flex flex-col gap-1 text-xs">
          {l.location}
          <input
            className="input input-sm w-36 font-mono"
            aria-label={`${l.stockUnits} ${l.location}`}
            defaultValue={location}
            onBlur={(e) => setLocation(e.target.value.trim().toUpperCase())}
            onKeyDown={(e) => {
              if (e.key === 'Enter') setLocation(e.currentTarget.value.trim().toUpperCase());
            }}
          />
        </label>
      }
    />
  );
}

// ---------------------------------------------------------------- 배정

const PLAN_STATES = ['PROPOSED', 'COMMITTED', 'NO_SOLUTION', 'STALE', 'UNDETERMINED', 'INVALID'] as const;
type PlanState = (typeof PLAN_STATES)[number];

export function PlanList({ mfcId }: { readonly mfcId: string }) {
  const api = useApi();
  const navigate = useNavigate();
  const [state, setState] = useQueryParam('planState', '');
  const [date, setDate] = useQueryParam('planDate', '');
  const a = messages.assignments;
  return (
    <CursorList
      title={l.plans}
      testId="list-plans"
      queryKey={['list', 'assignment-plans', mfcId, state, date]}
      fetchPage={(cursor) =>
        request(
          'GET',
          api.capacity.GET('/assignment-plans', {
            params: { query: { mfcId, ...arr<PlanState>(state), ...(date ? { date } : {}), ...(cursor ? { cursor } : {}) } },
          }),
        )
      }
      head={[l.id, l.stateCol, a.solver, l.createdBy, l.at]}
      cells={(p) => [
        <span className="font-mono">{p.planId}</span>,
        a.planState[p.state ?? ''] ?? p.state,
        p.solverStatus ?? messages.none,
        <Who id={p.createdBy} />,
        when(p.createdAt),
      ]}
      rowKey={(p) => p.planId ?? ''}
      onOpen={(p) => p.planId && void navigate(assignmentsPath(mfcId, `plans/${encodeURIComponent(p.planId)}`))}
      emptyText={l.empty}
      states={PLAN_STATES}
      stateLabels={a.planState}
      state={state}
      onState={setState}
      filters={
        <label className="flex flex-col gap-1 text-xs">
          {l.date}
          <input className="input input-sm w-40" type="date" aria-label={`${l.plans} ${l.date}`} value={date} onChange={(e) => setDate(e.target.value)} />
        </label>
      }
    />
  );
}
