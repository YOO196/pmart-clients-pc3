// 내 정보 — 로그인한 직원 본인. 보기는 hr-service `GET /hr/employees/me`(모든 직원, LAN 에서 MFC_SUPERVISOR·MFC_WORKER 200 확인 — 백엔드 2026-11-18).
// 인사 기록이 없는 계정은 404 → 오류가 아니라 "기록 없음".
// 사용자 결정(2026-11-18): 내 비밀번호는 본인이 직접(지금 + 새 비밀번호), 연락처(휴대폰·개인 메일)만 본인이 — 회사 메일(로그인 ID·사서함)은 인사팀만.
// 비밀번호 바꾸기(EA-3)·연락처(HR-3)는 백엔드 요청 중(`docs/handoff/mfc-backoffice/2026-11-18-backend-my-account.md`)이라 폼을 두지 않는다 — 계약에 없는 API 는 부르지 않는다.
import { useQuery } from '@tanstack/react-query';

import { ProblemCode, ProblemFailure, request } from '@pmart/web-core';
import { QueryState, toUiState } from '@pmart/web-ui';
import type { EmployeeSelf } from '../../api/hrSelf';
import { useApi } from '../../app/ApiContext';
import { useSession } from '../../app/SessionContext';
import { messages } from '../../shared/messages';

const m = messages.me;

export function MyInfoPage() {
  const api = useApi();
  const { session } = useSession();
  const query = useQuery({
    queryKey: ['hr', 'me', session?.subject],
    enabled: session !== null,
    queryFn: async (): Promise<EmployeeSelf | null> => {
      try {
        return await request('GET', api.hr.GET('/hr/employees/me', {}));
      } catch (e) {
        if (e instanceof ProblemFailure && e.problem.code === ProblemCode.notFound) return null;
        throw e;
      }
    },
  });
  return (
    <section className="max-w-2xl space-y-4">
      <h1 className="text-xl font-bold">{m.title}</h1>
      <QueryState state={toUiState(query, (me) => me === null)} onRetry={() => void query.refetch()} emptyText={m.noRecord}>
        {(me) => me && <Profile me={me} />}
      </QueryState>
      <div className="space-y-1 rounded-box bg-base-100 p-4" data-testid="me-password">
        <h2 className="font-bold">{m.passwordTitle}</h2>
        <p className="text-sm">{m.passwordPreparing}</p>
      </div>
      <div className="space-y-1 rounded-box bg-base-100 p-4" data-testid="me-contact">
        <h2 className="font-bold">{m.contactTitle}</h2>
        <p className="text-sm">{m.contactPreparing}</p>
      </div>
    </section>
  );
}

function Profile({ me }: { readonly me: EmployeeSelf }) {
  const rows: ReadonlyArray<readonly [string, string]> = [
    [m.fields.name, me.name],
    [m.fields.employeeNo, me.employeeNo],
    [m.fields.operatorId, me.operatorId],
    [m.fields.mailAddress, me.mailAddress],
    [m.fields.employmentType, m.employmentType[me.employmentType] ?? me.employmentType],
    [m.fields.affiliation, me.affiliation.type === 'CENTER' ? m.center(me.affiliation.code) : m.department(me.affiliation.code)],
    [m.fields.status, m.status[me.status] ?? me.status],
  ];
  return (
    <div className="space-y-2 rounded-box bg-base-100 p-4">
      <dl className="grid grid-cols-[8rem_1fr] gap-x-4 gap-y-2 text-sm" data-testid="me-profile">
        {rows.map(([k, v]) => (
          <div key={k} className="contents">
            <dt className="opacity-70">{k}</dt>
            <dd>{v}</dd>
          </div>
        ))}
      </dl>
      <p className="text-xs opacity-70">{m.mailNote}</p>
    </div>
  );
}
