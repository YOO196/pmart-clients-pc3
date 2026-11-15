// 전달 실패·도움요청 대기(라이더 운영).
// ⚠ BR-55 — 대기 목록 API(`GET /delivery-help-requests` 제안)는 아직 계약에 없다(PC 5 BOD-4 예정). 목 모드에서만 메모리 목, 실서버 모드는 안내만.
// 모양은 PC 5 제안(delivery-backoffice-staff-apis.md BOD-4)을 따른 가정. 처리(전달 실패 확정·반려 등)는 배송 화면에서 계약된 API 로 한다.
// "처리함" 닫기 API 는 둘지 아직 정해지지 않아 버튼을 두지 않는다. 라이더가 쓴 내용(detail)은 목록에 싣지 않는다(제안 그대로).
import { useQuery } from '@tanstack/react-query';
import { Link, useSearchParams } from 'react-router';

import { QueryState, toUiState } from '@pmart/web-ui';
import { messages as m } from '../../shared/messages';
import { label, NotInContract, when } from '../../shared/ops';

type QueueState = 'OPEN' | 'IN_PROGRESS' | 'RESOLVED';
const STATES: readonly QueueState[] = ['OPEN', 'IN_PROGRESS', 'RESOLVED'];
const isState = (v: string | null): v is QueueState => v !== null && (STATES as readonly string[]).includes(v);

export interface DraftHelpRequestRow {
  readonly requestId: string;
  readonly deliveryId: string;
  readonly orderId: string | null;
  readonly mfcId: string;
  readonly riderId: string;
  readonly category: string;
  readonly stage: string;
  readonly state: QueueState;
  readonly createdAt: string;
  readonly photoCount: number;
}

const rows: readonly DraftHelpRequestRow[] = [
  {
    requestId: 'HELP-MOCK-1',
    deliveryId: 'DLV-MOCK-2',
    orderId: 'ORD-MOCK-1002',
    mfcId: 'MFC-BSN-01',
    riderId: 'RID-MOCK-2',
    category: 'DELIVERY_FAILURE',
    stage: 'FAILURE_REPORTED',
    state: 'OPEN',
    createdAt: '2026-11-15T00:40:00Z',
    photoCount: 2,
  },
  {
    requestId: 'HELP-MOCK-2',
    deliveryId: 'DLV-MOCK-1',
    orderId: 'ORD-MOCK-1001',
    mfcId: 'MFC-BSN-01',
    riderId: 'RID-MOCK-1',
    category: 'CUSTOMER_UNREACHABLE',
    stage: 'ARRIVED_AT_CUSTOMER',
    state: 'OPEN',
    createdAt: '2026-11-15T01:05:00Z',
    photoCount: 0,
  },
];

/** 목 모드 전용(BR-55). 오래된 것 먼저. */
export const helpQueueMock = {
  list(state: QueueState): Promise<DraftHelpRequestRow[]> {
    return Promise.resolve(rows.filter((r) => r.state === state).toSorted((a, b) => a.createdAt.localeCompare(b.createdAt)));
  },
};

function Queue({ state }: { readonly state: QueueState }) {
  const query = useQuery({ queryKey: ['help-queue-mock', state], queryFn: () => helpQueueMock.list(state) });
  return (
    <QueryState state={toUiState(query)} onRetry={() => void query.refetch()}>
      {(items) =>
        items.length === 0 ? (
          <p className="text-sm opacity-70">{m.helpQueue.empty}</p>
        ) : (
          <table className="table table-sm rounded-box bg-base-100">
            <thead>
              <tr>
                <th>{m.helpQueue.createdAt}</th>
                <th>{m.helpQueue.category}</th>
                <th>{m.helpQueue.stage}</th>
                <th>{m.helpQueue.delivery}</th>
                <th>{m.helpQueue.rider}</th>
                <th>{m.helpQueue.photos}</th>
              </tr>
            </thead>
            <tbody>
              {items.map((r) => (
                <tr key={r.requestId} data-testid="help-row">
                  <td>{when(r.createdAt)}</td>
                  <td>{label(m.helpQueue.categoryName, r.category)}</td>
                  <td>{label(m.deliveries.executionState, r.stage)}</td>
                  <td>
                    <Link className="link" to={`/deliveries/${encodeURIComponent(r.deliveryId)}`}>
                      {r.deliveryId}
                    </Link>
                  </td>
                  <td>
                    <Link className="link" to={`/riders/${encodeURIComponent(r.riderId)}`}>
                      {r.riderId}
                    </Link>
                  </td>
                  <td>{r.photoCount}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )
      }
    </QueryState>
  );
}

export function HelpRequestQueuePage() {
  const [search, setSearch] = useSearchParams();
  const raw = search.get('state');
  const state: QueueState = isState(raw) ? raw : 'OPEN';
  return (
    <section className="space-y-4">
      <h1 className="text-xl font-bold">{m.helpQueue.title}</h1>
      <p className="text-sm opacity-70">{m.helpQueue.intro}</p>
      <NotInContract br="BR-55">
        {() => (
          <>
            <div role="group" aria-label={m.helpQueue.title} className="join">
              {STATES.map((s) => (
                <button key={s} type="button" aria-pressed={state === s} className={`btn join-item btn-sm ${state === s ? 'btn-active' : ''}`} onClick={() => setSearch({ state: s })}>
                  {m.helpQueue.state[s]}
                </button>
              ))}
            </div>
            <Queue state={state} />
          </>
        )}
      </NotInContract>
    </section>
  );
}
